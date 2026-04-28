import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'crm_loyalty_models.dart';

class LoyaltyRepository {
  static const String _dbName = 'crm_module_safe_mode.db';
  static const int _dbVersion = 1;

  static const String _loyaltyPointsTable = 'loyalty_points';
  static const String _customerLevelsTable = 'customer_levels';
  static const String _loyaltyTransactionsTable = 'loyalty_transactions';

  static bool _factoryInitialized = false;
  Database? _database;

  static void _ensureDatabaseFactoryInitialized() {
    if (_factoryInitialized) return;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    _factoryInitialized = true;
  }

  Future<Database> _openDb() async {
    if (_database != null) return _database!;

    _ensureDatabaseFactoryInitialized();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_loyaltyPointsTable(
            customerId TEXT PRIMARY KEY NOT NULL,
            customerName TEXT NOT NULL,
            totalPoints INTEGER NOT NULL DEFAULT 0,
            updatedAt INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_customerLevelsTable(
            customerId TEXT PRIMARY KEY NOT NULL,
            tier TEXT NOT NULL DEFAULT 'regular',
            pointsAtLastUpdate INTEGER NOT NULL DEFAULT 0,
            updatedAt INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_loyaltyTransactionsTable(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId TEXT NOT NULL,
            type TEXT NOT NULL,
            points INTEGER NOT NULL,
            discountAmount INTEGER NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT '',
            createdAt INTEGER NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_loyalty_tx_customer ON $_loyaltyTransactionsTable(customerId)',
        );
      },
    );

    return _database!;
  }

  // ─── LoyaltyPoint ────────────────────────────────────────────────────────────

  Future<LoyaltyPoint?> getPoints(String customerId) async {
    final db = await _openDb();
    final rows = await db.query(
      _loyaltyPointsTable,
      where: 'customerId = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LoyaltyPoint.fromMap(rows.first);
  }

  Future<int> recomputePointsFromTransactions(String customerId) async {
    final db = await _openDb();
    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'earn' THEN points ELSE 0 END), 0) AS earned,
        COALESCE(SUM(CASE WHEN type = 'redeem' THEN points ELSE 0 END), 0) AS redeemed
      FROM $_loyaltyTransactionsTable
      WHERE customerId = ?
      ''',
      [customerId],
    );

    if (result.isEmpty) return 0;
    final row = result.first;
    final earned = (row['earned'] as num?)?.toInt() ?? 0;
    final redeemed = (row['redeemed'] as num?)?.toInt() ?? 0;
    final balance = earned - redeemed;
    return balance < 0 ? 0 : balance;
  }

  Future<LoyaltyPoint?> ensurePointsSnapshotFromTransactions({
    required String customerId,
    required String customerName,
    List<String> customerIds = const <String>[],
  }) async {
    final ids = <String>{customerId, ...customerIds}
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final total = ids.length <= 1
        ? await recomputePointsFromTransactions(customerId)
        : await recomputePointsFromTransactionsForCustomerIds(ids);
    if (total <= 0) return null;

    final db = await _openDb();
    await _upsertPoints(db, customerId, customerName, total);

    return LoyaltyPoint(
      customerId: customerId,
      customerName: customerName,
      totalPoints: total,
      updatedAt: DateTime.now(),
    );
  }

  Future<LoyaltyPoint> seedPointsIfMissing({
    required String customerId,
    required String customerName,
    required int initialPoints,
    String note = 'Khởi tạo điểm CRM từ dữ liệu mua hàng cũ',
  }) async {
    final db = await _openDb();

    final existing = await getPoints(customerId);
    if (existing != null) return existing;

    final seededPoints = initialPoints < 0 ? 0 : initialPoints;

    await db.transaction((txn) async {
      await _upsertPoints(txn, customerId, customerName, seededPoints);
      await _upsertLevel(txn, customerId, _computeTier(seededPoints), seededPoints);

      if (seededPoints > 0) {
        await txn.insert(
          _loyaltyTransactionsTable,
          LoyaltyTransaction(
            customerId: customerId,
            type: LoyaltyTransactionType.earn,
            points: seededPoints,
            discountAmount: 0,
            note: note,
            createdAt: DateTime.now(),
          ).toMap(),
        );
      }
    });

    return LoyaltyPoint(
      customerId: customerId,
      customerName: customerName,
      totalPoints: seededPoints,
      updatedAt: DateTime.now(),
    );
  }

  Future<int> recomputePointsFromTransactionsForCustomerIds(
    List<String> customerIds,
  ) async {
    final ids = customerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return 0;

    final db = await _openDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    final result = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'earn' THEN points ELSE 0 END), 0) AS earned,
        COALESCE(SUM(CASE WHEN type = 'redeem' THEN points ELSE 0 END), 0) AS redeemed
      FROM $_loyaltyTransactionsTable
      WHERE customerId IN ($placeholders)
      ''',
      ids,
    );

    if (result.isEmpty) return 0;
    final row = result.first;
    final earned = (row['earned'] as num?)?.toInt() ?? 0;
    final redeemed = (row['redeemed'] as num?)?.toInt() ?? 0;
    final balance = earned - redeemed;
    return balance < 0 ? 0 : balance;
  }

  Future<List<LoyaltyPoint>> getAllPoints() async {
    final db = await _openDb();
    final rows = await db.query(
      _loyaltyPointsTable,
      orderBy: 'totalPoints DESC',
    );
    return rows.map(LoyaltyPoint.fromMap).toList(growable: false);
  }

  Future<void> _upsertPoints(
    DatabaseExecutor txn,
    String customerId,
    String customerName,
    int newTotal,
  ) async {
    await txn.insert(
      _loyaltyPointsTable,
      {
        'customerId': customerId,
        'customerName': customerName,
        'totalPoints': newTotal,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── CustomerLevel ───────────────────────────────────────────────────────────

  Future<CustomerLevel?> getLevel(String customerId) async {
    final db = await _openDb();
    final rows = await db.query(
      _customerLevelsTable,
      where: 'customerId = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CustomerLevel.fromMap(rows.first);
  }

  Future<void> _upsertLevel(
    DatabaseExecutor txn,
    String customerId,
    CustomerLevelTier tier,
    int points,
  ) async {
    await txn.insert(
      _customerLevelsTable,
      {
        'customerId': customerId,
        'tier': tier.toDbString(),
        'pointsAtLastUpdate': points,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── LoyaltyTransaction ───────────────────────────────────────────────────────

  Future<List<LoyaltyTransaction>> getTransactions(
    String customerId, {
    int limit = 50,
  }) async {
    final db = await _openDb();
    final rows = await db.query(
      _loyaltyTransactionsTable,
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return rows.map(LoyaltyTransaction.fromMap).toList(growable: false);
  }

  Future<List<LoyaltyTransaction>> getTransactionsForCustomerIds(
    List<String> customerIds, {
    int limit = 50,
  }) async {
    final ids = customerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <LoyaltyTransaction>[];

    final db = await _openDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      _loyaltyTransactionsTable,
      where: 'customerId IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return rows.map(LoyaltyTransaction.fromMap).toList(growable: false);
  }

  // ─── Giao dịch cộng / trừ điểm (atomic) ─────────────────────────────────────

  /// Cộng điểm khi mua hàng.
  /// Trả về LoyaltyPoint cập nhật sau giao dịch.
  Future<LoyaltyPoint> earnPoints({
    required String customerId,
    required String customerName,
    required int points,
    required String note,
  }) async {
    final db = await _openDb();
    late LoyaltyPoint updated;

    await db.transaction((txn) async {
      final existing = await txn.query(
        _loyaltyPointsTable,
        where: 'customerId = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      final currentPoints = existing.isEmpty
          ? 0
          : (existing.first['totalPoints'] as num?)?.toInt() ?? 0;

      final newTotal = currentPoints + points;
      await _upsertPoints(txn, customerId, customerName, newTotal);

      final tier = _computeTier(newTotal);
      await _upsertLevel(txn, customerId, tier, newTotal);

      await txn.insert(
        _loyaltyTransactionsTable,
        LoyaltyTransaction(
          customerId: customerId,
          type: LoyaltyTransactionType.earn,
          points: points,
          discountAmount: 0,
          note: note,
          createdAt: DateTime.now(),
        ).toMap(),
      );

      updated = LoyaltyPoint(
        customerId: customerId,
        customerName: customerName,
        totalPoints: newTotal,
        updatedAt: DateTime.now(),
      );
    });

    return updated;
  }

  /// Đổi điểm lấy chiết khấu.
  /// Trả về [discountAmount] (VND) hoặc ném [InsufficientPointsException].
  Future<({LoyaltyPoint updatedPoint, int discountAmount})> redeemPoints({
    required String customerId,
    required String customerName,
    required int pointsToRedeem,
    required String note,
  }) async {
    final db = await _openDb();
    late LoyaltyPoint updated;
    late int discountAmount;

    await db.transaction((txn) async {
      final existing = await txn.query(
        _loyaltyPointsTable,
        where: 'customerId = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      final currentPoints = existing.isEmpty
          ? 0
          : (existing.first['totalPoints'] as num?)?.toInt() ?? 0;

      if (currentPoints < pointsToRedeem) {
        throw InsufficientPointsException(
          available: currentPoints,
          requested: pointsToRedeem,
        );
      }

      discountAmount = _computeDiscount(pointsToRedeem);
      final newTotal = currentPoints - pointsToRedeem;

      await _upsertPoints(txn, customerId, customerName, newTotal);

      final tier = _computeTier(newTotal);
      await _upsertLevel(txn, customerId, tier, newTotal);

      await txn.insert(
        _loyaltyTransactionsTable,
        LoyaltyTransaction(
          customerId: customerId,
          type: LoyaltyTransactionType.redeem,
          points: pointsToRedeem,
          discountAmount: discountAmount,
          note: note,
          createdAt: DateTime.now(),
        ).toMap(),
      );

      updated = LoyaltyPoint(
        customerId: customerId,
        customerName: customerName,
        totalPoints: newTotal,
        updatedAt: DateTime.now(),
      );
    });

    return (updatedPoint: updated, discountAmount: discountAmount);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  CustomerLevelTier _computeTier(int points) {
    if (points >= 5000) return CustomerLevelTier.platinum;
    if (points >= 2000) return CustomerLevelTier.gold;
    if (points >= 800) return CustomerLevelTier.silver;
    return CustomerLevelTier.regular;
  }

  /// 500 điểm → 50.000 VND chiết khấu
  int _computeDiscount(int points) {
    return (points ~/ 500) * 50000;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

class InsufficientPointsException implements Exception {
  final int available;
  final int requested;

  const InsufficientPointsException({
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'InsufficientPointsException: có $available điểm, yêu cầu $requested điểm';
}
