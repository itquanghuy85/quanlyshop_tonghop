import 'package:sqflite/sqflite.dart';

import '../data/db_helper.dart';

class FirebaseUsageStatsService {
  static final DBHelper _db = DBHelper();
  static bool _initialized = false;
  static int _lastPruneAtMs = 0;

  static const String tableName = 'firebase_read_stats';
  static const Duration _retention = Duration(days: 14);

  static Future<void> logRealtimeRead({
    required String collection,
    required String? shopId,
    required int readCount,
    String source = 'listener',
  }) async {
    if (readCount <= 0) return;
    if (collection.trim().isEmpty) return;

    try {
      final db = await _readyDb();
      await db.insert(tableName, {
        'shopId': (shopId ?? '').trim(),
        'collectionName': collection.trim(),
        'readCount': readCount,
        'source': source,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      await _pruneOldRows(db);
    } catch (_) {
      // Telemetry must never block realtime sync flow.
    }
  }

  static Future<Map<String, int>> getReadCountsByCollection({
    required String shopId,
    Duration window = const Duration(hours: 24),
  }) async {
    if (shopId.trim().isEmpty) return const {};

    final db = await _readyDb();
    final thresholdMs = DateTime.now().subtract(window).millisecondsSinceEpoch;

    final rows = await db.rawQuery(
      '''
      SELECT
        collectionName,
        SUM(readCount) as totalReads
      FROM $tableName
      WHERE createdAt >= ?
        AND shopId = ?
      GROUP BY collectionName
      ''',
      [thresholdMs, shopId],
    );

    final result = <String, int>{};
    for (final row in rows) {
      final key = row['collectionName']?.toString() ?? '';
      if (key.isEmpty) continue;
      result[key] = _toInt(row['totalReads']);
    }
    return result;
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
        shopId TEXT NOT NULL,
        collectionName TEXT NOT NULL,
        readCount INTEGER NOT NULL,
        source TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_firebase_read_stats_shop_created ON $tableName(shopId, createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_firebase_read_stats_collection_created ON $tableName(collectionName, createdAt)',
    );
  }

  static Future<void> _pruneOldRows(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPruneAtMs < const Duration(minutes: 30).inMilliseconds) {
      return;
    }

    _lastPruneAtMs = now;
    final thresholdMs = now - _retention.inMilliseconds;
    await db.delete(tableName, where: 'createdAt < ?', whereArgs: [thresholdMs]);
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
