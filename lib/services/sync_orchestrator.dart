import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/db_helper.dart';
import 'storage_service.dart';
import 'user_service.dart';

/// Enum định nghĩa các loại entity được sync
enum SyncEntityType {
  repair,
  sale,
  product,
  expense,
  debt,
  customer,
  supplier,
  attendance,
  repairPart,
  quickInputCode,
  debtPayment,
  supplierPayment,
  partnerPayment,
  repairPartner,
  auditLog,
  cashClosing,
  adjustmentEntry,
  purchaseOrder,
  supplierImportHistory, // FIX BUG-001: Thêm entity type cho supplier import history
  salvagePhone,
}

/// Enum định nghĩa operation
enum SyncOperation { create, update, delete }

/// Model cho sync queue item
class SyncQueueItem {
  final int? id;
  final SyncEntityType entityType;
  final int entityId;
  final String? firestoreId;
  final SyncOperation operation;
  final Map<String, dynamic>? data;
  final int createdAt;
  final int retryCount;
  final String? lastError;
  final String status; // pending, processing, completed, failed

  SyncQueueItem({
    this.id,
    required this.entityType,
    required this.entityId,
    this.firestoreId,
    required this.operation,
    this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'entityType': entityType.name,
      'entityId': entityId,
      'firestoreId': firestoreId,
      'operation': operation.name,
      'data': data != null ? jsonEncode(data) : null,
      'createdAt': createdAt,
      'retryCount': retryCount,
      'lastError': lastError,
      'status': status,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as int?,
      entityType: SyncEntityType.values.firstWhere(
        (e) => e.name == map['entityType'],
        orElse: () => SyncEntityType.repair,
      ),
      entityId: map['entityId'] as int,
      firestoreId: map['firestoreId'] as String?,
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == map['operation'],
        orElse: () => SyncOperation.create,
      ),
      data: map['data'] != null ? jsonDecode(map['data'] as String) : null,
      createdAt: map['createdAt'] as int,
      retryCount: map['retryCount'] as int? ?? 0,
      lastError: map['lastError'] as String?,
      status: map['status'] as String? ?? 'pending',
    );
  }

  SyncQueueItem copyWith({
    int? id,
    SyncEntityType? entityType,
    int? entityId,
    String? firestoreId,
    SyncOperation? operation,
    Map<String, dynamic>? data,
    int? createdAt,
    int? retryCount,
    String? lastError,
    String? status,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      firestoreId: firestoreId ?? this.firestoreId,
      operation: operation ?? this.operation,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      status: status ?? this.status,
    );
  }
}

/// Service quản lý đồng bộ dữ liệu local -> cloud
class SyncOrchestrator {
  static final SyncOrchestrator _instance = SyncOrchestrator._internal();
  factory SyncOrchestrator() => _instance;
  SyncOrchestrator._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DBHelper _db = DBHelper();

  // Stream controller để notify UI về pending count
  final _pendingCountController = StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  // Stream controller để notify UI về sync status
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  // Connectivity subscription
  StreamSubscription? _connectivitySubscription;

  // Current pending count cache
  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  // Is syncing flag
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  static List<String> _splitImagePaths(String? csv) {
    if (csv == null) return const [];
    final raw = csv.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool _isCloudImagePath(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://');
  }

  Future<void> _normalizeRepairImagePathsForCloud(Map<String, dynamic> data) async {
    final rawImagePath = data['imagePath'];
    if (rawImagePath == null) return;

    final allPaths = _splitImagePaths(rawImagePath.toString());
    if (allPaths.isEmpty) {
      data['imagePath'] = '';
      return;
    }

    final cloudPaths = allPaths.where(_isCloudImagePath).toList();
    final localPaths = allPaths.where((p) => !_isCloudImagePath(p)).toList();

    if (localPaths.isEmpty) {
      data['imagePath'] = cloudPaths.join(',');
      return;
    }

    final folderSuffix = (data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch)
        .toString();
    final uploadedUrls = await StorageService.uploadMultipleImages(
      localPaths,
      'repairs/$folderSuffix',
    );

    if (uploadedUrls.length < localPaths.length) {
      throw Exception(
        'Repair images not fully uploaded (${uploadedUrls.length}/${localPaths.length}), keep in queue for retry',
      );
    }

    data['imagePath'] = [...cloudPaths, ...uploadedUrls].join(',');
  }

  // Max retry before marking as failed
  static const int maxRetries = 3;

  static bool _isPermanentSyncError(String error) {
    final normalized = error.toLowerCase();
    return normalized.contains('permission-denied') ||
        normalized.contains('permission_denied') ||
        normalized.contains('missing or insufficient permissions');
  }

  /// Khởi tạo orchestrator
  Future<void> init() async {
    debugPrint('🔄 SyncOrchestrator: Initializing...');

    // Load initial pending count
    await _refreshPendingCount();
    await _emitCurrentStatus();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection && _pendingCount > 0) {
        debugPrint('🔄 SyncOrchestrator: Network restored, auto-syncing...');
        // Auto sync when network is restored
        syncAll();
      }
    });

    debugPrint(
      '🔄 SyncOrchestrator: Initialized with $_pendingCount pending items',
    );
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _pendingCountController.close();
    _syncStatusController.close();
  }

  /// Thêm item vào sync queue
  Future<void> enqueue({
    required SyncEntityType entityType,
    required int entityId,
    String? firestoreId,
    required SyncOperation operation,
    Map<String, dynamic>? data,
    bool allowReviveFailed = false,
  }) async {
    final db = await _db.database;

    // Check if already exists in queue
    final existing = await db.query(
      'sync_queue',
      where: 'entityType = ? AND entityId = ?',
      whereArgs: [entityType.name, entityId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingStatus = existing.first['status'] as String? ?? 'pending';

      if (existingStatus == 'failed' && !allowReviveFailed) {
        debugPrint(
          '🔄 SyncOrchestrator: Skip auto-enqueue for failed ${entityType.name}#$entityId',
        );
        await _refreshPendingCount();
        await _emitCurrentStatus();
        return;
      }

      // Update existing entry
      await db.update(
        'sync_queue',
        {
          'operation': operation.name,
          'data': data != null ? jsonEncode(data) : null,
          'firestoreId': firestoreId,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'status': 'pending',
          'retryCount': 0,
          'lastError': null,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      debugPrint(
        '🔄 SyncOrchestrator: Updated existing queue item for ${entityType.name}#$entityId',
      );
    } else {
      // Create new entry
      final item = SyncQueueItem(
        entityType: entityType,
        entityId: entityId,
        firestoreId: firestoreId,
        operation: operation,
        data: data,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await db.insert('sync_queue', item.toMap());
      debugPrint(
        '🔄 SyncOrchestrator: Enqueued ${entityType.name}#$entityId (${operation.name})',
      );
    }

    await _refreshPendingCount();
    await _emitCurrentStatus();
  }

  /// Lấy số lượng pending
  Future<int> getPendingCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status IN ('pending', 'processing')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Lấy danh sách pending items
  Future<List<SyncQueueItem>> getPendingItems({int limit = 50}) async {
    final db = await _db.database;
    final results = await db.query(
      'sync_queue',
      where: "status IN ('pending', 'processing')",
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    return results.map((r) => SyncQueueItem.fromMap(r)).toList();
  }

  /// Sync tất cả pending items
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      debugPrint('🔄 SyncOrchestrator: Already syncing, skipping...');
      return SyncResult(success: 0, failed: 0, total: 0, skipped: true);
    }

    // Check connectivity
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasConnection = connectivityResults.any(
      (r) => r != ConnectivityResult.none,
    );
    if (!hasConnection) {
      debugPrint('🔄 SyncOrchestrator: No network, skipping sync');
      _syncStatusController.add(SyncStatus.noNetwork);
      return SyncResult(success: 0, failed: 0, total: 0, noNetwork: true);
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    int successCount = 0;
    int failedCount = 0;

    try {
      final items = await getPendingItems();
      debugPrint('🔄 SyncOrchestrator: Starting sync of ${items.length} items');

      for (final item in items) {
        try {
          await _processSyncItem(item);
          successCount++;
        } catch (e) {
          debugPrint(
            '🔄 SyncOrchestrator: Failed to sync ${item.entityType.name}#${item.entityId}: $e',
          );
          await _markItemFailed(item, e.toString());
          failedCount++;
        }
      }

      debugPrint(
        '🔄 SyncOrchestrator: Sync completed - success: $successCount, failed: $failedCount',
      );

      await _refreshPendingCount();
      await _emitCurrentStatus();

      return SyncResult(
        success: successCount,
        failed: failedCount,
        total: items.length,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Process single sync item
  Future<void> _processSyncItem(SyncQueueItem item) async {
    final db = await _db.database;

    // Mark as processing
    await db.update(
      'sync_queue',
      {'status': 'processing'},
      where: 'id = ?',
      whereArgs: [item.id],
    );

    // Retry logic cho shopId - shop mới có thể chưa có claims
    String? shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      debugPrint('🔄 SyncOrchestrator: shopId null, retrying with claims refresh...');
      // Thử refresh claims cho shop mới
      try {
        await UserService.syncUserInfo(
          FirebaseAuth.instance.currentUser?.uid ?? '',
          FirebaseAuth.instance.currentUser?.email ?? '',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        shopId = await UserService.getCurrentShopId();
      } catch (e) {
        debugPrint('🔄 SyncOrchestrator: Claims refresh failed: $e');
      }
      
      if (shopId == null) {
        throw Exception('No shopId available after retry');
      }
    }

    String? newFirestoreId;

    switch (item.operation) {
      case SyncOperation.create:
        newFirestoreId = await _handleCreate(item, shopId);
        break;
      case SyncOperation.update:
        await _handleUpdate(item, shopId);
        break;
      case SyncOperation.delete:
        await _handleDelete(item, shopId);
        break;
    }

    // Mark as completed and remove from queue
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [item.id]);

    // Update local entity with firestoreId if created
    if (newFirestoreId != null && item.operation == SyncOperation.create) {
      await _updateLocalFirestoreId(
        item.entityType,
        item.entityId,
        newFirestoreId,
      );
    }

    // Mark local entity as synced
    await _markLocalAsSynced(item.entityType, item.entityId);

    debugPrint(
      '🔄 SyncOrchestrator: Successfully synced ${item.entityType.name}#${item.entityId}',
    );
  }

  /// Handle create operation
  Future<String> _handleCreate(SyncQueueItem item, String shopId) async {
    final collection = _getCollectionName(item.entityType);
    if (collection == null) {
      throw Exception('Unknown entity type: ${item.entityType}');
    }

    final data =
        item.data ?? await _getEntityData(item.entityType, item.entityId);
    if (data == null) {
      throw Exception(
        'No data found for ${item.entityType.name}#${item.entityId}',
      );
    }

    // Add shopId if not present
    data['shopId'] = shopId;
    data['updatedAt'] = FieldValue.serverTimestamp();

    // Ensure web-compatible image URLs are stored for repairs.
    if (item.entityType == SyncEntityType.repair) {
      await _normalizeRepairImagePathsForCloud(data);
    }

    // Remove local-only fields
    data.remove('id');
    data.remove('isSynced');

    // FIX: Sử dụng firestoreId đã có (local-generated) làm document ID
    // thay vì để Firestore auto-generate, tránh race condition với realtime listener
    final existingFirestoreId =
        item.firestoreId ?? data['firestoreId'] as String?;

    if (existingFirestoreId != null && existingFirestoreId.isNotEmpty) {
      // Set document với ID đã có sẵn
      data.remove('firestoreId'); // Không lưu field này, dùng document ID
      await _firestore
          .collection(collection)
          .doc(existingFirestoreId)
          .set(data);
      debugPrint(
        '🔄 SyncOrchestrator: Created doc with existing ID: $existingFirestoreId',
      );
      return existingFirestoreId;
    } else {
      // Fallback: auto-generate ID nếu không có
      final docRef = await _firestore.collection(collection).add(data);
      debugPrint(
        '🔄 SyncOrchestrator: Created doc with auto-generated ID: ${docRef.id}',
      );
      return docRef.id;
    }
  }

  /// Handle update operation
  Future<void> _handleUpdate(SyncQueueItem item, String shopId) async {
    if (item.firestoreId == null) {
      // No firestoreId means this was created offline, create instead
      final newId = await _handleCreate(item, shopId);
      await _updateLocalFirestoreId(item.entityType, item.entityId, newId);
      return;
    }

    final collection = _getCollectionName(item.entityType);
    if (collection == null) {
      throw Exception('Unknown entity type: ${item.entityType}');
    }

    final data =
        item.data ?? await _getEntityData(item.entityType, item.entityId);
    if (data == null) {
      throw Exception(
        'No data found for ${item.entityType.name}#${item.entityId}',
      );
    }

    // Add shopId and timestamp
    data['shopId'] = shopId;
    data['updatedAt'] = FieldValue.serverTimestamp();

    // Ensure web-compatible image URLs are stored for repairs.
    if (item.entityType == SyncEntityType.repair) {
      await _normalizeRepairImagePathsForCloud(data);
    }

    // Remove local-only fields
    data.remove('id');
    data.remove('isSynced');
    data.remove('firestoreId');

    await _firestore
        .collection(collection)
        .doc(item.firestoreId)
        .set(data, SetOptions(merge: true));
  }

  /// Handle delete operation
  Future<void> _handleDelete(SyncQueueItem item, String shopId) async {
    if (item.firestoreId == null) {
      // Never synced, just remove from queue
      return;
    }

    final collection = _getCollectionName(item.entityType);
    if (collection == null) {
      throw Exception('Unknown entity type: ${item.entityType}');
    }

    // Soft delete
    await _firestore.collection(collection).doc(item.firestoreId).update({
      'deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mark item as failed
  Future<void> _markItemFailed(SyncQueueItem item, String error) async {
    final db = await _db.database;
    final newRetryCount = item.retryCount + 1;
    final shouldPermanentlyFail =
        _isPermanentSyncError(error) || newRetryCount >= maxRetries;

    if (shouldPermanentlyFail) {
      // Mark as permanently failed
      await db.update(
        'sync_queue',
        {'status': 'failed', 'lastError': error, 'retryCount': newRetryCount},
        where: 'id = ?',
        whereArgs: [item.id],
      );
    } else {
      // Reset to pending for retry
      await db.update(
        'sync_queue',
        {'status': 'pending', 'lastError': error, 'retryCount': newRetryCount},
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }

    await _refreshPendingCount();
    await _emitCurrentStatus();
  }

  /// Refresh pending count
  Future<void> _refreshPendingCount() async {
    _pendingCount = await getPendingCount();
    _pendingCountController.add(_pendingCount);
  }

  Future<int> _getFailedCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'failed'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> _emitCurrentStatus() async {
    final failedCount = await _getFailedCount();
    if (_pendingCount > 0) {
      _syncStatusController.add(SyncStatus.hasPending);
      return;
    }
    if (failedCount > 0) {
      _syncStatusController.add(SyncStatus.error);
      return;
    }
    _syncStatusController.add(SyncStatus.synced);
  }

  /// Get collection name for entity type
  String? _getCollectionName(SyncEntityType type) {
    switch (type) {
      case SyncEntityType.repair:
        return 'repairs';
      case SyncEntityType.sale:
        return 'sales';
      case SyncEntityType.product:
        return 'products';
      case SyncEntityType.expense:
        return 'expenses';
      case SyncEntityType.debt:
        return 'debts';
      case SyncEntityType.customer:
        return 'customers';
      case SyncEntityType.supplier:
        return 'suppliers';
      case SyncEntityType.attendance:
        return 'attendance';
      case SyncEntityType.repairPart:
        return 'repair_parts';
      case SyncEntityType.quickInputCode:
        return 'quick_input_codes';
      case SyncEntityType.debtPayment:
        return 'debt_payments';
      case SyncEntityType.supplierPayment:
        return 'supplier_payments';
      case SyncEntityType.partnerPayment:
        return 'repair_partner_payments';
      case SyncEntityType.repairPartner:
        return 'repair_partners';
      case SyncEntityType.auditLog:
        return 'audit_logs';
      case SyncEntityType.cashClosing:
        return 'cash_closings';
      case SyncEntityType.adjustmentEntry:
        return 'adjustment_entries';
      case SyncEntityType.purchaseOrder:
        return 'purchase_orders';
      case SyncEntityType.supplierImportHistory:
        return 'supplier_import_history';
      case SyncEntityType.salvagePhone:
        return 'salvage_phones';
    }
  }

  /// Get table name for entity type
  String? _getTableName(SyncEntityType type) {
    switch (type) {
      case SyncEntityType.repair:
        return 'repairs';
      case SyncEntityType.sale:
        return 'sales';
      case SyncEntityType.product:
        return 'products';
      case SyncEntityType.expense:
        return 'expenses';
      case SyncEntityType.debt:
        return 'debts';
      case SyncEntityType.customer:
        return 'customers';
      case SyncEntityType.supplier:
        return 'suppliers';
      case SyncEntityType.attendance:
        return 'attendance';
      case SyncEntityType.repairPart:
        return 'repair_parts';
      case SyncEntityType.quickInputCode:
        return 'quick_input_codes';
      case SyncEntityType.debtPayment:
        return 'debt_payments';
      case SyncEntityType.supplierPayment:
        return 'supplier_payments';
      case SyncEntityType.partnerPayment:
        return 'repair_partner_payments';
      case SyncEntityType.repairPartner:
        return 'repair_partners';
      case SyncEntityType.auditLog:
        return 'audit_logs';
      case SyncEntityType.cashClosing:
        return 'cash_closings';
      case SyncEntityType.adjustmentEntry:
        return 'adjustment_entries';
      case SyncEntityType.purchaseOrder:
        return 'purchase_orders';
      case SyncEntityType.supplierImportHistory:
        return 'supplier_import_history';
      case SyncEntityType.salvagePhone:
        return 'salvage_phones';
    }
  }

  /// Get entity data from local DB
  Future<Map<String, dynamic>?> _getEntityData(
    SyncEntityType type,
    int entityId,
  ) async {
    final table = _getTableName(type);
    if (table == null) return null;

    final db = await _db.database;
    final results = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [entityId],
    );

    if (results.isEmpty) return null;
    return Map<String, dynamic>.from(results.first);
  }

  /// Update local entity with firestoreId
  Future<void> _updateLocalFirestoreId(
    SyncEntityType type,
    int entityId,
    String firestoreId,
  ) async {
    final table = _getTableName(type);
    if (table == null) return;

    final db = await _db.database;
    await db.update(
      table,
      {'firestoreId': firestoreId},
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  /// Mark local entity as synced
  Future<void> _markLocalAsSynced(SyncEntityType type, int entityId) async {
    final table = _getTableName(type);
    if (table == null) return;

    final db = await _db.database;
    await db.update(
      table,
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  /// Clear failed items (admin function)
  Future<int> clearFailedItems() async {
    final db = await _db.database;
    final count = await db.delete('sync_queue', where: "status = 'failed'");
    await _refreshPendingCount();
    await _emitCurrentStatus();
    return count;
  }

  /// Retry failed items
  Future<void> retryFailedItems() async {
    final db = await _db.database;
    await db.update('sync_queue', {
      'status': 'pending',
      'retryCount': 0,
      'lastError': null,
    }, where: "status = 'failed'");
    await _refreshPendingCount();
    await _emitCurrentStatus();
  }

  /// Get failed items
  Future<List<SyncQueueItem>> getFailedItems() async {
    final db = await _db.database;
    final results = await db.query(
      'sync_queue',
      where: "status = 'failed'",
      orderBy: 'createdAt DESC',
    );
    return results.map((r) => SyncQueueItem.fromMap(r)).toList();
  }

  /// Get sync stats
  Future<Map<String, int>> getSyncStats() async {
    final db = await _db.database;
    final pending = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'pending'",
    );
    final processing = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'processing'",
    );
    final failed = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'failed'",
    );

    return {
      'pending': Sqflite.firstIntValue(pending) ?? 0,
      'processing': Sqflite.firstIntValue(processing) ?? 0,
      'failed': Sqflite.firstIntValue(failed) ?? 0,
    };
  }

  // ============== CONVENIENCE METHODS ==============

  /// Enqueue a repair for sync
  Future<void> enqueueRepair(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.repair,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue a sale for sync
  Future<void> enqueueSale(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.sale,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue a product for sync
  Future<void> enqueueProduct(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.product,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue an expense for sync
  Future<void> enqueueExpense(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.expense,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue a debt for sync
  Future<void> enqueueDebt(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.debt,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue a customer for sync
  Future<void> enqueueCustomer(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.customer,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue a supplier for sync
  Future<void> enqueueSupplier(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.supplier,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue attendance for sync
  Future<void> enqueueAttendance(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.attendance,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue repair part for sync
  Future<void> enqueueRepairPart(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.repairPart,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue debt payment for sync
  Future<void> enqueueDebtPayment(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.debtPayment,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// FIX BUG-002: Enqueue supplier payment for sync
  Future<void> enqueueSupplierPayment(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.supplierPayment,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }

  /// Enqueue supplier import history for sync
  Future<void> enqueueSupplierImportHistory(
    int id, {
    String? firestoreId,
    SyncOperation operation = SyncOperation.update,
  }) async {
    await enqueue(
      entityType: SyncEntityType.supplierImportHistory,
      entityId: id,
      firestoreId: firestoreId,
      operation: operation,
    );
  }
}

/// Sync status enum
enum SyncStatus {
  synced, // All data synced
  hasPending, // Has pending items
  syncing, // Currently syncing
  noNetwork, // No network available
  error, // Sync error occurred
}

/// Sync result class
class SyncResult {
  final int success;
  final int failed;
  final int total;
  final bool skipped;
  final bool noNetwork;

  SyncResult({
    required this.success,
    required this.failed,
    required this.total,
    this.skipped = false,
    this.noNetwork = false,
  });

  @override
  String toString() {
    if (noNetwork) return 'Không có mạng';
    if (skipped) return 'Đang đồng bộ...';
    return 'Đồng bộ: $success thành công, $failed lỗi / $total';
  }
}
