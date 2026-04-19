import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db_helper.dart';

class SyncAuditDomainStats {
  final int successCount;
  final int retryCount;
  final int failedCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  const SyncAuditDomainStats({
    required this.successCount,
    required this.retryCount,
    required this.failedCount,
    required this.lastSuccessAt,
    required this.lastFailureAt,
  });

  int get totalIssues => retryCount + failedCount;
}

class SyncAuditEntityTypeStats {
  final int successCount;
  final int retryCount;
  final int failedCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  const SyncAuditEntityTypeStats({
    required this.successCount,
    required this.retryCount,
    required this.failedCount,
    required this.lastSuccessAt,
    required this.lastFailureAt,
  });

  int get writeAttempts => successCount + retryCount + failedCount;
}

class SyncAuditEvent {
  final int id;
  final String domainKey;
  final String entityType;
  final int entityId;
  final String? firestoreId;
  final String operation;
  final String outcome;
  final String queueStatus;
  final String? errorMessage;
  final int retryCount;
  final DateTime createdAt;

  const SyncAuditEvent({
    required this.id,
    required this.domainKey,
    required this.entityType,
    required this.entityId,
    required this.firestoreId,
    required this.operation,
    required this.outcome,
    required this.queueStatus,
    required this.errorMessage,
    required this.retryCount,
    required this.createdAt,
  });

  factory SyncAuditEvent.fromMap(Map<String, dynamic> map) {
    return SyncAuditEvent(
      id: SyncAuditService._toInt(map['id']),
      domainKey: map['domainKey']?.toString() ?? 'other',
      entityType: map['entityType']?.toString() ?? 'unknown',
      entityId: SyncAuditService._toInt(map['entityId']),
      firestoreId: map['firestoreId']?.toString(),
      operation: map['operation']?.toString() ?? 'unknown',
      outcome: map['outcome']?.toString() ?? 'unknown',
      queueStatus: map['queueStatus']?.toString() ?? 'unknown',
      errorMessage: map['errorMessage']?.toString(),
      retryCount: SyncAuditService._toInt(map['retryCount']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        SyncAuditService._toInt(map['createdAt']),
      ),
    );
  }
}

class SyncAuditService {
  static final DBHelper _db = DBHelper();
  static bool _initialized = false;

  static const String tableName = 'sync_audit_log';

  static Future<void> logSuccess({
    required String entityType,
    required int entityId,
    required String operation,
    String? firestoreId,
  }) async {
    await _insert(
      entityType: entityType,
      entityId: entityId,
      firestoreId: firestoreId,
      operation: operation,
      outcome: 'success',
      queueStatus: 'completed',
      retryCount: 0,
      errorMessage: null,
    );
  }

  static Future<void> logFailure({
    required String entityType,
    required int entityId,
    required String operation,
    required String queueStatus,
    required int retryCount,
    String? firestoreId,
    String? errorMessage,
  }) async {
    final normalizedStatus = queueStatus.trim().toLowerCase();
    final outcome = normalizedStatus == 'failed' ? 'failed' : 'retry';

    await _insert(
      entityType: entityType,
      entityId: entityId,
      firestoreId: firestoreId,
      operation: operation,
      outcome: outcome,
      queueStatus: normalizedStatus,
      retryCount: retryCount,
      errorMessage: _safeError(errorMessage),
    );
  }

  static Future<Map<String, SyncAuditDomainStats>> getDomainStats({
    Duration window = const Duration(hours: 24),
  }) async {
    final db = await _readyDb();
    final thresholdMs = DateTime.now().subtract(window).millisecondsSinceEpoch;

    final rows = await db.rawQuery(
      '''
      SELECT
        domainKey,
        SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END) as successCount,
        SUM(CASE WHEN outcome = 'retry' THEN 1 ELSE 0 END) as retryCount,
        SUM(CASE WHEN outcome = 'failed' THEN 1 ELSE 0 END) as failedCount,
        MAX(CASE WHEN outcome = 'success' THEN createdAt ELSE NULL END) as lastSuccessAt,
        MAX(CASE WHEN outcome IN ('retry', 'failed') THEN createdAt ELSE NULL END) as lastFailureAt
      FROM $tableName
      WHERE createdAt >= ?
      GROUP BY domainKey
      ''',
      [thresholdMs],
    );

    final result = <String, SyncAuditDomainStats>{};
    for (final row in rows) {
      final key = row['domainKey']?.toString() ?? 'other';
      result[key] = SyncAuditDomainStats(
        successCount: _toInt(row['successCount']),
        retryCount: _toInt(row['retryCount']),
        failedCount: _toInt(row['failedCount']),
        lastSuccessAt: _toDateTime(row['lastSuccessAt']),
        lastFailureAt: _toDateTime(row['lastFailureAt']),
      );
    }

    return result;
  }

  static Future<Map<String, SyncAuditEntityTypeStats>> getEntityTypeStats({
    Duration window = const Duration(hours: 24),
  }) async {
    final db = await _readyDb();
    final thresholdMs = DateTime.now().subtract(window).millisecondsSinceEpoch;

    final rows = await db.rawQuery(
      '''
      SELECT
        entityType,
        SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END) as successCount,
        SUM(CASE WHEN outcome = 'retry' THEN 1 ELSE 0 END) as retryCount,
        SUM(CASE WHEN outcome = 'failed' THEN 1 ELSE 0 END) as failedCount,
        MAX(CASE WHEN outcome = 'success' THEN createdAt ELSE NULL END) as lastSuccessAt,
        MAX(CASE WHEN outcome IN ('retry', 'failed') THEN createdAt ELSE NULL END) as lastFailureAt
      FROM $tableName
      WHERE createdAt >= ?
      GROUP BY entityType
      ''',
      [thresholdMs],
    );

    final result = <String, SyncAuditEntityTypeStats>{};
    for (final row in rows) {
      final key = row['entityType']?.toString() ?? '';
      if (key.isEmpty) continue;
      result[key] = SyncAuditEntityTypeStats(
        successCount: _toInt(row['successCount']),
        retryCount: _toInt(row['retryCount']),
        failedCount: _toInt(row['failedCount']),
        lastSuccessAt: _toDateTime(row['lastSuccessAt']),
        lastFailureAt: _toDateTime(row['lastFailureAt']),
      );
    }

    return result;
  }

  static Future<List<SyncAuditEvent>> getRecentEvents({int limit = 120}) async {
    final db = await _readyDb();
    final rows = await db.query(
      tableName,
      orderBy: 'createdAt DESC',
      limit: limit,
    );

    return rows.map(SyncAuditEvent.fromMap).toList();
  }

  static Future<String> writeMarkdownReport({
    required String markdown,
    String prefix = 'sync_report',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final fileName =
        '${prefix}_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.md';
    final path = p.join(dir.path, fileName);
    final file = File(path);
    await file.writeAsString(markdown);
    return file.path;
  }

  static Future<void> _insert({
    required String entityType,
    required int entityId,
    required String operation,
    required String outcome,
    required String queueStatus,
    required int retryCount,
    String? firestoreId,
    String? errorMessage,
  }) async {
    final db = await _readyDb();

    await db.insert(tableName, {
      'domainKey': _mapDomainKey(entityType),
      'entityType': entityType,
      'entityId': entityId,
      'firestoreId': firestoreId,
      'operation': operation,
      'outcome': outcome,
      'queueStatus': queueStatus,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<Database> _readyDb() async {
    final db = await _db.database;
    if (!_initialized) {
      await _ensureTable(db);
      _initialized = true;
    }
    return db;
  }

  static Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        domainKey TEXT NOT NULL,
        entityType TEXT NOT NULL,
        entityId INTEGER NOT NULL,
        firestoreId TEXT,
        operation TEXT NOT NULL,
        outcome TEXT NOT NULL,
        queueStatus TEXT NOT NULL,
        errorMessage TEXT,
        retryCount INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_audit_domain_created ON $tableName(domainKey, createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_audit_outcome_created ON $tableName(outcome, createdAt)',
    );
  }

  static String _mapDomainKey(String entityType) {
    switch (entityType) {
      case 'expense':
      case 'debt':
      case 'debtPayment':
      case 'supplierPayment':
      case 'partnerPayment':
      case 'cashClosing':
      case 'adjustmentEntry':
        return 'financial';
      case 'repair':
      case 'repairPart':
      case 'repairPartner':
        return 'repair';
      case 'product':
      case 'purchaseOrder':
      case 'supplierImportHistory':
      case 'quickInputCode':
        return 'inventory';
      case 'sale':
      case 'customer':
      case 'salvagePhone':
        return 'sales';
      default:
        return 'other';
    }
  }

  static String? _safeError(String? error) {
    if (error == null) return null;
    final trimmed = error.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= 600) return trimmed;
    return '${trimmed.substring(0, 600)}...';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static DateTime? _toDateTime(dynamic value) {
    final ms = _toInt(value);
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
