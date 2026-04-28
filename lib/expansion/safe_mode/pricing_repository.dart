import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'pricing_models.dart';

/// PricingRepository — SQLite repository riêng cho Pricing module.
/// DB file: pricing_module_safe_mode.db (không đụng repair_shop_v22.db)
class PricingRepository {
  static const _dbName = 'pricing_module_safe_mode.db';
  static const _dbVersion = 1;

  // Tên bảng
  static const _tableRules = 'price_rules';
  static const _tableCustomerPricing = 'customer_pricing';

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableRules (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        productId TEXT    NOT NULL,
        type      TEXT    NOT NULL,
        minQty    INTEGER NOT NULL DEFAULT 0,
        price     REAL    NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_price_rules_product ON $_tableRules (productId)',
    );
    await db.execute(
      'CREATE INDEX idx_price_rules_type ON $_tableRules (type)',
    );

    await db.execute('''
      CREATE TABLE $_tableCustomerPricing (
        customerId  TEXT PRIMARY KEY,
        pricingType TEXT NOT NULL,
        updatedAt   INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Placeholder — khi cần migrate schema trong tương lai
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ─── PriceRule CRUD ────────────────────────────────────────────────────

  /// Thêm mới 1 rule giá. Trả về id được gán.
  Future<int> addRule(PriceRule rule) async {
    final db = await _database;
    final now = DateTime.now();
    return db.insert(
      _tableRules,
      rule.copyWith(createdAt: now, updatedAt: now).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cập nhật rule đã tồn tại (theo id).
  Future<void> updateRule(PriceRule rule) async {
    if (rule.id == null) throw ArgumentError('PriceRule.id must not be null to update');
    final db = await _database;
    await db.update(
      _tableRules,
      rule.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  /// Xoá rule theo id.
  Future<void> deleteRule(int id) async {
    final db = await _database;
    await db.delete(_tableRules, where: 'id = ?', whereArgs: [id]);
  }

  /// Lấy tất cả rule của 1 sản phẩm, sắp xếp: minQty giảm dần (rule cụ thể hơn ưu tiên trước).
  Future<List<PriceRule>> getRulesForProduct(String productId) async {
    final db = await _database;
    final rows = await db.query(
      _tableRules,
      where: 'productId = ?',
      whereArgs: [productId],
      orderBy: 'minQty DESC, type ASC',
    );
    return rows.map(PriceRule.fromMap).toList();
  }

  /// Lấy tất cả rule (admin view).
  Future<List<PriceRule>> getAllRules() async {
    final db = await _database;
    final rows = await db.query(_tableRules, orderBy: 'productId, type, minQty DESC');
    return rows.map(PriceRule.fromMap).toList();
  }

  // ─── CustomerPricing CRUD ─────────────────────────────────────────────

  /// Lưu hoặc cập nhật loại giá cho 1 khách hàng (upsert theo customerId).
  Future<void> saveCustomerPricing(CustomerPricing pricing) async {
    final db = await _database;
    await db.insert(
      _tableCustomerPricing,
      pricing.copyWith(updatedAt: DateTime.now()).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lấy loại giá của 1 khách. Trả về null nếu chưa cài đặt (dùng normal).
  Future<CustomerPricing?> getCustomerPricing(String customerId) async {
    final db = await _database;
    final rows = await db.query(
      _tableCustomerPricing,
      where: 'customerId = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CustomerPricing.fromMap(rows.first);
  }

  /// Xoá setting của 1 khách (reset về normal).
  Future<void> removeCustomerPricing(String customerId) async {
    final db = await _database;
    await db.delete(
      _tableCustomerPricing,
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
  }

  /// Lấy tất cả khách có cài giá riêng.
  Future<List<CustomerPricing>> getAllCustomerPricings() async {
    final db = await _database;
    final rows = await db.query(_tableCustomerPricing, orderBy: 'pricingType, customerId');
    return rows.map(CustomerPricing.fromMap).toList();
  }
}
