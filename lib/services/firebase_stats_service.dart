import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum StatsOpType { read, write, upload, imageNetwork, imageCached }

class StatsOp {
  final DateTime timestamp;
  final StatsOpType type;
  final String label; // collection name, url, etc.
  final int count;
  final int? bytes;

  const StatsOp({
    required this.timestamp,
    required this.type,
    required this.label,
    this.count = 1,
    this.bytes,
  });

  String get typeIcon {
    switch (type) {
      case StatsOpType.read:
        return '📖';
      case StatsOpType.write:
        return '✏️';
      case StatsOpType.upload:
        return '☁️';
      case StatsOpType.imageNetwork:
        return '🖼️';
      case StatsOpType.imageCached:
        return '💾';
    }
  }

  String get typeLabel {
    switch (type) {
      case StatsOpType.read:
        return 'READ';
      case StatsOpType.write:
        return 'WRITE';
      case StatsOpType.upload:
        return 'UPLOAD';
      case StatsOpType.imageNetwork:
        return 'IMG net';
      case StatsOpType.imageCached:
        return 'IMG cache';
    }
  }

  Map<String, dynamic> toMap() => {
    'ts': timestamp.millisecondsSinceEpoch,
    'type': type.index,
    'label': label,
    'count': count,
    if (bytes != null) 'bytes': bytes,
  };

  factory StatsOp.fromMap(Map<String, dynamic> m) => StatsOp(
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
    type: StatsOpType.values[m['type'] as int],
    label: m['label'] as String,
    count: m['count'] as int? ?? 1,
    bytes: m['bytes'] as int?,
  );
}

class FirebaseStatsSnapshot {
  // ── Totals today ──────────────────────────────────────────────
  final int totalReads;
  final int totalWrites;
  final int totalUploads;
  final int totalUploadBytes;
  final int totalImagesNetwork;
  final int totalImagesCached;

  // ── By collection ─────────────────────────────────────────────
  final Map<String, int> readsByCollection;
  final Map<String, int> writesByCollection;

  // ── Recent ops (last 100) ─────────────────────────────────────
  final List<StatsOp> recentOps;

  // ── Active ────────────────────────────────────────────────────
  final int activeListeners;
  final DateTime statsDate;

  // ── Cloud collection counts (from Firebase) ───────────────────
  final Map<String, int> cloudDocCounts;
  final Map<String, String> cloudCountErrors;
  final List<String> cloudAllowedCollections;
  final DateTime? cloudLastUpdated;
  final bool isRefreshingCloudCounts;

  // ── Session (since app launch, not persisted) ─────────────────
  final int sessionReads;
  final int sessionWrites;
  final int sessionUploads;
  final int sessionImages;
  final Duration sessionDuration;

  const FirebaseStatsSnapshot({
    required this.totalReads,
    required this.totalWrites,
    required this.totalUploads,
    required this.totalUploadBytes,
    required this.totalImagesNetwork,
    required this.totalImagesCached,
    required this.readsByCollection,
    required this.writesByCollection,
    required this.recentOps,
    required this.activeListeners,
    required this.statsDate,
    required this.cloudDocCounts,
    required this.cloudCountErrors,
    required this.cloudAllowedCollections,
    required this.cloudLastUpdated,
    required this.isRefreshingCloudCounts,
    required this.sessionReads,
    required this.sessionWrites,
    required this.sessionUploads,
    required this.sessionImages,
    required this.sessionDuration,
  });

  double get imageCacheHitRate {
    final total = totalImagesNetwork + totalImagesCached;
    if (total == 0) return 0;
    return totalImagesCached / total;
  }

  String get uploadBytesFormatted {
    if (totalUploadBytes < 1024) return '$totalUploadBytes B';
    if (totalUploadBytes < 1024 * 1024) {
      return '${(totalUploadBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalUploadBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // Ước tính chi phí (theo bảng giá Firestore Blaze plan)
  // $0.06 per 100K reads, $0.18 per 100K writes
  double get estimatedCostToday {
    final readCost = (totalReads / 100000) * 0.06;
    final writeCost = (totalWrites / 100000) * 0.18;
    return readCost + writeCost;
  }

  // % của free quota
  double get readsQuotaPercent => (totalReads / 50000).clamp(0.0, 1.0);
  double get writesQuotaPercent => (totalWrites / 20000).clamp(0.0, 1.0);

  int get totalCloudDocuments =>
      cloudDocCounts.values.fold<int>(0, (total, value) => total + value);

  int get cloudCollectionsSuccess => cloudDocCounts.length;

  int get cloudCollectionsError => cloudCountErrors.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service singleton
// ─────────────────────────────────────────────────────────────────────────────

class FirebaseStatsService {
  FirebaseStatsService._();

  static final FirebaseStatsService _instance = FirebaseStatsService._();
  static FirebaseStatsService get instance => _instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Shared prefs key ───────────────────────────────────────────
  static const String _kDate = 'fbs_date';
  static const String _kReads = 'fbs_reads';
  static const String _kWrites = 'fbs_writes';
  static const String _kUploads = 'fbs_uploads';
  static const String _kUploadBytes = 'fbs_upload_bytes';
  static const String _kImgNet = 'fbs_img_net';
  static const String _kImgCache = 'fbs_img_cache';
  static const String _kReadsByColl = 'fbs_reads_coll';
  static const String _kWritesByColl = 'fbs_writes_coll';
  static const String _kRecentOps = 'fbs_recent_ops';
  static const String _kCloudCounts = 'fbs_cloud_counts';
  static const String _kCloudErrors = 'fbs_cloud_errors';
  static const String _kCloudUpdated = 'fbs_cloud_updated';

  // ── In-memory daily totals (persisted) ────────────────────────
  int _reads = 0;
  int _writes = 0;
  int _uploads = 0;
  int _uploadBytes = 0;
  int _imgNet = 0;
  int _imgCache = 0;
  final Map<String, int> _readsByColl = {};
  final Map<String, int> _writesByColl = {};

  // ── In-memory session totals (not persisted) ──────────────────
  int _sessionReads = 0;
  int _sessionWrites = 0;
  int _sessionUploads = 0;
  int _sessionImages = 0;
  final DateTime _sessionStart = DateTime.now();

  // ── Active listener count ─────────────────────────────────────
  int _activeListeners = 0;
  // ── Date stats belong to (for display) ───────────────────────
  DateTime _statsDate = DateTime.now();
  DateTime? _cloudLastUpdated;
  bool _isRefreshingCloudCounts = false;
  DateTime? _lastCloudRefreshAttempt;
  final Map<String, int> _cloudDocCounts = {};
  final Map<String, String> _cloudCountErrors = {};
  List<String> _cloudAllowedCollections = const [];
  // ── Recent ops queue (last 100, persisted) ────────────────────
  final List<StatsOp> _recentOps = [];
  static const int _maxRecentOps = 100;
  static const Duration _cloudRefreshCooldown = Duration(seconds: 20);

  static const List<String> _cloudCollections = [
    'repairs',
    'products',
    'sales',
    'expenses',
    'debts',
    'debt_payments',
    'attendance',
    'quick_input_codes',
    'supplier_payments',
    'repair_partner_payments',
    'customers',
    'suppliers',
    'repair_partners',
    'repair_parts',
    'supplier_import_history',
    'supplier_product_prices',
    'audit_logs',
    'payment_intents',
    'cash_closings',
    'sales_returns',
    'sales_return_items',
    'financial_activity_log',
    'payment_requests',
    'leave_requests',
    'shift_swaps',
    'import_orders',
    'import_order_items',
    'product_variants',
    'purchase_orders',
    'employee_salary_settings',
    'work_schedules',
    'salvage_phones',
  ];

  // ── Stream ────────────────────────────────────────────────────
  final StreamController<FirebaseStatsSnapshot> _controller =
      StreamController<FirebaseStatsSnapshot>.broadcast();

  Stream<FirebaseStatsSnapshot> get stream => _controller.stream;

  bool _initialized = false;

  // ── Debounce emit ─────────────────────────────────────────────
  Timer? _emitTimer;

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    await _instance._load();
    _instance._initialized = true;
    _instance._emit();
    unawaited(refreshCloudCounts(force: true));
  }

  static Future<void> refreshCloudCounts({bool force = false}) async {
    await _instance._refreshCloudCounts(force: force);
  }

  /// Gọi khi có Firestore reads
  static void trackRead(String collection, int count) {
    if (count <= 0) return;
    _instance._checkDayRollover();
    _instance._reads += count;
    _instance._sessionReads += count;
    _instance._readsByColl[collection] =
        (_instance._readsByColl[collection] ?? 0) + count;
    _instance._addOp(
      StatsOp(
        timestamp: DateTime.now(),
        type: StatsOpType.read,
        label: collection,
        count: count,
      ),
    );
    _instance._scheduleSave();
  }

  /// Gọi khi có Firestore write (add/set/update/delete)
  static void trackWrite(
    String collection, {
    int count = 1,
    String operation = 'write',
  }) {
    if (count <= 0) return;
    _instance._checkDayRollover();
    _instance._writes += count;
    _instance._sessionWrites += count;
    _instance._writesByColl[collection] =
        (_instance._writesByColl[collection] ?? 0) + count;
    _instance._addOp(
      StatsOp(
        timestamp: DateTime.now(),
        type: StatsOpType.write,
        label: '$collection:$operation',
        count: count,
      ),
    );
    _instance._scheduleSave();
  }

  /// Gọi khi upload lên Firebase Storage
  static void trackUpload(String path, {int bytes = 0}) {
    _instance._checkDayRollover();
    _instance._uploads++;
    _instance._sessionUploads++;
    _instance._uploadBytes += bytes;
    _instance._addOp(
      StatsOp(
        timestamp: DateTime.now(),
        type: StatsOpType.upload,
        label: _shortLabel(path),
        bytes: bytes,
      ),
    );
    _instance._scheduleSave();
  }

  /// Gọi khi load ảnh từ network
  static void trackImageNetwork(String url) {
    _instance._checkDayRollover();
    _instance._imgNet++;
    _instance._sessionImages++;
    _instance._addOp(
      StatsOp(
        timestamp: DateTime.now(),
        type: StatsOpType.imageNetwork,
        label: _shortLabel(url),
      ),
    );
    _instance._scheduleSave();
  }

  /// Gọi khi ảnh được lấy từ cache
  static void trackImageCached(String url) {
    _instance._checkDayRollover();
    _instance._imgCache++;
    _instance._sessionImages++;
    _instance._addOp(
      StatsOp(
        timestamp: DateTime.now(),
        type: StatsOpType.imageCached,
        label: _shortLabel(url),
      ),
    );
    // Image cache hits are high frequency — only emit (no heavy save)
    _instance._scheduleEmit();
  }

  /// Cập nhật số lượng active Firestore listeners
  static void updateListenerCount(int count) {
    if (_instance._activeListeners == count) return;
    _instance._activeListeners = count;
    _instance._scheduleEmit();
  }

  /// Trả về snapshot hiện tại không qua stream
  static FirebaseStatsSnapshot current() => _instance._buildSnapshot();

  /// Xóa toàn bộ stats hôm nay
  static Future<void> resetToday() async {
    _instance._reads = 0;
    _instance._writes = 0;
    _instance._uploads = 0;
    _instance._uploadBytes = 0;
    _instance._imgNet = 0;
    _instance._imgCache = 0;
    _instance._readsByColl.clear();
    _instance._writesByColl.clear();
    _instance._recentOps.clear();
    _instance._statsDate = DateTime.now();
    await _instance._save();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _checkDayRollover() {
    if (!_initialized) return;
    final today = _todayKey();
    final storedDay =
        '${_statsDate.year}-${_statsDate.month.toString().padLeft(2, '0')}-${_statsDate.day.toString().padLeft(2, '0')}';
    if (storedDay != today) {
      // Ngày mới — reset toàn bộ bộ đếm
      debugPrint(
        '[FirestoreStats] Day rollover: $storedDay → $today, resetting counters',
      );
      _reads = 0;
      _writes = 0;
      _uploads = 0;
      _uploadBytes = 0;
      _imgNet = 0;
      _imgCache = 0;
      _readsByColl.clear();
      _writesByColl.clear();
      _recentOps.clear();
      _statsDate = DateTime.now();
      _save(); // persist mới
    }
  }

  void _addOp(StatsOp op) {
    _recentOps.insert(0, op);
    if (_recentOps.length > _maxRecentOps) {
      _recentOps.removeRange(_maxRecentOps, _recentOps.length);
    }
  }

  static String _shortLabel(String s) {
    if (s.length <= 40) return s;
    final parts = s.split('/');
    if (parts.length >= 2) return '…/${parts.last}';
    return '…${s.substring(s.length - 38)}';
  }

  Future<void> _refreshCloudCounts({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastCloudRefreshAttempt != null) {
      final elapsed = now.difference(_lastCloudRefreshAttempt!);
      if (elapsed < _cloudRefreshCooldown) {
        return;
      }
    }
    _lastCloudRefreshAttempt = now;

    if (_isRefreshingCloudCounts) {
      return;
    }

    _isRefreshingCloudCounts = true;
    _emit();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _cloudCountErrors
          ..clear()
          ..['auth'] = 'Không có phiên đăng nhập';
        return;
      }

      final isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      final permissions = await UserService.getCurrentUserPermissions();
      final role = await UserService.getUserRole(user.uid);

      String? shopId = UserService.getShopIdSync();
      shopId ??= await UserService.getCurrentShopId();

      if (shopId == null || shopId.isEmpty) {
        _cloudCountErrors
          ..clear()
          ..['shopId'] = 'Không tìm thấy shopId hiện tại';
        _cloudDocCounts.clear();
        _cloudAllowedCollections = const [];
        return;
      }

      final allowedCollections = _cloudCollections.where((collection) {
        return _canReadCollection(
          collection: collection,
          permissions: permissions,
          role: role,
          isSuperAdmin: isSuperAdmin,
        );
      }).toList();

      final counts = <String, int>{};
      final errors = <String, String>{};

      for (final collection in allowedCollections) {
        try {
          final query = _firestore
              .collection(collection)
              .where('shopId', isEqualTo: shopId);
          final aggregate = await query.count().get().timeout(
            const Duration(seconds: 7),
          );
          counts[collection] = aggregate.count ?? 0;
        } catch (e) {
          errors[collection] = _normalizeError(e);
        }
      }

      _cloudDocCounts
        ..clear()
        ..addAll(counts);
      _cloudCountErrors
        ..clear()
        ..addAll(errors);
      _cloudAllowedCollections = allowedCollections;
      _cloudLastUpdated = DateTime.now();
      await _save();
    } catch (e) {
      _cloudCountErrors
        ..clear()
        ..['runtime'] = _normalizeError(e);
    } finally {
      _isRefreshingCloudCounts = false;
      _emit();
    }
  }

  String _normalizeError(Object e) {
    final text = e.toString();
    if (text.contains('permission-denied') ||
        text.contains('PERMISSION_DENIED')) {
      return 'Permission denied';
    }
    if (text.contains('unavailable')) {
      return 'Network unavailable';
    }
    if (text.length > 120) {
      return '${text.substring(0, 120)}...';
    }
    return text;
  }

  bool _hasPermission(Map<String, dynamic> permissions, String key) {
    return permissions[key] == true;
  }

  bool _isManagerLike(String role, bool isSuperAdmin) {
    return isSuperAdmin ||
        role == 'admin' ||
        role == 'owner' ||
        role == 'manager';
  }

  bool _isStaffLike(String role, bool isSuperAdmin) {
    return _isManagerLike(role, isSuperAdmin) ||
        role == 'employee' ||
        role == 'technician';
  }

  bool _canReadCollection({
    required String collection,
    required Map<String, dynamic> permissions,
    required String role,
    required bool isSuperAdmin,
  }) {
    if (isSuperAdmin) return true;

    switch (collection) {
      case 'repairs':
      case 'repair_parts':
      case 'repair_partners':
      case 'partner_repair_history':
      case 'salvage_phones':
        return _hasPermission(permissions, 'allowViewRepairs');
      case 'sales':
      case 'customers':
      case 'payment_requests':
      case 'sales_returns':
      case 'sales_return_items':
        return _hasPermission(permissions, 'allowViewSales');
      case 'products':
      case 'product_variants':
      case 'quick_input_codes':
      case 'supplier_import_history':
      case 'supplier_product_prices':
      case 'import_orders':
      case 'import_order_items':
      case 'purchase_orders':
        return _hasPermission(permissions, 'allowViewInventory');
      case 'suppliers':
        return _hasPermission(permissions, 'allowViewSuppliers');
      case 'expenses':
        return _hasPermission(permissions, 'allowViewExpenses') &&
            _isManagerLike(role, isSuperAdmin);
      case 'debts':
        return _hasPermission(permissions, 'allowViewDebts') ||
            _hasPermission(permissions, 'allowViewSales');
      case 'debt_payments':
      case 'payment_intents':
        return _isStaffLike(role, isSuperAdmin);
      case 'attendance':
      case 'leave_requests':
      case 'shift_swaps':
      case 'audit_logs':
      case 'supplier_payments':
      case 'repair_partner_payments':
      case 'cash_closings':
      case 'employee_salary_settings':
      case 'work_schedules':
      case 'financial_activity_log':
        return _isManagerLike(role, isSuperAdmin);
      default:
        return true;
    }
  }

  FirebaseStatsSnapshot _buildSnapshot() => FirebaseStatsSnapshot(
    totalReads: _reads,
    totalWrites: _writes,
    totalUploads: _uploads,
    totalUploadBytes: _uploadBytes,
    totalImagesNetwork: _imgNet,
    totalImagesCached: _imgCache,
    readsByCollection: Map.unmodifiable(_readsByColl),
    writesByCollection: Map.unmodifiable(_writesByColl),
    recentOps: List.unmodifiable(_recentOps),
    activeListeners: _activeListeners,
    statsDate: _statsDate, // ngày thực tế của stats, không phải now()
    cloudDocCounts: Map.unmodifiable(_cloudDocCounts),
    cloudCountErrors: Map.unmodifiable(_cloudCountErrors),
    cloudAllowedCollections: List.unmodifiable(_cloudAllowedCollections),
    cloudLastUpdated: _cloudLastUpdated,
    isRefreshingCloudCounts: _isRefreshingCloudCounts,
    sessionReads: _sessionReads,
    sessionWrites: _sessionWrites,
    sessionUploads: _sessionUploads,
    sessionImages: _sessionImages,
    sessionDuration: DateTime.now().difference(_sessionStart),
  );

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_buildSnapshot());
    }
  }

  void _scheduleEmit() {
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 300), _emit);
  }

  void _scheduleSave() {
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 500), () {
      _emit();
      _save();
    });
  }

  // ── Persistence ───────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_kDate) ?? '';
      final today = _todayKey();

      if (savedDate != today) {
        // New day — reset all counters
        debugPrint('[FirestoreStats] New day — resetting counters');
        await prefs.setString(_kDate, today);
        _statsDate = DateTime.now();
        _reads = 0;
        _writes = 0;
        _uploads = 0;
        _uploadBytes = 0;
        _imgNet = 0;
        _imgCache = 0;
        _readsByColl.clear();
        _writesByColl.clear();
        _recentOps.clear();
      } else {
        _statsDate = DateTime.tryParse(savedDate) ?? DateTime.now();
        _reads = prefs.getInt(_kReads) ?? 0;
        _writes = prefs.getInt(_kWrites) ?? 0;
        _uploads = prefs.getInt(_kUploads) ?? 0;
        _uploadBytes = prefs.getInt(_kUploadBytes) ?? 0;
        _imgNet = prefs.getInt(_kImgNet) ?? 0;
        _imgCache = prefs.getInt(_kImgCache) ?? 0;

        final readsColl = prefs.getString(_kReadsByColl);
        if (readsColl != null) {
          final m = jsonDecode(readsColl) as Map<String, dynamic>;
          m.forEach((k, v) => _readsByColl[k] = v as int);
        }

        final writesColl = prefs.getString(_kWritesByColl);
        if (writesColl != null) {
          final m = jsonDecode(writesColl) as Map<String, dynamic>;
          m.forEach((k, v) => _writesByColl[k] = v as int);
        }

        final opsJson = prefs.getString(_kRecentOps);
        if (opsJson != null) {
          final list = jsonDecode(opsJson) as List<dynamic>;
          for (final item in list) {
            try {
              _recentOps.add(StatsOp.fromMap(item as Map<String, dynamic>));
            } catch (_) {}
          }
        }
      }

      final cloudCounts = prefs.getString(_kCloudCounts);
      if (cloudCounts != null) {
        final m = jsonDecode(cloudCounts) as Map<String, dynamic>;
        _cloudDocCounts.clear();
        m.forEach((k, v) {
          _cloudDocCounts[k] = (v as num).toInt();
        });
      }

      final cloudErrors = prefs.getString(_kCloudErrors);
      if (cloudErrors != null) {
        final m = jsonDecode(cloudErrors) as Map<String, dynamic>;
        _cloudCountErrors.clear();
        m.forEach((k, v) {
          _cloudCountErrors[k] = v.toString();
        });
      }

      final cloudUpdatedMs = prefs.getInt(_kCloudUpdated);
      if (cloudUpdatedMs != null && cloudUpdatedMs > 0) {
        _cloudLastUpdated = DateTime.fromMillisecondsSinceEpoch(cloudUpdatedMs);
      }

      debugPrint(
        '[FirestoreStats] Loaded: reads=$_reads, writes=$_writes, uploads=$_uploads',
      );
    } catch (e) {
      debugPrint('[FirestoreStats] Load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDate, _todayKey());
      await prefs.setInt(_kReads, _reads);
      await prefs.setInt(_kWrites, _writes);
      await prefs.setInt(_kUploads, _uploads);
      await prefs.setInt(_kUploadBytes, _uploadBytes);
      await prefs.setInt(_kImgNet, _imgNet);
      await prefs.setInt(_kImgCache, _imgCache);
      await prefs.setString(_kReadsByColl, jsonEncode(_readsByColl));
      await prefs.setString(_kWritesByColl, jsonEncode(_writesByColl));
      await prefs.setString(_kCloudCounts, jsonEncode(_cloudDocCounts));
      await prefs.setString(_kCloudErrors, jsonEncode(_cloudCountErrors));
      if (_cloudLastUpdated != null) {
        await prefs.setInt(
          _kCloudUpdated,
          _cloudLastUpdated!.millisecondsSinceEpoch,
        );
      }
      // Chỉ lưu 50 ops gần nhất để tránh làm nặng SharedPreferences
      final opsToSave = _recentOps.take(50).map((o) => o.toMap()).toList();
      await prefs.setString(_kRecentOps, jsonEncode(opsToSave));
    } catch (e) {
      debugPrint('[FirestoreStats] Save error: $e');
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
