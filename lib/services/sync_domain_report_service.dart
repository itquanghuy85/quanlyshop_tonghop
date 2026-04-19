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
    if (hasError) return 'Loi sync';
    if (hasPending) return 'Chua sync het';
    return 'Da sync';
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

  static final List<_DomainConfig> _domainConfigs = [
    const _DomainConfig(
      key: 'financial',
      title: 'Tai chinh',
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
      title: 'Don sua',
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
      title: 'Ban hang',
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
    final db = await DBHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final shopId = await UserService.getCurrentShopId();

    final effectiveHealth =
        healthReport ?? await SyncHealthCheck.runFullCheck();
    final auditStats = await SyncAuditService.getDomainStats();

    final reports = <DomainSyncReport>[];

    for (final config in _domainConfigs) {
      final queueStats = await _countQueueStats(db, config.queueEntityTypes);
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

      reports.add(
        DomainSyncReport(
          key: config.key,
          title: config.title,
          pendingQueue: queueStats['pending'] ?? 0,
          processingQueue: queueStats['processing'] ?? 0,
          failedQueue: queueStats['failed'] ?? 0,
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

    return SyncDomainReportSnapshot(
      generatedAt: DateTime.now(),
      domains: reports,
    );
  }

  static Future<Map<String, int>> _countQueueStats(
    Database db,
    List<String> entityTypes,
  ) async {
    if (entityTypes.isEmpty) {
      return const {'pending': 0, 'processing': 0, 'failed': 0};
    }

    try {
      final placeholders = List.filled(entityTypes.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT status, COUNT(*) as c
        FROM sync_queue
        WHERE entityType IN ($placeholders)
          AND status IN ('pending', 'processing', 'failed')
        GROUP BY status
        ''', entityTypes);

      final result = <String, int>{'pending': 0, 'processing': 0, 'failed': 0};

      for (final row in rows) {
        final status = row['status']?.toString();
        final count = _toInt(row['c']);
        if (status == null) continue;
        if (!result.containsKey(status)) continue;
        result[status] = count;
      }

      return result;
    } catch (_) {
      return const {'pending': 0, 'processing': 0, 'failed': 0};
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
}
