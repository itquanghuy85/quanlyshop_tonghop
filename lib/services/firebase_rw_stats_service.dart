import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_usage_stats_service.dart';
import 'sync_audit_service.dart';
import 'sync_orchestrator.dart';
import 'sync_service.dart';
import 'user_service.dart';

class FirebaseCollectionRwStat {
  final String collection;
  final String title;
  final int? cloudDocumentCount;
  final int reads24h;
  final int writeAttempts24h;
  final int writeSuccess24h;
  final int writeRetry24h;
  final int writeFailed24h;
  final bool listenerActive;
  final String? cloudCountError;

  const FirebaseCollectionRwStat({
    required this.collection,
    required this.title,
    required this.cloudDocumentCount,
    required this.reads24h,
    required this.writeAttempts24h,
    required this.writeSuccess24h,
    required this.writeRetry24h,
    required this.writeFailed24h,
    required this.listenerActive,
    required this.cloudCountError,
  });
}

class FirebaseRwDashboardSnapshot {
  final DateTime generatedAt;
  final String? shopId;
  final List<FirebaseCollectionRwStat> collectionStats;
  final int activeListeners;
  final int totalListeners;
  final int pendingQueue;
  final int failedQueue;
  final List<String> warnings;

  const FirebaseRwDashboardSnapshot({
    required this.generatedAt,
    required this.shopId,
    required this.collectionStats,
    required this.activeListeners,
    required this.totalListeners,
    required this.pendingQueue,
    required this.failedQueue,
    this.warnings = const [],
  });

  int get totalCloudDocuments =>
      collectionStats.fold<int>(0, (sum, e) => sum + (e.cloudDocumentCount ?? 0));

  int get totalReads24h =>
      collectionStats.fold<int>(0, (sum, e) => sum + e.reads24h);

  int get totalWriteAttempts24h =>
      collectionStats.fold<int>(0, (sum, e) => sum + e.writeAttempts24h);

  int get totalWriteSuccess24h =>
      collectionStats.fold<int>(0, (sum, e) => sum + e.writeSuccess24h);

  int get totalWriteFailed24h =>
      collectionStats.fold<int>(0, (sum, e) => sum + e.writeFailed24h);
}

class _CollectionConfig {
  final String collection;
  final String title;
  final List<String> entityTypes;
  final bool isShopSubcollection;

  const _CollectionConfig({
    required this.collection,
    required this.title,
    required this.entityTypes,
    this.isShopSubcollection = false,
  });
}

class _CloudCountResult {
  final int? count;
  final String? error;

  const _CloudCountResult({required this.count, required this.error});
}

class FirebaseRwStatsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final SyncOrchestrator _orchestrator = SyncOrchestrator();
  static const Duration _stepTimeout = Duration(seconds: 8);

  static const List<_CollectionConfig> _configs = [
    _CollectionConfig(
      collection: 'repairs',
      title: 'Đơn sửa',
      entityTypes: ['repair'],
    ),
    _CollectionConfig(
      collection: 'repair_parts',
      title: 'Linh kiện sửa',
      entityTypes: ['repairPart'],
    ),
    _CollectionConfig(
      collection: 'sales',
      title: 'Đơn bán',
      entityTypes: ['sale'],
    ),
    _CollectionConfig(
      collection: 'products',
      title: 'Sản phẩm',
      entityTypes: ['product'],
    ),
    _CollectionConfig(
      collection: 'expenses',
      title: 'Chi phí',
      entityTypes: ['expense'],
    ),
    _CollectionConfig(
      collection: 'debts',
      title: 'Công nợ',
      entityTypes: ['debt'],
    ),
    _CollectionConfig(
      collection: 'debt_payments',
      title: 'Thu nợ',
      entityTypes: ['debtPayment'],
    ),
    _CollectionConfig(
      collection: 'purchase_orders',
      title: 'Đơn nhập',
      entityTypes: ['purchaseOrder'],
    ),
    _CollectionConfig(
      collection: 'customers',
      title: 'Khách hàng',
      entityTypes: ['customer'],
    ),
    _CollectionConfig(
      collection: 'quick_input_codes',
      title: 'Mã nhanh',
      entityTypes: ['quickInputCode'],
    ),
    _CollectionConfig(
      collection: 'supplier_import_history',
      title: 'Lịch sử nhập NCC',
      entityTypes: ['supplierImportHistory'],
    ),
    _CollectionConfig(
      collection: 'cash_closings',
      title: 'Sổ quỹ',
      entityTypes: ['cashClosing'],
    ),
    _CollectionConfig(
      collection: 'supplier_payments',
      title: 'Thanh toán NCC',
      entityTypes: ['supplierPayment'],
    ),
    _CollectionConfig(
      collection: 'repair_partner_payments',
      title: 'Thanh toán đối tác sửa',
      entityTypes: ['partnerPayment'],
    ),
    _CollectionConfig(
      collection: 'payment_requests',
      title: 'Yêu cầu đóng tiền',
      entityTypes: const [],
    ),
    _CollectionConfig(
      collection: 'sales_returns',
      title: 'Trả hàng',
      entityTypes: const [],
    ),
    _CollectionConfig(
      collection: 'salvage_phones',
      title: 'Kho máy xác',
      entityTypes: ['salvagePhone'],
    ),
    _CollectionConfig(
      collection: 'product_categories',
      title: 'Danh mục SP',
      entityTypes: const [],
      isShopSubcollection: true,
    ),
  ];

  static Future<FirebaseRwDashboardSnapshot> buildSnapshot() async {
    final now = DateTime.now();
    final warnings = <String>[];
    final shopId = await UserService.getCurrentShopId();
    final hasShopContext = shopId != null && shopId.isNotEmpty;

    if (!hasShopContext) {
      warnings.add(
        'Chưa xác định shopId hiện tại, số liệu cloud/read sẽ giới hạn để tránh lẫn dữ liệu giữa shop.',
      );
    }

    final queueStats = await _orchestrator.getSyncStats();
    final listeners = SyncService.subscriptionStatus;
    final activeListeners = listeners.values.where((v) => v).length;

    if (activeListeners > 0) {
      warnings.add(
        'Trạng thái ON thể hiện collection đang được đồng bộ (đa số là polling get theo chu kỳ), không chỉ realtime listener.',
      );
    }

    final readByCollection = hasShopContext
        ? await FirebaseUsageStatsService.getReadCountsByCollection(
            shopId: shopId,
          )
        : const <String, int>{};

    final entityStats = await SyncAuditService.getEntityTypeStats();

    final stats = <FirebaseCollectionRwStat>[];
    for (final config in _configs) {
      final cloud = await _countCloudDocs(config: config, shopId: shopId);
      int success = 0;
      int retry = 0;
      int failed = 0;

      for (final entityType in config.entityTypes) {
        final s = entityStats[entityType];
        if (s == null) continue;
        success += s.successCount;
        retry += s.retryCount;
        failed += s.failedCount;
      }

      final writes = success + retry + failed;
      final reads = readByCollection[config.collection] ?? 0;

      stats.add(
        FirebaseCollectionRwStat(
          collection: config.collection,
          title: config.title,
          cloudDocumentCount: cloud.count,
          reads24h: reads,
          writeAttempts24h: writes,
          writeSuccess24h: success,
          writeRetry24h: retry,
          writeFailed24h: failed,
          listenerActive: listeners[config.collection] ?? false,
          cloudCountError: cloud.error,
        ),
      );
    }

    stats.sort((a, b) {
      final writeCompare = b.writeAttempts24h.compareTo(a.writeAttempts24h);
      if (writeCompare != 0) return writeCompare;
      final readCompare = b.reads24h.compareTo(a.reads24h);
      if (readCompare != 0) return readCompare;
      return a.title.compareTo(b.title);
    });

    return FirebaseRwDashboardSnapshot(
      generatedAt: now,
      shopId: shopId,
      collectionStats: stats,
      activeListeners: activeListeners,
      totalListeners: listeners.length,
      pendingQueue: queueStats['pending'] ?? 0,
      failedQueue: queueStats['failed'] ?? 0,
      warnings: warnings,
    );
  }

  static Future<_CloudCountResult> _countCloudDocs({
    required _CollectionConfig config,
    required String? shopId,
  }) async {
    if (shopId == null || shopId.isEmpty) {
      return const _CloudCountResult(count: null, error: 'Thiếu shopId');
    }

    try {
      Query<Map<String, dynamic>> query;
      if (config.isShopSubcollection) {
        query = _db
            .collection('shops')
            .doc(shopId)
            .collection(config.collection);
      } else {
        query = _db
            .collection(config.collection)
            .where('shopId', isEqualTo: shopId);
      }

      final snapshot = await query.count().get().timeout(_stepTimeout);
      return _CloudCountResult(count: snapshot.count, error: null);
    } on TimeoutException {
      return _CloudCountResult(
        count: null,
        error: 'Timeout ${_stepTimeout.inSeconds}s',
      );
    } on FirebaseException catch (e) {
      return _CloudCountResult(
        count: null,
        error: '${e.code}: ${e.message ?? 'unknown'}',
      );
    } catch (e) {
      return _CloudCountResult(count: null, error: e.toString());
    }
  }
}
