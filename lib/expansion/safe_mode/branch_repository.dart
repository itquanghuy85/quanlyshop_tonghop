import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'branch_models.dart';

/// SQLite repository cho Multi-Branch module.
/// DB riêng: multibranch_safe_mode.db — không đụng DB chính.
class BranchRepository {
  static const _dbName = 'multibranch_safe_mode.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    return openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE branches (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        shopId   TEXT NOT NULL,
        name     TEXT NOT NULL,
        address  TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE branch_users (
        userId     TEXT NOT NULL,
        branchId   INTEGER NOT NULL,
        role       TEXT NOT NULL DEFAULT 'staff',
        assignedAt INTEGER NOT NULL,
        PRIMARY KEY (userId, branchId),
        FOREIGN KEY (branchId) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE branch_inventory (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        productId TEXT NOT NULL,
        branchId  INTEGER NOT NULL,
        quantity  INTEGER NOT NULL DEFAULT 0,
        updatedAt INTEGER NOT NULL,
        UNIQUE(productId, branchId),
        FOREIGN KEY (branchId) REFERENCES branches(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_branch_users_branch ON branch_users(branchId)');
    await db.execute(
        'CREATE INDEX idx_branch_inv_product ON branch_inventory(productId)');
    await db.execute(
        'CREATE INDEX idx_branches_shop ON branches(shopId)');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ─── Branches ──────────────────────────────────────────────────────────────

  /// Thêm chi nhánh mới. Trả về id.
  Future<int> addBranch(Branch branch) async {
    final db = await _database;
    return db.insert('branches', branch.toMap());
  }

  /// Cập nhật thông tin chi nhánh.
  Future<void> updateBranch(Branch branch) async {
    assert(branch.id != null);
    final db = await _database;
    await db.update(
      'branches',
      branch.toMap(),
      where: 'id = ?',
      whereArgs: [branch.id],
    );
  }

  /// Soft-delete: đánh isActive = 0.
  Future<void> deactivateBranch(int branchId) async {
    final db = await _database;
    await db.update(
      'branches',
      {'isActive': 0},
      where: 'id = ?',
      whereArgs: [branchId],
    );
  }

  /// Lấy tất cả chi nhánh của shop (chỉ active).
  Future<List<Branch>> getBranchesForShop(String shopId,
      {bool activeOnly = true}) async {
    final db = await _database;
    final rows = await db.query(
      'branches',
      where: activeOnly ? 'shopId = ? AND isActive = 1' : 'shopId = ?',
      whereArgs: [shopId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(Branch.fromMap).toList();
  }

  /// Lấy 1 chi nhánh theo id.
  Future<Branch?> getBranchById(int id) async {
    final db = await _database;
    final rows =
        await db.query('branches', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Branch.fromMap(rows.first);
  }

  // ─── BranchUsers ───────────────────────────────────────────────────────────

  /// Gán user vào chi nhánh (upsert).
  Future<void> assignUser(BranchUser bu) async {
    final db = await _database;
    await db.insert(
      'branch_users',
      bu.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Gỡ user khỏi tất cả chi nhánh của shop rồi gán lại 1 chi nhánh mới.
  /// Dùng khi chuyển chi nhánh.
  Future<void> reassignUser({
    required String userId,
    required int newBranchId,
    String role = 'staff',
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(
        'branch_users',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      await txn.insert('branch_users', {
        'userId': userId,
        'branchId': newBranchId,
        'role': role,
        'assignedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Lấy chi nhánh hiện tại của user (lấy bản ghi đầu tiên).
  Future<Branch?> getBranchForUser(String userId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT b.*
      FROM branches b
      INNER JOIN branch_users bu ON bu.branchId = b.id
      WHERE bu.userId = ?
      LIMIT 1
    ''', [userId]);
    if (rows.isEmpty) return null;
    return Branch.fromMap(rows.first);
  }

  /// Lấy danh sách userId trong 1 chi nhánh.
  Future<List<BranchUser>> getUsersInBranch(int branchId) async {
    final db = await _database;
    final rows = await db.query(
      'branch_users',
      where: 'branchId = ?',
      whereArgs: [branchId],
    );
    return rows.map(BranchUser.fromMap).toList();
  }

  // ─── BranchInventory ───────────────────────────────────────────────────────

  /// Upsert số lượng tồn cho 1 sản phẩm tại 1 chi nhánh.
  Future<void> upsertInventory(BranchInventory inv) async {
    final db = await _database;
    await db.insert(
      'branch_inventory',
      inv.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Điều chỉnh số lượng (cộng/trừ) trong transaction.
  Future<void> adjustInventory({
    required String productId,
    required int branchId,
    required int delta,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'branch_inventory',
        where: 'productId = ? AND branchId = ?',
        whereArgs: [productId, branchId],
      );
      if (rows.isEmpty) {
        // Chưa có bản ghi → tạo mới
        await txn.insert('branch_inventory', {
          'productId': productId,
          'branchId': branchId,
          'quantity': delta.clamp(0, double.maxFinite.toInt()),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        final current = rows.first['quantity'] as int;
        final newQty = (current + delta).clamp(0, double.maxFinite.toInt());
        await txn.update(
          'branch_inventory',
          {
            'quantity': newQty,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'productId = ? AND branchId = ?',
          whereArgs: [productId, branchId],
        );
      }
    });
  }

  /// Lấy tất cả tồn kho của 1 chi nhánh.
  Future<List<BranchInventory>> getInventoryForBranch(int branchId) async {
    final db = await _database;
    final rows = await db.query(
      'branch_inventory',
      where: 'branchId = ?',
      whereArgs: [branchId],
      orderBy: 'updatedAt DESC',
    );
    return rows.map(BranchInventory.fromMap).toList();
  }

  /// Lấy tồn kho của 1 sản phẩm tại 1 chi nhánh.
  Future<BranchInventory?> getInventoryItem({
    required String productId,
    required int branchId,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'branch_inventory',
      where: 'productId = ? AND branchId = ?',
      whereArgs: [productId, branchId],
    );
    if (rows.isEmpty) return null;
    return BranchInventory.fromMap(rows.first);
  }

  /// Lấy tổng tồn kho của 1 sản phẩm trên tất cả chi nhánh.
  Future<int> getTotalQuantityForProduct(String productId) async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT SUM(quantity) as total FROM branch_inventory WHERE productId = ?',
      [productId],
    );
    return (result.first['total'] as int?) ?? 0;
  }
}
