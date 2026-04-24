import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../utils/repair_status_validator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/repair_model.dart';
import '../models/repair_service_model.dart';
import '../models/repair_partner_model.dart';
import '../models/payment_intent_model.dart';
import '../models/shop_settings_model.dart';
import '../constants/financial_constants.dart';
import '../services/unified_printer_service.dart';
import '../services/repair_partner_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/payment_intent_service.dart';
import '../services/category_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../widgets/responsive_wrapper.dart';
import '../services/notification_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_service.dart';
import '../services/firestore_service.dart';
import '../services/firestore_write_helper.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../services/financial_activity_service.dart';
import '../services/storage_service.dart';
import '../services/encryption_service.dart';
import 'package:image_picker/image_picker.dart';
import '../data/db_helper.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_cached_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'inventory_view.dart';
import 'repair_partner_view.dart';
import 'repair_invoice_template_view.dart';
import 'repair_invoice_preview_view.dart';

class RepairDetailView extends StatefulWidget {
  final Repair repair;
  const RepairDetailView({super.key, required this.repair});

  @override
  State<RepairDetailView> createState() => _RepairDetailViewState();
}

class _RepairDetailViewState extends State<RepairDetailView> {
  final db = DBHelper();
  late Repair r;
  bool _isUpdating = false;
  bool _isPrinting = false;
  String _shopName = "";
  String _shopAddr = "";
  String _shopPhone = "";
  bool _hasPermission = false;
  bool _canViewRevenue = false;
  bool _canViewCostPrice = false;
  bool _canEditRepairOrder = false;
  bool _canEditRepairFinancial = false;
  List<RepairPartner> _partners = [];
  String? _lastModifiedBy;
  int? _lastModifiedAt;

  // Shop settings for dynamic terminology (reserved for future multi-industry use)
  // ignore: unused_field
  ShopSettings? _shopSettings;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _repairDocSubscription;
  bool _hasReceivedServerDocSnapshot = false;

  AppLocalizations get loc => AppLocalizations.of(context)!;

  bool get _canViewAnyFinancial => _canViewRevenue || _canViewCostPrice;

  @override
  void initState() {
    super.initState();
    r = widget.repair;
    _loadShopSettings();
    _checkPermission();
    _loadShopInfo();
    _loadPartners();
    unawaited(_startRepairRealtimeListener(forceRestart: true));
    unawaited(_loadLastModifierInfo());
  }

  Future<void> _startRepairRealtimeListener({bool forceRestart = false}) async {
    final targetId = (r.firestoreId ?? '').trim();
    if (targetId.isEmpty) return;

    if (!forceRestart && _repairDocSubscription != null) {
      return;
    }

    await _repairDocSubscription?.cancel();
    _repairDocSubscription = null;
    _hasReceivedServerDocSnapshot = false;

    _repairDocSubscription = FirestoreService.watchRepairDoc(targetId).listen(
      (snapshot) {
        unawaited(_applyRepairDocSnapshot(snapshot));
      },
      onError: (error) {
        debugPrint('❌ [RepairDetailView] Realtime doc listener lỗi: $error');
      },
    );
  }

  Future<void> _applyRepairDocSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!snapshot.exists) return;

    if (snapshot.metadata.isFromCache && _hasReceivedServerDocSnapshot) {
      return;
    }

    if (!snapshot.metadata.isFromCache) {
      _hasReceivedServerDocSnapshot = true;
    }

    try {
      final rawData = Map<String, dynamic>.from(snapshot.data() ?? {});
      final data = EncryptionService.decryptMap(rawData);
      if (data['deleted'] == true) return;

      SyncService.convertTimestampFieldsPublic(data);
      data['firestoreId'] = snapshot.id;
      data['isSynced'] = 1;

      final isPartialSnapshot = _isPartialRepairSnapshot(data);
      final latest = Repair.fromMap(data);
      var safeLatest = await _mergeSnapshotWithLocalIfPartial(data, latest);
      safeLatest = await _protectLocalUnsyncedRepairFromStaleCloud(
        data,
        safeLatest,
      );

      // Khi đang xử lý thao tác cập nhật và snapshot cloud chỉ là patch trạng thái,
      // bỏ qua để tránh ghi đè đơn local thành giá 0/thiếu dữ liệu.
      if (_isUpdating && isPartialSnapshot) {
        debugPrint(
          'ℹ️ [RepairDetailView] Skip partial realtime snapshot while updating: ${snapshot.id}',
        );
        return;
      }

      final recoveredLocalData =
          isPartialSnapshot &&
          (safeLatest.price > 0 ||
              safeLatest.cost > 0 ||
              safeLatest.services.isNotEmpty ||
              safeLatest.customerName.trim().isNotEmpty ||
              safeLatest.model.trim().isNotEmpty);

      if (recoveredLocalData) {
        // Snapshot cloud bị thiếu dữ liệu, giữ bản local đầy đủ và ép sync ngược.
        safeLatest.isSynced = false;
      }

      await db.upsertRepair(safeLatest);

      if (recoveredLocalData && safeLatest.id != null) {
        try {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.repair,
            entityId: safeLatest.id!,
            firestoreId: safeLatest.firestoreId,
            operation: SyncOperation.update,
            data: safeLatest.toMap(),
          );
          // ignore: unawaited_futures
          unawaited(SyncOrchestrator().syncAll());
        } catch (e) {
          debugPrint(
            '⚠️ [RepairDetailView] enqueue heal partial repair snapshot lỗi: $e',
          );
        }
      }

      if (!mounted || _isUpdating) return;
      setState(() => r = safeLatest);
      unawaited(_loadLastModifierInfo());
    } catch (e) {
      debugPrint('⚠️ [RepairDetailView] _applyRepairDocSnapshot lỗi: $e');
    }
  }

  bool _isPartialRepairSnapshot(Map<String, dynamic> data) {
    final hasIdentity =
        (data['customerName']?.toString().trim().isNotEmpty ?? false) ||
        (data['model']?.toString().trim().isNotEmpty ?? false) ||
        (data['phone']?.toString().trim().isNotEmpty ?? false);
    final hasFinancial =
        data.containsKey('price') ||
        data.containsKey('cost') ||
        data.containsKey('totalCost') ||
      data.containsKey('services') ||
      data.containsKey('requestedDeliveryPrice');
    final hasCreatedAt = _parseTimestamp(data['createdAt']) > 0;

    return !hasIdentity && !hasFinancial && !hasCreatedAt;
  }

  Future<Repair> _mergeSnapshotWithLocalIfPartial(
    Map<String, dynamic> cloudData,
    Repair cloudRepair,
  ) async {
    if (!_isPartialRepairSnapshot(cloudData)) {
      return cloudRepair;
    }

    final firestoreId = (cloudRepair.firestoreId ?? '').trim();
    if (firestoreId.isEmpty) {
      return cloudRepair;
    }

    final localRepair = await db.getRepairByFirestoreId(firestoreId);
    if (localRepair == null) {
      return cloudRepair;
    }

    return localRepair.copyWith(
      status: cloudRepair.status,
      pendingDeliveryApproval: cloudRepair.pendingDeliveryApproval,
      requestedDeliveryPrice: cloudRepair.requestedDeliveryPrice != null
          ? cloudRepair.requestedDeliveryPrice
          : localRepair.requestedDeliveryPrice,
      lastCaredAt: cloudRepair.lastCaredAt ?? localRepair.lastCaredAt,
      finishedAt: cloudRepair.finishedAt ?? localRepair.finishedAt,
      deliveredAt: cloudRepair.deliveredAt ?? localRepair.deliveredAt,
      repairedBy: (cloudRepair.repairedBy ?? '').trim().isNotEmpty
          ? cloudRepair.repairedBy
          : localRepair.repairedBy,
      repairedByUid: (cloudRepair.repairedByUid ?? '').trim().isNotEmpty
          ? cloudRepair.repairedByUid
          : localRepair.repairedByUid,
      deliveredBy: (cloudRepair.deliveredBy ?? '').trim().isNotEmpty
          ? cloudRepair.deliveredBy
          : localRepair.deliveredBy,
      deliveredByUid: (cloudRepair.deliveredByUid ?? '').trim().isNotEmpty
          ? cloudRepair.deliveredByUid
          : localRepair.deliveredByUid,
      paymentMethod: cloudRepair.paymentMethod.trim().isNotEmpty
          ? cloudRepair.paymentMethod
          : localRepair.paymentMethod,
    );
  }

  int _extractCloudRepairTimeMs(Map<String, dynamic> cloudData) {
    final updatedAt = _parseTimestamp(cloudData['updatedAt']);
    if (updatedAt > 0) return updatedAt;

    final lastCaredAt = _parseTimestamp(cloudData['lastCaredAt']);
    if (lastCaredAt > 0) return lastCaredAt;

    final deliveredAt = _parseTimestamp(cloudData['deliveredAt']);
    if (deliveredAt > 0) return deliveredAt;

    final finishedAt = _parseTimestamp(cloudData['finishedAt']);
    if (finishedAt > 0) return finishedAt;

    return _parseTimestamp(cloudData['createdAt']);
  }

  Future<Repair> _protectLocalUnsyncedRepairFromStaleCloud(
    Map<String, dynamic> cloudData,
    Repair cloudRepair,
  ) async {
    final firestoreId = (cloudRepair.firestoreId ?? '').trim();
    if (firestoreId.isEmpty) {
      return cloudRepair;
    }

    final localRepair = await db.getRepairByFirestoreId(firestoreId);
    if (localRepair == null || localRepair.isSynced) {
      return cloudRepair;
    }

    final localTime = localRepair.lastCaredAt ?? localRepair.createdAt;
    final cloudTime = _extractCloudRepairTimeMs(cloudData);

    // Cloud chỉ được phép ghi đè khi thật sự mới hơn local unsynced.
    const toleranceMs = 5000;
    final cloudClearlyNewer =
        cloudTime > 0 && cloudTime > localTime + toleranceMs;
    if (cloudClearlyNewer) {
      return cloudRepair;
    }

    debugPrint(
      '🛡️ [RepairDetailView] Keep local unsynced repair $firestoreId (local: $localTime, cloud: $cloudTime)',
    );

    return localRepair.copyWith(
      status: cloudRepair.status,
      pendingDeliveryApproval: cloudRepair.pendingDeliveryApproval,
      requestedDeliveryPrice: cloudRepair.requestedDeliveryPrice != null
          ? cloudRepair.requestedDeliveryPrice
          : localRepair.requestedDeliveryPrice,
      lastCaredAt: cloudRepair.lastCaredAt ?? localRepair.lastCaredAt,
      finishedAt: cloudRepair.finishedAt ?? localRepair.finishedAt,
      deliveredAt: cloudRepair.deliveredAt ?? localRepair.deliveredAt,
      repairedBy: (cloudRepair.repairedBy ?? '').trim().isNotEmpty
          ? cloudRepair.repairedBy
          : localRepair.repairedBy,
      repairedByUid: (cloudRepair.repairedByUid ?? '').trim().isNotEmpty
          ? cloudRepair.repairedByUid
          : localRepair.repairedByUid,
      deliveredBy: (cloudRepair.deliveredBy ?? '').trim().isNotEmpty
          ? cloudRepair.deliveredBy
          : localRepair.deliveredBy,
      deliveredByUid: (cloudRepair.deliveredByUid ?? '').trim().isNotEmpty
          ? cloudRepair.deliveredByUid
          : localRepair.deliveredByUid,
      paymentMethod: cloudRepair.paymentMethod.trim().isNotEmpty
          ? cloudRepair.paymentMethod
          : localRepair.paymentMethod,
    );
  }

  String _normalizeActionText(String rawAction) {
    return rawAction.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isWalkInRepair(Repair repair) {
    if (repair.isWalkIn) return true;

    bool looksWalkIn(String? raw) {
      final value = _normalizeActionText(raw ?? '');
      if (value.isEmpty) return false;
      return value.contains('KHÁCH VÃNG LAI') ||
          value.contains('KHACH VANG LAI') ||
          value.contains('KHÁCH LẺ') ||
          value.contains('KHACH LE') ||
          value.contains('WALK IN') ||
          value == 'VÃNG LAI' ||
          value == 'VANG LAI';
    }

    return looksWalkIn(repair.customerName) || looksWalkIn(repair.walkInName);
  }

  Future<String> _resolveCurrentStaffName({String fallback = 'NV'}) async {
    try {
      final name = (await UserService.getCurrentUserName()).trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}

    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
    if (email.isNotEmpty && email.contains('@')) {
      final prefix = email.split('@').first.trim();
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }

    return fallback;
  }

  bool _isDeliveryRequestAction(String rawAction) {
    final action = _normalizeActionText(rawAction);
    if (action.isEmpty) return false;

    final localizedAction = _normalizeActionText(
      loc.actionRequestDeliveryApproval,
    );
    return action == localizedAction ||
        action == 'YÊU CẦU DUYỆT GIAO' ||
        action == 'REQUEST DELIVERY APPROVAL';
  }

  Future<int?> _findDeliveryRequestedAt() async {
    final targetId = (r.firestoreId ?? '').trim();
    if (targetId.isEmpty) return null;

    try {
      final dbConn = await db.database;
      final rows = await dbConn.query(
        'audit_logs',
        columns: ['action', 'createdAt'],
        where: 'targetType = ? AND targetId = ?',
        whereArgs: ['REPAIR', targetId],
        orderBy: 'createdAt DESC',
        limit: 40,
      );

      for (final row in rows) {
        final action = row['action']?.toString() ?? '';
        if (!_isDeliveryRequestAction(action)) continue;

        final createdAt = _parseTimestamp(row['createdAt']);
        if (createdAt > 0) return createdAt;
      }
    } catch (e) {
      debugPrint('⚠️ [RepairDetailView] _findDeliveryRequestedAt lỗi: $e');
    }

    return null;
  }

  Future<void> _loadLastModifierInfo() async {
    final targetId = (r.firestoreId ?? '').trim();
    if (targetId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _lastModifiedBy = null;
        _lastModifiedAt = null;
      });
      return;
    }

    try {
      final dbConn = await db.database;
      final rows = await dbConn.query(
        'audit_logs',
        columns: ['userName', 'action', 'createdAt'],
        where: 'targetType = ? AND targetId = ?',
        whereArgs: ['REPAIR', targetId],
        orderBy: 'createdAt DESC',
        limit: 30,
      );

      Map<String, dynamic>? modifierRow;
      for (final row in rows) {
        final action = row['action']?.toString() ?? '';
        if (_isRepairEditAction(action)) {
          modifierRow = row;
          break;
        }
      }

      String? modifiedBy;
      int? modifiedAt;

      if (modifierRow != null) {
        final userName = modifierRow['userName']?.toString();
        final label = _staffLabel(userName);
        if (label != '---') {
          modifiedBy = label;
        }

        final parsedAt = _parseTimestamp(modifierRow['createdAt']);
        if (parsedAt > 0) {
          modifiedAt = parsedAt;
        }
      }

      if (!mounted) return;
      setState(() {
        _lastModifiedBy = modifiedBy;
        _lastModifiedAt = modifiedAt;
      });
    } catch (e) {
      debugPrint('⚠️ [RepairDetailView] _loadLastModifierInfo lỗi: $e');
    }
  }

  bool _isRepairEditAction(String rawAction) {
    final action = _normalizeActionText(rawAction);
    if (action.isEmpty) return false;

    final localizedEditAction = _normalizeActionText(loc.editRepairAction);
    return action == localizedEditAction ||
        action == 'SỬA ĐƠN SỬA' ||
        action == 'CHỈNH SỬA THÔNG TIN ĐƠN SỬA' ||
        action == 'EDIT REPAIR';
  }

  int _parseTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _statusFlowFor(int status, {required bool pendingApproval}) {
    if (status <= 1) return 'received';
    if (status == 2) return 'repairing';
    if (status == 3) {
      return pendingApproval ? 'pending_approval' : 'approved';
    }
    return 'delivered';
  }

  Future<Repair?> _loadPersistedRepairSnapshot() async {
    if (r.id != null) {
      return db.getRepairById(r.id!);
    }
    final firestoreId = (r.firestoreId ?? '').trim();
    if (firestoreId.isEmpty) return null;
    return db.getRepairByFirestoreId(firestoreId);
  }

  int _displayedChargePrice(Repair repair) {
    final requested = repair.requestedDeliveryPrice;
    if (repair.pendingDeliveryApproval && requested != null) {
      return requested;
    }
    return repair.price;
  }

  String _displayedPriceLabel(Repair repair) {
    final requested = repair.requestedDeliveryPrice;
    if (repair.pendingDeliveryApproval && requested != null) {
      return 'Giá yêu cầu';
    }
    return loc.priceLabel;
  }

  bool _hasFinancialImpact(Repair? previous, Repair current) {
    if (previous == null) {
      return current.price != 0 ||
          current.cost != 0 ||
          (current.requestedDeliveryPrice ?? 0) != 0 ||
          current.paymentMethod.trim().isNotEmpty ||
          current.status == 4;
    }

    return previous.price != current.price ||
        previous.cost != current.cost ||
        previous.requestedDeliveryPrice != current.requestedDeliveryPrice ||
        previous.paymentMethod != current.paymentMethod ||
        previous.costRecordedInFund != current.costRecordedInFund ||
        previous.costPaymentMethod != current.costPaymentMethod ||
        previous.costRecordedAmount != current.costRecordedAmount ||
        previous.status != current.status ||
        previous.pendingDeliveryApproval != current.pendingDeliveryApproval;
  }

  void _emitRepairChanged({
    bool financialImpact = false,
    bool includeDebts = false,
    bool includeServiceChanges = false,
  }) {
    final eventBus = EventBus();
    eventBus.emit(EventBus.repairsChanged);
    if (financialImpact) {
      eventBus.emit(EventBus.financialChanged);
    }
    if (includeDebts) {
      eventBus.emit('debts_changed');
    }
    if (includeServiceChanges) {
      eventBus.emit('repair_services_changed');
    }
  }

  Future<void> _pushRepairStatusToCloud({
    required int status,
    required bool pendingApproval,
    int? finishedAt,
    int? deliveredAt,
    String? repairedBy,
    String? repairedByUid,
    String? deliveredBy,
    String? deliveredByUid,
    String? paymentMethod,
    int? requestedDeliveryPrice,
    bool includeRequestedDeliveryPrice = false,
  }) async {
    final targetId = (r.firestoreId ?? '').trim();
    if (targetId.isEmpty) return;

    final payload = <String, dynamic>{
      'status': status,
      'statusFlow': _statusFlowFor(status, pendingApproval: pendingApproval),
      'pendingDeliveryApproval': pendingApproval,
      'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
    };

    final lastCaredAt = r.lastCaredAt;
    if (lastCaredAt != null && lastCaredAt > 0) {
      payload['lastCaredAt'] = lastCaredAt;
    }
    if (finishedAt != null && finishedAt > 0) {
      payload['finishedAt'] = finishedAt;
    }
    if (deliveredAt != null && deliveredAt > 0) {
      payload['deliveredAt'] = deliveredAt;
    }
    if ((repairedBy ?? '').trim().isNotEmpty) {
      payload['repairedBy'] = repairedBy!.trim();
    }
    if ((repairedByUid ?? '').trim().isNotEmpty) {
      payload['repairedByUid'] = repairedByUid!.trim();
    }
    if ((deliveredBy ?? '').trim().isNotEmpty) {
      payload['deliveredBy'] = deliveredBy!.trim();
    }
    if ((deliveredByUid ?? '').trim().isNotEmpty) {
      payload['deliveredByUid'] = deliveredByUid!.trim();
    }
    if ((paymentMethod ?? '').trim().isNotEmpty) {
      payload['paymentMethod'] = paymentMethod!.trim();
    }
    if (includeRequestedDeliveryPrice) {
      payload['requestedDeliveryPrice'] = requestedDeliveryPrice;
    }

    final docSnapshot = await FirestoreService.getRepairDoc(targetId);
    if (!docSnapshot.exists) {
      // Nếu doc chưa tồn tại trên cloud mà chỉ set patch status,
      // Firestore sẽ tạo doc thiếu trường và làm local bị ghi đè về 0 khi listener chạy.
      // Bootstrap full payload trước để tránh mất price/cost/customer/model.
      final bootstrap = Map<String, dynamic>.from(r.toMap());
      bootstrap['firestoreId'] = targetId;
      bootstrap['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final shopId = (await UserService.getCurrentShopId())?.trim();
      if (shopId != null && shopId.isNotEmpty) {
        bootstrap['shopId'] = shopId;
      }
      bootstrap.addAll(payload);

      final encryptedBootstrap = EncryptionService.encryptMap(bootstrap);
      await FirestoreService.upsertRepairPatchByFirestoreId(
        targetId,
        encryptedBootstrap,
      );
      return;
    }

    await FirestoreService.upsertRepairPatchByFirestoreId(targetId, payload);
  }

  @override
  void dispose() {
    _repairDocSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  Future<void> _loadPartners() async {
    try {
      final partnerService = RepairPartnerService();
      final partners = await partnerService.getRepairPartners();
      if (!mounted) return;
      setState(() {
        _partners = partners;
        // Resolve partnerName cho các dịch vụ đã có partnerId
        for (final s in r.services) {
          if (s.partnerId != null && s.partnerName == null) {
            final match = partners.where((p) => p.id == s.partnerId);
            if (match.isNotEmpty) {
              s.partnerName = match.first.name;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ [RepairDetailView] _loadPartners lỗi: $e');
    }
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    final role = await UserService.getRoleFast();
    final isManagerLike =
        role == 'admin' || role == 'owner' || role == 'manager';
    final canViewCostPrice = perms['allowViewCostPrice'] == true;
    final canViewRevenue =
        perms['allowViewRevenue'] == true || canViewCostPrice;
    if (!mounted) return;
    setState(() {
      _hasPermission = perms['allowViewRepairs'] ?? false;
      _canViewRevenue = canViewRevenue;
      _canViewCostPrice = canViewCostPrice;
      _canEditRepairOrder = isManagerLike;
      _canEditRepairFinancial = isManagerLike && canViewRevenue;
    });
  }

  bool _ensureCanEditRepairOrder() {
    if (_canEditRepairOrder) return true;
    NotificationService.showSnackBar(
      'Nhân viên không có quyền sửa đơn sửa.',
      color: Colors.orange,
    );
    return false;
  }

  bool _ensureCanEditRepairFinancial() {
    if (_canEditRepairFinancial) return true;
    NotificationService.showSnackBar(
      'Nhân viên không có quyền sửa tài chính đơn sửa.',
      color: Colors.orange,
    );
    return false;
  }

  Future<void> _loadShopInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final rawShopName = (prefs.getString('shop_name') ?? '').trim();
    final normalizedShopName =
        rawShopName.toLowerCase() == 'shop new' ||
            rawShopName.toLowerCase() == 'shop_new' ||
            rawShopName.toLowerCase() == 'shopnew'
        ? 'Quản Lý Shop'
        : (rawShopName.isNotEmpty ? rawShopName : loc.defaultShopName);
    if (!mounted) return;
    setState(() {
      _shopName = normalizedShopName;
      _shopAddr = prefs.getString('shop_address') ?? loc.defaultShopDesc;
      _shopPhone = prefs.getString('shop_phone') ?? loc.defaultShopPhone;
    });
  }

  bool _isGsStoragePath(String path) {
    return StorageService.isGsStoragePath(path);
  }

  bool _isStorageRelativePath(String path) {
    return StorageService.isStorageRelativePath(path);
  }

  Future<String?> _resolveDisplayImagePath(String path) async {
    return StorageService.resolveDisplayUrl(path);
  }

  Widget _buildSmartImage(String path) {
    final normalized = path.trim();
    if (_isGsStoragePath(normalized) || _isStorageRelativePath(normalized)) {
      return FutureBuilder<String?>(
        future: _resolveDisplayImagePath(normalized),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) {
            return const Icon(Icons.broken_image, color: AppColors.error);
          }
          return AppCachedImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 400,
          );
        },
      );
    }
    if (normalized.startsWith('http') ||
        normalized.startsWith('blob:') ||
        normalized.startsWith('data:')) {
      return AppCachedImage(
        imageUrl: normalized,
        fit: BoxFit.cover,
        memCacheWidth: 400,
      );
    }
    if (kIsWeb) {
      return const Icon(Icons.broken_image, color: AppColors.error);
    }
    File file = File(normalized);
    if (file.existsSync()) return Image.file(file, fit: BoxFit.cover);
    return const Icon(Icons.cloud_download, color: AppColors.primary);
  }

  bool _isWebImageSource(String path) {
    return StorageService.isDisplayableCloudPath(path);
  }

  List<String> _displayableImages(List<String> images) {
    final normalized = images
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((path) {
          if (StorageService.isResolvableDisplayPath(path)) return true;
          return !kIsWeb;
        })
        .toList();
    if (!kIsWeb) return normalized;
    final web = normalized.where(_isWebImageSource).toList();
    return web;
  }

  Future<void> _updateStatus(int newStatus) async {
    if (_isUpdating) return; // Guard chống double-tap
    debugPrint(
      'Starting status update from ${r.status} to $newStatus for repair ${r.firestoreId}',
    );

    // Validate status transition using state machine
    final transitionError = RepairStatusValidator.getTransitionError(
      r.status,
      newStatus,
    );
    if (transitionError != null) {
      NotificationService.showSnackBar(transitionError, color: AppColors.error);
      return;
    }

      // FIX C-03: Set lock TRƯỚC await đầu tiên cho status 1/2/3.
      // Status 4 delegate sang _approveDelivery/_submitForDeliveryApproval có guard riêng.
      if (newStatus != 4) _isUpdating = true;

      final currentStaffName = await _resolveCurrentStaffName(fallback: 'NV');

    final repairsBefore = await db.getAllRepairs();
    debugPrint('Repairs count before update: ${repairsBefore.length}');

    // Chỉ admin/owner mới được giao máy (status 4)
    // Nếu đơn đang chờ duyệt (pendingDeliveryApproval = true), phải duyệt trước
    if (newStatus == 4) {
      final currentRole = await UserService.getRoleFast();
      final isManagerOrOwner =
          currentRole == 'admin' ||
          currentRole == 'owner' ||
          currentRole == 'manager';
      debugPrint(
        'Giao máy check: role=$currentRole, isManager=$isManagerOrOwner, pending=${r.pendingDeliveryApproval}',
      );

      // Nhân viên bấm "Giao máy" -> chuyển sang "Chờ duyệt giao"
      // (status 3 + pendingDeliveryApproval = true). Quản lý/chủ shop sẽ duyệt.
      if (!isManagerOrOwner) {
        if (r.pendingDeliveryApproval) {
          NotificationService.showSnackBar(
            loc.orderPendingApproval,
            color: Colors.deepOrange,
          );
          return;
        }
        await _submitForDeliveryApproval();
        return;
      }

      // Admin/owner duyệt đơn chờ giao
      await _approveDelivery();
      return;
    }

    // NOTE: Code below is DEAD CODE - kept for reference only
    // Admin/owner always goes through _approveDelivery() above
    /*
    if (newStatus == 4) {
      // GIAO MÁY (DEAD CODE)
      String payMethod = loc.cash;
      String selectedWarranty = r.warranty.isEmpty ? loc.month1 : r.warranty;
      final List<String> warrantyOptions = [
        loc.noWarranty,
        loc.month1,
        loc.month3,
        loc.month6,
        loc.month12,
      ];

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dialogLoc = AppLocalizations.of(ctx)!;
          return StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
              title: Text(dialogLoc.confirmDeliveryAndPayment),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dialogLoc.selectWarrantyPeriod,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: warrantyOptions
                        .map(
                          (opt) => ChoiceChip(
                            label: Text(opt, style: AppTextStyles.caption),
                            selected: selectedWarranty == opt,
                            onSelected: (v) =>
                                setS(() => selectedWarranty = opt),
                            selectedColor: AppColors.primary.withOpacity(0.2),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dialogLoc.selectPaymentMethod,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [dialogLoc.cash, dialogLoc.transfer, dialogLoc.debt]
                        .map(
                          (m) => ChoiceChip(
                            label: Text(m, style: AppTextStyles.caption),
                            selected: payMethod == m,
                            onSelected: (v) => setS(() => payMethod = m),
                            selectedColor:
                                AppColors.secondary.withOpacity(0.2),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(dialogLoc.cancel),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: AppButtonStyles.elevatedButtonStyle,
                  child: Text(dialogLoc.completeDelivery,
                      style: AppTextStyles.button),
                ),
              ],
            ),
          );
        },
      );

      if (confirm != true) return;
      r.warranty = selectedWarranty;
      r.paymentMethod = payMethod;
      r.deliveredAt = DateTime.now().millisecondsSinceEpoch;

      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";

      // GHI NHẬT KÝ GIAO MÁY
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: loc.actionDeliverDevice,
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: loc.deliveredDevice(r.model, r.customerName, selectedWarranty),
      );

      if (payMethod == "CÔNG NỢ") {
        // FIX: Tạo firestoreId TRƯỚC khi insert để tránh duplicate khi sync
        final debtFId =
            "debt_${DateTime.now().millisecondsSinceEpoch}_${r.phone.hashCode}";
        final debtData = {
          'personName': r.customerName,
          'phone': r.phone,
          'totalAmount': r.price,
          'paidAmount': 0,
          'type': "CUSTOMER_OWES",
          'status': "ACTIVE",
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'note': loc.debtNoteForRepair(r.model),
          'linkedId': r.firestoreId,
          'firestoreId': debtFId, // Set firestoreId ngay từ đầu
        };
        final debtId = await db.insertDebt(debtData);

        // Queue sync debt to cloud via SyncOrchestrator
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: debtData,
        );
        
        // Tạo PaymentIntent cho việc thu nợ sau này (CHỜ THU)
        final intent = PaymentIntent(
          id: 'pi_repair_debt_${DateTime.now().millisecondsSinceEpoch}_${r.id}',
          type: PaymentIntentType.customerDebtCollection,
          amount: r.price,
          description: 'Thu tiền sửa máy: ${r.model} - ${r.customerName}',
          referenceId: debtFId,
          referenceType: 'repair_debt',
          personName: r.customerName,
          personPhone: r.phone,
          createdBy: user?.uid ?? 'unknown',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'repairId': r.id,
            'repairFirestoreId': r.firestoreId,
            'debtId': debtId,
            'debtFirestoreId': debtFId,
            'debtType': 'CUSTOMER_OWES',
          },
        );
        await PaymentIntentService.createIntent(intent);
        debugPrint('💳 Created PaymentIntent for repair debt collection: ${intent.id}');
      } else if (r.price > 0) {
        // Thanh toán tiền mặt/chuyển khoản - Tạo PaymentIntent (CHỜ THU)
        final intent = PaymentIntent(
          id: 'pi_repair_${DateTime.now().millisecondsSinceEpoch}_${r.id}',
          type: PaymentIntentType.repairService,
          amount: r.price,
          description: 'Thu tiền sửa máy: ${r.model} - ${r.customerName}',
          referenceId: r.firestoreId,
          referenceType: 'repair',
          personName: r.customerName,
          personPhone: r.phone,
          createdBy: user?.uid ?? 'unknown',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'repairId': r.id,
            'repairFirestoreId': r.firestoreId,
            'paymentMethod': payMethod,
            'model': r.model,
          },
        );
        await PaymentIntentService.createIntent(intent);
        debugPrint('💳 Created PaymentIntent for repair payment: ${intent.id}');
      }

      // GHIM ĐƠN SỬA VÀO CHAT NỘI BỘ KHI GIAO MÁY
      final key = r.firestoreId ?? "repair_${r.createdAt}";
      final summary = loc.repairOrderSummary(
          r.customerName, r.phone, r.model, '${MoneyUtils.formatCurrency(r.price)} đ');
      final msg = loc.chatDeviceDelivered(summary);
      await FirestoreService.sendChat(
        message: msg,
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: summary,
      );
    }
    */
    // END OF DEAD CODE BLOCK

    if (newStatus == 3) {
      r.finishedAt = DateTime.now().millisecondsSinceEpoch;
      // Ghi nhận người sửa xong = user hiện tại
      final user = FirebaseAuth.instance.currentUser;
      r.repairedBy = currentStaffName;
      r.repairedByUid = user?.uid;
      // Không tự động set pendingDeliveryApproval = true
      // Để user chủ động bấm nút "GIAO MÁY" sau khi sửa xong
    }

    // Update lastCaredAt for conflict resolution during sync
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.isSynced = false; // Mark as needing sync

    setState(() {
      r.status = newStatus;
      _isUpdating = true;
    });
    try {
      debugPrint(
        'Updating repair status to $newStatus for repair ${r.firestoreId}',
      );
      await db.upsertRepair(r);

      try {
        await _pushRepairStatusToCloud(
          status: r.status,
          pendingApproval: r.pendingDeliveryApproval,
          finishedAt: r.finishedAt,
          deliveredAt: r.deliveredAt,
          repairedBy: r.repairedBy,
          repairedByUid: r.repairedByUid,
          deliveredBy: r.deliveredBy,
          deliveredByUid: r.deliveredByUid,
          paymentMethod: r.paymentMethod,
        );
      } catch (e) {
        debugPrint('⚠️ [RepairDetailView] Push status realtime lỗi: $e');
      }

      // Queue sync repair to cloud via SyncOrchestrator
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );

        // Await sync so indicator turns green after status change
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
      }

      debugPrint('Repair status updated successfully');
      final repairsAfter = await db.getAllRepairs();
      debugPrint('Repairs count after update: ${repairsAfter.length}');
      NotificationService.showSnackBar(
        loc.statusUpdated(_getStatusText(newStatus)),
        color: AppColors.success,
      );
      _emitRepairChanged();

      // GỬI PUSH NOTIFICATION khi thay đổi trạng thái (trừ status 4 đã xử lý riêng)
      if (newStatus != 4) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          final userName = currentStaffName;
          final key = r.firestoreId ?? "repair_${r.createdAt}";
          final summary = loc.repairOrderShare(
            r.customerName,
            r.phone,
            r.model,
            '',
          );

          String emoji = "";
          String statusMsg = "";
          switch (newStatus) {
            case 1:
              emoji = "📥";
              statusMsg = loc.statusReceivedMsg;
              break;
            case 2:
              emoji = "🔧";
              statusMsg = loc.statusStartRepairMsg;
              break;
            case 3:
              emoji = "✔️";
              statusMsg = loc.statusRepairDoneUpper;
              break;
          }

          final msg = "$emoji $statusMsg: $summary";

          // Gửi push notification cho mọi người
          await NotificationService.sendCloudNotification(
            title: '$emoji $statusMsg',
            body:
                '👤 ${r.customerName} • 📱 ${r.model}\n💰 ${MoneyUtils.formatCurrency(r.price)}đ',
            type: 'new_order',
            data: {'targetType': 'repair', 'targetId': key, 'repairId': key},
          );

          // Ghim vào chat nội bộ
          await FirestoreService.sendChat(
            message: msg,
            senderId: user?.uid ?? 'guest',
            senderName: userName,
            linkedType: 'repair',
            linkedKey: key,
            linkedSummary: summary,
          );
        } catch (e) {
          debugPrint('Failed to send status notification/chat: $e');
        }
      }
    } catch (e) {
      debugPrint('Error updating repair status: $e');
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  String _getStatusText(int s, {bool pendingApproval = false}) {
    if (s == 3 && pendingApproval) {
      return loc.statusPendingApproval;
    }
    switch (s) {
      case 1:
        return loc.statusReceivedUpper;
      case 2:
        return loc.statusRepairingUpper;
      case 3:
        return loc.statusRepairDoneUpper;
      case 4:
        return loc.statusDeliveredUpper;
      default:
        return loc.statusOther;
    }
  }

  Color _getStatusColor(int s, {bool pendingApproval = false}) {
    if (s == 3 && pendingApproval) {
      return AppColors.repairPendingApproval;
    }
    switch (s) {
      case 1:
        return AppColors.repairReceived;
      case 2:
        return AppColors.repairRepairing;
      case 3:
        return AppColors.repairDone;
      case 4:
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  /// Nhân viên submit đơn chờ duyệt giao (pendingDeliveryApproval = true)
  Future<void> _submitForDeliveryApproval() async {
    if (_isUpdating) return; // Guard chống double-tap
    // Kiểm tra thông tin khách hàng trước khi giao máy
    // Khách vãng lai (isWalkIn) được phép giao mà không cần thông tin đầy đủ
    if (!_isWalkInRepair(r) &&
        (r.phone.trim().isEmpty || r.customerName.trim().isEmpty)) {
      final shouldEdit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ Thiếu thông tin khách hàng'),
          content: const Text(
            'Vui lòng cập nhật thông tin khách hàng (Tên, SĐT) trước khi giao máy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cập nhật ngay'),
            ),
          ],
        ),
      );
      if (shouldEdit == true) {
        await _editBasicInfo();
      }
      return;
    }

    String payMethod = loc.cash;
    String selectedWarranty = r.warranty.isEmpty ? '1 tháng' : r.warranty;
    final List<String> warrantyOptions = [
      loc.noWarranty,
      '1 tháng',
      '3 tháng',
      '6 tháng',
      '12 tháng',
    ];
    final formKey = GlobalKey<FormState>();
    final priceCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(_displayedChargePrice(r)),
    );

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text(dialogLoc.sendApprovalRequest),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dialogLoc.orderWillBeSentForApproval,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CurrencyTextField(
                    controller: priceCtrl,
                    label: dialogLoc.chargeCustomerVnd,
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 0,
                      fieldName: dialogLoc.chargeCustomerLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dialogLoc.selectWarrantyPeriod,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: warrantyOptions
                        .map(
                          (opt) => ChoiceChip(
                            label: Text(opt, style: AppTextStyles.caption),
                            selected: selectedWarranty == opt,
                            onSelected: (v) =>
                                setS(() => selectedWarranty = opt),
                            selectedColor: AppColors.primary.withOpacity(0.2),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dialogLoc.selectPaymentMethod,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        [dialogLoc.cash, dialogLoc.transfer, dialogLoc.debt]
                            .map(
                              (m) => ChoiceChip(
                                label: Text(m, style: AppTextStyles.caption),
                                selected: payMethod == m,
                                onSelected: (v) => setS(() => payMethod = m),
                                selectedColor: AppColors.secondary.withOpacity(
                                  0.2,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(dialogLoc.cancel),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                ),
                child: Text(
                  dialogLoc.sendApprovalRequest,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;
    final parsedPrice = MoneyUtils.parseCurrency(priceCtrl.text);

    final user = FirebaseAuth.instance.currentUser;
    final userName = await _resolveCurrentStaffName(fallback: 'NV');
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    r.requestedDeliveryPrice = parsedPrice;
    r.warranty = selectedWarranty;
    r.paymentMethod = payMethod;
    r.lastCaredAt = nowMs;
    r.isSynced = false;

    setState(() {
      // Nếu đơn chưa ở status 3 (Sửa xong), chuyển lên status 3 trước
      if (r.status < 3) {
        r.status = 3;
        r.finishedAt = nowMs;
        // Ghi nhận người sửa xong
        r.repairedBy = userName;
        r.repairedByUid = user?.uid;
      }
      // Người gửi yêu cầu giao được xem là người giao thực tế.
      r.deliveredBy = userName;
      r.deliveredByUid = user?.uid;
      // Dùng thời điểm gửi yêu cầu duyệt làm mốc thời gian giao hiển thị.
      r.deliveredAt = nowMs;
      r.pendingDeliveryApproval = true; // Đánh dấu chờ duyệt
      _isUpdating = true;
    });

    try {
      await db.upsertRepair(r);

      try {
        await _pushRepairStatusToCloud(
          status: r.status,
          pendingApproval: r.pendingDeliveryApproval,
          finishedAt: r.finishedAt,
          deliveredAt: r.deliveredAt,
          repairedBy: r.repairedBy,
          repairedByUid: r.repairedByUid,
          deliveredBy: r.deliveredBy,
          deliveredByUid: r.deliveredByUid,
          paymentMethod: r.paymentMethod,
          requestedDeliveryPrice: r.requestedDeliveryPrice,
          includeRequestedDeliveryPrice: true,
        );
      } catch (e) {
        debugPrint(
          '⚠️ [RepairDetailView] Push pending approval realtime lỗi: $e',
        );
      }

      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );

        // Await sync để tránh trạng thái pending kéo dài (nút sync vàng).
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
        // FIX: Also trigger targeted repair sync for reliability
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }

      final key = r.firestoreId ?? "repair_${r.createdAt}";

      // Gửi notification cho quản lý
      await NotificationService.sendCloudNotification(
        title: '📋 YÊU CẦU DUYỆT GIAO MÁY',
        body:
            '👤 ${r.customerName} • 📱 ${r.model}\n💰 ${MoneyUtils.formatCurrency(parsedPrice)}đ (giá yêu cầu)\n👷 $userName',
        type: 'approval_needed',
        data: {'targetType': 'repair', 'targetId': key, 'repairId': key},
      );

      // Log và chat
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: loc.actionRequestDeliveryApproval,
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: loc.requestDeliveryApprovalDesc(r.model, r.customerName),
      );

      await FirestoreService.sendChat(
        message: loc.chatRequestDeliveryApproval(
          r.model,
          r.customerName,
          MoneyUtils.formatCurrency(parsedPrice),
        ),
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: loc.pendingDeliveryApproval(r.customerName),
      );

      NotificationService.showSnackBar(
        loc.sentDeliveryApprovalRequest,
        color: Colors.deepOrange,
      );
      _emitRepairChanged(financialImpact: false);
      // Trở về danh sách đơn sửa sau khi gửi yêu cầu giao
      if (mounted) Navigator.pop(context, true);
      return;
    } catch (e) {
      debugPrint('Error submitting for approval: $e');
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  /// Quản lý duyệt đơn giao máy (pendingDeliveryApproval -> status 4)
  Future<void> _approveDelivery() async {
    if (_isUpdating) return; // Guard chống double-tap
    // Kiểm tra thông tin khách hàng trước khi giao máy
    // Khách vãng lai (isWalkIn) được phép giao mà không cần thông tin đầy đủ
    if (!_isWalkInRepair(r) &&
        (r.phone.trim().isEmpty || r.customerName.trim().isEmpty)) {
      final shouldEdit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ Thiếu thông tin khách hàng'),
          content: const Text(
            'Vui lòng cập nhật thông tin khách hàng (Tên, SĐT) trước khi duyệt giao máy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cập nhật ngay'),
            ),
          ],
        ),
      );
      if (shouldEdit == true) {
        await _editBasicInfo();
      }
      return;
    }

    String selectedWarranty = r.warranty.isEmpty ? 'KO BH' : r.warranty;
    final List<String> warrantyOptions = [
      'KO BH',
      '1 THÁNG',
      '3 THÁNG',
      '6 THÁNG',
      '12 THÁNG',
    ];
    final requestedPriceForApproval = _displayedChargePrice(r);
    final formKey = GlobalKey<FormState>();
    final priceCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(requestedPriceForApproval),
    );
    final costCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(r.cost),
    );

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text(dialogLoc.approveDelivery),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dialogLoc.customerInfo(r.customerName),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(dialogLoc.deviceInfo(r.model)),
                        Text(
                          dialogLoc.priceInfo(
                            MoneyUtils.formatCurrency(requestedPriceForApproval),
                          ),
                        ),
                        if (r.requestedDeliveryPrice != null)
                          Text(
                            'Giá hiện tại trong sổ: ${MoneyUtils.formatCurrency(r.price)}',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                            ),
                          ),
                        Text(dialogLoc.paymentInfo(r.paymentMethod)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CurrencyTextField(
                    controller: priceCtrl,
                    label: dialogLoc.chargeCustomerVnd,
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 0,
                      fieldName: dialogLoc.chargeCustomerLabel,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CurrencyTextField(
                    controller: costCtrl,
                    label: dialogLoc.partsCostVnd,
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 0,
                      fieldName: dialogLoc.partsCost,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dialogLoc.selectWarrantyNote,
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: warrantyOptions
                        .map(
                          (opt) => ChoiceChip(
                            label: Text(opt, style: AppTextStyles.caption),
                            selected: selectedWarranty == opt,
                            onSelected: (_) =>
                                setS(() => selectedWarranty = opt),
                            selectedColor: AppColors.primary.withOpacity(0.2),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dialogLoc.confirmApproveDelivery,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(dialogLoc.cancel),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx, false);
                  // Từ chối - quay lại status 3
                  await _rejectDeliveryApproval();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(dialogLoc.reject),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(
                  dialogLoc.approve,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;

    // Cho phép quản lý/chủ shop chỉnh lại bảo hành trước khi duyệt
    r.price = MoneyUtils.parseCurrency(priceCtrl.text);
    r.cost = MoneyUtils.parseCurrency(costCtrl.text);
    r.requestedDeliveryPrice = null;
    r.warranty = selectedWarranty;
    final debtImpact = r.paymentMethod == "CÔNG NỢ";

    final user = FirebaseAuth.instance.currentUser;
    final userName = await _resolveCurrentStaffName(fallback: 'QL');
    final approverName = userName;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final requestedDeliveryAt = await _findDeliveryRequestedAt();

    r.deliveredAt = requestedDeliveryAt ?? nowMs;
    r.lastCaredAt = nowMs;
    r.isSynced = false;

    // Giữ người giao do nhân viên đã gửi yêu cầu; chỉ fallback về người duyệt nếu chưa có.
    if ((r.deliveredBy ?? '').trim().isEmpty) {
      r.deliveredBy = userName;
      r.deliveredByUid = user?.uid;
    }
    final deliveredByName = (r.deliveredBy ?? '').trim().isNotEmpty
        ? (r.deliveredBy ?? '').trim()
        : approverName;

    setState(() {
      r.status = 4; // Đã giao
      r.pendingDeliveryApproval = false; // Reset pending flag
      _isUpdating = true;
    });

    try {
      // Tạo công nợ nếu thanh toán công nợ
      if (r.paymentMethod == "CÔNG NỢ") {
        final debtFId =
            "debt_${DateTime.now().millisecondsSinceEpoch}_${r.phone.hashCode}";
        final debtData = {
          'personName': r.customerName,
          'phone': r.phone,
          'totalAmount': r.price,
          'paidAmount': 0,
          'type': "CUSTOMER_OWES",
          'status': "ACTIVE",
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'note': loc.debtNoteRepair(r.model),
          'linkedId': r.firestoreId,
          'firestoreId': debtFId,
        };
        final debtId = await db.insertDebt(debtData);
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: debtData,
        );

        // Công nợ đã ghi nhận ở bảng debts - không cần tạo PaymentIntent
        debugPrint(
          '✅ Repair debt recorded: $debtFId (no PaymentIntent needed)',
        );
      } else if (r.price > 0) {
        // Ghi nhận thu tiền sửa chữa trực tiếp
        final payResult = await PaymentIntentService.executePaymentDirect(
          type: PaymentIntentType.repairService,
          amount: r.price,
          paymentMethod: PaymentMethod.fromCode(r.paymentMethod),
          description: 'Thu tiền sửa máy: ${r.model} - ${r.customerName}',
          executedBy: user?.uid ?? 'unknown',
          referenceId: r.firestoreId,
          referenceType: 'repair',
          personName: r.customerName,
          personPhone: r.phone,
          idempotencyKey: r.firestoreId,
          metadata: {
            'repairId': r.id,
            'repairFirestoreId': r.firestoreId,
            'paymentMethod': r.paymentMethod,
            'model': r.model,
          },
        );
        debugPrint(
          '💳 Repair payment ${payResult.success ? "OK" : "FAILED"}: ${r.price}đ',
        );
      }

      await db.upsertRepair(r);

      try {
        await _pushRepairStatusToCloud(
          status: r.status,
          pendingApproval: r.pendingDeliveryApproval,
          finishedAt: r.finishedAt,
          deliveredAt: r.deliveredAt,
          repairedBy: r.repairedBy,
          repairedByUid: r.repairedByUid,
          deliveredBy: r.deliveredBy,
          deliveredByUid: r.deliveredByUid,
          paymentMethod: r.paymentMethod,
          requestedDeliveryPrice: null,
          includeRequestedDeliveryPrice: true,
        );
      } catch (e) {
        debugPrint(
          '⚠️ [RepairDetailView] Push approved delivery realtime lỗi: $e',
        );
      }

      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );

        // Await sync để tránh trạng thái pending kéo dài (nút sync vàng).
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
        // FIX: Also trigger targeted repair sync for reliability
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }

      // Log
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "DUYỆT GIAO MÁY",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: loc.approvedDelivery(r.model, r.customerName, r.warranty),
      );

      // Financial activity log (only for debt repairs - non-debt handled by PaymentIntentService)
      if (r.price > 0 && r.paymentMethod == 'CÔNG NỢ') {
        await FinancialActivityService.logRepair(
          firestoreId: r.firestoreId ?? 'repair_${r.createdAt}',
          amount: r.price,
          paymentMethod: r.paymentMethod,
          customerName: r.customerName,
          phone: r.phone,
          deviceModel: r.model,
          createdBy: user?.email,
        );
      }

      // Chat notification
      final key = r.firestoreId ?? "repair_${r.createdAt}";
      final summary = loc.repairOrderShare(
        r.customerName,
        r.phone,
        r.model,
        "${MoneyUtils.formatCurrency(r.price)}đ",
      );
      await FirestoreService.sendChat(
        message: loc.chatApprovedDelivery(summary),
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: summary,
      );

      // Push notification khi giao máy (status 4)
      try {
        final deliveredClock = DateFormat(
          'HH\'H\'mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!));
        await NotificationService.sendCloudNotification(
          title: '✅ ĐÃ DUYỆT GIAO MÁY • $deliveredClock',
          body:
              '👷 Giao: $deliveredByName • ⏰ $deliveredClock\n✅ Duyệt: $approverName\n👤 ${r.customerName} • 📱 ${r.model}\n💰 ${MoneyUtils.formatCurrency(r.price)}đ',
          type: 'new_order',
          data: {'targetType': 'repair', 'targetId': key, 'repairId': key},
        );
      } catch (e) {
        debugPrint('Failed to send delivery notification: $e');
      }

      NotificationService.showSnackBar(
        loc.approvedAndCompletedDelivery,
        color: Colors.green,
      );
      _emitRepairChanged(financialImpact: true, includeDebts: debtImpact);
      // Trở về danh sách đơn sửa sau khi duyệt giao
      if (mounted) Navigator.pop(context, true);
      return;
    } catch (e) {
      debugPrint('Error approving delivery: $e');
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  /// Từ chối duyệt giao - reset pendingDeliveryApproval
  Future<void> _rejectDeliveryApproval() async {
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.requestedDeliveryPrice = null;
    r.isSynced = false;

    setState(() {
      r.pendingDeliveryApproval =
          false; // Reset pending flag (giữ nguyên status 3)
      _isUpdating = true;
    });

    try {
      await db.upsertRepair(r);

      try {
        await _pushRepairStatusToCloud(
          status: r.status,
          pendingApproval: r.pendingDeliveryApproval,
          finishedAt: r.finishedAt,
          deliveredAt: r.deliveredAt,
          repairedBy: r.repairedBy,
          repairedByUid: r.repairedByUid,
          deliveredBy: r.deliveredBy,
          deliveredByUid: r.deliveredByUid,
          paymentMethod: r.paymentMethod,
          requestedDeliveryPrice: null,
          includeRequestedDeliveryPrice: true,
        );
      } catch (e) {
        debugPrint('⚠️ [RepairDetailView] Push reject realtime lỗi: $e');
      }

      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );

        // Await sync để tránh trạng thái pending kéo dài (nút sync vàng).
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
        // FIX: Also trigger targeted repair sync for reliability
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }

      final user = FirebaseAuth.instance.currentUser;
      final userName = await _resolveCurrentStaffName(fallback: 'QL');

      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "TỪ CHỐI GIAO",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: loc.rejectDeliveryDesc(r.model),
      );

      NotificationService.showSnackBar(
        loc.rejectedBackToRepairDone,
        color: Colors.red,
      );
      _emitRepairChanged();
    } catch (e) {
      debugPrint('Error rejecting delivery: $e');
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  Future<void> _saveData() async {
    if (!_ensureCanEditRepairOrder()) return;
    setState(() => _isUpdating = true);
    HapticFeedback.mediumImpact();
    try {
      final previousSnapshot = await _loadPersistedRepairSnapshot();
      final financialImpact = _hasFinancialImpact(previousSnapshot, r);
      var debtChanged = false;

      // Update lastCaredAt for conflict resolution during sync
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false; // Mark as needing sync

      await db.upsertRepair(r);

      // Ghi nhật ký sửa đơn
      final user = FirebaseAuth.instance.currentUser;
      final userName = await _resolveCurrentStaffName(fallback: 'NV');
      await db.logAction(
        userId: user?.uid ?? '0',
        userName: userName,
        action: loc.editRepairAction,
        type: 'REPAIR',
        targetId: r.firestoreId,
        desc:
            'Cập nhật đơn sửa ${r.model} - ${r.customerName} - Giá: ${r.price}đ',
      );

      // Queue sync repair to cloud via SyncOrchestrator
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );

        // Await sync so indicator turns green after save
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
      }

      // Update debt if payment method is debt and repair is delivered
      if (r.paymentMethod == 'CÔNG NỢ' && r.status == 4) {
        final existingDebts = await db.getAllDebts();
        final linkedDebt = existingDebts
            .where((d) => d['linkedId'] == r.firestoreId)
            .firstOrNull;
        final debtAmount = r.price - r.cost; // Profit amount
        if (linkedDebt != null) {
          // Update existing debt
          linkedDebt['amount'] = debtAmount;
          linkedDebt['remainingAmount'] =
              debtAmount - (linkedDebt['paidAmount'] ?? 0);
          linkedDebt['status'] = linkedDebt['remainingAmount'] > 0
              ? 'ACTIVE'
              : 'PAID';
          await db.updateDebt(linkedDebt);
          debtChanged = true;

          // Queue sync debt to cloud via SyncOrchestrator
          final debtId = linkedDebt['id'] as int?;
          if (debtId != null) {
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.debt,
              entityId: debtId,
              firestoreId: linkedDebt['firestoreId'] as String?,
              operation: SyncOperation.update,
              data: linkedDebt,
            );
          }
        }
        // Removed create new debt logic to avoid duplicates
      }

      NotificationService.showSnackBar(
        loc.savedOrderChanges,
        color: AppColors.success,
      );
      _emitRepairChanged(
        financialImpact: financialImpact || debtChanged,
        includeDebts: debtChanged,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        loc.errorSaving(e.toString()),
        color: AppColors.error,
      );
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  /// Lối tắt vào Kho Phụ Tùng (PartsInventoryView)
  Future<void> _navigateToPartsInventory() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final role = currentUser != null
        ? await UserService.getUserRole(currentUser.uid)
        : 'user';
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            InventoryView(role: role, initialFilterType: 'LINH_KIEN'),
      ),
    );
  }

  /// Lối tắt vào Đối Tác Sửa Chữa
  Future<void> _navigateToRepairPartners() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RepairPartnerView()),
    );
    if (!mounted) return;
    await _loadPartners();
  }

  /// Dialog chọn phụ tùng từ kho và tự động trừ kho
  /// LƯU Ý: Mỗi lần chọn và xác nhận sẽ THÊM vào đơn và TRỪ KHO ngay lập tức
  /// [skipWarning] = true khi gọi từ flow đổi PT (đã xác nhận ở bước trước)
  Future<void> _selectPartsFromInventory({bool skipWarning = false}) async {
    if (!_ensureCanEditRepairOrder()) return;
    // Hiển thị cảnh báo nếu đã có phụ tùng
    if (!skipWarning && r.partsUsed.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Text(loc.luuYTitle),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.orderAlreadyHasParts,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(r.partsUsed, style: const TextStyle(color: Colors.blue)),
              const SizedBox(height: 16),
              Text(
                loc.partsWillBeAddedAndDeducted,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.cancelButton),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text(
                loc.continueAddMore,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Lấy linh kiện từ CẢ 2 nguồn: repair_parts (kho cũ) + products type='LINH KIỆN' (kho mới)
    final parts = await db.getAllPartsUnified();
    if (parts.isEmpty) {
      // Thử load products để xem có nhưng chưa đánh đúng loại
      final allProducts = await db.getAllProducts();
      final linhKienProducts = allProducts
          .where((p) => p.type == 'LINH_KIEN')
          .toList();
      // phuKienProducts reserved for future use

      String msg = loc.partsInventoryEmpty;
      if (allProducts.isEmpty) {
        msg += loc.noProductsInInventory;
      } else {
        msg += loc.totalProductsLinhKien(
          allProducts.length,
          linhKienProducts.length,
        );
        if (linhKienProducts.isEmpty) {
          msg += loc.goToInventoryAddParts;
        }
      }

      NotificationService.showSnackBar(msg, color: Colors.orange);
      return;
    }

    // Hiển thị dialog chọn linh kiện
    final result = await showDialog<Map<String, int>?>(
      context: context,
      builder: (ctx) => _PartsSelectionDialog(
        parts: parts,
        onOpenPartsInventory: _navigateToPartsInventory,
      ),
    );

    if (result != null && result.isNotEmpty) {
      int totalCost = 0;
      List<String> usedParts = [];
      List<Map<String, dynamic>> selectedPartsInfo = [];

      for (var entry in result.entries) {
        final uniqueKey = entry.key;
        final qty = entry.value;

        // Parse uniqueKey = "source_id" (source có thể chứa underscore như "repair_parts")
        // Lấy phần cuối cùng sau dấu _ làm id
        final lastUnderscoreIndex = uniqueKey.lastIndexOf('_');
        final source = uniqueKey.substring(0, lastUnderscoreIndex);
        final partId = int.parse(uniqueKey.substring(lastUnderscoreIndex + 1));

        final part = parts.firstWhere(
          (p) => p['id'] == partId && p['source'] == source,
        );
        final partName = part['partName'] ?? '';
        final partCost = part['cost'] as int? ?? 0;
        final supplierName = part['supplier'] ?? part['supplierName'] ?? '';

        totalCost += partCost * qty;
        usedParts.add("$partName x$qty");
        selectedPartsInfo.add({
          'id': partId,
          'source': source,
          'name': partName,
          'cost': partCost,
          'qty': qty,
          'supplier': supplierName,
        });
      }

      // === KIỂM TRA NGUỒN LINH KIỆN ===
      // Linh kiện từ 'products' hoặc 'repair_parts' đều đã được thanh toán khi nhập kho
      // → KHÔNG cần hỏi thanh toán lại (chi phí đã ghi nhận khi nhập kho: công nợ/tiền mặt/CK)
      final allFromStock = selectedPartsInfo.every(
        (p) => p['source'] == 'products' || p['source'] == 'repair_parts',
      );

      // Tất cả linh kiện đều từ kho → không cần dialog thanh toán
      if (allFromStock) {
        // Cập nhật repair object trong bộ nhớ trước
        final currentParts =
            r.partsUsed.isEmpty ? <String>[] : r.partsUsed.split(', ');
        final newPartsList = [...currentParts, ...usedParts];
        r.partsUsed = newPartsList.join(', ');
        r.cost = r.cost + totalCost;
        r.isSynced = false;

        // === ATOMIC: trừ kho + cập nhật đơn sửa trong một SQLite transaction ===
        final atomicResult = await db.deductPartsAndUpdateRepairAtomic(
          parts: selectedPartsInfo,
          repair: r,
        );

        if (!atomicResult.success) {
          // Rollback repair object về trạng thái cũ
          r.partsUsed = currentParts.join(', ');
          r.cost = r.cost - totalCost;
          r.isSynced = true;
          NotificationService.showSnackBar(
            '❌ ${atomicResult.message ?? "Không thể trừ kho"}',
            color: Colors.red,
          );
          return;
        }

        // Sync Firestore cho từng part (best-effort, sau khi transaction SQLite đã commit)
        for (final p in atomicResult.partsToSync) {
          final fid = p['firestoreId'] as String?;
          if (fid == null || fid.isEmpty) continue;
          final collection = p['collection'] as String;
          final newQty = p['newQty'] as int;
          try {
            await FirebaseFirestore.instance
                .collection(collection)
                .doc(fid)
                .update({
                  'quantity': newQty,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
          } catch (e) {
            debugPrint('⚠️ Sync $collection/$fid failed: $e');
          }
        }

        if (r.firestoreId != null && r.id != null) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.repair,
            entityId: r.id!,
            firestoreId: r.firestoreId,
            operation: SyncOperation.update,
            data: r.toMap(),
          );
          try {
            await SyncOrchestrator().syncAll();
          } catch (_) {}
          // ignore: unawaited_futures
          SyncService.syncRepairData();
        }

        NotificationService.showSnackBar(
          loc.addedPartsFromInventoryMsg(usedParts.join(', ')),
          color: Colors.green,
        );

        setState(() {});
        _emitRepairChanged(financialImpact: true);
        return;
      }

      // === HỎI PHƯƠNG THỨC THANH TOÁN CHO PHỤ TÙNG (chỉ với repair_parts) ===
      final paymentResult = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (ctx) => _PartsPaymentDialog(
          totalCost: totalCost,
          partsDescription: usedParts.join(', '),
        ),
      );

      if (paymentResult == null) {
        // User hủy, không làm gì
        return;
      }

      final paymentMethod = paymentResult['method'] as String;
      final supplierName =
          paymentResult['supplier'] as String? ?? 'Nhà cung cấp phụ tùng';

      // Cập nhật repair trong bộ nhớ trước khi thực hiện atomic
      final prevPartsUsed = r.partsUsed;
      final prevCost = r.cost;
      if (r.partsUsed.isNotEmpty) {
        r.partsUsed = '${r.partsUsed}, ${usedParts.join(', ')}';
      } else {
        r.partsUsed = usedParts.join(', ');
      }
      r.cost += totalCost;
      r.isSynced = false;

      // === ATOMIC: trừ kho + cập nhật đơn sửa trong một SQLite transaction ===
      final atomicResult = await db.deductPartsAndUpdateRepairAtomic(
        parts: selectedPartsInfo,
        repair: r,
      );

      if (!atomicResult.success) {
        // Rollback repair object về trạng thái cũ
        r.partsUsed = prevPartsUsed;
        r.cost = prevCost;
        r.isSynced = true;
        NotificationService.showSnackBar(
          '❌ ${atomicResult.message ?? "Không thể trừ kho"}',
          color: Colors.red,
        );
        return;
      }

      // Sync Firestore cho từng part (best-effort)
      for (final p in atomicResult.partsToSync) {
        final fid = p['firestoreId'] as String?;
        if (fid == null || fid.isEmpty) continue;
        final collection = p['collection'] as String;
        final newQty = p['newQty'] as int;
        try {
          await FirebaseFirestore.instance
              .collection(collection)
              .doc(fid)
              .update({
                'quantity': newQty,
                'updatedAt': FieldValue.serverTimestamp(),
              });
        } catch (e) {
          debugPrint('⚠️ Sync $collection/$fid failed: $e');
        }
      }

      // === XỬ LÝ THANH TOÁN ===
      final now = DateTime.now().millisecondsSinceEpoch;
      final shopId = await UserService.getCurrentShopId() ?? '';

      if (paymentMethod == 'CÔNG NỢ') {
        // Tạo debt record - Shop nợ nhà cung cấp
        try {
          final debtFId = 'debt_parts_${now}_${r.id}';
          final partNamesDetailed = selectedPartsInfo
              .map((p) => '${p['name']} x${p['qty']} (${MoneyUtils.formatCurrency(p['cost'] as int? ?? 0)}đ/cái)')
              .join(', ');
          final debtData = {
            'firestoreId': debtFId,
            'type': 'SHOP_OWES',
            'debtType': 'SHOP_OWES',
            'personName': supplierName,
            'phone': '',
            'totalAmount': totalCost,
            'paidAmount': 0,
            'note':
                'Nợ phụ tùng: $partNamesDetailed = ${MoneyUtils.formatCurrency(totalCost)}đ - Đơn sửa ${r.model} (${r.customerName})',
            'status': 'ACTIVE',
            'createdAt': now,
            'shopId': shopId,
            'linkedId': r.firestoreId ?? '',
            'relatedPartId': '',
            'deleted': 0,
            'isSynced': 0,
          };
          final debtId = await db.insertDebt(debtData);

          if (debtId > 0) {
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.debt,
              entityId: debtId,
              firestoreId: debtFId,
              operation: SyncOperation.create,
              data: debtData,
            );
          }

          // Công nợ đã ghi nhận ở bảng debts - không cần PaymentIntent
          debugPrint('✅ Parts debt recorded: $debtFId');
          EventBus().emit('debts_changed');
          EventBus().emit(EventBus.financialChanged);
        } catch (e) {
          debugPrint('❌ Error creating parts debt: $e');
        }
      } else {
        // TIỀN MẶT hoặc CHUYỂN KHOẢN - ghi nhận thanh toán trực tiếp
        try {
          final payResult = await PaymentIntentService.executePaymentDirect(
            type: PaymentIntentType.repairPartnerDebt,
            amount: totalCost,
            paymentMethod: PaymentMethod.fromCode(paymentMethod),
            description:
                'Thanh toán phụ tùng: $supplierName - ${usedParts.join(', ')}',
            executedBy: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            referenceId: r.firestoreId,
            referenceType: 'parts_payment',
            personName: supplierName,
            idempotencyKey:
                'parts_${r.firestoreId}_${totalCost}_$paymentMethod',
            metadata: {
              'repairId': r.id,
              'repairFirestoreId': r.firestoreId,
              'parts': usedParts.join(', '),
              'paymentMethod': paymentMethod,
            },
          );
          debugPrint(
            '💳 Parts payment ${payResult.success ? "OK" : "FAILED"}: ${totalCost}đ',
          );
        } catch (e) {
          debugPrint('❌ Error creating parts payment intent: $e');
        }
      }

      // Đồng bộ đơn sửa lên cloud
      if (r.firestoreId != null && r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }

      setState(() {});

      NotificationService.showSnackBar(
        loc.addedPartsWithPayment(paymentMethod, usedParts.join(', ')),
        color: Colors.green,
      );
      _emitRepairChanged(financialImpact: true);
    }
  }

  /// Xóa phụ tùng khỏi đơn sửa chữa và trả lại kho
  Future<void> _removePartFromRepair() async {
    if (!_ensureCanEditRepairOrder()) return;
    if (r.partsUsed.isEmpty) {
      NotificationService.showSnackBar(
        'Đơn sửa chữa chưa có phụ tùng nào.',
        color: Colors.orange,
      );
      return;
    }

    // Parse partsUsed string: "PIN IPHONE 11 x1, MÀN HÌNH IP12 x2"
    final parts = r.partsUsed
        .split(', ')
        .where((p) => p.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return;

    // Show dialog to select which part to remove
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Text('XÓA PHỤ TÙNG', style: TextStyle(fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chọn phụ tùng cần xóa và trả lại kho:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...parts.asMap().entries.map((entry) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.build,
                      size: 18,
                      color: Colors.blue,
                    ),
                    title: Text(
                      entry.value,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => Navigator.pop(ctx, entry.key),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );

    if (selectedIndex == null) return;

    final removedPart = parts[selectedIndex];

    // Parse part name and quantity from "PART_NAME xQTY"
    String partName = removedPart;
    int partQty = 1;
    final xMatch = RegExp(r'^(.+)\s+x(\d+)$').firstMatch(removedPart);
    if (xMatch != null) {
      partName = xMatch.group(1)!.trim();
      partQty = int.tryParse(xMatch.group(2)!) ?? 1;
    }

    // Confirm
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Xóa "$removedPart" khỏi đơn sửa và trả lại $partQty vào kho?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'XÁC NHẬN XÓA',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Restore part quantity to inventory
    final restored = await db.restorePartQuantityByNameUnified(
      partName,
      partQty,
    );
    if (restored) {
      debugPrint('✅ Restored $partName x$partQty to inventory');
    } else {
      debugPrint('⚠️ Could not find part "$partName" in inventory to restore');
    }

    // 2. Estimate cost of the removed part (from parts data if possible)
    int removedCost = 0;
    final allParts = await db.getAllPartsUnified();
    for (final p in allParts) {
      final pName = (p['partName'] ?? '').toString().toUpperCase();
      if (pName == partName.toUpperCase()) {
        removedCost = (p['cost'] as int? ?? 0) * partQty;
        break;
      }
    }

    // 3. Update partsUsed string
    parts.removeAt(selectedIndex);
    r.partsUsed = parts.join(', ');

    // 4. Reduce cost
    r.cost = (r.cost - removedCost).clamp(0, r.cost);
    r.isSynced = false;
    await db.updateRepair(r);

    // 5. Sync
    if (r.firestoreId != null && r.id != null) {
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.repair,
        entityId: r.id!,
        firestoreId: r.firestoreId,
        operation: SyncOperation.update,
        data: r.toMap(),
      );
      try {
        await SyncOrchestrator().syncAll();
      } catch (_) {}
    }

    // 6. Log audit
    await AuditService.logAction(
      action: 'PART_REMOVED',
      entityType: 'repair',
      entityId: r.id?.toString() ?? '',
      summary:
          'Xóa phụ tùng: $removedPart (trả kho: ${restored ? "OK" : "Không tìm thấy"})',
      payload: {
        'partName': partName,
        'quantity': partQty,
        'removedCost': removedCost,
        'restored': restored,
      },
    );

    NotificationService.showSnackBar(
      'Đã xóa $removedPart${restored ? " và trả lại kho" : ""}',
      color: Colors.green,
    );
    _emitRepairChanged(financialImpact: true);

    if (mounted) setState(() {});
  }

  /// Đổi phụ tùng: xóa linh kiện cũ (trả kho) → chọn linh kiện mới thay thế
  Future<void> _swapPartInRepair() async {
    if (!_ensureCanEditRepairOrder()) return;
    if (r.partsUsed.isEmpty) {
      NotificationService.showSnackBar(
        'Đơn sửa chữa chưa có phụ tùng nào để đổi.',
        color: Colors.orange,
      );
      return;
    }

    // Parse partsUsed
    final parts = r.partsUsed
        .split(', ')
        .where((p) => p.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return;

    // Bước 1: Chọn phụ tùng cần đổi
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.deepPurple),
            SizedBox(width: 8),
            Expanded(
              child: Text('ĐỔI PHỤ TÙNG', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chọn phụ tùng cần đổi:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...parts.asMap().entries.map((entry) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.build,
                      size: 18,
                      color: Colors.blue,
                    ),
                    title: Text(
                      entry.value,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.swap_horiz,
                        color: Colors.deepPurple,
                      ),
                      onPressed: () => Navigator.pop(ctx, entry.key),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );

    if (selectedIndex == null) return;

    final removedPart = parts[selectedIndex];

    // Parse tên và số lượng: "PART_NAME xQTY"
    String partName = removedPart;
    int partQty = 1;
    final xMatch = RegExp(r'^(.+)\s+x(\d+)$').firstMatch(removedPart);
    if (xMatch != null) {
      partName = xMatch.group(1)!.trim();
      partQty = int.tryParse(xMatch.group(2)!) ?? 1;
    }

    // Bước 2: Xóa phụ tùng cũ + trả kho
    final restored = await db.restorePartQuantityByNameUnified(
      partName,
      partQty,
    );
    debugPrint(
      restored
          ? '✅ Đổi PT - Đã trả kho: $partName x$partQty'
          : '⚠️ Đổi PT - Không tìm thấy "$partName" trong kho để trả',
    );

    // Tính giá vốn phụ tùng bị xóa
    int removedCost = 0;
    final allParts = await db.getAllPartsUnified();
    for (final p in allParts) {
      final pName = (p['partName'] ?? '').toString().toUpperCase();
      if (pName == partName.toUpperCase()) {
        removedCost = (p['cost'] as int? ?? 0) * partQty;
        break;
      }
    }

    // Cập nhật repair: xóa phụ tùng cũ khỏi danh sách
    parts.removeAt(selectedIndex);
    r.partsUsed = parts.join(', ');
    r.cost = (r.cost - removedCost).clamp(0, r.cost);
    r.isSynced = false;
    await db.updateRepair(r);

    if (r.firestoreId != null && r.id != null) {
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.repair,
        entityId: r.id!,
        firestoreId: r.firestoreId,
        operation: SyncOperation.update,
        data: r.toMap(),
      );
      try {
        await SyncOrchestrator().syncAll();
      } catch (_) {}
    }

    // Log xóa
    await AuditService.logAction(
      action: 'PART_SWAP_REMOVE',
      entityType: 'repair',
      entityId: r.id?.toString() ?? '',
      summary:
          'Đổi PT - xóa: $removedPart (trả kho: ${restored ? "OK" : "Không tìm thấy"})',
      payload: {
        'partName': partName,
        'quantity': partQty,
        'removedCost': removedCost,
        'restored': restored,
      },
    );

    if (mounted) setState(() {});
    _emitRepairChanged(financialImpact: true);

    // Bước 3: Tự động mở dialog chọn phụ tùng mới (bỏ qua cảnh báo)
    if (!mounted) return;
    NotificationService.showSnackBar(
      'Đã xóa "$removedPart" — chọn phụ tùng thay thế.',
      color: Colors.blue,
    );
    await _selectPartsFromInventory(skipWarning: true);
  }

  Future<void> _editFinancials() async {
    if (!_ensureCanEditRepairFinancial()) {
      return;
    }

    if (!_canViewAnyFinancial) {
      NotificationService.showSnackBar(
        'Bạn không có quyền xem/chỉnh sửa tài chính',
        color: Colors.orange,
      );
      return;
    }

    // Lock editing when repair is delivered (status 4)
    if (r.status == 4) {
      NotificationService.showSnackBar(
        'Đã giao máy — không thể sửa giá',
        color: Colors.orange,
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final priceC = TextEditingController(
      text: CurrencyTextField.formatDisplay(r.price),
    );
    final costC = TextEditingController(
      text: CurrencyTextField.formatDisplay(r.cost),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(dialogLoc.repairOrderFinance),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CurrencyTextField(
                    controller: priceC,
                    label: dialogLoc.chargeCustomerVnd,
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 0,
                      fieldName: dialogLoc.chargeCustomerLabel,
                    ),
                  ),
                  if (_canViewCostPrice) ...[
                    const SizedBox(height: 12),
                    CurrencyTextField(
                      controller: costC,
                      label: dialogLoc.partsCostVnd,
                      validator: (v) => MoneyUtils.validateAmount(
                        v ?? '',
                        min: 0,
                        fieldName: dialogLoc.partsCost,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(dialogLoc.cancelButton),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  Navigator.pop(ctx, true);
                },
                child: Text(dialogLoc.saveButton),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      final parsedPrice = MoneyUtils.parseCurrency(priceC.text);
      final parsedCost = _canViewCostPrice
          ? MoneyUtils.parseCurrency(costC.text)
          : r.cost;
      final oldCost = r.cost;
      final wasFundRecorded = r.costRecordedInFund;

      // Update pricing
      setState(() {
        r.price = parsedPrice;
        r.cost = parsedCost;
      });

      // Show fund recording popup if cost > 0 and cost changed or not yet recorded
      if (parsedCost > 0 && (parsedCost != oldCost || !wasFundRecorded)) {
        await _showCostFundRecordingPopup(parsedCost);
      } else if (parsedCost == 0 && wasFundRecorded) {
        // Reset fund recording if cost is now 0
        setState(() {
          r.costRecordedInFund = false;
          r.costPaymentMethod = null;
          r.costRecordedAt = null;
          r.costRecordedAmount = 0;
        });
      }

      await _saveData();
    }
  }

  /// Show popup asking whether to record parts cost in cash fund
  Future<void> _showCostFundRecordingPopup(int costAmount) async {
    final fundResult = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('GHI VÀO SỔ QUỸ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chi phí vốn linh kiện: ${MoneyUtils.formatVND(costAmount)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ghi chi phí này vào sổ quỹ để cập nhật biến động quỹ tiền mặt / ngân hàng?',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'SKIP'),
            child: const Text('Không ghi'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'CHUYỂN KHOẢN'),
            icon: const Icon(Icons.account_balance, size: 18),
            label: const Text('Chuyển khoản'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'TIỀN MẶT'),
            icon: const Icon(Icons.payments, size: 18),
            label: const Text('Tiền mặt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (fundResult != null && fundResult != 'SKIP') {
      setState(() {
        r.costRecordedInFund = true;
        r.costPaymentMethod = fundResult;
        r.costRecordedAt = DateTime.now().millisecondsSinceEpoch;
        r.costRecordedAmount = costAmount;
      });
      NotificationService.showSnackBar(
        'Đã ghi ${MoneyUtils.formatVND(costAmount)} vào sổ quỹ ($fundResult)',
        color: Colors.green,
      );
    } else {
      setState(() {
        r.costRecordedInFund = false;
        r.costPaymentMethod = null;
        r.costRecordedAt = null;
        r.costRecordedAmount = 0;
      });
    }
  }

  /// Cho phép KTV ghi chú cho đơn sửa (vd: kt thay ic hay sàng main ...)
  Future<void> _editTechnicianNotes() async {
    if (!_ensureCanEditRepairOrder()) return;
    final notesC = TextEditingController(text: r.notes ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(dialogLoc.techNotesTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dialogLoc.repairProcessNotes,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesC,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: dialogLoc.techNotesHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dialogLoc.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(dialogLoc.save),
            ),
          ],
        );
      },
    );
    if (result == true) {
      setState(() {
        r.notes = notesC.text.trim().isEmpty ? null : notesC.text.trim();
      });
      _saveData();
      NotificationService.showSnackBar(
        loc.savedTechnicianNotes,
        color: Colors.green,
      );
    }
  }

  Future<void> _editBasicInfo() async {
    if (!_ensureCanEditRepairOrder()) return;
    if (r.status == 4) return; // Đã giao thì khóa chỉnh sửa

    final formKey = GlobalKey<FormState>();
    final nameC = TextEditingController(text: r.customerName);
    final phoneC = TextEditingController(text: r.phone);
    final modelC = TextEditingController(text: r.model);
    final issueC = TextEditingController(text: r.issue);
    final accC = TextEditingController(text: r.accessories);
    final warrantyC = TextEditingController(text: r.warranty);
    final addressC = TextEditingController(text: r.address);
    final notesC = TextEditingController(text: r.notes ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(dialogLoc.editOrderInfoTitle),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.customerNameLabel,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  TextFormField(
                    controller: phoneC,
                    decoration: InputDecoration(
                      labelText: r.isWalkIn
                          ? '${dialogLoc.phoneLabel} (không bắt buộc)'
                          : dialogLoc.phoneLabel,
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      // Khách vãng lai không bắt buộc nhập SĐT
                      if (r.isWalkIn && text.isEmpty) return null;
                      if (text.isEmpty) return dialogLoc.phoneRequired2;
                      final err = UserService.validatePhone(text, dialogLoc);
                      return err;
                    },
                  ),
                  TextFormField(
                    controller: modelC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.deviceModelLabel,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? dialogLoc.enterModelRequired
                        : null,
                  ),
                  TextFormField(
                    controller: issueC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.deviceIssueLabel,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? dialogLoc.enterIssueRequired
                        : null,
                  ),
                  TextFormField(
                    controller: accC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.accessoriesIncludedLabel,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  TextFormField(
                    controller: warrantyC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.warrantyLabel2,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  TextFormField(
                    controller: addressC,
                    decoration: InputDecoration(
                      labelText: dialogLoc.addressLabel2,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  TextFormField(
                    controller: notesC,
                    decoration: InputDecoration(labelText: dialogLoc.note),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dialogLoc.cancelButton),
            ),
            ElevatedButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx, true);
              },
              child: Text(dialogLoc.saveButton),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        r.customerName = nameC.text.trim().toUpperCase();
        r.phone = phoneC.text.trim();
        r.model = modelC.text.trim().toUpperCase();
        r.issue = issueC.text.trim().toUpperCase();
        r.accessories = accC.text.trim().toUpperCase();
        r.warranty = warrantyC.text.trim().toUpperCase();
        r.address = addressC.text.trim().toUpperCase();
        r.notes = notesC.text.trim().isNotEmpty ? notesC.text.trim() : null;
      });
      await _saveData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.repairDetailTitle)),
        body: Center(
          child: Text(
            loc.noAccessPermission,
            style: AppTextStyles.body1.copyWith(
              color: AppColors.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    final displayPrice = _displayedChargePrice(r);
    final displayProfit = displayPrice - r.cost;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2962FF),
                const Color(0xFF2962FF).withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Tooltip(
          message: loc.trackRepairProgress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.repairOrderDetail,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                r.model,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: _shareToZalo,
            icon: const Icon(Icons.share_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RepairInvoicePreviewView(
                    repair: r,
                    shopInfo: {
                      'shopName': _shopName,
                      'shopAddr': _shopAddr,
                      'shopPhone': _shopPhone,
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.preview, color: Colors.white),
          ),
          IconButton(
            onPressed: _printReceipt,
            icon: const Icon(Icons.print_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RepairInvoiceTemplateView(),
                ),
              );
            },
            icon: const Icon(Icons.design_services, color: Colors.white),
          ),
        ],
      ),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              // === COMPACT: Status + Actions gộp ===
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Status row
                      _buildCompactStatusRow(),
                      const SizedBox(height: 10),
                      // Action buttons
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ),

              // === COMPACT: Tài chính + Dịch vụ gộp ===
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header tài chính
                      if (_canViewAnyFinancial) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet,
                              size: 18,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              loc.financeTitleUpper,
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const Spacer(),
                            if (_canEditRepairFinancial)
                              TextButton.icon(
                                onPressed: _editFinancials,
                                icon: const Icon(Icons.edit, size: 14),
                                label: Text(loc.editButton),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_canViewCostPrice)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (displayProfit >= 0
                                                ? AppColors.success
                                                : AppColors.error)
                                            .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loc.profitLabel,
                                        style: AppTextStyles.overline.copyWith(
                                          color: displayProfit >= 0
                                              ? AppColors.success
                                              : AppColors.error,
                                        ),
                                      ),
                                      Text(
                                        "${MoneyUtils.formatCurrency(displayProfit)} đ",
                                        style: AppTextStyles.body2.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: displayProfit >= 0
                                              ? AppColors.success
                                              : AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_canViewCostPrice && _canViewRevenue)
                              const SizedBox(width: 8),
                            if (_canViewRevenue)
                              _miniFinCompact(
                                _displayedPriceLabel(r),
                                displayPrice,
                                AppColors.primary,
                              ),
                            if (_canViewRevenue && _canViewCostPrice)
                              const SizedBox(width: 8),
                            if (_canViewCostPrice)
                              _miniFinCompact(
                                loc.costLabel,
                                r.cost,
                                AppColors.warning,
                              ),
                          ],
                        ),
                        if (r.pendingDeliveryApproval &&
                            r.requestedDeliveryPrice != null) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Đang chờ duyệt giá yêu cầu: ${MoneyUtils.formatCurrency(displayPrice)} đ',
                              style: AppTextStyles.overline.copyWith(
                                color: Colors.deepOrange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        // Indicator: cost recorded in fund
                        if (_canViewCostPrice &&
                            r.costRecordedInFund &&
                            r.cost > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 12,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đã ghi sổ quỹ (${r.costPaymentMethod ?? ""})',
                                style: AppTextStyles.overline.copyWith(
                                  color: Colors.green.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      // Phụ tùng
                      if (r.partsUsed.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.build,
                              size: 14,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                loc.partsShort(r.partsUsed),
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.blue,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Quick actions
                      if (r.status < 4 && _canEditRepairOrder) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _quickAction(
                              loc.partsLabel,
                              Icons.inventory_2,
                              Colors.blue,
                              _selectPartsFromInventory,
                            ),
                            _quickAction(
                              loc.partsInventoryShort,
                              Icons.warehouse,
                              Colors.teal,
                              _navigateToPartsInventory,
                            ),
                            if (r.partsUsed.isNotEmpty)
                              _quickAction(
                                'Đổi PT',
                                Icons.swap_horiz,
                                Colors.deepPurple,
                                _swapPartInRepair,
                              ),
                            if (r.partsUsed.isNotEmpty)
                              _quickAction(
                                'Xóa PT',
                                Icons.delete_sweep,
                                Colors.red,
                                _removePartFromRepair,
                              ),
                            _quickAction(
                              loc.techShort,
                              Icons.note_add,
                              Colors.orange,
                              _editTechnicianNotes,
                            ),
                          ],
                        ),
                      ],

                      // Divider và Dịch vụ
                      const Divider(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.handyman,
                            size: 18,
                            color: Colors.teal.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            loc.servicesCount(r.services.length),
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                          const Spacer(),
                          if (r.status != 4 && _canEditRepairOrder)
                            TextButton.icon(
                              onPressed: _showAddServiceDialog,
                              icon: const Icon(Icons.add, size: 14),
                              label: Text(loc.add),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      if (r.services.isEmpty)
                        Text(
                          loc.noServicesYet,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onSurface.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        ...r.services.asMap().entries.map(
                          (e) => _buildCompactServiceItem(e.key, e.value),
                        ),
                      if (r.services.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                loc.totalServices,
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_canViewAnyFinancial)
                                Text(
                                  "${MoneyUtils.formatCurrency(r.services.fold(0, (sum, s) => sum + s.cost))} đ",
                                  style: AppTextStyles.body2.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.warning,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // === COMPACT: Khách hàng + Hình ảnh ===
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row: icon + tên + edit + call
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.customerName.toUpperCase(),
                              style: AppTextStyles.body2.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (r.status < 4 && _canEditRepairOrder)
                            IconButton(
                              onPressed: _editBasicInfo,
                              icon: const Icon(Icons.edit, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Chỉnh sửa thông tin',
                            ),
                          TextButton.icon(
                            onPressed: _callCustomer,
                            icon: const Icon(Icons.call, size: 14),
                            label: Text(r.phone, style: AppTextStyles.caption),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Info rows - hiển thị trực tiếp, không ẩn trong dropdown
                      _compactInfoRow(loc.deviceIssueLabel, r.issue),
                      _compactInfoRow(
                        'Nhận',
                        _formatStageActorWithTime(
                          actorRaw: r.createdBy,
                          timestamp: r.createdAt,
                        ),
                      ),
                      _compactInfoRow(
                        'Sửa',
                        _formatStageActorWithTime(
                          actorRaw: r.repairedBy,
                          timestamp: _repairStageTimestamp(r),
                        ),
                      ),
                      _compactInfoRow(
                        'Giao',
                        _formatStageActorWithTime(
                          actorRaw: r.deliveredBy,
                          timestamp: _deliveryStageTimestamp(r),
                        ),
                      ),
                      if (_hasModifierInfo)
                        _compactInfoRow('Sửa đổi', _formatModifierInfo()),
                      if (r.accessories.isNotEmpty)
                        _compactInfoRow("PK", r.accessories),
                      if (r.warranty.isNotEmpty)
                        _compactInfoRow(loc.warranty, r.warranty),
                      if (r.notes != null && r.notes!.isNotEmpty)
                        _compactInfoRow(loc.note, r.notes!),

                      // Hình ảnh
                      if (_displayableImages(r.receiveImages).isNotEmpty ||
                          (r.status < 4 && _canEditRepairOrder)) ...[
                        const Divider(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.photo_library,
                              size: 16,
                              color: Colors.pink.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              loc.imagesCount(
                                _displayableImages(r.receiveImages).length,
                              ),
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.pink.shade700,
                              ),
                            ),
                            const Spacer(),
                            if (r.status < 4 && _canEditRepairOrder)
                              GestureDetector(
                                onTap: _addReceiveImage,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.withAlpha(20),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.pink.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_a_photo, size: 13, color: Colors.pink.shade700),
                                      const SizedBox(width: 4),
                                      Text('Thêm ảnh', style: AppTextStyles.overline.copyWith(color: Colors.pink.shade700)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_displayableImages(r.receiveImages).isNotEmpty)
                        SizedBox(
                          height: 60,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _displayableImages(
                              r.receiveImages,
                            ).length,
                            itemBuilder: (ctx, i) => GestureDetector(
                              onTap: () => _showFullImage(
                                _displayableImages(r.receiveImages),
                                i,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                width: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _buildSmartImage(
                                    _displayableImages(r.receiveImages)[i],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  void _callCustomer() async {
    if (r.phone.isNotEmpty) {
      final uri = Uri.parse('tel:${r.phone}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<void> _addReceiveImage() async {
    if (!_canEditRepairOrder) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (picked == null) return;
    if (mounted) setState(() => _isUpdating = true);
    try {
      String? uploadedUrl;
      if (!kIsWeb) {
        uploadedUrl = await StorageService.uploadAndGetUrl(picked.path, 'repairs');
      } else {
        uploadedUrl = await StorageService.uploadXFileAndGetUrl(picked, 'repairs');
      }
      if (uploadedUrl == null) {
        NotificationService.showSnackBar('Tải ảnh lên thất bại', color: AppColors.error);
        return;
      }
      final existing = r.imagePath ?? '';
      final updated = existing.isEmpty ? uploadedUrl : '$existing,$uploadedUrl';
      r.imagePath = updated;
      r.isSynced = false;
      await db.upsertRepair(r);
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }
      if (mounted) setState(() {});
      NotificationService.showSnackBar('Đã thêm ảnh nhận máy', color: AppColors.success);
    } catch (e) {
      NotificationService.showSnackBar('Lỗi thêm ảnh: $e', color: AppColors.error);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // === COMPACT HELPER WIDGETS ===

  Widget _buildCompactStatusRow() {
    Color color;
    IconData icon;
    switch (r.status) {
      case 1:
        color = Colors.blue;
        icon = Icons.assignment_turned_in;
        break;
      case 2:
        color = Colors.orange;
        icon = Icons.build;
        break;
      case 3:
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case 4:
        color = AppColors.primary;
        icon = Icons.verified;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.model.toUpperCase(),
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getStatusText(
                  r.status,
                  pendingApproval: r.pendingDeliveryApproval,
                ),
                style: AppTextStyles.caption.copyWith(
                  color: _getStatusColor(
                    r.status,
                    pendingApproval: r.pendingDeliveryApproval,
                  ),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (r.pendingDeliveryApproval &&
                  r.requestedDeliveryPrice != null)
                Text(
                  'Giá yêu cầu: ${MoneyUtils.formatCurrency(r.requestedDeliveryPrice ?? 0)} đ',
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.deepOrange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniFinCompact(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.overline.copyWith(color: color, fontSize: 11),
          ),
          Text(
            MoneyUtils.formatCurrency(value),
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(color: color, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactServiceItem(int index, RepairService s) {
    return Container(
      margin: EdgeInsets.only(top: index > 0 ? 6 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_circle, size: 16, color: Colors.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.serviceName,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (s.partnerName != null)
                  Text(
                    loc.partnerLabel(s.partnerName!),
                    style: AppTextStyles.overline.copyWith(color: Colors.blue),
                  ),
              ],
            ),
          ),
          if (_canViewAnyFinancial)
            Text(
              "${MoneyUtils.formatCurrency(s.cost)} đ",
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
              ),
            ),
          if (r.status != 4 && _canEditRepairOrder)
            IconButton(
              icon: const Icon(Icons.edit, size: 14, color: Colors.grey),
              onPressed: () => _showAddServiceDialog(s, index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  Widget _compactInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              "$label:",
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTextStyles.caption)),
        ],
      ),
    );
  }

  Color _staffStageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'nhận':
        return AppColors.repairReceived;
      case 'sửa':
        return AppColors.repairRepairing;
      case 'xong':
        return AppColors.repairDone;
      case 'giao':
        return AppColors.primary;
      default:
        return AppColors.onSurface;
    }
  }

  Widget _staffInfoRow(String label, String value) {
    final color = _staffStageColor(label);
    final isUnknown = value.trim() == '---';
    return _infoRow(
      label,
      value,
      labelColor: color.withOpacity(0.9),
      valueColor: isUnknown ? AppColors.onSurface.withOpacity(0.55) : color,
      valueWeight: FontWeight.w700,
    );
  }

  int? _repairStageTimestamp(Repair rep) {
    if ((rep.finishedAt ?? 0) > 0) return rep.finishedAt;
    if ((rep.startedAt ?? 0) > 0) return rep.startedAt;
    return null;
  }

  int? _deliveryStageTimestamp(Repair rep) {
    if ((rep.deliveredAt ?? 0) > 0) return rep.deliveredAt;
    if ((rep.deliveredBy ?? '').trim().isEmpty) return null;

    if ((rep.lastCaredAt ?? 0) > 0) return rep.lastCaredAt;
    if ((rep.finishedAt ?? 0) > 0) return rep.finishedAt;
    return null;
  }

  String _formatStageActorWithTime({
    required String? actorRaw,
    required int? timestamp,
  }) {
    final actor = _staffLabel(actorRaw);
    final timeAndDay = _formatTimeAndDay(timestamp);

    if (actor == '---' && timeAndDay == '---') return '---';
    if (actor == '---') return timeAndDay;
    if (timeAndDay == '---') return actor;
    return '$actor  $timeAndDay';
  }

  String _formatTimeAndDay(int? timestamp) {
    if (timestamp == null || timestamp <= 0) return '---';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final time = DateFormat('HH:mm').format(dt);
    final day = DateFormat('dd/MM/yyyy').format(dt);
    return '$time - $day';
  }

  bool get _hasModifierInfo =>
      _lastModifiedBy != null && (_lastModifiedAt ?? 0) > 0;

  String _formatModifierInfo() {
    if (!_hasModifierInfo) return '---';
    return '${_lastModifiedBy!}  ${_formatTimeAndDay(_lastModifiedAt)}';
  }

  Widget _buildStatusCard() {
    Color color;
    IconData icon;

    switch (r.status) {
      case 1:
        color = Colors.blue;
        icon = Icons.assignment_turned_in;
        break;
      case 2:
        color = Colors.orange;
        icon = Icons.build;
        break;
      case 3:
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case 4:
        color = AppColors.primary;
        icon = Icons.verified;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.model.toUpperCase(), style: AppTextStyles.headline5),
                Text(
                  _getStatusText(
                    r.status,
                    pendingApproval: r.pendingDeliveryApproval,
                  ),
                  style: AppTextStyles.body2.copyWith(
                    color: _getStatusColor(
                      r.status,
                      pendingApproval: r.pendingDeliveryApproval,
                    ),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    debugPrint(
      '_buildActionButtons: status=${r.status}, pendingDeliveryApproval=${r.pendingDeliveryApproval}',
    );

    if (r.status == 4) return const SizedBox();

    if (r.status == 3 && r.pendingDeliveryApproval) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.deepOrange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.deepOrange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_empty, color: Colors.deepOrange.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.waitingManagerApproval,
                style: TextStyle(
                  color: Colors.deepOrange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (r.status == 3 && !r.pendingDeliveryApproval) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.repairDoneReadyForDelivery,
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Status < 3: nút ĐÃ XONG đã được dời xuống thanh hành động dưới cùng
    // để gom cùng LƯU/IN/ZALO trên một hàng.
    return const SizedBox.shrink();
  }

  Widget _buildFinancialContent() {
    final displayPrice = _displayedChargePrice(r);
    final displayProfit = displayPrice - r.cost;

    return Column(
      children: [
        if (_canViewCostPrice)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc.expectedProfit,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "${MoneyUtils.formatCurrency(displayProfit)} đ",
                style: AppTextStyles.headline5.copyWith(
                  color: displayProfit >= 0
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ],
          ),
        const Divider(height: 25),
        Row(
          children: [
            _miniFin(_displayedPriceLabel(r), displayPrice, AppColors.primary),
            if (_canViewCostPrice)
              _miniFin(loc.costLabel, r.cost, AppColors.warning),
          ],
        ),
        if (r.pendingDeliveryApproval && r.requestedDeliveryPrice != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Đang chờ duyệt giá yêu cầu: ${MoneyUtils.formatCurrency(displayPrice)} đ',
                style: AppTextStyles.overline.copyWith(
                  color: Colors.deepOrange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        // Hiển thị phụ tùng đã dùng
        if (r.partsUsed.isNotEmpty) ...[
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.build, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.partsUsedLabel(r.partsUsed),
                  style: AppTextStyles.caption.copyWith(color: Colors.blue),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        // Chỉ khóa các nút sửa khi ĐÃ GIAO (status 4)
        if (r.status < 4)
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _selectPartsFromInventory,
                icon: const Icon(
                  Icons.inventory_2,
                  size: 14,
                  color: Colors.blue,
                ),
                label: Text(
                  loc.partsLabel,
                  style: AppTextStyles.caption.copyWith(color: Colors.blue),
                ),
              ),
              // Lối tắt vào Kho Linh Kiện
              TextButton.icon(
                onPressed: _navigateToPartsInventory,
                icon: const Icon(Icons.warehouse, size: 14, color: Colors.teal),
                label: Text(
                  loc.partsInventoryShort,
                  style: AppTextStyles.caption.copyWith(color: Colors.teal),
                ),
              ),
              // Đổi phụ tùng chọn nhầm
              if (r.partsUsed.isNotEmpty)
                TextButton.icon(
                  onPressed: _swapPartInRepair,
                  icon: const Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: Colors.deepPurple,
                  ),
                  label: Text(
                    'Đổi PT',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              // Xóa phụ tùng đã chọn nhầm
              if (r.partsUsed.isNotEmpty)
                TextButton.icon(
                  onPressed: _removePartFromRepair,
                  icon: const Icon(
                    Icons.delete_sweep,
                    size: 14,
                    color: Colors.red,
                  ),
                  label: Text(
                    'Xóa PT',
                    style: AppTextStyles.caption.copyWith(color: Colors.red),
                  ),
                ),
              TextButton.icon(
                onPressed: _editTechnicianNotes,
                icon: const Icon(
                  Icons.note_add,
                  size: 14,
                  color: Colors.orange,
                ),
                label: Text(
                  loc.techShort,
                  style: AppTextStyles.caption.copyWith(color: Colors.orange),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildServicesContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with add button
        if (r.status != 4)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showAddServiceDialog,
              icon: const Icon(Icons.add, size: 18, color: Colors.blue),
              label: Text(
                loc.addServiceButton,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (r.services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              loc.noServicesMessage,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface.withOpacity(0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...r.services.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Container(
              margin: EdgeInsets.only(
                bottom: i < r.services.length - 1 ? 10 : 0,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.build_circle, size: 20, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.serviceName,
                          style: AppTextStyles.body2.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (s.partnerName != null)
                          Text(
                            loc.partnerLabel(s.partnerName!),
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    "${MoneyUtils.formatCurrency(s.cost)} đ",
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (r.status != 4)
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.grey,
                      ),
                      onPressed: () => _showAddServiceDialog(s, i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            );
          }),
        if (r.services.isNotEmpty) ...[
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc.totalServiceCost,
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "${MoneyUtils.formatCurrency(r.services.fold(0, (sum, s) => sum + s.cost))} đ",
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildImageContent() {
    final images = _displayableImages(r.receiveImages);
    if (images.isEmpty) {
      return Text(
        loc.noImages,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.onSurface.withOpacity(0.5),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _showFullImage(images, i),
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            width: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildSmartImage(images[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerContent() {
    return Column(
      children: [
        _infoRow(loc.customerLabel, r.customerName),
        _phoneRow(loc.phoneNumberLabel, r.phone),
        _infoRow(loc.deviceIssueLabel, r.issue),
        _staffInfoRow(
          'Nhận',
          _formatStageActorWithTime(
            actorRaw: r.createdBy,
            timestamp: r.createdAt,
          ),
        ),
        _staffInfoRow(
          'Sửa',
          _formatStageActorWithTime(
            actorRaw: r.repairedBy,
            timestamp: _repairStageTimestamp(r),
          ),
        ),
        _staffInfoRow(
          'Giao',
          _formatStageActorWithTime(
            actorRaw: r.deliveredBy,
            timestamp: _deliveryStageTimestamp(r),
          ),
        ),
        if (_hasModifierInfo) _infoRow('Sửa đổi', _formatModifierInfo()),
        _infoRow(
          loc.accessoriesLabel,
          r.accessories.isEmpty ? loc.noAccessories : r.accessories,
        ),
        _infoRow(loc.warranty, r.warranty.isEmpty ? loc.noneYet : r.warranty),
        if (r.notes != null && r.notes!.isNotEmpty)
          _infoRow(loc.note, r.notes!),
      ],
    );
  }

  Widget _buildFinancialSummary() {
    final displayPrice = _displayedChargePrice(r);
    final displayProfit = displayPrice - r.cost;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (_canViewCostPrice)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  loc.expectedProfit,
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${MoneyUtils.formatCurrency(displayProfit)} đ",
                  style: AppTextStyles.headline5.copyWith(
                    color: displayProfit >= 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ],
            ),
          const Divider(height: 25),
          Row(
            children: [
              _miniFin(
                _displayedPriceLabel(r),
                displayPrice,
                AppColors.primary,
              ),
              if (_canViewCostPrice)
                _miniFin(loc.costLabel, r.cost, AppColors.warning),
            ],
          ),
          if (r.pendingDeliveryApproval && r.requestedDeliveryPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Đang chờ duyệt giá yêu cầu: ${MoneyUtils.formatCurrency(displayPrice)} đ',
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.deepOrange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Hiển thị phụ tùng đã dùng
          if (r.partsUsed.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.build, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.partsUsedLabel(r.partsUsed),
                    style: AppTextStyles.caption.copyWith(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Chỉ khóa các nút sửa khi ĐÃ GIAO (status 4)
          if (r.status < 4)
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _selectPartsFromInventory,
                  icon: const Icon(
                    Icons.inventory_2,
                    size: 14,
                    color: Colors.blue,
                  ),
                  label: Text(
                    loc.partsLabel,
                    style: AppTextStyles.caption.copyWith(color: Colors.blue),
                  ),
                ),
                // Lối tắt vào Kho Linh Kiện
                TextButton.icon(
                  onPressed: _navigateToPartsInventory,
                  icon: const Icon(
                    Icons.warehouse,
                    size: 14,
                    color: Colors.teal,
                  ),
                  label: Text(
                    loc.partsInventoryShort,
                    style: AppTextStyles.caption.copyWith(color: Colors.teal),
                  ),
                ),
                // Đổi phụ tùng chọn nhầm
                if (r.partsUsed.isNotEmpty)
                  TextButton.icon(
                    onPressed: _swapPartInRepair,
                    icon: const Icon(
                      Icons.swap_horiz,
                      size: 14,
                      color: Colors.deepPurple,
                    ),
                    label: Text(
                      'Đổi PT',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                // Xóa phụ tùng đã chọn nhầm
                if (r.partsUsed.isNotEmpty)
                  TextButton.icon(
                    onPressed: _removePartFromRepair,
                    icon: const Icon(
                      Icons.delete_sweep,
                      size: 14,
                      color: Colors.red,
                    ),
                    label: Text(
                      'Xóa PT',
                      style: AppTextStyles.caption.copyWith(color: Colors.red),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _editFinancials,
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text(loc.editPrice, style: AppTextStyles.caption),
                ),
                TextButton.icon(
                  onPressed: _editTechnicianNotes,
                  icon: const Icon(
                    Icons.note_add,
                    size: 14,
                    color: Colors.orange,
                  ),
                  label: Text(
                    loc.techShort,
                    style: AppTextStyles.caption.copyWith(color: Colors.orange),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _miniFin(String l, int v, Color c) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          MoneyUtils.formatCurrency(v),
          style: AppTextStyles.body2.copyWith(
            color: c,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _buildServicesSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc.repairServices,
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Chỉ khóa nút thêm dịch vụ khi ĐÃ GIAO (status 4)
              if (r.status != 4)
                TextButton.icon(
                  onPressed: _showAddServiceDialog,
                  icon: const Icon(Icons.add, size: 18, color: Colors.blue),
                  label: Text(
                    loc.addService,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 16),
          if (r.services.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                loc.noServicesYet,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...r.services.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return Container(
                margin: EdgeInsets.only(
                  bottom: i < r.services.length - 1 ? 10 : 0,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.build_circle,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.serviceName,
                            style: AppTextStyles.body2.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (s.partnerName != null)
                            Text(
                              loc.partnerLabel(s.partnerName!),
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.blue,
                              ),
                            ),
                          if (s.partnerName != null && s.paymentMethod != null)
                            Text(
                              'TT: ${s.paymentMethod}',
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      "${MoneyUtils.formatCurrency(s.cost)} đ",
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Chỉ khóa nút sửa dịch vụ khi ĐÃ GIAO (status 4)
                    if (r.status != 4)
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: () => _showAddServiceDialog(s, i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              );
            }),
          if (r.services.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  loc.totalServiceCost,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${MoneyUtils.formatCurrency(r.services.fold(0, (sum, s) => sum + s.cost))} đ",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddServiceDialog([
    RepairService? editService,
    int? editIndex,
  ]) async {
    if (!_ensureCanEditRepairOrder()) return;
    await _loadPartners();
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final serviceCtrl = TextEditingController(
      text: editService?.serviceName ?? '',
    );
    final costCtrl = TextEditingController(
      text: editService != null
          ? MoneyUtils.formatCurrency(editService.cost)
          : '',
    );
    final availablePartners = List<RepairPartner>.from(_partners);

    RepairPartner? selectedPartner;
    if (editService != null &&
        editService.partnerId != null &&
        availablePartners.isNotEmpty) {
      for (final partner in availablePartners) {
        if (partner.id == editService.partnerId) {
          selectedPartner = partner;
          break;
        }
      }
    }

    // Phương thức thanh toán cho đối tác
    String? selectedPaymentMethod = editService?.paymentMethod;
    final paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];
    if (selectedPaymentMethod != null &&
        !paymentMethods.contains(selectedPaymentMethod)) {
      selectedPaymentMethod = null;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final dialogLoc = AppLocalizations.of(ctx)!;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  editService != null
                      ? dialogLoc.editService
                      : dialogLoc.addServiceTitle,
                ),
                // Lối tắt vào Đối Tác Sửa Chữa
                IconButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToRepairPartners();
                  },
                  icon: const Icon(Icons.group, color: Colors.teal, size: 20),
                  tooltip: dialogLoc.viewRepairPartners,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: serviceCtrl,
                      decoration: InputDecoration(
                        labelText: dialogLoc.serviceNameRequired,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? dialogLoc.pleaseEnterServiceName
                          : null,
                    ),
                    const SizedBox(height: 10),
                    CurrencyTextField(
                      controller: costCtrl,
                      label: dialogLoc.costVnd,
                      validator: (v) => MoneyUtils.validateAmount(
                        v ?? '',
                        min: 1,
                        fieldName: dialogLoc.costField,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (availablePartners.isNotEmpty)
                      DropdownButtonFormField<RepairPartner?>(
                        decoration: InputDecoration(
                          labelText: dialogLoc.partnerOptional2,
                        ),
                        key: ValueKey(selectedPartner?.id),
                        initialValue: selectedPartner,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(dialogLoc.noPartnerOption),
                          ),
                          ...availablePartners.map(
                            (p) =>
                                DropdownMenuItem(value: p, child: Text(p.name)),
                          ),
                        ],
                        onChanged: (p) => setS(() {
                          selectedPartner = p;
                          if (p == null) {
                            selectedPaymentMethod = null;
                          }
                        }),
                      ),
                    if (availablePartners.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chưa có đối tác sửa chữa để chọn.',
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _navigateToRepairPartners();
                              },
                              icon: const Icon(Icons.group, size: 16),
                              label: Text(dialogLoc.viewRepairPartners),
                            ),
                          ],
                        ),
                      ),
                    // Phương thức thanh toán (chỉ hiện khi có đối tác)
                    if (selectedPartner != null) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: dialogLoc.partnerPaymentMethodRequired,
                          prefixIcon: const Icon(Icons.payment, size: 20),
                        ),
                        initialValue: selectedPaymentMethod,
                        items: paymentMethods
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (v) => setS(() => selectedPaymentMethod = v),
                        validator: (v) =>
                            selectedPartner != null && (v == null || v.isEmpty)
                            ? dialogLoc.pleaseSelectPaymentMethod
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (editService != null)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _deleteService(editIndex!);
                  },
                  child: Text(
                    dialogLoc.delete,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(dialogLoc.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  // Không cần nhân 1000 - user đã nhập số đầy đủ với formatter
                  // Ví dụ: nhập "50.000" → parse ra 50000 VNĐ (đúng)
                  final cost = MoneyUtils.parseCurrency(costCtrl.text);
                  final service = RepairService(
                    firestoreId:
                        editService?.firestoreId ??
                        RepairPartnerService.generateServiceFirestoreId(),
                    serviceName: serviceCtrl.text.trim().toUpperCase(),
                    cost: cost,
                    partnerId: selectedPartner?.id,
                    partnerName: selectedPartner?.name,
                    paymentMethod: selectedPaymentMethod,
                  );
                  Navigator.pop(ctx);
                  await _saveService(service, editIndex);
                },
                child: Text(
                  editService != null ? dialogLoc.update : dialogLoc.add,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _repairOrderTrackingId() {
    final firestoreId = r.firestoreId?.trim();
    if (firestoreId != null && firestoreId.isNotEmpty) {
      return firestoreId;
    }
    return 'local_${r.id ?? 0}';
  }

  bool _didPartnerHistoryChange(
    RepairService? oldService,
    RepairService newService,
  ) {
    if (oldService == null) {
      return newService.partnerId != null;
    }
    return oldService.partnerId != newService.partnerId ||
        (oldService.serviceName.trim().toUpperCase() !=
            newService.serviceName.trim().toUpperCase()) ||
        oldService.cost != newService.cost;
  }

  bool _didPartnerFinancialStateChange(
    RepairService? oldService,
    RepairService newService,
  ) {
    if (oldService == null) {
      return newService.partnerId != null;
    }
    return oldService.partnerId != newService.partnerId ||
        oldService.cost != newService.cost ||
        (oldService.paymentMethod ?? '') != (newService.paymentMethod ?? '');
  }

  Future<void> _cleanupPartnerHistoryForService(RepairService service) async {
    if (service.partnerId == null) {
      return;
    }

    final normalizedServiceName = service.serviceName.trim().toUpperCase();
    final histories = await db.getPartnerRepairHistory(
      repairOrderId: _repairOrderTrackingId(),
    );
    final dbInstance = await db.database;

    for (final history in histories) {
      final samePartner = history['partnerId'] == service.partnerId;
      final sameIssue =
          (history['issue'] ?? '').toString().trim().toUpperCase() ==
          normalizedServiceName;
      final sameRepairContent =
          (history['repairContent'] ?? '').toString().trim().toUpperCase() ==
          normalizedServiceName;
      final sameCost =
          (history['partnerCost'] as num?)?.toInt() == service.cost;
      if (!samePartner || !sameIssue || !sameRepairContent || !sameCost) {
        continue;
      }

      final firestoreId = history['firestoreId']?.toString();
      if (firestoreId != null && firestoreId.isNotEmpty) {
        await db.deletePartnerRepairHistoryByFirestoreId(firestoreId);
        await FirestoreService.deletePartnerRepairHistoryByFirestoreId(
          firestoreId,
        );
        continue;
      }

      final localId = history['id'] as int?;
      if (localId != null) {
        await dbInstance.delete(
          'partner_repair_history',
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    }
  }

  Future<void> _deleteDebtSnapshot(Map<String, dynamic> debtRow) async {
    final debtFId = debtRow['firestoreId']?.toString();
    final localId = debtRow['id'] as int?;
    if (debtFId == null || debtFId.isEmpty || localId == null) {
      return;
    }

    await db.deleteDebtByFirestoreId(debtFId);
    await SyncOrchestrator().enqueue(
      entityType: SyncEntityType.debt,
      entityId: localId,
      firestoreId: debtFId,
      operation: SyncOperation.delete,
      data: {...debtRow, 'deleted': true},
    );
  }

  Future<void> _cleanupPartnerDebtForService(RepairService service) async {
    if (service.partnerId == null || (service.paymentMethod ?? '').isEmpty) {
      return;
    }

    final repairOrderId = _repairOrderTrackingId();
    final serviceFirestoreId = service.firestoreId?.trim();
    if (serviceFirestoreId != null && serviceFirestoreId.isNotEmpty) {
      final stableDebtId = RepairPartnerService.buildPartnerDebtFirestoreId(
        repairOrderId: repairOrderId,
        serviceFirestoreId: serviceFirestoreId,
        partnerId: service.partnerId!,
        partnerCost: service.cost,
      );
      final stableDebt = await db.getDebtByFirestoreId(stableDebtId);
      if (stableDebt != null) {
        await _deleteDebtSnapshot(stableDebt);
      }
    }

    final dbInstance = await db.database;
    final legacyRows = await dbInstance.query(
      'debts',
      where:
          'linkedId = ? AND relatedPartId = ? AND totalAmount = ? AND (deleted IS NULL OR deleted = 0)',
      whereArgs: [repairOrderId, service.partnerId.toString(), service.cost],
    );
    final serviceName = service.serviceName.trim().toUpperCase();
    final seenIds = <int>{};
    for (final row in legacyRows) {
      final localId = row['id'] as int?;
      if (localId == null || seenIds.contains(localId)) {
        continue;
      }
      final note = (row['note'] ?? '').toString().toUpperCase();
      if (!note.contains(serviceName)) {
        continue;
      }
      seenIds.add(localId);
      await _deleteDebtSnapshot(Map<String, dynamic>.from(row));
    }
  }

  Future<void> _deletePartnerPaymentSnapshot(
    Map<String, dynamic> paymentRow,
  ) async {
    final paymentFId = paymentRow['firestoreId']?.toString();
    final localId = paymentRow['id'] as int?;
    if (paymentFId == null || paymentFId.isEmpty || localId == null) {
      return;
    }

    await db.deleteRepairPartnerPaymentByFirestoreId(paymentFId);
    await SyncOrchestrator().enqueue(
      entityType: SyncEntityType.partnerPayment,
      entityId: localId,
      firestoreId: paymentFId,
      operation: SyncOperation.delete,
      data: {...paymentRow, 'deleted': true},
    );
  }

  Future<void> _cleanupPartnerDirectPaymentForService(
    RepairService service,
    int? legacyIndex,
  ) async {
    if (service.partnerId == null ||
        service.paymentMethod == null ||
        service.paymentMethod == 'CÔNG NỢ') {
      return;
    }

    final repairOrderId = _repairOrderTrackingId();
    final serviceFirestoreId = service.firestoreId?.trim();
    final keyCandidates = <String>{};

    if (serviceFirestoreId != null && serviceFirestoreId.isNotEmpty) {
      keyCandidates.add(
        RepairPartnerService.buildPartnerPaymentIdempotencyKey(
          repairOrderId: repairOrderId,
          serviceFirestoreId: serviceFirestoreId,
          partnerId: service.partnerId!,
          partnerCost: service.cost,
          paymentMethod: service.paymentMethod!,
        ),
      );
    }

    if (legacyIndex != null && r.firestoreId != null) {
      keyCandidates.add(
        'detail_${r.firestoreId}_${service.partnerId}_${legacyIndex}_${service.serviceName}_${service.cost}_${service.paymentMethod}',
      );
      keyCandidates.add(
        'create_${r.firestoreId}_${service.partnerId}_${legacyIndex}_${service.serviceName}_${service.cost}_${service.paymentMethod}',
      );
    }

    for (final key in keyCandidates) {
      final paymentFirestoreId =
          PaymentIntentService.buildDirectPaymentRecordFirestoreId(
            type: PaymentIntentType.repairPartnerDebt,
            idempotencyKey: key,
          );
      final intentId = PaymentIntentService.buildDirectPaymentIntentId(
        type: PaymentIntentType.repairPartnerDebt,
        idempotencyKey: key,
      );
      if (paymentFirestoreId == null || intentId == null) {
        continue;
      }

      final paymentRow = await db.getRepairPartnerPaymentByFirestoreId(
        paymentFirestoreId,
      );
      if (paymentRow != null) {
        await _deletePartnerPaymentSnapshot(paymentRow);
      }
      await db.deletePaymentIntent(intentId);
    }
  }

  Future<void> _cleanupPartnerServiceRecords(
    RepairService service,
    int? legacyIndex,
  ) async {
    await _cleanupPartnerHistoryForService(service);
    await _cleanupPartnerDebtForService(service);
    await _cleanupPartnerDirectPaymentForService(service, legacyIndex);
  }

  Future<void> _createPartnerFinancialRecordsForService(
    RepairService service,
  ) async {
    if (service.partnerId == null) {
      return;
    }

    final repairOrderId = _repairOrderTrackingId();
    final partnerService = RepairPartnerService();
    await partnerService.createPartnerHistoryForRepair(
      repairOrderId: repairOrderId,
      partnerId: service.partnerId!,
      partnerCost: service.cost,
      customerName: r.customerName,
      deviceModel: r.model,
      issue: service.serviceName,
      repairContent: service.serviceName,
    );

    if (service.paymentMethod == null || service.paymentMethod!.isEmpty) {
      return;
    }

    final serviceFirestoreId = service.firestoreId?.trim();
    if (serviceFirestoreId == null || serviceFirestoreId.isEmpty) {
      return;
    }

    final trackingNote = RepairPartnerService.buildPartnerTrackingNote(
      repairOrderId: repairOrderId,
      serviceFirestoreId: serviceFirestoreId,
      serviceName: service.serviceName,
      deviceModel: r.model,
      customerName: r.customerName,
      isDebt: service.paymentMethod == 'CÔNG NỢ',
    );

    if (service.paymentMethod != 'CÔNG NỢ') {
      final payResult = await PaymentIntentService.executePaymentDirect(
        type: PaymentIntentType.repairPartnerDebt,
        amount: service.cost,
        paymentMethod: PaymentMethod.fromCode(service.paymentMethod),
        description:
            'Trả đối tác: ${service.partnerName ?? "N/A"} - ${service.serviceName}',
        executedBy: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
        referenceId: repairOrderId,
        referenceType: 'repair_partner_service',
        personName: service.partnerName,
        notes: trackingNote,
        metadata: {
          'repairId': r.id,
          'repairFirestoreId': repairOrderId,
          'partnerId': service.partnerId,
          'partnerName': service.partnerName,
          'serviceName': service.serviceName,
          'paymentMethod': service.paymentMethod,
          'serviceFirestoreId': serviceFirestoreId,
        },
        idempotencyKey: RepairPartnerService.buildPartnerPaymentIdempotencyKey(
          repairOrderId: repairOrderId,
          serviceFirestoreId: serviceFirestoreId,
          partnerId: service.partnerId!,
          partnerCost: service.cost,
          paymentMethod: service.paymentMethod!,
        ),
      );
      debugPrint(
        '💳 Partner payment ${payResult.success ? "OK" : "FAILED"}: ${service.cost}đ',
      );
      return;
    }

    try {
      final shopId = await UserService.getCurrentShopId() ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;
      final debtFId = RepairPartnerService.buildPartnerDebtFirestoreId(
        repairOrderId: repairOrderId,
        serviceFirestoreId: serviceFirestoreId,
        partnerId: service.partnerId!,
        partnerCost: service.cost,
      );
      // Guard chống nhân đôi: nếu debt đã tồn tại với cùng firestoreId thì bỏ qua
      final existingDebt = await db.getDebtByFirestoreId(debtFId);
      if (existingDebt != null) {
        debugPrint('ℹ️ Partner debt đã tồn tại, bỏ qua tạo trùng: $debtFId');
        return;
      }
      final debtData = {
        'firestoreId': debtFId,
        'type': 'SHOP_OWES',
        'debtType': 'SHOP_OWES',
        'personName': service.partnerName ?? 'Đối tác sửa chữa',
        'phone': '',
        'totalAmount': service.cost,
        'paidAmount': 0,
        'note': trackingNote,
        'status': 'ACTIVE',
        'createdAt': now,
        'shopId': shopId,
        'linkedId': repairOrderId,
        'relatedPartId': service.partnerId?.toString() ?? '',
        'deleted': 0,
        'isSynced': 0,
      };
      final debtId = await db.insertDebt(debtData);
      if (debtId > 0) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: debtData,
        );
      }
      EventBus().emit('debts_changed');
      EventBus().emit(EventBus.financialChanged);
    } catch (e) {
      debugPrint('❌ Error creating partner debt: $e');
    }
  }

  Future<void> _saveService(RepairService service, int? editIndex) async {
    if (!_ensureCanEditRepairOrder()) return;
    setState(() => _isUpdating = true);
    try {
      final newServices = List<RepairService>.from(r.services);
      final oldService = editIndex != null ? newServices[editIndex] : null;
      final trackedService = service.copyWith(
        firestoreId:
            service.firestoreId ??
            oldService?.firestoreId ??
            RepairPartnerService.generateServiceFirestoreId(),
      );

      final shouldRefreshHistory =
          editIndex == null ||
          _didPartnerHistoryChange(oldService, trackedService);
      final shouldRefreshFinancials =
          editIndex == null ||
          _didPartnerFinancialStateChange(oldService, trackedService);

      if (editIndex != null && oldService != null) {
        if (shouldRefreshHistory || shouldRefreshFinancials) {
          await _cleanupPartnerServiceRecords(oldService, editIndex);
        }
      }

      if (editIndex != null) {
        newServices[editIndex] = trackedService;
      } else {
        newServices.add(trackedService);
      }
      final updatedCost =
          (r.cost - (oldService?.cost ?? 0) + trackedService.cost).clamp(
            0,
            999999999,
          );
      r.services = newServices;
      r.cost = updatedCost;
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false;
      await db.upsertRepair(r);

      if (trackedService.partnerId != null &&
          (shouldRefreshHistory || shouldRefreshFinancials)) {
        await _createPartnerFinancialRecordsForService(trackedService);
      }

      NotificationService.showSnackBar(
        editIndex != null ? loc.serviceUpdated : loc.serviceAdded,
        color: AppColors.success,
      );
      _emitRepairChanged(
        financialImpact: true,
        includeDebts: true,
        includeServiceChanges: true,
      );
      // FIX: Enqueue repair sync after saving service
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
        // ignore: unawaited_futures
        SyncOrchestrator().syncAll();
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }
    } catch (e) {
      NotificationService.showSnackBar(
        '${loc.error}: $e',
        color: AppColors.error,
      );
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  Future<void> _deleteService(int index) async {
    if (!_ensureCanEditRepairOrder()) return;
    setState(() => _isUpdating = true);
    try {
      final newServices = List<RepairService>.from(r.services);
      final removedService = newServices[index];
      await _cleanupPartnerServiceRecords(removedService, index);
      newServices.removeAt(index);
      r.services = newServices;
      r.cost = (r.cost - removedService.cost).clamp(0, 999999999);
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false;
      await db.upsertRepair(r);
      // FIX: Enqueue repair sync after deleting service
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
        // ignore: unawaited_futures
        SyncOrchestrator().syncAll();
        // ignore: unawaited_futures
        SyncService.syncRepairData();
      }
      NotificationService.showSnackBar(
        loc.serviceDeleted,
        color: AppColors.warning,
      );
      _emitRepairChanged(
        financialImpact: true,
        includeDebts: true,
        includeServiceChanges: true,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        '${loc.error}: $e',
        color: AppColors.error,
      );
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  Widget _buildImageGallery() {
    final images = _displayableImages(r.receiveImages);
    if (images.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.receivedImages,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _showFullImage(images, i),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildSmartImage(images[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showFullImage(List<String> images, int initialIndex) async {
    final resolvedImages = <String>[];
    for (final image in images) {
      final resolved = await _resolveDisplayImagePath(image);
      if (resolved != null && resolved.isNotEmpty) {
        resolvedImages.add(resolved);
      }
    }
    if (resolvedImages.isEmpty) return;
    final safeInitialIndex = initialIndex
        .clamp(0, resolvedImages.length - 1)
        .toInt();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              itemCount: resolvedImages.length,
              builder: (context, index) {
                final path = resolvedImages[index].trim();
                return PhotoViewGalleryPageOptions(
                  imageProvider:
                      (path.startsWith('http') ||
                          path.startsWith('blob:') ||
                          path.startsWith('data:'))
                      ? CachedNetworkImageProvider(path) as ImageProvider
                      : kIsWeb
                      ? CachedNetworkImageProvider(path) as ImageProvider
                      : FileImage(File(path)),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                );
              },
              pageController: PageController(initialPage: safeInitialIndex),
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _infoRow(loc.customerLabel, r.customerName),
          _phoneRow(loc.phoneNumberLabel, r.phone),
          _infoRow(loc.deviceIssueLabel, r.issue),
          _staffInfoRow(
            'Nhận',
            _formatStageActorWithTime(
              actorRaw: r.createdBy,
              timestamp: r.createdAt,
            ),
          ),
          _staffInfoRow(
            'Sửa',
            _formatStageActorWithTime(
              actorRaw: r.repairedBy,
              timestamp: _repairStageTimestamp(r),
            ),
          ),
          _staffInfoRow(
            'Giao',
            _formatStageActorWithTime(
              actorRaw: r.deliveredBy,
              timestamp: _deliveryStageTimestamp(r),
            ),
          ),
          if (_hasModifierInfo) _infoRow('Sửa đổi', _formatModifierInfo()),
          _infoRow(
            loc.accessoriesLabel,
            r.accessories.isEmpty ? loc.noAccessories : r.accessories,
          ),
          _infoRow(loc.warranty, r.warranty.isEmpty ? loc.noneYet : r.warranty),
          if (r.notes != null && r.notes!.isNotEmpty)
            _infoRow(loc.note, r.notes!),
        ],
      ),
    );
  }

  Widget _infoRow(
    String l,
    String v, {
    Color? labelColor,
    Color? valueColor,
    FontWeight? valueWeight,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppTextStyles.caption.copyWith(
            color: labelColor ?? AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            v,
            style: AppTextStyles.body2.copyWith(
              color: valueColor,
              fontWeight: valueWeight ?? FontWeight.bold,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    ),
  );

  Widget _phoneRow(String label, String phone) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        Row(
          children: [
            Text(
              phone,
              style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _dialPhone(phone),
              icon: const Icon(Icons.call, color: AppColors.success, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Gọi điện',
            ),
          ],
        ),
      ],
    ),
  );

  String _staffLabel(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return '---';
    if (value.contains('@')) {
      return value.split('@').first.toUpperCase();
    }
    return value.toUpperCase();
  }

  Future<void> _dialPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      NotificationService.showSnackBar(
        'Không thể gọi điện: $phone',
        color: Colors.red,
      );
    }
  }

  Widget _buildBottomActions() {
    const compactLabelStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 10,
      height: 1,
    );

    return FutureBuilder<String>(
      future: UserService.getRoleFast(),
      builder: (context, snapshot) {
        final role = snapshot.data ?? 'user';
        final isManager =
            role == 'admin' || role == 'owner' || role == 'manager';

        Widget? statusButton;
        if (r.status < 3) {
          statusButton = ElevatedButton.icon(
            onPressed: _isUpdating ? null : () => _updateStatus(3),
            icon: _isUpdating
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle, color: Colors.white, size: 14),
            label: const Text(
              'XONG',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        } else if (r.status == 3 && r.pendingDeliveryApproval) {
          if (isManager) {
            statusButton = ElevatedButton.icon(
              onPressed: _isUpdating ? null : _approveDelivery,
              icon: _isUpdating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified, color: Colors.white, size: 14),
              label: const Text(
                'DUYỆT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          } else {
            // Nhân viên đã gửi yêu cầu duyệt thì ẩn nút đổi trạng thái.
            statusButton = null;
          }
        } else if (r.status == 3) {
          if (isManager) {
            statusButton = ElevatedButton.icon(
              onPressed: _isUpdating ? null : () => _updateStatus(4),
              icon: _isUpdating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.local_shipping,
                      color: Colors.white,
                      size: 14,
                    ),
              label: const Text(
                'GIAO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          } else {
            statusButton = ElevatedButton.icon(
              onPressed: _isUpdating ? null : _submitForDeliveryApproval,
              icon: _isUpdating
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 14),
              label: const Text(
                'Y/C DUYỆT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (statusButton != null) ...[
                  Expanded(child: statusButton),
                  const SizedBox(width: 4),
                ],
                if (_canEditRepairOrder) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUpdating ? null : _saveData,
                      icon: _isUpdating
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded, size: 14),
                      label: const Text('LƯU', style: compactLabelStyle),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _printReceipt,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.print,
                            color: Colors.white,
                            size: 14,
                          ),
                    label: const Text(
                      'IN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareToZalo,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    label: const Text(
                      'ZALO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareToZalo() async {
    final sharePrice = _displayedChargePrice(r);
    final String content = loc.shareRepairReceipt(
      _shopName,
      r.model.toUpperCase(),
      r.customerName,
      r.phone,
      r.issue,
      r.warranty,
      '${MoneyUtils.formatCurrency(sharePrice)} đ',
    );
    await Share.share(content);
  }

  Future<void> _printReceipt() async {
    // Show printer selection dialog giống như in hóa đơn bán hàng
    final messenger = ScaffoldMessenger.of(context);
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return; // User cancelled

    // Extract printer configuration
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter =
        printerConfig['bluetoothPrinter'] as BluetoothPrinterConfig?;
    final wifiIp = printerConfig['wifiIp'] as String?;

    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    HapticFeedback.mediumImpact();
    NotificationService.showSnackBar(loc.preparingPrint, color: Colors.blue);

    try {
      final success = await UnifiedPrinterService.printRepairReceiptFromRepair(
        r,
        {'shopName': _shopName, 'shopAddr': _shopAddr, 'shopPhone': _shopPhone},
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );

      if (success) {
        NotificationService.showSnackBar(loc.printSuccess, color: Colors.green);
      } else {
        NotificationService.showSnackBar(loc.printFailed, color: Colors.red);
      }
    } catch (e) {
      NotificationService.showSnackBar(
        loc.printError(e.toString()),
        color: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }
}

/// Dialog widget riêng biệt để chọn linh kiện - tách ra để quản lý state đúng cách
class _PartsSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> parts;
  final Future<void> Function() onOpenPartsInventory;

  const _PartsSelectionDialog({
    required this.parts,
    required this.onOpenPartsInventory,
  });

  @override
  State<_PartsSelectionDialog> createState() => _PartsSelectionDialogState();
}

class _PartsSelectionDialogState extends State<_PartsSelectionDialog> {
  AppLocalizations get loc => AppLocalizations.of(context)!;
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, int> selectedQuantities = {};

  int get totalSelected => selectedQuantities.values.fold(0, (a, b) => a + b);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _searchCtrl.text.trim().toLowerCase();
    final filteredParts = widget.parts.where((p) {
      if (keyword.isEmpty) return true;
      final name = (p['partName'] ?? '').toString().toLowerCase();
      final supplier = (p['supplier'] ?? p['supplierName'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(keyword) || supplier.contains(keyword);
    }).toList();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.inventory_2, color: Colors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(loc.selectPartsTitle, style: AppTextStyles.headline3),
          ),
          // Shortcut to add new part from PartsInventoryView
          Material(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await widget.onOpenPartsInventory();
                // Refresh parts list after returning from PartsInventoryView
                if (mounted) {
                  final db = DBHelper();
                  final updatedParts = await db.getAllPartsUnified();
                  if (mounted) {
                    setState(() {
                      widget.parts
                        ..clear()
                        ..addAll(updatedParts);
                    });
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle,
                      color: Colors.orange.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'NHẬP LK MỚI',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: loc.searchPartOrSupplier,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredParts.isEmpty
                  ? Center(
                      child: Text(
                        loc.noPartsFound,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredParts.length,
                      itemBuilder: (context, index) {
                        final part = filteredParts[index];
                        final partId = part['id'] as int;
                        final source = part['source'] as String;
                        final uniqueKey = "${source}_$partId";
                        final partName = part['partName'] ?? '';
                        final partQty = part['quantity'] as int? ?? 0;
                        final partCost = part['cost'] as int? ?? 0;
                        final partPrice = part['price'] as int? ?? 0;
                        final supplier =
                            (part['supplier'] ?? part['supplierName'] ?? '')
                                .toString();
                        final isFromProducts = source == 'products';
                        final currentQty = selectedQuantities[uniqueKey] ?? 0;

                        return Card(
                          color: currentQty > 0
                              ? Colors.green.shade50
                              : (isFromProducts ? Colors.blue.shade50 : null),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dòng 1: Icon + Tên + Tag nguồn
                                Row(
                                  children: [
                                    Icon(
                                      isFromProducts
                                          ? Icons.inventory
                                          : Icons.build,
                                      color: isFromProducts
                                          ? Colors.blue
                                          : Colors.blue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        partName,
                                        style: AppTextStyles.subtitle1.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isFromProducts
                                            ? Colors.blue.withOpacity(0.2)
                                            : Colors.blue.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isFromProducts
                                            ? loc.mainWarehouse
                                            : loc.oldWarehouse,
                                        style: AppTextStyles.caption.copyWith(
                                          color: isFromProducts
                                              ? Colors.blue
                                              : Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Dòng 2: Supplier + tồn + giá
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (supplier.isNotEmpty)
                                      Chip(
                                        label: Text(
                                          supplier,
                                          style: AppTextStyles.caption,
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    Text(
                                      loc.stockQty(partQty),
                                      style: AppTextStyles.body2.copyWith(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    Text(
                                      loc.costPrice(
                                        MoneyUtils.formatCurrency(partCost),
                                      ),
                                      style: AppTextStyles.caption,
                                    ),
                                    Text(
                                      loc.sellPrice(
                                        MoneyUtils.formatCurrency(partPrice),
                                      ),
                                      style: AppTextStyles.caption,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Dòng 3: Nút +/- (compact hơn)
                                if (partQty > 0)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Nút trừ (nhỏ gọn hơn)
                                      Material(
                                        color: currentQty > 0
                                            ? Colors.red
                                            : Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(5),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                          onTap: currentQty > 0
                                              ? () {
                                                  setState(() {
                                                    if (currentQty <= 1) {
                                                      selectedQuantities.remove(
                                                        uniqueKey,
                                                      );
                                                    } else {
                                                      selectedQuantities[uniqueKey] =
                                                          currentQty - 1;
                                                    }
                                                  });
                                                }
                                              : null,
                                          child: Container(
                                            width: 26,
                                            height: 22,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.remove,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Số lượng
                                      Container(
                                        width: 38,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$currentQty',
                                          style: AppTextStyles.caption.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: currentQty > 0
                                                ? Colors.green.shade700
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                      // Nút cộng (nhỏ gọn hơn)
                                      Material(
                                        color: currentQty < partQty
                                            ? Colors.green
                                            : Colors.grey.shade300,
                                        borderRadius: BorderRadius.circular(5),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                          onTap: currentQty < partQty
                                              ? () {
                                                  setState(() {
                                                    selectedQuantities[uniqueKey] =
                                                        currentQty + 1;
                                                  });
                                                }
                                              : null,
                                          child: Container(
                                            width: 26,
                                            height: 22,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.add,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      loc.outOfStock,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(loc.cancel),
        ),
        ElevatedButton(
          onPressed: totalSelected > 0
              ? () => Navigator.pop(
                  context,
                  Map<String, int>.from(selectedQuantities),
                )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            disabledBackgroundColor: Colors.grey.shade300,
          ),
          child: Text(
            totalSelected > 0 ? loc.confirmQty(totalSelected) : loc.confirmBtn,
            style: TextStyle(
              color: totalSelected > 0 ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog chọn phương thức thanh toán cho phụ tùng
class _PartsPaymentDialog extends StatefulWidget {
  final int totalCost;
  final String partsDescription;

  const _PartsPaymentDialog({
    required this.totalCost,
    required this.partsDescription,
  });

  @override
  State<_PartsPaymentDialog> createState() => _PartsPaymentDialogState();
}

class _PartsPaymentDialogState extends State<_PartsPaymentDialog> {
  String _selectedMethod = 'TIỀN MẶT';
  final _supplierController = TextEditingController();

  AppLocalizations get loc => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _supplierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.payment, color: Colors.green),
          const SizedBox(width: 10),
          Text(loc.partsPaymentTitle, style: const TextStyle(fontSize: 17)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tổng tiền
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    loc.totalPartsAmount,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${MoneyUtils.formatCurrency(widget.totalCost)} đ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Mô tả phụ tùng
            Text(
              loc.partsDesc(widget.partsDescription),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Nhập tên nhà cung cấp
            TextField(
              controller: _supplierController,
              decoration: InputDecoration(
                labelText: loc.supplierOptional,
                hintText: loc.supplierHint,
                prefixIcon: const Icon(Icons.store, size: 20),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Chọn phương thức thanh toán
            Text(
              loc.paymentMethodLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            // Radio buttons
            _buildPaymentOption('TIỀN MẶT', Icons.money, Colors.green),
            _buildPaymentOption(
              'CHUYỂN KHOẢN',
              Icons.account_balance,
              Colors.blue,
            ),
            _buildPaymentOption('CÔNG NỢ', Icons.access_time, Colors.orange),

            // Cảnh báo nếu chọn công nợ
            if (_selectedMethod == 'CÔNG NỢ')
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.debtWarning,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(loc.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'method': _selectedMethod,
              'supplier': _supplierController.text.trim().isEmpty
                  ? loc.defaultPartsSupplier
                  : _supplierController.text.trim().toUpperCase(),
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedMethod == 'CÔNG NỢ'
                ? Colors.orange
                : Colors.green,
          ),
          child: Text(
            _selectedMethod == 'CÔNG NỢ' ? loc.recordDebt : loc.confirm,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentOption(String method, IconData icon, Color color) {
    final isSelected = _selectedMethod == method;
    return InkWell(
      onTap: () => setState(() => _selectedMethod = method),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 10),
            Text(
              method,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.black87,
              ),
            ),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
