import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db_helper.dart';
import 'sync_audit_service.dart';
import 'sync_health_check.dart';
import 'user_service.dart';

class DomainSyncReport {
  final String key;
  final String title;
  final int pendingQueue;
  final int processingQueue;
  final int failedQueue;
  final int stalePendingQueue;
  final int staleProcessingQueue;
  final int? oldestQueueAgeMinutes;
  final int unsyncedLocal;
  final int mismatchCount;
  final int totalLocalRecords;
  final DateTime? lastSyncAt;
  final int recentSuccessCount;
  final int recentRetryCount;
  final int recentFailedCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  const DomainSyncReport({
    required this.key,
    required this.title,
    required this.pendingQueue,
    required this.processingQueue,
    required this.failedQueue,
    required this.stalePendingQueue,
    required this.staleProcessingQueue,
    required this.oldestQueueAgeMinutes,
    required this.unsyncedLocal,
    required this.mismatchCount,
    required this.totalLocalRecords,
    required this.lastSyncAt,
    required this.recentSuccessCount,
    required this.recentRetryCount,
    required this.recentFailedCount,
    required this.lastSuccessAt,
    required this.lastFailureAt,
  });

  int get queueTotal => pendingQueue + processingQueue + failedQueue;

  int get staleQueueTotal => stalePendingQueue + staleProcessingQueue;

  bool get hasStuckQueue => staleQueueTotal > 0;

  bool get hasError => failedQueue > 0;

  bool get hasPending =>
      !hasError &&
      (pendingQueue > 0 ||
          processingQueue > 0 ||
          unsyncedLocal > 0 ||
          mismatchCount > 0);

  int get recentIssueCount => recentRetryCount + recentFailedCount;

  bool get isSynced => !hasError && !hasPending;

  String get statusLabel {
    if (hasError) return 'Lỗi sync';
    if (hasStuckQueue) return 'Cảnh báo kẹt sync';
    if (hasPending) return 'Chưa sync hết';
    return 'Đã sync';
  }
}

class SyncDomainReportSnapshot {
  final DateTime generatedAt;
  final List<DomainSyncReport> domains;

  const SyncDomainReportSnapshot({
    required this.generatedAt,
    required this.domains,
  });

  int get totalFailed => domains.fold<int>(0, (sum, d) => sum + d.failedQueue);

  int get totalPending => domains.fold<int>(
    0,
    (sum, d) =>
        sum +
        d.pendingQueue +
        d.processingQueue +
        d.unsyncedLocal +
        d.mismatchCount,
  );

  int get totalStuckQueue =>
      domains.fold<int>(0, (sum, d) => sum + d.staleQueueTotal);

  bool get hasOperationalAlerts => totalFailed > 0 || totalStuckQueue > 0;

  List<DomainSyncReport> get alertDomains =>
      domains.where((d) => d.hasError || d.hasStuckQueue).toList();
}

class _DomainConfig {
  final String key;
  final String title;
  final List<String> queueEntityTypes;
  final List<String> localTables;
  final List<String> healthCollections;
  final List<String> lastSyncCollections;

  const _DomainConfig({
    required this.key,
    required this.title,
    required this.queueEntityTypes,
    required this.localTables,
    required this.healthCollections,
    required this.lastSyncCollections,
  });
}

class SyncDomainReportService {
  static const _lastSyncPrefix = 'lastSync_';
  static const int stuckQueueThresholdMinutes = 20;

  static final List<_DomainConfig> _domainConfigs = [
    const _DomainConfig(
      key: 'financial',
      title: 'Tài chính',
      queueEntityTypes: [
        'expense',
        'debt',
        'debtPayment',
        'supplierPayment',
        'partnerPayment',
        'cashClosing',
        'adjustmentEntry',
      ],
      localTables: [
        'expenses',
        'debts',
        'debt_payments',
        'supplier_payments',
        'repair_partner_payments',
        'cash_closings',
        'financial_activity_log',
        'payment_intents',
        'payment_requests',
      ],
      healthCollections: ['expenses', 'debts', 'debt_payments'],
      lastSyncCollections: [
        'expenses',
        'debts',
        'debt_payments',
        'supplier_payments',
        'repair_partner_payments',
        'cash_closings',
        'financial_activity_log',
        'payment_intents',
        'payment_requests',
      ],
    ),
    const _DomainConfig(
      key: 'repair',
      title: 'Đơn sửa',
      queueEntityTypes: ['repair', 'repairPart', 'repairPartner'],
      localTables: [
        'repairs',
        'repair_parts',
        'repair_partners',
        'partner_repair_history',
      ],
      healthCollections: ['repairs', 'repair_parts'],
      lastSyncCollections: ['repairs', 'repair_parts', 'repair_partners'],
    ),
    const _DomainConfig(
      key: 'inventory',
      title: 'Kho',
      queueEntityTypes: [
        'product',
        'purchaseOrder',
        'supplierImportHistory',
        'quickInputCode',
      ],
      localTables: [
        'products',
        'purchase_orders',
        'supplier_import_history',
        'quick_input_codes',
        'import_orders',
        'import_order_items',
      ],
      healthCollections: ['products', 'quick_input_codes'],
      lastSyncCollections: [
        'products',
        'purchase_orders',
        'supplier_import_history',
        'quick_input_codes',
        'import_orders',
        'import_order_items',
      ],
    ),
    const _DomainConfig(
      key: 'sales',
      title: 'Bán hàng',
      queueEntityTypes: ['sale', 'customer', 'salvagePhone'],
      localTables: [
        'sales',
        'sales_returns',
        'sales_return_items',
        'customers',
      ],
      healthCollections: ['sales', 'customers'],
      lastSyncCollections: [
        'sales',
        'sales_returns',
        'sales_return_items',
        'customers',
      ],
    ),
  ];

  static final Map<String, Set<String>> _columnCache = <String, Set<String>>{};

  static Future<SyncDomainReportSnapshot> buildReport({
    SyncHealthReport? healthReport,
  }) async {
    final generatedAt = DateTime.now();
    final generatedAtMs = generatedAt.millisecondsSinceEpoch;
    final db = await DBHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final shopId = await UserService.getCurrentShopId();

    final effectiveHealth =
        healthReport ?? await SyncHealthCheck.runFullCheck();
    final auditStats = await SyncAuditService.getDomainStats();

    final reports = <DomainSyncReport>[];

    for (final config in _domainConfigs) {
      final queueStats = await _countQueueStats(
        db,
        config.queueEntityTypes,
        nowMs: generatedAtMs,
      );
      final unsyncedLocal = await _countLocalUnsynced(
        db,
        config.localTables,
        shopId,
      );
      final totalLocalRecords = await _countTotalLocal(
        db,
        config.localTables,
        shopId,
      );
      final mismatchCount = _countMismatches(
        effectiveHealth,
        config.healthCollections,
      );
      final lastSyncAt = _resolveLastSyncAt(
        prefs,
        shopId,
        config.lastSyncCollections,
      );
      final domainAuditStats =
          auditStats[config.key] ??
          const SyncAuditDomainStats(
            successCount: 0,
            retryCount: 0,
            failedCount: 0,
            lastSuccessAt: null,
            lastFailureAt: null,
          );
      final oldestQueueCreatedAt = _toInt(queueStats['oldestQueueCreatedAt']);
      final oldestQueueAgeMinutes = _computeAgeMinutes(
        generatedAtMs,
        oldestQueueCreatedAt,
      );

      reports.add(
        DomainSyncReport(
          key: config.key,
          title: config.title,
          pendingQueue: queueStats['pending'] ?? 0,
          processingQueue: queueStats['processing'] ?? 0,
          failedQueue: queueStats['failed'] ?? 0,
          stalePendingQueue: queueStats['stalePending'] ?? 0,
          staleProcessingQueue: queueStats['staleProcessing'] ?? 0,
          oldestQueueAgeMinutes: oldestQueueAgeMinutes,
          unsyncedLocal: unsyncedLocal,
          mismatchCount: mismatchCount,
          totalLocalRecords: totalLocalRecords,
          lastSyncAt: lastSyncAt,
          recentSuccessCount: domainAuditStats.successCount,
          recentRetryCount: domainAuditStats.retryCount,
          recentFailedCount: domainAuditStats.failedCount,
          lastSuccessAt: domainAuditStats.lastSuccessAt,
          lastFailureAt: domainAuditStats.lastFailureAt,
        ),
      );
    }

    return SyncDomainReportSnapshot(generatedAt: generatedAt, domains: reports);
  }

  static Future<Map<String, int>> _countQueueStats(
    Database db,
    List<String> entityTypes, {
    required int nowMs,
  }) async {
    if (entityTypes.isEmpty) {
      return const {
        'pending': 0,
        'processing': 0,
        'failed': 0,
        'stalePending': 0,
        'staleProcessing': 0,
        'oldestQueueCreatedAt': 0,
      };
    }

    try {
      final staleThresholdMs = nowMs - (stuckQueueThresholdMinutes * 60 * 1000);
      final placeholders = List.filled(entityTypes.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT
          SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pendingCount,
          SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) as processingCount,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failedCount,
          SUM(CASE WHEN status = 'pending' AND createdAt <= ? THEN 1 ELSE 0 END) as stalePendingCount,
          SUM(CASE WHEN status = 'processing' AND createdAt <= ? THEN 1 ELSE 0 END) as staleProcessingCount,
          MIN(CASE WHEN status IN ('pending', 'processing') THEN createdAt ELSE NULL END) as oldestQueueCreatedAt
        FROM sync_queue
        WHERE entityType IN ($placeholders)
          AND status IN ('pending', 'processing', 'failed')
        ''',
        [staleThresholdMs, staleThresholdMs, ...entityTypes],
      );

      final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};
      return {
        'pending': _toInt(row['pendingCount']),
        'processing': _toInt(row['processingCount']),
        'failed': _toInt(row['failedCount']),
        'stalePending': _toInt(row['stalePendingCount']),
        'staleProcessing': _toInt(row['staleProcessingCount']),
        'oldestQueueCreatedAt': _toInt(row['oldestQueueCreatedAt']),
      };
    } catch (_) {
      return const {
        'pending': 0,
        'processing': 0,
        'failed': 0,
        'stalePending': 0,
        'staleProcessing': 0,
        'oldestQueueCreatedAt': 0,
      };
    }
  }

  static Future<int> _countLocalUnsynced(
    Database db,
    List<String> tables,
    String? shopId,
  ) async {
    var total = 0;
    for (final table in tables) {
      total += await _countTableRows(
        db,
        table,
        shopId: shopId,
        onlyUnsynced: true,
      );
    }
    return total;
  }

  static Future<int> _countTotalLocal(
    Database db,
    List<String> tables,
    String? shopId,
  ) async {
    var total = 0;
    for (final table in tables) {
      total += await _countTableRows(
        db,
        table,
        shopId: shopId,
        onlyUnsynced: false,
      );
    }
    return total;
  }

  static int _countMismatches(
    SyncHealthReport report,
    List<String> collections,
  ) {
    var total = 0;
    for (final result in report.results) {
      if (collections.contains(result.collection)) {
        total += result.effectiveMismatchCount;
      }
    }
    return total;
  }

  static DateTime? _resolveLastSyncAt(
    SharedPreferences prefs,
    String? shopId,
    List<String> collections,
  ) {
    if (shopId == null || shopId.isEmpty) return null;

    var latestMs = 0;
    for (final collection in collections) {
      final key = '$_lastSyncPrefix${collection}_$shopId';
      final value = prefs.getInt(key) ?? 0;
      if (value > latestMs) latestMs = value;
    }

    if (latestMs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(latestMs);
  }

  static Future<int> _countTableRows(
    Database db,
    String table, {
    required String? shopId,
    required bool onlyUnsynced,
  }) async {
    try {
      final columns = await _getColumns(db, table);
      if (columns.isEmpty) return 0;

      final where = <String>[];
      final whereArgs = <dynamic>[];

      if (onlyUnsynced && columns.contains('isSynced')) {
        where.add('(isSynced = 0 OR isSynced IS NULL)');
      }

      if (columns.contains('deleted')) {
        where.add('(deleted IS NULL OR deleted = 0)');
      }

      if (shopId != null && shopId.isNotEmpty && columns.contains('shopId')) {
        where.add('(shopId = ? OR shopId IS NULL)');
        whereArgs.add(shopId);
      }

      final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $table $whereSql',
        whereArgs,
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<Set<String>> _getColumns(Database db, String table) async {
    final cached = _columnCache[table];
    if (cached != null) return cached;

    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      final columns = rows
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();
      _columnCache[table] = columns;
      return columns;
    } catch (_) {
      const empty = <String>{};
      _columnCache[table] = empty;
      return empty;
    }
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _computeAgeMinutes(int nowMs, int createdAtMs) {
    if (createdAtMs <= 0) return null;
    if (nowMs <= createdAtMs) return 0;
    return ((nowMs - createdAtMs) / 60000).floor();
  }
}
