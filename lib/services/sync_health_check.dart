import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/attendance_model.dart';
import '../models/quick_input_code_model.dart';
import 'user_service.dart';
import 'sync_service.dart';
import 'encryption_service.dart';

/// Global notifier để các widget có thể theo dõi sync health
/// true = healthy, false = có vấn đề, null = chưa kiểm tra
final ValueNotifier<bool?> syncHealthNotifier = ValueNotifier<bool?>(null);

/// Số lượng mismatches (để hiển thị badge)
final ValueNotifier<int> syncMismatchCountNotifier = ValueNotifier<int>(0);

/// Kết quả kiểm tra sync cho một collection
class SyncCheckResult {
  final String collection;
  final int localCount;
  final int cloudCount;
  final int localOnly; // Có local nhưng không có cloud
  final int cloudOnly; // Có cloud nhưng không có local
  final int matched; // Có cả hai
  final int unsyncedLocal; // Chưa sync lên cloud
  final int pendingCreateLocal; // Local mới, chưa có firestoreId
  final int pendingUpdateLocal; // Đã có firestoreId nhưng còn cờ unsynced
  final List<String> missingOnCloud; // IDs có local mà không có cloud
  final List<String> missingOnLocal; // IDs có cloud mà không có local
  final String? error;

  SyncCheckResult({
    required this.collection,
    required this.localCount,
    required this.cloudCount,
    required this.localOnly,
    required this.cloudOnly,
    required this.matched,
    required this.unsyncedLocal,
    this.pendingCreateLocal = 0,
    this.pendingUpdateLocal = 0,
    this.missingOnCloud = const [],
    this.missingOnLocal = const [],
    this.error,
  });

  int get effectiveMismatchCount =>
      cloudOnly + localOnly + pendingCreateLocal + pendingUpdateLocal;

  bool get isHealthy => effectiveMismatchCount == 0;
  bool get hasIssues => !isHealthy;

  double get syncPercentage {
    if (cloudCount == 0 && localCount == 0) return 100.0;
    final baseline = math.max(cloudCount, localCount);
    if (baseline == 0) return 100.0;

    final percentage = (matched / baseline) * 100;
    if (hasIssues) {
      return percentage.clamp(0.0, 99.0);
    }
    return percentage.clamp(0.0, 100.0);
  }

  int get displayPercentage {
    if (isHealthy) return 100;
    return syncPercentage.floor().clamp(0, 99);
  }
}

/// Tổng kết kiểm tra sync
class SyncHealthReport {
  final DateTime checkedAt;
  final String? shopId;
  final List<SyncCheckResult> results;
  final bool isFullyHealthy;
  final int totalLocalRecords;
  final int totalCloudRecords;
  final int totalMismatches;

  SyncHealthReport({
    required this.checkedAt,
    required this.shopId,
    required this.results,
    required this.isFullyHealthy,
    required this.totalLocalRecords,
    required this.totalCloudRecords,
    required this.totalMismatches,
  });

  String get summary {
    if (isFullyHealthy) {
      return '✅ Dữ liệu đồng bộ hoàn toàn ($totalCloudRecords records)';
    }
    return '⚠️ Có $totalMismatches records chưa đồng bộ';
  }
}

/// Service kiểm tra tình trạng sync
class SyncHealthCheck {
  static final _db = FirebaseFirestore.instance;
  static final _localDb = DBHelper();
  static final Map<String, Set<String>> _tableColumnsCache = {};

  /// Kiểm tra toàn bộ sync health
  static Future<SyncHealthReport> runFullCheck() async {
    debugPrint('🔍 Bắt đầu kiểm tra Sync Health...');

    final user = FirebaseAuth.instance.currentUser;
    final String? shopId = await UserService.getCurrentShopId();
    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();

    // LOG QUAN TRỌNG
    debugPrint(
      '⚡ runFullCheck: user=${user?.uid}, email=${user?.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin',
    );

    // Cần có shopId để check (super admin phải chọn shop trước)
    if (shopId == null) {
      if (isSuperAdmin) {
        debugPrint(
          '⚠️ runFullCheck: Super admin chưa chọn shop, bỏ qua kiểm tra',
        );
      } else {
        debugPrint('⚠️ runFullCheck: Không có shopId, bỏ qua kiểm tra');
      }
      return SyncHealthReport(
        checkedAt: DateTime.now(),
        shopId: null,
        results: [],
        isFullyHealthy: true, // Trả về true để không hiện loading mãi
        totalLocalRecords: 0,
        totalCloudRecords: 0,
        totalMismatches: 0,
      );
    }

    // Có shopId (bao gồm cả super admin đã chọn shop) - tiến hành check
    final String validShopId = shopId;

    final List<SyncCheckResult> results = [];
    int totalLocal = 0;
    int totalCloud = 0;
    int totalMismatches = 0;

    const collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
      'debt_payments',
    ];

    final allowedCollections =
        await SyncService.filterCollectionsForCurrentUser(collections);

    final skippedCollections = collections
        .where((collection) => !allowedCollections.contains(collection))
        .toList();
    if (skippedCollections.isNotEmpty) {
      debugPrint(
        'ℹ️ Sync Health bỏ qua collections ngoài quyền hiện tại: $skippedCollections',
      );
    }

    for (final collection in allowedCollections) {
      results.add(
        await _checkCollection(collection: collection, shopId: validShopId),
      );
    }

    // Tính tổng
    for (var r in results) {
      totalLocal += r.localCount;
      totalCloud += r.cloudCount;
      totalMismatches += r.effectiveMismatchCount;
    }

    final report = SyncHealthReport(
      checkedAt: DateTime.now(),
      shopId: shopId,
      results: results,
      isFullyHealthy: results.every((r) => r.isHealthy),
      totalLocalRecords: totalLocal,
      totalCloudRecords: totalCloud,
      totalMismatches: totalMismatches,
    );

    debugPrint('📊 Sync Health Report:');
    debugPrint('   Shop: $shopId');
    debugPrint(
      '   Local: $totalLocal | Cloud: $totalCloud | Mismatches: $totalMismatches',
    );
    for (var r in results) {
      final status = r.isHealthy ? '✅' : '⚠️';
      debugPrint(
        '   $status ${r.collection}: local=${r.localCount}, cloud=${r.cloudCount}, unsynced=${r.unsyncedLocal}',
      );
      if (r.missingOnLocal.isNotEmpty && r.missingOnLocal.length <= 5) {
        debugPrint('      Missing on local: ${r.missingOnLocal}');
      }
    }

    // Cập nhật global notifiers
    syncHealthNotifier.value = report.isFullyHealthy;
    syncMismatchCountNotifier.value = totalMismatches;

    return report;
  }

  /// Kiểm tra một collection cụ thể
  static Future<SyncCheckResult> _checkCollection({
    required String collection,
    required String shopId,
  }) async {
    try {
      // Lấy dữ liệu từ cloud - chỉ dùng 1 where để tránh cần composite index
      // Filter deleted ở client side
      final cloudSnap = await _db
          .collection(collection)
          .where('shopId', isEqualTo: shopId)
          .get();

      // DEBUG: Log chi tiết để tìm nguyên nhân cloud = 0
      debugPrint(
        '📊 _checkCollection $collection: shopId=$shopId, cloudDocs=${cloudSnap.docs.length}',
      );
      if (cloudSnap.docs.isEmpty) {
        // Thử query không filter shopId để xem có data không
        final allDocs = await _db.collection(collection).limit(5).get();
        if (allDocs.docs.isNotEmpty) {
          final sampleShopIds = allDocs.docs
              .map((d) => d.data()['shopId'])
              .toSet();
          debugPrint(
            '⚠️ $collection có ${allDocs.docs.length}+ docs trên cloud nhưng shopId khác: $sampleShopIds',
          );
        } else {
          debugPrint('ℹ️ $collection không có data nào trên cloud');
        }
      }

      // Filter ra các documents không bị xóa (deleted != true)
      final cloudRows = _buildCloudComparisonRows(collection, cloudSnap.docs);
      final cloudIds = cloudRows.keys.toSet();
      final localRows = await _getActiveLocalRows(collection, shopId: shopId);
      final localIds = _buildLocalComparisonKeys(collection, localRows);
      final localCount = localIds.length;
      final unsyncedCount = localRows.where(_isUnsyncedRow).length;
      final pendingCreateLocal = localRows
          .where(
            (row) => _isUnsyncedRow(row) && _firestoreIdFromRow(row) == null,
          )
          .length;
      final pendingUpdateLocal = localRows.where((row) {
        final firestoreId = _firestoreIdFromRow(row);
        return _isUnsyncedRow(row) &&
            firestoreId != null &&
            cloudIds.contains(firestoreId);
      }).length;

      debugPrint(
        '   → localCount=$localCount, localWithFirestoreId=${localIds.length}, cloudCount=${cloudIds.length}, unsynced=$unsyncedCount, pendingCreate=$pendingCreateLocal, pendingUpdate=$pendingUpdateLocal',
      );

      final cloudOnly = cloudIds.difference(localIds).length;

      // AUTO-FIX: Tự động download records thiếu trên local
      if (cloudOnly > 0) {
        debugPrint(
          '   🔧 Auto-fix: Tải $cloudOnly records thiếu cho $collection...',
        );
        final missingIds = cloudIds.difference(localIds);
        int fixed = 0;
        for (final docId in missingIds) {
          try {
            var data = Map<String, dynamic>.from(cloudRows[docId]!);
            data = EncryptionService.decryptMap(data);
            data['firestoreId'] = data['firestoreId'] ?? docId;
            data['isSynced'] = 1;
            data['deleted'] = data['deleted'] ?? 0;
            SyncService.convertTimestampFieldsPublic(data);
            await _upsertToLocal(collection, data);
            fixed++;
          } catch (e) {
            debugPrint('   ❌ Không tải được $docId: $e');
          }
        }
        debugPrint(
          '   ✅ Đã tải $fixed/$cloudOnly records thiếu cho $collection',
        );
      }

      // Re-count sau auto-fix
      final localRowsAfter = await _getActiveLocalRows(
        collection,
        shopId: shopId,
      );
      final localIdsAfter = _buildLocalComparisonKeys(
        collection,
        localRowsAfter,
      );
      final localCountAfter = localIdsAfter.length;
      final matchedAfter = localIdsAfter.intersection(cloudIds).length;
      final cloudOnlyAfter = cloudIds.difference(localIdsAfter).length;
      final localOnlyAfter = localIdsAfter.difference(cloudIds).length;
      final unsyncedAfter = localRowsAfter.where(_isUnsyncedRow).length;
      final pendingCreateAfter = localRowsAfter
          .where(
            (row) => _isUnsyncedRow(row) && _firestoreIdFromRow(row) == null,
          )
          .length;
      final pendingUpdateAfter = localRowsAfter.where((row) {
        final firestoreId = _firestoreIdFromRow(row);
        return _isUnsyncedRow(row) &&
            firestoreId != null &&
            cloudIds.contains(firestoreId);
      }).length;

      return SyncCheckResult(
        collection: collection,
        localCount: localCountAfter,
        cloudCount: cloudIds.length,
        localOnly: localOnlyAfter,
        cloudOnly: cloudOnlyAfter,
        matched: matchedAfter,
        unsyncedLocal: unsyncedAfter,
        pendingCreateLocal: pendingCreateAfter,
        pendingUpdateLocal: pendingUpdateAfter,
        missingOnCloud: localIdsAfter.difference(cloudIds).take(10).toList(),
        missingOnLocal: cloudIds.difference(localIdsAfter).take(10).toList(),
      );
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra $collection: $e');
      return SyncCheckResult(
        collection: collection,
        localCount: 0,
        cloudCount: 0,
        localOnly: 0,
        cloudOnly: 0,
        matched: 0,
        unsyncedLocal: 0,
        pendingCreateLocal: 0,
        pendingUpdateLocal: 0,
        error: e.toString(),
      );
    }
  }

  static Future<Set<String>> _getTableColumns(String table) async {
    final cached = _tableColumnsCache[table];
    if (cached != null) return cached;

    final db = await _localDb.database;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final columns = info
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .toSet();
    _tableColumnsCache[table] = columns;
    return columns;
  }

  static Future<List<Map<String, dynamic>>> _getActiveLocalRows(
    String collection, {
    required String shopId,
  }) async {
    final db = await _localDb.database;
    final columns = await _getTableColumns(collection);
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (columns.contains('deleted')) {
      whereClauses.add('(deleted IS NULL OR deleted = 0)');
    }
    if (columns.contains('shopId')) {
      whereClauses.add('(shopId = ? OR shopId IS NULL)');
      whereArgs.add(shopId);
    }

    return db.query(
      collection,
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );
  }

  static String? _firestoreIdFromRow(Map<String, dynamic> row) {
    final value = row['firestoreId']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Map<String, Map<String, dynamic>> _buildCloudComparisonRows(
    String collection,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final rows = <String, Map<String, dynamic>>{};

    for (final doc in docs) {
      var data = Map<String, dynamic>.from(doc.data());
      if (data['deleted'] == true) continue;

      data['firestoreId'] = doc.id;
      data = EncryptionService.decryptMap(data);
      final key = _comparisonKeyForRow(collection, data, fallbackId: doc.id);
      if (key == null) continue;
      rows.putIfAbsent(key, () => data);
    }

    return rows;
  }

  static Set<String> _buildLocalComparisonKeys(
    String collection,
    Iterable<Map<String, dynamic>> rows,
  ) {
    return rows
        .map((row) => _comparisonKeyForRow(collection, row))
        .whereType<String>()
        .toSet();
  }

  static String? _comparisonKeyForRow(
    String collection,
    Map<String, dynamic> row, {
    String? fallbackId,
  }) {
    switch (collection) {
      case 'customers':
        final phone = _normalizePhone(row['phone']);
        if (phone.isNotEmpty) return 'phone:$phone';

        final name = _normalizeText(row['name'] ?? row['customerName']);
        if (name.isNotEmpty) return 'name:$name';
        break;
      case 'suppliers':
        final supplierFirestoreId = _normalizeText(
          row['firestoreId'] ?? fallbackId,
        );
        if (supplierFirestoreId.isNotEmpty) {
          return 'id:$supplierFirestoreId';
        }

        final name = _normalizeText(row['name']);
        if (name.isNotEmpty) return 'name:$name';

        final phone = _normalizePhone(row['phone']);
        if (phone.isNotEmpty) return 'phone:$phone';
        break;
      case 'repair_parts':
        final repairPartFirestoreId = _normalizeText(
          row['firestoreId'] ?? fallbackId,
        );
        if (repairPartFirestoreId.isNotEmpty) {
          return 'id:$repairPartFirestoreId';
        }

        final partName = _normalizeText(row['partName'] ?? row['name']);
        final model = _normalizeText(row['compatibleModels']);
        final cost = (row['cost'] as num?)?.toInt() ?? 0;
        final price = (row['price'] as num?)?.toInt() ?? 0;
        if (partName.isNotEmpty) {
          return 'part:$partName|model:$model|cost:$cost|price:$price';
        }
        break;
    }

    final firestoreId = _normalizeText(row['firestoreId'] ?? fallbackId);
    if (firestoreId.isNotEmpty) return 'id:$firestoreId';
    return null;
  }

  static String _normalizeText(dynamic value) {
    return value?.toString().trim().toUpperCase() ?? '';
  }

  static String _normalizePhone(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  static bool _isUnsyncedRow(Map<String, dynamic> row) {
    final value = row['isSynced'];
    if (value is bool) return value != true;
    if (value is num) return value.toInt() != 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized != '1' && normalized != 'true';
    }
    return true;
  }

  /// Tự động sửa các vấn đề sync (download + upload + mark synced)
  static Future<int> autoFix() async {
    debugPrint('🔧 Bắt đầu Auto Fix Sync...');

    int fixedCount = 0;

    // BƯỚC 1: Upload local chưa sync lên cloud
    debugPrint('📤 Bước 1: Upload local lên cloud...');
    try {
      await SyncService.syncAllToCloud();
      debugPrint('✅ Upload hoàn thành');
    } catch (e) {
      debugPrint('❌ Lỗi upload: $e');
    }

    // BƯỚC 2: Download TẤT CẢ từ cloud về local và đánh dấu isSynced
    debugPrint('📥 Bước 2: Download từ cloud về local...');
    final String? shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      debugPrint('❌ Không có shopId');
      return fixedCount;
    }

    // Danh sách các collection cần sync
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts', // Kho linh kiện
      'debt_payments', // Lịch sử thanh toán công nợ
    ];

    for (var collection in collections) {
      try {
        debugPrint('   📥 Đang xử lý $collection...');

        // Lấy tất cả từ cloud
        final cloudSnap = await _db
            .collection(collection)
            .where('shopId', isEqualTo: shopId)
            .get();

        // Lấy local IDs
        final localIds = await _getLocalIds(collection);

        // Đếm cloud docs (không bị deleted)
        final activeCloudDocs = cloudSnap.docs
            .where((d) => d.data()['deleted'] != true)
            .toList();
        debugPrint(
          '      Cloud total: ${cloudSnap.docs.length}, active: ${activeCloudDocs.length}, local: ${localIds.length}',
        );

        int collectionFixed = 0;
        int collectionUpdated = 0;
        for (var doc in activeCloudDocs) {
          var data = Map<String, dynamic>.from(doc.data());
          data = EncryptionService.decryptMap(data);

          data['firestoreId'] = doc.id;
          data['isSynced'] = 1; // Đánh dấu đã sync
          data['deleted'] = data['deleted'] ?? 0; // Ensure deleted field exists
          SyncService.convertTimestampFieldsPublic(data);

          try {
            // Upsert tất cả - cả records mới lẫn records cần cập nhật isSynced
            await _upsertToLocal(collection, data);
            if (!localIds.contains(doc.id)) {
              collectionFixed++;
              fixedCount++;
              debugPrint('      ➕ Mới: ${doc.id}');
            } else {
              collectionUpdated++;
            }
          } catch (e) {
            debugPrint('      ❌ Lỗi xử lý ${doc.id}: $e');
          }
        }

        // Xóa local records đã bị xóa trên cloud
        final deletedCloudDocs = cloudSnap.docs
            .where((d) => d.data()['deleted'] == true)
            .toList();
        int deletedLocally = 0;
        for (var doc in deletedCloudDocs) {
          if (localIds.contains(doc.id)) {
            try {
              // Đánh dấu deleted = 1 trong local thay vì xóa hẳn
              await _markDeletedInLocal(collection, doc.id);
              deletedLocally++;
              debugPrint('      🗑️ Marked deleted: ${doc.id}');
            } catch (e) {
              debugPrint('      ❌ Lỗi đánh dấu xóa ${doc.id}: $e');
            }
          }
        }

        debugPrint(
          '   ✅ $collection: +$collectionFixed mới, ~$collectionUpdated cập nhật, -$deletedLocally xóa',
        );
      } catch (e) {
        debugPrint('   ❌ Lỗi xử lý $collection: $e');
      }
    }

    // BƯỚC 3: Đánh dấu tất cả records local đã có firestoreId là synced
    debugPrint('🔄 Bước 3: Đánh dấu records đã sync...');
    try {
      await _markAllAsSynced();
      debugPrint('✅ Đã đánh dấu sync');
    } catch (e) {
      debugPrint('❌ Lỗi đánh dấu sync: $e');
    }

    debugPrint('✅ Auto Fix hoàn thành: đã tải $fixedCount records mới');
    return fixedCount;
  }

  /// Đánh dấu tất cả records có firestoreId là đã sync
  static Future<void> _markAllAsSynced() async {
    final db = await _localDb.database;

    // Cập nhật isSynced = 1 cho tất cả records có firestoreId
    final tables = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
      'debt_payments',
    ];

    for (var table in tables) {
      try {
        await db.rawUpdate(
          'UPDATE $table SET isSynced = 1 WHERE firestoreId IS NOT NULL AND firestoreId != ""',
        );
        debugPrint('   ✅ Đã đánh dấu $table');
      } catch (e) {
        debugPrint('   ⚠️ Không thể đánh dấu $table: $e');
      }
    }
  }

  /// Lấy danh sách local IDs cho một collection (chỉ lấy records active, không deleted)
  static Future<Set<String>> _getLocalIds(String collection) async {
    final db = _localDb;
    final dbInstance = await db.database;

    switch (collection) {
      case 'repairs':
        final repairs = await dbInstance.query(
          'repairs',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return repairs
            .where((r) => r['firestoreId'] != null)
            .map((r) => r['firestoreId'] as String)
            .toSet();
      case 'sales':
        final sales = await dbInstance.query(
          'sales',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return sales
            .where((s) => s['firestoreId'] != null)
            .map((s) => s['firestoreId'] as String)
            .toSet();
      case 'products':
        final products = await dbInstance.query(
          'products',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return products
            .where((p) => p['firestoreId'] != null)
            .map((p) => p['firestoreId'] as String)
            .toSet();
      case 'expenses':
        final expenses = await dbInstance.query(
          'expenses',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return expenses
            .where((e) => e['firestoreId'] != null)
            .map((e) => e['firestoreId'] as String)
            .toSet();
      case 'debts':
        final debts = await dbInstance.query(
          'debts',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return debts
            .where((d) => d['firestoreId'] != null)
            .map((d) => d['firestoreId'] as String)
            .toSet();
      case 'attendance':
        final attendance = await dbInstance.query(
          'attendance',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return attendance
            .where((a) => a['firestoreId'] != null)
            .map((a) => a['firestoreId'] as String)
            .toSet();
      case 'customers':
        final customers = await dbInstance.query(
          'customers',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return customers
            .where((c) => c['firestoreId'] != null)
            .map((c) => c['firestoreId'] as String)
            .toSet();
      case 'suppliers':
        final suppliers = await dbInstance.query(
          'suppliers',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return suppliers
            .where((s) => s['firestoreId'] != null)
            .map((s) => s['firestoreId'] as String)
            .toSet();
      case 'quick_input_codes':
        final codes = await dbInstance.query(
          'quick_input_codes',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return codes
            .where((c) => c['firestoreId'] != null)
            .map((c) => c['firestoreId'] as String)
            .toSet();
      case 'repair_parts':
        final parts = await dbInstance.query(
          'repair_parts',
          where: '(deleted = 0 OR deleted IS NULL)',
        );
        return parts
            .where((p) => p['firestoreId'] != null)
            .map((p) => p['firestoreId'] as String)
            .toSet();
      case 'debt_payments':
        final payments = await dbInstance.query('debt_payments');
        return payments
            .where((p) => p['firestoreId'] != null)
            .map((p) => p['firestoreId'] as String)
            .toSet();
      default:
        return {};
    }
  }

  /// Upsert dữ liệu vào local DB
  static Future<void> _upsertToLocal(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final db = _localDb;

    switch (collection) {
      case 'repairs':
        await db.upsertRepair(Repair.fromMap(data));
        break;
      case 'sales':
        await db.upsertSale(SaleOrder.fromMap(data));
        break;
      case 'products':
        await db.upsertProduct(Product.fromMap(data));
        break;
      case 'expenses':
        await db.upsertExpense(Expense.fromMap(data));
        break;
      case 'debts':
        await db.upsertDebt(Debt.fromMap(data));
        break;
      case 'attendance':
        await db.upsertAttendance(Attendance.fromMap(data));
        break;
      case 'customers':
        await db.upsertCustomer(data);
        break;
      case 'suppliers':
        await db.upsertSupplier(data);
        break;
      case 'quick_input_codes':
        await db.upsertQuickInputCode(QuickInputCode.fromMap(data));
        break;
      case 'repair_parts':
        await db.upsertRepairPart(data);
        break;
      case 'debt_payments':
        await db.upsertDebtPayment(data);
        break;
    }
  }

  /// Đánh dấu record đã bị xóa trong local DB
  static Future<void> _markDeletedInLocal(
    String collection,
    String firestoreId,
  ) async {
    final db = await _localDb.database;

    try {
      await db.update(
        collection,
        {
          'deleted': 1,
          'isSynced': 1,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } catch (e) {
      debugPrint('❌ Lỗi đánh dấu deleted cho $collection/$firestoreId: $e');
    }
  }
}
