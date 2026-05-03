import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_write_helper.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/purchase_order_model.dart';
import '../models/attendance_model.dart';
import '../models/leave_request_model.dart';
import '../models/quick_input_code_model.dart';
import '../services/user_service.dart';

/// Kết quả của [DBHelper.deductPartsAndUpdateRepairAtomic].
class AtomicPartsResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> partsToSync;
  const AtomicPartsResult({
    required this.success,
    this.message,
    this.partsToSync = const [],
  });
}

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  static bool _factoryInitialized = false;
  DBHelper._internal();
  factory DBHelper() => _instance;

  static void _ensureDatabaseFactoryInitialized() {
    if (_factoryInitialized) return;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    _factoryInitialized = true;
  }

  /// Helper: build SQL WHERE clause that matches both old (Vietnamese) and new (ASCII) type values
  /// e.g. 'LINH_KIEN' → "(type = 'LINH_KIEN' OR type = 'LINH KIỆN')"
  static String _typeWhereClause(String type, List<dynamic> args) {
    switch (type) {
      case 'LINH_KIEN':
        args.addAll(['LINH_KIEN', 'LINH KIỆN']);
        return '(type = ? OR type = ?)';
      case 'PHU_KIEN':
        args.addAll(['PHU_KIEN', 'PHỤ KIỆN']);
        return '(type = ? OR type = ?)';
      default:
        args.add(type);
        return 'type = ?';
    }
  }

  /// Helper để lấy shopId hiện tại (dùng cho query, không throw exception)
  /// Trả về shopId hoặc null nếu không có
  Future<String?> _getCurrentShopId() async {
    // Thử lấy từ cache trước (nhanh)
    final cachedShopId = UserService.getShopIdSync();
    if (cachedShopId != null && cachedShopId.isNotEmpty) {
      return cachedShopId;
    }
    // Nếu không có cache, thử lấy từ Firestore
    return await UserService.getCurrentShopId();
  }

  /// Helper để đảm bảo shopId hợp lệ trước khi ghi dữ liệu quan trọng
  /// Trả về shopId hoặc throw Exception nếu không có
  Future<String> _ensureValidShopId([String? existingShopId]) async {
    if (existingShopId != null && existingShopId.isNotEmpty) {
      return existingShopId;
    }

    // Thử lấy từ cache trước (nhanh)
    final cachedShopId = UserService.getShopIdSync();
    if (cachedShopId != null && cachedShopId.isNotEmpty) {
      return cachedShopId;
    }

    // Nếu không có cache, thử lấy từ Firestore
    final shopId = await UserService.getCurrentShopId();
    if (shopId != null && shopId.isNotEmpty) {
      return shopId;
    }

    // Log cảnh báo nếu không có shopId
    debugPrint('⚠️ DBHelper: No valid shopId available for data write');
    throw Exception(
      'Không có shopId hợp lệ. Vui lòng đăng xuất và đăng nhập lại.',
    );
  }

  /// Helper để lấy shopId cho các truy vấn nhạy cảm theo tenant.
  /// Trả về null nếu chưa có shopId (caller nên trả về rỗng để tránh lộ dữ liệu chéo shop).
  Future<String?> _getScopedShopId(String context) async {
    final shopId = await _getCurrentShopId();
    if (shopId == null || shopId.isEmpty) {
      debugPrint(
        'DBHelper.$context: missing shopId, return empty scoped result',
      );
      return null;
    }
    return shopId;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  /// Cache column names per table to avoid repeated PRAGMA queries
  static final Map<String, Set<String>> _tableColumnsCache = {};

  /// Get valid column names for a table, cached for performance
  Future<Set<String>> _getTableColumns(
    String table, {
    DatabaseExecutor? executor,
  }) async {
    if (_tableColumnsCache.containsKey(table)) {
      return _tableColumnsCache[table]!;
    }
    final dbExecutor = executor ?? await database;
    final cols = await dbExecutor.rawQuery('PRAGMA table_info($table)');
    final names = cols.map((c) => c['name'] as String).toSet();
    _tableColumnsCache[table] = names;
    return names;
  }

  /// Strip keys from data that don't exist as columns in the given table
  Future<Map<String, dynamic>> _filterToTableColumns(
    String table,
    Map<String, dynamic> data, {
    DatabaseExecutor? executor,
  }) async {
    final validCols = await _getTableColumns(table, executor: executor);
    data.removeWhere((key, _) => !validCols.contains(key));
    return data;
  }

  Future<bool> _tableHasColumn(
    DatabaseExecutor executor,
    String table,
    String column,
  ) async {
    final cols = await executor.rawQuery('PRAGMA table_info($table)');
    return cols.any((c) => (c['name'] ?? '').toString() == column);
  }

  Future<void> _ensureColumnExists({
    required DatabaseExecutor executor,
    required String table,
    required String column,
    required String definition,
    required String logScope,
  }) async {
    if (await _tableHasColumn(executor, table, column)) {
      return;
    }

    try {
      await executor.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
      _tableColumnsCache.remove(table);
      debugPrint('$logScope: added $column to $table');
    } catch (e) {
      debugPrint('$logScope error ($table.$column): $e');
    }
  }

  // 🔥 FIX: tách riêng function này
Future<void> _forceFixMissingColumns(Database db) async {
  await _ensureColumnExists(
    executor: db,
    table: 'repairs',
    column: 'requestedDeliveryPrice',
    definition: 'INTEGER',
    logScope: 'FORCE FIX',
  );

  await _ensureColumnExists(
    executor: db,
    table: 'repairs',
    column: 'pendingDeliveryApproval',
    definition: 'INTEGER DEFAULT 0',
    logScope: 'FORCE FIX',
  );

  await _ensureColumnExists(
    executor: db,
    table: 'repairs',
    column: 'costRecordedAmount',
    definition: 'INTEGER DEFAULT 0',
    logScope: 'FORCE FIX',
  );
}

// 🔥 FIX: function này phải riêng, không lồng
Future<void> _ensureUniqueIndexExists({
  required DatabaseExecutor executor,
  required String indexName,
  required String table,
  required String column,
  required String logScope,
}) async {
  try {
    await executor.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS $indexName ON $table($column)',
    );
  } catch (e) {
    debugPrint('$logScope error ($indexName): $e');
  }
}
  Future<void> _ensurePaymentIntentsSchema([DatabaseExecutor? executor]) async {
    final dbExecutor = executor ?? await database;

    try {
      await dbExecutor.execute('''
        CREATE TABLE IF NOT EXISTS payment_intents(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          intentId TEXT UNIQUE NOT NULL,
          firestoreId TEXT,
          type TEXT NOT NULL,
          amount INTEGER NOT NULL,
          description TEXT,
          status TEXT DEFAULT 'PENDING',
          personName TEXT,
          personPhone TEXT,
          referenceId TEXT,
          referenceType TEXT,
          paymentMethod TEXT,
          createdBy TEXT,
          createdAt INTEGER,
          paidBy TEXT,
          paidAt INTEGER,
          notes TEXT,
          metadata TEXT,
          shopId TEXT,
          isSynced INTEGER DEFAULT 0,
          deleted INTEGER DEFAULT 0,
          updatedAt INTEGER
        )
      ''');

      final cols = await dbExecutor.rawQuery(
        'PRAGMA table_info(payment_intents)',
      );
      final colNames = cols.map((c) => c['name'] as String).toSet();

      if (!colNames.contains('firestoreId')) {
        await dbExecutor.execute(
          'ALTER TABLE payment_intents ADD COLUMN firestoreId TEXT',
        );
        _tableColumnsCache.remove('payment_intents');
      }
      if (!colNames.contains('deleted')) {
        await dbExecutor.execute(
          'ALTER TABLE payment_intents ADD COLUMN deleted INTEGER DEFAULT 0',
        );
        _tableColumnsCache.remove('payment_intents');
      }
      if (!colNames.contains('updatedAt')) {
        await dbExecutor.execute(
          'ALTER TABLE payment_intents ADD COLUMN updatedAt INTEGER',
        );
        _tableColumnsCache.remove('payment_intents');
      }

      await dbExecutor.execute(
        'CREATE INDEX IF NOT EXISTS idx_payment_intents_firestoreId ON payment_intents(firestoreId)',
      );
    } catch (e) {
      debugPrint('DB: ensure payment_intents schema error: $e');
    }
  }

  Future<void> _ensurePayrollSettingsColumns(
    DatabaseExecutor executor, {
    String logScope = 'DB',
  }) async {
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommType',
      definition: 'TEXT DEFAULT "percent"',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommTier1Max',
      definition: 'REAL DEFAULT 10000000',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommTier1Value',
      definition: 'REAL DEFAULT 20000',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommTier2Max',
      definition: 'REAL DEFAULT 50000000',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommTier2Value',
      definition: 'REAL DEFAULT 50000',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'saleCommTier3Value',
      definition: 'REAL DEFAULT 100000',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'repairCommType',
      definition: 'TEXT DEFAULT "percent"',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'transportAllowance',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'mealAllowance',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'phoneAllowance',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'otherAllowance',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'otherAllowanceNote',
      definition: 'TEXT',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'targetBonus',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
    await _ensureColumnExists(
      executor: executor,
      table: 'payroll_settings',
      column: 'monthlyTarget',
      definition: 'REAL DEFAULT 0',
      logScope: logScope,
    );
  }

  Future<Database> _initDB() async {
  _ensureDatabaseFactoryInitialized();
  String path = join(await getDatabasesPath(), 'repair_shop_v22.db');

  final db = await openDatabase(
    path,
    version: 96,
    onConfigure: (db) async {
      try {
        await db.rawQuery('PRAGMA foreign_keys = ON');
      } catch (e) {
        debugPrint('DB onConfigure foreign_keys error: $e');
      }

      if (!kIsWeb) {
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        } catch (e) {
          debugPrint('DB onConfigure journal_mode error: $e');
        }
        try {
          await db.rawQuery('PRAGMA synchronous = NORMAL');
        } catch (e) {
          debugPrint('DB onConfigure synchronous error: $e');
        }
      }

      try {
        await db.rawQuery('PRAGMA busy_timeout = 5000');
      } catch (e) {
        debugPrint('DB onConfigure busy_timeout error: $e');
      }
    },

      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repairs(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, customerName TEXT, phone TEXT, isWalkIn INTEGER DEFAULT 0, walkInName TEXT, walkInPhone TEXT, model TEXT, issue TEXT, accessories TEXT, address TEXT, imagePath TEXT, deliveredImage TEXT, warranty TEXT, partsUsed TEXT, status INTEGER, price INTEGER, cost INTEGER, paymentMethod TEXT, createdAt INTEGER, startedAt INTEGER, finishedAt INTEGER, deliveredAt INTEGER, createdBy TEXT, createdByUid TEXT, repairedBy TEXT, repairedByUid TEXT, deliveredBy TEXT, deliveredByUid TEXT, lastCaredAt INTEGER, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, color TEXT, imei TEXT, condition TEXT, services TEXT, notes TEXT, pendingDeliveryApproval INTEGER DEFAULT 0, requestedDeliveryPrice INTEGER, costRecordedInFund INTEGER DEFAULT 0, costPaymentMethod TEXT, costRecordedAt INTEGER, costRecordedAmount INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS products(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, name TEXT, brand TEXT, model TEXT, imei TEXT, cost INTEGER, price INTEGER, condition TEXT, status INTEGER DEFAULT 1, description TEXT, images TEXT, warranty TEXT, createdAt INTEGER, updatedAt INTEGER, supplier TEXT, type TEXT DEFAULT "DIEN_THOAI", quantity INTEGER DEFAULT 1, color TEXT, isSynced INTEGER DEFAULT 0, capacity TEXT, size TEXT, paymentMethod TEXT, labelInfo TEXT, isPending INTEGER DEFAULT 0, pendingSupplier TEXT, deleted INTEGER DEFAULT 0, labelNote TEXT, categoryId TEXT, unit TEXT, expiryDate INTEGER, batchNumber TEXT, variantParentId TEXT, customData TEXT, sku TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS sales(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, customerName TEXT, phone TEXT, isWalkIn INTEGER DEFAULT 0, walkInName TEXT, walkInPhone TEXT, address TEXT, productNames TEXT, productImeis TEXT, totalPrice INTEGER, totalCost INTEGER, discount INTEGER DEFAULT 0, paymentMethod TEXT, sellerName TEXT, sellerUid TEXT, soldAt INTEGER, notes TEXT, gifts TEXT, isInstallment INTEGER DEFAULT 0, downPayment INTEGER DEFAULT 0, downPaymentMethod TEXT, loanAmount INTEGER DEFAULT 0, installmentTerm TEXT, bankName TEXT, bankName2 TEXT, loanAmount2 INTEGER DEFAULT 0, warranty TEXT, settlementPlannedAt INTEGER, settlementReceivedAt INTEGER, settlementAmount INTEGER DEFAULT 0, settlementFee INTEGER DEFAULT 0, settlementNote TEXT, settlementCode TEXT, cashAmount INTEGER DEFAULT 0, transferAmount INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, avatarUrl TEXT, coverUrl TEXT, coverAlignX REAL DEFAULT 0, coverAlignY REAL DEFAULT 0, name TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, createdAt INTEGER, lastVisitAt INTEGER, updatedAt INTEGER, totalSpent INTEGER DEFAULT 0, totalRepairs INTEGER DEFAULT 0, totalRepairCost INTEGER DEFAULT 0, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, contactPerson TEXT, phone TEXT, email TEXT, address TEXT, note TEXT, items TEXT, importCount INTEGER DEFAULT 0, totalAmount INTEGER DEFAULT 0, active INTEGER DEFAULT 1, favorite INTEGER DEFAULT 0, type TEXT, createdAt INTEGER, updatedAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, title TEXT, description TEXT, amount INTEGER, category TEXT, date INTEGER, note TEXT, paymentMethod TEXT, createdAt INTEGER, createdBy TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, relatedPartId TEXT, type TEXT DEFAULT "CHI", scope TEXT DEFAULT "SHOP")',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS debts(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, personName TEXT, phone TEXT, totalAmount INTEGER, paidAmount INTEGER DEFAULT 0, type TEXT, debtType TEXT, status TEXT, createdAt INTEGER, note TEXT, isSynced INTEGER DEFAULT 0, linkedId TEXT, linkedType TEXT, createdBy TEXT, shopId TEXT, relatedPartId TEXT, deleted INTEGER DEFAULT 0, updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS attendance(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, email TEXT, name TEXT, dateKey TEXT, checkInAt INTEGER, checkOutAt INTEGER, overtimeOn INTEGER DEFAULT 0, overtimeStartAt INTEGER, overtimeEndAt INTEGER, photoIn TEXT, photoOut TEXT, note TEXT, status TEXT DEFAULT "pending", approvedBy TEXT, approvedAt INTEGER, rejectReason TEXT, requestType TEXT, locked INTEGER DEFAULT 0, createdAt INTEGER, location TEXT, isLate INTEGER DEFAULT 0, isEarlyLeave INTEGER DEFAULT 0, workSchedule TEXT, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS leave_requests(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, email TEXT, name TEXT, leaveType TEXT, startDate TEXT, endDate TEXT, totalDays REAL, reason TEXT, status TEXT DEFAULT "pending", approvedBy TEXT, approvedAt INTEGER, rejectReason TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS audit_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, userName TEXT, action TEXT, targetType TEXT, targetId TEXT, description TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, summary TEXT, role TEXT, email TEXT, payload TEXT, entityType TEXT, entityId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS inventory_checks(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, type TEXT, checkDate INTEGER, itemsJson TEXT, status TEXT, createdBy TEXT, createdAt INTEGER, isSynced INTEGER DEFAULT 0, isCompleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_partner_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partnerId INTEGER, partnerName TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS cash_closings(id INTEGER PRIMARY KEY AUTOINCREMENT, dateKey TEXT UNIQUE, cashStart INTEGER DEFAULT 0, bankStart INTEGER DEFAULT 0, cashEnd INTEGER DEFAULT 0, bankEnd INTEGER DEFAULT 0, expectedCashDelta INTEGER DEFAULT 0, expectedBankDelta INTEGER DEFAULT 0, note TEXT, createdAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS payroll_settings(id INTEGER PRIMARY KEY AUTOINCREMENT, baseSalary INTEGER DEFAULT 0, saleCommPercent REAL DEFAULT 1.0, saleCommType TEXT DEFAULT "percent", saleCommTier1Max REAL DEFAULT 10000000, saleCommTier1Value REAL DEFAULT 20000, saleCommTier2Max REAL DEFAULT 50000000, saleCommTier2Value REAL DEFAULT 50000, saleCommTier3Value REAL DEFAULT 100000, repairProfitPercent REAL DEFAULT 10.0, repairCommType TEXT DEFAULT "percent", transportAllowance REAL DEFAULT 0, mealAllowance REAL DEFAULT 0, phoneAllowance REAL DEFAULT 0, otherAllowance REAL DEFAULT 0, otherAllowanceNote TEXT, targetBonus REAL DEFAULT 0, monthlyTarget REAL DEFAULT 0, updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS payroll_locks(id INTEGER PRIMARY KEY AUTOINCREMENT, monthKey TEXT UNIQUE, locked INTEGER DEFAULT 0, lockedBy TEXT, lockedAt INTEGER, note TEXT)',
        );
        await db.execute('''CREATE TABLE IF NOT EXISTS employee_salary_settings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            staffId TEXT NOT NULL,
            staffName TEXT,
            shopId TEXT,
            baseSalary REAL DEFAULT 0,
            dailyRate REAL DEFAULT 0,
            salaryType TEXT DEFAULT "monthly",
            saleCommType TEXT DEFAULT "percent",
            saleCommValue REAL DEFAULT 1.0,
            saleCommTier1Max REAL DEFAULT 10000000,
            saleCommTier1Value REAL DEFAULT 20000,
            saleCommTier2Max REAL DEFAULT 50000000,
            saleCommTier2Value REAL DEFAULT 50000,
            saleCommTier3Value REAL DEFAULT 100000,
            repairCommType TEXT DEFAULT "percent",
            repairCommValue REAL DEFAULT 10.0,
            transportAllowance REAL DEFAULT 0,
            mealAllowance REAL DEFAULT 0,
            phoneAllowance REAL DEFAULT 0,
            otherAllowance REAL DEFAULT 0,
            otherAllowanceNote TEXT,
            monthlyTarget REAL DEFAULT 0,
            targetBonusPercent REAL DEFAULT 0,
            standardHoursPerDay REAL DEFAULT 8.0,
            overtimeRate REAL DEFAULT 150,
            createdAt INTEGER,
            updatedAt INTEGER,
            updatedBy TEXT,
            isActive INTEGER DEFAULT 1,
            isSynced INTEGER DEFAULT 0
          )''');
        await db.execute(
          'CREATE TABLE IF NOT EXISTS purchase_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, orderCode TEXT UNIQUE, supplierName TEXT, supplierPhone TEXT, supplierAddress TEXT, itemsJson TEXT, totalAmount INTEGER, totalCost INTEGER, createdAt INTEGER, createdBy TEXT, status TEXT DEFAULT "PENDING", paymentMethod TEXT, notes TEXT, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS work_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT UNIQUE, startTime TEXT DEFAULT "08:00", endTime TEXT DEFAULT "17:00", breakTime INTEGER DEFAULT 1, maxOtHours INTEGER DEFAULT 4, workDays TEXT DEFAULT "[1,2,3,4,5,6]", holidays TEXT, weekdayOtRate INTEGER DEFAULT 150, weekendOtRate INTEGER DEFAULT 200, holidayOtRate INTEGER DEFAULT 300, shopId TEXT, updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS debt_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, debtId INTEGER, debtFirestoreId TEXT, debtType TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, createdBy TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, personName TEXT, receivedBy TEXT, totalDebt INTEGER DEFAULT 0, alreadyPaid INTEGER DEFAULT 0, customerName TEXT, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS quick_input_codes(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, code TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, labelInfo TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_product_prices(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, productName TEXT, productBrand TEXT, productModel TEXT, costPrice INTEGER, lastUpdated INTEGER, createdAt INTEGER, isActive INTEGER DEFAULT 1, shopId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_import_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, supplierName TEXT, productName TEXT, productBrand TEXT, productModel TEXT, imei TEXT, quantity INTEGER, costPrice INTEGER, totalAmount INTEGER, paymentMethod TEXT, importDate INTEGER, importedBy TEXT, importedByUid TEXT, referenceId TEXT, createdAt INTEGER, notes TEXT, isSynced INTEGER DEFAULT 0, shopId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_partners(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, phone TEXT, note TEXT, active INTEGER DEFAULT 1, createdAt INTEGER, updatedAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS partner_repair_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, repairOrderId TEXT, partnerId INTEGER, partnerFirestoreId TEXT, customerName TEXT, deviceModel TEXT, issue TEXT, partnerCost INTEGER, repairContent TEXT, sentAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_parts(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partName TEXT, compatibleModels TEXT, cost INTEGER, price INTEGER, quantity INTEGER, updatedAt INTEGER, createdAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0, supplierId INTEGER, paymentMethod TEXT, createdBy TEXT, stockEntryId TEXT)',
        );
        // Sync queue table for tracking pending sync operations
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_queue(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entityType TEXT NOT NULL,
            entityId INTEGER NOT NULL,
            firestoreId TEXT,
            operation TEXT NOT NULL,
            data TEXT,
            createdAt INTEGER NOT NULL,
            retryCount INTEGER DEFAULT 0,
            lastError TEXT,
            status TEXT DEFAULT 'pending'
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity ON sync_queue(entityType, entityId)',
        );
        // === SALES RETURNS TABLES (v60) - CHỈ THÊM MỚI, KHÔNG SỬA LOGIC CŨ ===
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales_returns(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            salesOrderId INTEGER,
            salesOrderFirestoreId TEXT,
            customerName TEXT,
            customerPhone TEXT,
            returnDate INTEGER,
            totalReturnAmount INTEGER DEFAULT 0,
            totalReturnCost INTEGER DEFAULT 0,
            refundMethod TEXT DEFAULT 'TIỀN MẶT',
            note TEXT,
            createdAt INTEGER,
            createdBy TEXT,
            approvedBy TEXT,
            approvedAt INTEGER,
            status TEXT DEFAULT 'APPROVED',
            shopId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales_return_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            salesReturnId INTEGER,
            salesReturnFirestoreId TEXT,
            productId INTEGER,
            productFirestoreId TEXT,
            productName TEXT,
            productImei TEXT,
            quantity INTEGER DEFAULT 1,
            price INTEGER DEFAULT 0,
            cost INTEGER DEFAULT 0,
            amount INTEGER DEFAULT 0,
            shopId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_returns_shopId ON sales_returns(shopId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_returns_salesOrderId ON sales_returns(salesOrderId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_return_items_salesReturnId ON sales_return_items(salesReturnId)',
        );
        // === FINANCIAL ACTIVITY LOG TABLE (v61) ===
        await db.execute('''
          CREATE TABLE IF NOT EXISTS financial_activity_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            activityType TEXT NOT NULL,
            amount INTEGER NOT NULL,
            direction TEXT NOT NULL,
            paymentMethod TEXT,
            referenceType TEXT,
            referenceId TEXT,
            title TEXT NOT NULL,
            description TEXT,
            customerName TEXT,
            phone TEXT,
            productInfo TEXT,
            balanceAfterCash INTEGER,
            balanceAfterBank INTEGER,
            createdAt INTEGER NOT NULL,
            createdBy TEXT,
            shopId TEXT,
            isSynced INTEGER DEFAULT 0,
            extraData TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_financial_activity_shopId ON financial_activity_log(shopId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_financial_activity_createdAt ON financial_activity_log(createdAt)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_financial_activity_type ON financial_activity_log(activityType)',
        );
        // === MULTI-INDUSTRY EXPANSION - Phase 1 (v75) ===
        await db.execute('''
          CREATE TABLE IF NOT EXISTS shop_settings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            shopId TEXT,
            businessType TEXT DEFAULT 'electronics',
            businessTypeName TEXT,
            enableRepair INTEGER DEFAULT 1,
            enableExpiry INTEGER DEFAULT 0,
            enableVariants INTEGER DEFAULT 0,
            enableSerial INTEGER DEFAULT 1,
            enableWarranty INTEGER DEFAULT 1,
            enableBatch INTEGER DEFAULT 0,
            defaultUnit TEXT DEFAULT 'cái',
            expiryWarningDays INTEGER DEFAULT 7,
            lowStockWarning INTEGER DEFAULT 5,
            createdAt INTEGER,
            updatedAt INTEGER,
            updatedBy TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            shopId TEXT,
            name TEXT,
            description TEXT,
            icon TEXT,
            color TEXT,
            parentId TEXT,
            sortOrder INTEGER DEFAULT 0,
            trackExpiry INTEGER DEFAULT 0,
            trackSerial INTEGER DEFAULT 0,
            hasVariants INTEGER DEFAULT 0,
            hasWarranty INTEGER DEFAULT 0,
            defaultWarrantyDays INTEGER DEFAULT 0,
            customFields TEXT,
            isActive INTEGER DEFAULT 1,
            createdAt INTEGER,
            updatedAt INTEGER,
            updatedBy TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_product_categories_shopId ON product_categories(shopId)',
        );
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_variants(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            shopId TEXT,
            productId TEXT,
            sku TEXT,
            size TEXT,
            color TEXT,
            colorCode TEXT,
            material TEXT,
            style TEXT,
            costPrice INTEGER DEFAULT 0,
            salePrice INTEGER DEFAULT 0,
            quantity INTEGER DEFAULT 0,
            minQuantity INTEGER DEFAULT 0,
            barcode TEXT,
            image TEXT,
            isActive INTEGER DEFAULT 1,
            createdAt INTEGER,
            updatedAt INTEGER,
            updatedBy TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_product_variants_productId ON product_variants(productId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_product_variants_shopId ON product_variants(shopId)',
        );

        // Salvage phones (Kho máy xác)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS salvage_phones(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            shopId TEXT,
            deviceName TEXT,
            customerName TEXT,
            customerPhone TEXT,
            cost INTEGER DEFAULT 0,
            notes TEXT,
            images TEXT,
            status TEXT DEFAULT 'STORED',
            createdAt INTEGER,
            updatedAt INTEGER,
            createdBy TEXT,
            isSynced INTEGER DEFAULT 0,
            deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salvage_phones_shopId ON salvage_phones(shopId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salvage_phones_status ON salvage_phones(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_salvage_phones_createdAt ON salvage_phones(createdAt)',
        );

        // Import orders (Phiếu nhập kho)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS import_orders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            shopId TEXT,
            orderCode TEXT,
            supplierId TEXT,
            supplierName TEXT,
            totalQuantity INTEGER DEFAULT 0,
            totalAmount INTEGER DEFAULT 0,
            paymentMethod TEXT,
            paymentStatus TEXT DEFAULT 'PAID',
            paidAmount INTEGER,
            status TEXT DEFAULT 'CONFIRMED',
            importDate INTEGER,
            importedBy TEXT,
            importedByUid TEXT,
            stockEntryId TEXT,
            notes TEXT,
            createdAt INTEGER,
            updatedAt INTEGER,
            isSynced INTEGER DEFAULT 0,
            deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_orders_shopId ON import_orders(shopId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_orders_importDate ON import_orders(importDate)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_orders_status ON import_orders(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_orders_stockEntryId ON import_orders(stockEntryId)',
        );

        // Import order items (Chi tiết phiếu nhập)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS import_order_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firestoreId TEXT UNIQUE,
            importOrderFirestoreId TEXT,
            productType TEXT DEFAULT 'OTHER',
            categoryId TEXT,
            productName TEXT,
            productBrand TEXT,
            productModel TEXT,
            imei TEXT,
            sku TEXT,
            quantity INTEGER DEFAULT 1,
            unit TEXT,
            costPrice INTEGER DEFAULT 0,
            totalAmount INTEGER DEFAULT 0,
            color TEXT,
            size TEXT,
            capacity TEXT,
            condition TEXT,
            warranty INTEGER,
            compatibleModels TEXT,
            notes TEXT,
            shopId TEXT,
            isSynced INTEGER DEFAULT 0,
            deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_order_items_orderFsId ON import_order_items(importOrderFirestoreId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_import_order_items_shopId ON import_order_items(shopId)',
        );

        // === Performance indexes for frequently queried columns ===
        // repairs
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_createdAt ON repairs(createdAt)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_status ON repairs(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_repairedBy ON repairs(repairedBy)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repairs_deleted ON repairs(deleted)',
        );
        // sales
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_soldAt ON sales(soldAt)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_sellerName ON sales(sellerName)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_deleted ON sales(deleted)',
        );
        // products
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_deleted ON products(deleted)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_status ON products(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_shopId ON products(shopId)',
        );
        // expenses
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)',
        );
        // debts
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_debts_createdAt ON debts(createdAt)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_debts_status ON debts(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_debts_deleted ON debts(deleted)',
        );
        // attendance
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attendance_dateKey ON attendance(dateKey)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attendance_userId ON attendance(userId)',
        );
        // leave_requests
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_leave_requests_userId ON leave_requests(userId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status)',
        );
        // debt_payments
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_debt_payments_paidAt ON debt_payments(paidAt)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_debt_payments_debtId ON debt_payments(debtId)',
        );
        // supplier_payments
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_supplier_payments_paidAt ON supplier_payments(paidAt)',
        );
        // repair_partner_payments
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_repair_partner_payments_paidAt ON repair_partner_payments(paidAt)',
        );
        // customers
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
        );
        await db.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_shop_phone_unique ON customers(shopId, phone) WHERE phone IS NOT NULL AND phone <> ''",
        );
      },
      onUpgrade: (db, oldV, newV) async {
        debugPrint('Upgrading DB from $oldV to $newV');
        if (oldV < 18) {
          try {
            await db.execute('ALTER TABLE debts ADD COLUMN linkedId TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (debts linkedId): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS purchase_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, orderCode TEXT UNIQUE, supplierName TEXT, supplierPhone TEXT, supplierAddress TEXT, itemsJson TEXT, totalAmount INTEGER, totalCost INTEGER, createdAt INTEGER, createdBy TEXT, status TEXT DEFAULT "PENDING", notes TEXT, isSynced INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (purchase_orders): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS work_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT UNIQUE, startTime TEXT DEFAULT "08:00", endTime TEXT DEFAULT "17:00", breakTime INTEGER DEFAULT 1, maxOtHours INTEGER DEFAULT 4, workDays TEXT DEFAULT "[1,2,3,4,5,6]", updatedAt INTEGER)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (work_schedules): $e');
          }
        }
        if (oldV < 19) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS debt_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, debtId INTEGER, debtFirestoreId TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, createdBy TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (debt_payments): $e');
          }
        }
        if (oldV < 20) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS payroll_locks(id INTEGER PRIMARY KEY AUTOINCREMENT, monthKey TEXT UNIQUE, locked INTEGER DEFAULT 0, lockedBy TEXT, lockedAt INTEGER, note TEXT)',
            );
          } catch (_) {}
        }
        if (oldV < 21) {
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN paymentMethod TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products paymentMethod): $e');
          }
        }
        if (oldV < 22) {
          // Ensure paymentMethod column exists (in case upgrade failed)
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN paymentMethod TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products paymentMethod v22): $e');
          }
        }
        if (oldV < 23) {
          try {
            await db.execute(
              'ALTER TABLE purchase_orders ADD COLUMN paymentMethod TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (purchase_orders paymentMethod): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS quick_input_codes(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, labelInfo TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (quick_input_codes): $e');
          }
        }
        if (oldV < 24) {
          try {
            await db.execute(
              'ALTER TABLE inventory_checks ADD COLUMN checkedBy TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (inventory_checks checkedBy): $e');
          }
        }
        if (oldV < 25) {
          try {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products model): $e');
          }
        }
        if (oldV < 69) {
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN deleted INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products deleted): $e');
          }
        }
        if (oldV < 70) {
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN isWalkIn INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (repairs isWalkIn): $e');
          }
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN walkInName TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (repairs walkInName): $e');
          }
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN walkInPhone TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (repairs walkInPhone): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN isWalkIn INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (sales isWalkIn): $e');
          }
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN walkInName TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (sales walkInName): $e');
          }
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN walkInPhone TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (sales walkInPhone): $e');
          }
        }
        if (oldV < 71) {
          try {
            await db.execute('ALTER TABLE products ADD COLUMN labelInfo TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products labelInfo): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE quick_input_codes ADD COLUMN labelInfo TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (quick_input_codes labelInfo): $e');
          }
        }
        if (oldV < 72) {
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN stockEntryId TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts stockEntryId): $e');
          }
        }
        if (oldV < 73) {
          // Add shopId, updatedAt, model, labelNote to products table for multi-shop support
          try {
            await db.execute('ALTER TABLE products ADD COLUMN shopId TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN updatedAt INTEGER',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products updatedAt): $e');
          }
          try {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products model): $e');
          }
          try {
            await db.execute('ALTER TABLE products ADD COLUMN labelNote TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products labelNote): $e');
          }
        }
        if (oldV < 74) {
          // Add firestoreId column to payment_intents table for cloud sync
          debugPrint(
            'DB upgrade v74: Adding firestoreId to payment_intents table...',
          );
          try {
            await db.execute(
              'ALTER TABLE payment_intents ADD COLUMN firestoreId TEXT',
            );
            debugPrint('v74: added firestoreId column to payment_intents');
          } catch (e) {
            debugPrint('v74 error (firestoreId): $e');
          }
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_payment_intents_firestoreId ON payment_intents(firestoreId)',
            );
            debugPrint('v74: created index on payment_intents firestoreId');
          } catch (e) {
            debugPrint('v74 error (index): $e');
          }
        }
        // === MULTI-INDUSTRY EXPANSION - Phase 1 (v75) ===
        if (oldV < 75) {
          debugPrint('DB upgrade v75: Multi-industry expansion tables...');
          // shop_settings table
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS shop_settings(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                shopId TEXT,
                businessType TEXT DEFAULT 'electronics',
                businessTypeName TEXT,
                enableRepair INTEGER DEFAULT 1,
                enableExpiry INTEGER DEFAULT 0,
                enableVariants INTEGER DEFAULT 0,
                enableSerial INTEGER DEFAULT 1,
                enableWarranty INTEGER DEFAULT 1,
                enableBatch INTEGER DEFAULT 0,
                defaultUnit TEXT DEFAULT 'cái',
                expiryWarningDays INTEGER DEFAULT 7,
                lowStockWarning INTEGER DEFAULT 5,
                createdAt INTEGER,
                updatedAt INTEGER,
                updatedBy TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            debugPrint('v75: created shop_settings table');
          } catch (e) {
            debugPrint('v75 error (shop_settings): $e');
          }
          // product_categories table
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS product_categories(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                shopId TEXT,
                name TEXT,
                description TEXT,
                icon TEXT,
                color TEXT,
                parentId TEXT,
                sortOrder INTEGER DEFAULT 0,
                trackExpiry INTEGER DEFAULT 0,
                trackSerial INTEGER DEFAULT 0,
                hasVariants INTEGER DEFAULT 0,
                hasWarranty INTEGER DEFAULT 0,
                defaultWarrantyDays INTEGER DEFAULT 0,
                customFields TEXT,
                isActive INTEGER DEFAULT 1,
                createdAt INTEGER,
                updatedAt INTEGER,
                updatedBy TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_product_categories_shopId ON product_categories(shopId)',
            );
            debugPrint('v75: created product_categories table');
          } catch (e) {
            debugPrint('v75 error (product_categories): $e');
          }
          // product_variants table
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS product_variants(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                shopId TEXT,
                productId TEXT,
                sku TEXT,
                size TEXT,
                color TEXT,
                colorCode TEXT,
                material TEXT,
                style TEXT,
                costPrice INTEGER DEFAULT 0,
                salePrice INTEGER DEFAULT 0,
                quantity INTEGER DEFAULT 0,
                minQuantity INTEGER DEFAULT 0,
                barcode TEXT,
                image TEXT,
                isActive INTEGER DEFAULT 1,
                createdAt INTEGER,
                updatedAt INTEGER,
                updatedBy TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_product_variants_productId ON product_variants(productId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_product_variants_shopId ON product_variants(shopId)',
            );
            debugPrint('v75: created product_variants table');
          } catch (e) {
            debugPrint('v75 error (product_variants): $e');
          }
          // Add new columns to products table for multi-industry
          try {
            await db.execute('ALTER TABLE products ADD COLUMN categoryId TEXT');
            debugPrint('v75: added categoryId to products');
          } catch (e) {
            debugPrint('v75 error (products categoryId): $e');
          }
          try {
            await db.execute('ALTER TABLE products ADD COLUMN unit TEXT');
            debugPrint('v75: added unit to products');
          } catch (e) {
            debugPrint('v75 error (products unit): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN expiryDate INTEGER',
            );
            debugPrint('v75: added expiryDate to products');
          } catch (e) {
            debugPrint('v75 error (products expiryDate): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN batchNumber TEXT',
            );
            debugPrint('v75: added batchNumber to products');
          } catch (e) {
            debugPrint('v75 error (products batchNumber): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN variantParentId TEXT',
            );
            debugPrint('v75: added variantParentId to products');
          } catch (e) {
            debugPrint('v75 error (products variantParentId): $e');
          }
          try {
            await db.execute('ALTER TABLE products ADD COLUMN customData TEXT');
            debugPrint('v75: added customData to products');
          } catch (e) {
            debugPrint('v75 error (products customData): $e');
          }
          debugPrint('v75: Multi-industry expansion complete');
        }
        if (oldV < 76) {
          // v76: Add tiered commission columns to employee_salary_settings
          debugPrint('DB upgrade v76: Adding tiered commission columns...');
          try {
            await db.execute(
              'ALTER TABLE employee_salary_settings ADD COLUMN saleCommTier1Max REAL DEFAULT 10000000',
            );
            debugPrint('v76: added saleCommTier1Max');
          } catch (e) {
            debugPrint('v76 error (saleCommTier1Max): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE employee_salary_settings ADD COLUMN saleCommTier1Value REAL DEFAULT 20000',
            );
            debugPrint('v76: added saleCommTier1Value');
          } catch (e) {
            debugPrint('v76 error (saleCommTier1Value): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE employee_salary_settings ADD COLUMN saleCommTier2Max REAL DEFAULT 50000000',
            );
            debugPrint('v76: added saleCommTier2Max');
          } catch (e) {
            debugPrint('v76 error (saleCommTier2Max): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE employee_salary_settings ADD COLUMN saleCommTier2Value REAL DEFAULT 50000',
            );
            debugPrint('v76: added saleCommTier2Value');
          } catch (e) {
            debugPrint('v76 error (saleCommTier2Value): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE employee_salary_settings ADD COLUMN saleCommTier3Value REAL DEFAULT 100000',
            );
            debugPrint('v76: added saleCommTier3Value');
          } catch (e) {
            debugPrint('v76 error (saleCommTier3Value): $e');
          }
          debugPrint('v76: Tiered commission columns complete');
        }
        if (oldV < 77) {
          // v77: Add size column to products for fashion products
          debugPrint('DB upgrade v77: Adding size column to products...');
          try {
            await db.execute('ALTER TABLE products ADD COLUMN size TEXT');
            debugPrint('v77: added size column to products');
          } catch (e) {
            debugPrint('v77 error (size): $e');
          }
          debugPrint('v77: Fashion size column complete');
        }
        if (oldV < 78) {
          // v78: Add updatedAt column to audit_logs for Firestore sync compatibility
          debugPrint('DB upgrade v78: Adding updatedAt to audit_logs...');
          try {
            await db.execute(
              'ALTER TABLE audit_logs ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('v78: added updatedAt to audit_logs');
          } catch (e) {
            debugPrint('v78 error (audit_logs updatedAt): $e');
          }
          debugPrint('v78: audit_logs updatedAt complete');
        }
        if (oldV < 79) {
          // v79: Add cashAmount and transferAmount to sales for combined payment support
          debugPrint(
            'DB upgrade v79: Adding cashAmount and transferAmount to sales...',
          );
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN cashAmount INTEGER DEFAULT 0',
            );
            debugPrint('v79: added cashAmount to sales');
          } catch (e) {
            debugPrint('v79 error (cashAmount): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN transferAmount INTEGER DEFAULT 0',
            );
            debugPrint('v79: added transferAmount to sales');
          } catch (e) {
            debugPrint('v79 error (transferAmount): $e');
          }
          debugPrint('v79: Combined payment columns complete');
        }
        if (oldV < 80) {
          // v80: Add type column to expenses for THU/CHI distinction
          debugPrint('DB upgrade v80: Adding type column to expenses...');
          try {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN type TEXT DEFAULT "CHI"',
            );
            debugPrint('v80: added type column to expenses');
          } catch (e) {
            debugPrint('v80 error (expenses type): $e');
          }
          debugPrint('v80: Expense type column complete');
        }
        if (oldV < 81) {
          // v81: Add sku column to products
          debugPrint('DB upgrade v81: Adding sku column to products...');
          try {
            await db.execute('ALTER TABLE products ADD COLUMN sku TEXT');
            debugPrint('v81: added sku column to products');
          } catch (e) {
            debugPrint('v81 error (products sku): $e');
          }
          debugPrint('v81: Products sku column complete');
        }
        if (oldV < 82) {
          // v82: Add performance indexes for frequently queried columns
          debugPrint('DB upgrade v82: Adding performance indexes...');
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_repairs_createdAt ON repairs(createdAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_repairs_status ON repairs(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_repairs_repairedBy ON repairs(repairedBy)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_repairs_deleted ON repairs(deleted)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_soldAt ON sales(soldAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_sellerName ON sales(sellerName)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_deleted ON sales(deleted)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_deleted ON products(deleted)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_status ON products(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_shopId ON products(shopId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_debts_createdAt ON debts(createdAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_debts_status ON debts(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_debts_deleted ON debts(deleted)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_attendance_dateKey ON attendance(dateKey)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_attendance_userId ON attendance(userId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_debt_payments_paidAt ON debt_payments(paidAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_debt_payments_debtId ON debt_payments(debtId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_supplier_payments_paidAt ON supplier_payments(paidAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_repair_partner_payments_paidAt ON repair_partner_payments(paidAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
            );
            debugPrint('v82: All performance indexes created');
          } catch (e) {
            debugPrint('v82 error (indexes): $e');
          }
        }
        if (oldV < 83) {
          // v83: Add deleted column to sales table (was missing, caused index creation crash)
          debugPrint('DB upgrade v83: Adding deleted column to sales...');
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('v83: sales.deleted column added');
          } catch (e) {
            // Column may already exist if DB was recreated fresh with v83 schema
            debugPrint('v83: sales.deleted column already exists or error: $e');
          }
          // Re-create the index that failed in v82 due to missing column
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_deleted ON sales(deleted)',
            );
            debugPrint('v83: idx_sales_deleted created');
          } catch (e) {
            debugPrint('v83 error (sales deleted index): $e');
          }
        }
        if (oldV < 84) {
          // v84: Add partnerFirestoreId column to partner_repair_history for stable cross-device sync
          debugPrint(
            'DB upgrade v84: Adding partnerFirestoreId to partner_repair_history...',
          );
          try {
            await db.execute(
              'ALTER TABLE partner_repair_history ADD COLUMN partnerFirestoreId TEXT',
            );
            debugPrint('v84: partnerFirestoreId column added');
          } catch (e) {
            debugPrint('v84: partnerFirestoreId already exists or error: $e');
          }
        }
        if (oldV < 85) {
          // v85: Add repair parts cost tracking columns for cash fund recording
          debugPrint(
            'DB upgrade v85: Adding repair cost fund tracking columns...',
          );
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN costRecordedInFund INTEGER DEFAULT 0',
            );
            debugPrint('v85: costRecordedInFund column added');
          } catch (e) {
            debugPrint('v85: costRecordedInFund already exists or error: $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN costPaymentMethod TEXT',
            );
            debugPrint('v85: costPaymentMethod column added');
          } catch (e) {
            debugPrint('v85: costPaymentMethod already exists or error: $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN costRecordedAt INTEGER',
            );
            debugPrint('v85: costRecordedAt column added');
          } catch (e) {
            debugPrint('v85: costRecordedAt already exists or error: $e');
          }
          debugPrint('v85: Repair cost fund tracking complete');
        }
        if (oldV < 86) {
          // v86: Add type column to suppliers for KHO TỔNG support
          debugPrint('DB upgrade v86: Adding type column to suppliers...');
          try {
            await db.execute('ALTER TABLE suppliers ADD COLUMN type TEXT');
            debugPrint('v86: type column added to suppliers');
          } catch (e) {
            debugPrint('v86: type column already exists or error: $e');
          }
        }
        if (oldV < 87) {
          // v87: Persist exact amount recorded into fund for repairs
          debugPrint('DB upgrade v87: Adding costRecordedAmount to repairs...');
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN costRecordedAmount INTEGER DEFAULT 0',
            );
            debugPrint('v87: costRecordedAmount column added');
          } catch (e) {
            debugPrint('v87: costRecordedAmount already exists or error: $e');
          }
        }
        if (oldV < 88) {
          // v88: customers.phone was globally UNIQUE and caused cross-shop/walk-in conflicts.
          // Recreate customers table and enforce uniqueness by (shopId, phone) only.
          debugPrint(
            'DB upgrade v88: Rebuilding customers uniqueness to (shopId, phone)...',
          );
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS customers_new(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                avatarUrl TEXT,
                coverUrl TEXT,
                coverAlignX REAL DEFAULT 0,
                coverAlignY REAL DEFAULT 0,
                name TEXT,
                phone TEXT,
                email TEXT,
                address TEXT,
                notes TEXT,
                createdAt INTEGER,
                lastVisitAt INTEGER,
                updatedAt INTEGER,
                totalSpent INTEGER DEFAULT 0,
                totalRepairs INTEGER DEFAULT 0,
                totalRepairCost INTEGER DEFAULT 0,
                shopId TEXT,
                isSynced INTEGER DEFAULT 0,
                deleted INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              INSERT INTO customers_new(
                id, firestoreId, avatarUrl, coverUrl, coverAlignX, coverAlignY,
                name, phone, email, address, notes,
                createdAt, lastVisitAt, updatedAt,
                totalSpent, totalRepairs, totalRepairCost,
                shopId, isSynced, deleted
              )
              SELECT
                id, firestoreId, avatarUrl, coverUrl,
                COALESCE(coverAlignX, 0), COALESCE(coverAlignY, 0),
                name, phone, email, address, notes,
                createdAt, lastVisitAt, updatedAt,
                totalSpent, totalRepairs, totalRepairCost,
                shopId, isSynced, deleted
              FROM customers
            ''');
            await db.execute('DROP TABLE customers');
            await db.execute('ALTER TABLE customers_new RENAME TO customers');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
            );
            await db.execute(
              "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_shop_phone_unique ON customers(shopId, phone) WHERE phone IS NOT NULL AND phone <> ''",
            );
            debugPrint('v88: customers table rebuilt successfully');
          } catch (e) {
            debugPrint('v88 error (customers rebuild): $e');
          }
        }
        if (oldV < 89) {
          // v89: Add missing columns to debt_payments for Firestore sync compatibility
          for (final col in [
            'personName TEXT',
            'receivedBy TEXT',
            'totalDebt INTEGER DEFAULT 0',
            'alreadyPaid INTEGER DEFAULT 0',
            'customerName TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE debt_payments ADD COLUMN $col');
            } catch (_) {}
          }
        }
        if (oldV < 90) {
          // v90: Attendance management overhaul - add overtime window, request type; create leave_requests table
          for (final col in [
            'overtimeStartAt INTEGER',
            'overtimeEndAt INTEGER',
            'requestType TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE attendance ADD COLUMN $col');
            } catch (_) {}
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS leave_requests(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, email TEXT, name TEXT, leaveType TEXT, startDate TEXT, endDate TEXT, totalDays REAL, reason TEXT, status TEXT DEFAULT "pending", approvedBy TEXT, approvedAt INTEGER, rejectReason TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_leave_requests_userId ON leave_requests(userId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status)',
            );
          } catch (e) {
            debugPrint('v90 error (leave_requests): $e');
          }
        }
        if (oldV < 91) {
          for (final col in [
            'createdByUid TEXT',
            'repairedByUid TEXT',
            'deliveredByUid TEXT',
          ]) {
            try {
              await db.execute('ALTER TABLE repairs ADD COLUMN $col');
            } catch (_) {}
          }
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN sellerUid TEXT');
          } catch (_) {}
        }
        if (oldV < 92) {
          // v92: Salvage phones (Kho máy xác)
          try {
            await db.execute(
              "CREATE TABLE IF NOT EXISTS salvage_phones(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, deviceName TEXT, customerName TEXT, customerPhone TEXT, cost INTEGER DEFAULT 0, notes TEXT, images TEXT, status TEXT DEFAULT 'STORED', createdAt INTEGER, updatedAt INTEGER, createdBy TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)",
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_salvage_phones_shopId ON salvage_phones(shopId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_salvage_phones_status ON salvage_phones(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_salvage_phones_createdAt ON salvage_phones(createdAt)',
            );
          } catch (e) {
            debugPrint('v92 error (salvage_phones): $e');
          }
        }
        if (oldV < 93) {
          // v93: Import orders (Phiếu nhập kho) + items
          try {
            await db.execute(
              "CREATE TABLE IF NOT EXISTS import_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, orderCode TEXT, supplierId TEXT, supplierName TEXT, totalQuantity INTEGER DEFAULT 0, totalAmount INTEGER DEFAULT 0, paymentMethod TEXT, paymentStatus TEXT DEFAULT 'PAID', paidAmount INTEGER, status TEXT DEFAULT 'CONFIRMED', importDate INTEGER, importedBy TEXT, importedByUid TEXT, stockEntryId TEXT, notes TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)",
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_orders_shopId ON import_orders(shopId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_orders_importDate ON import_orders(importDate)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_orders_status ON import_orders(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_orders_stockEntryId ON import_orders(stockEntryId)',
            );

            await db.execute(
              "CREATE TABLE IF NOT EXISTS import_order_items(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, importOrderFirestoreId TEXT, productType TEXT DEFAULT 'OTHER', categoryId TEXT, productName TEXT, productBrand TEXT, productModel TEXT, imei TEXT, sku TEXT, quantity INTEGER DEFAULT 1, unit TEXT, costPrice INTEGER DEFAULT 0, totalAmount INTEGER DEFAULT 0, color TEXT, size TEXT, capacity TEXT, condition TEXT, warranty INTEGER, compatibleModels TEXT, notes TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)",
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_order_items_orderFsId ON import_order_items(importOrderFirestoreId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_import_order_items_shopId ON import_order_items(shopId)',
            );
          } catch (e) {
            debugPrint('v93 error (import_orders): $e');
          }
        }
        if (oldV < 94) {
          // v94: Add scope column for expenses (SHOP / CA_NHAN)
          try {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN scope TEXT DEFAULT "SHOP"',
            );
          } catch (_) {}
          try {
            await db.execute(
              "UPDATE expenses SET scope = 'SHOP' WHERE scope IS NULL OR TRIM(scope) = ''",
            );
          } catch (_) {}
        }
        if (oldV < 95) {
          // v95: Backfill columns missing on legacy iOS/Android DBs.
          await _ensureColumnExists(
            executor: db,
            table: 'expenses',
            column: 'createdBy',
            definition: 'TEXT',
            logScope: 'DB upgrade v95',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'inventory_checks',
            column: 'createdAt',
            definition: 'INTEGER',
            logScope: 'DB upgrade v95',
          );
        }
        if (oldV < 96) {
          // v96: Lưu giá yêu cầu thu riêng cho luồng giao máy chờ duyệt.
          await _ensureColumnExists(
            executor: db,
            table: 'repairs',
            column: 'requestedDeliveryPrice',
            definition: 'INTEGER',
            logScope: 'DB upgrade v96',
          );
        }
        if (oldV < 26) {
          // Migration to remove kpkPrice and pkPrice columns from products and quick_input_codes tables
          // Since SQLite doesn't support DROP COLUMN, we'll recreate tables without these columns
          try {
            // Create new products table without kpkPrice and pkPrice
            await db.execute(
              'CREATE TABLE products_new(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, brand TEXT, imei TEXT, cost INTEGER, price INTEGER, condition TEXT, status INTEGER DEFAULT 1, description TEXT, images TEXT, warranty TEXT, createdAt INTEGER, supplier TEXT, type TEXT DEFAULT "DIEN_THOAI", quantity INTEGER DEFAULT 1, color TEXT, isSynced INTEGER DEFAULT 0, capacity TEXT, paymentMethod TEXT, model TEXT)',
            );
            // Copy data from old table to new table
            await db.execute(
              'INSERT INTO products_new SELECT id, firestoreId, name, brand, imei, cost, price, condition, status, description, images, warranty, createdAt, supplier, type, quantity, color, isSynced, capacity, paymentMethod, model FROM products',
            );
            // Drop old table and rename new table
            await db.execute('DROP TABLE products');
            await db.execute('ALTER TABLE products_new RENAME TO products');
            debugPrint(
              'DB upgrade: removed kpkPrice and pkPrice from products table',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (products remove kpkPrice/pkPrice): $e',
            );
          }

          try {
            // Create new quick_input_codes table without kpkPrice and pkPrice
            await db.execute(
              'CREATE TABLE quick_input_codes_new(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
            );
            // Copy data from old table to new table
            await db.execute(
              'INSERT INTO quick_input_codes_new SELECT id, firestoreId, shopId, name, type, brand, model, capacity, color, condition, cost, price, description, supplier, paymentMethod, isActive, createdAt, isSynced FROM quick_input_codes',
            );
            // Drop old table and rename new table
            await db.execute('DROP TABLE quick_input_codes');
            await db.execute(
              'ALTER TABLE quick_input_codes_new RENAME TO quick_input_codes',
            );
            debugPrint(
              'DB upgrade: removed kpkPrice and pkPrice from quick_input_codes table',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (quick_input_codes remove kpkPrice/pkPrice): $e',
            );
          }
        }
        if (oldV < 27) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS supplier_product_prices(id INTEGER PRIMARY KEY AUTOINCREMENT, supplierId INTEGER, productName TEXT, productBrand TEXT, productModel TEXT, costPrice INTEGER, lastUpdated INTEGER, createdAt INTEGER, isActive INTEGER DEFAULT 1)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (supplier_product_prices): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS supplier_import_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, supplierName TEXT, productName TEXT, productBrand TEXT, productModel TEXT, imei TEXT, quantity INTEGER, costPrice INTEGER, totalAmount INTEGER, paymentMethod TEXT, importDate INTEGER, importedBy TEXT, notes TEXT, isSynced INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (supplier_import_history): $e');
          }
        }
        if (oldV < 28) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS repair_parts(id INTEGER PRIMARY KEY AUTOINCREMENT, partName TEXT, compatibleModels TEXT, cost INTEGER, price INTEGER, quantity INTEGER, updatedAt INTEGER, createdAt INTEGER, stockEntryId TEXT)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts): $e');
          }
        }
        if (oldV < 29) {
          try {
            await db.execute(
              'ALTER TABLE quick_input_codes ADD COLUMN code TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (quick_input_codes code): $e');
          }
        }
        if (oldV < 30) {
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_import_history',
            column: 'shopId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_product_prices',
            column: 'shopId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_import_history',
            column: 'firestoreId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_product_prices',
            column: 'firestoreId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureUniqueIndexExists(
            executor: db,
            indexName: 'idx_supplier_import_history_firestoreId_unique',
            table: 'supplier_import_history',
            column: 'firestoreId',
            logScope: 'DB upgrade',
          );
          await _ensureUniqueIndexExists(
            executor: db,
            indexName: 'idx_supplier_product_prices_firestoreId_unique',
            table: 'supplier_product_prices',
            column: 'firestoreId',
            logScope: 'DB upgrade',
          );
        }
        if (oldV < 31) {
          try {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products model): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN updatedAt INTEGER',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products updatedAt): $e');
          }
        }
        if (oldV < 32) {
          // Force re-run migration for products columns
          try {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (products model v32): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN updatedAt INTEGER',
            );
          } catch (e) {
            debugPrint('DB upgrade error (products updatedAt v32): $e');
          }
        }
        if (oldV < 33) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS repair_partners(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, phone TEXT, note TEXT, active INTEGER DEFAULT 1, createdAt INTEGER, updatedAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (repair_partners): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS partner_repair_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, repairOrderId TEXT, partnerId INTEGER, partnerFirestoreId TEXT, customerName TEXT, deviceModel TEXT, issue TEXT, partnerCost INTEGER, repairContent TEXT, sentAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (partner_repair_history): $e');
          }
        }
        if (oldV < 34) {
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (repairs services): $e');
          }
        }
        if (oldV < 35) {
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (supplier_payments): $e');
          }
          try {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS repair_partner_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partnerId INTEGER, partnerName TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, updatedAt INTEGER)',
            );
          } catch (e) {
            debugPrint('DB upgrade error (repair_partner_payments): $e');
          }
        }
        if (oldV < 36) {
          // Update suppliers table schema to match current Supplier model
          try {
            // Add missing columns to suppliers table
            await db.execute('ALTER TABLE suppliers ADD COLUMN email TEXT');
            await db.execute('ALTER TABLE suppliers ADD COLUMN note TEXT');
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN active INTEGER DEFAULT 1',
            );
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN updatedAt INTEGER',
            );
            debugPrint(
              'DB upgrade: added email, note, active, updatedAt columns to suppliers table',
            );
          } catch (e) {
            debugPrint('DB upgrade error (suppliers schema update): $e');
          }
        }
        if (oldV < 37) {
          // Ensure supplier tables have required columns
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_import_history',
            column: 'firestoreId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_import_history',
            column: 'shopId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_product_prices',
            column: 'firestoreId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureColumnExists(
            executor: db,
            table: 'supplier_product_prices',
            column: 'shopId',
            definition: 'TEXT',
            logScope: 'DB upgrade',
          );
          await _ensureUniqueIndexExists(
            executor: db,
            indexName: 'idx_supplier_import_history_firestoreId_unique',
            table: 'supplier_import_history',
            column: 'firestoreId',
            logScope: 'DB upgrade',
          );
          await _ensureUniqueIndexExists(
            executor: db,
            indexName: 'idx_supplier_product_prices_firestoreId_unique',
            table: 'supplier_product_prices',
            column: 'firestoreId',
            logScope: 'DB upgrade',
          );
        }
        if (oldV < 39) {
          // Align customers table schema with Customer model
          try {
            await db.execute('ALTER TABLE customers ADD COLUMN email TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (customers email): $e');
          }
          try {
            await db.execute('ALTER TABLE customers ADD COLUMN notes TEXT');
          } catch (e) {
            debugPrint('DB upgrade error (customers notes): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN lastVisitAt INTEGER',
            );
          } catch (e) {
            debugPrint('DB upgrade error (customers lastVisitAt): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN totalSpent INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (customers totalSpent): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN totalRepairs INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (customers totalRepairs): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN totalRepairCost INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (customers totalRepairCost): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN deleted INTEGER DEFAULT 0',
            );
          } catch (e) {
            debugPrint('DB upgrade error (customers deleted): $e');
          }
        }
        if (oldV < 40) {
          // Đảm bảo bảng repairs có cột services để lưu JSON danh sách dịch vụ
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
            debugPrint('DB upgrade: added services to repairs');
          } catch (e) {
            debugPrint('DB upgrade error (repairs services): $e');
          }
        }
        if (oldV < 41) {
          // Thêm cột notes vào repairs để lưu ghi chú đơn sửa
          try {
            await db.execute('ALTER TABLE repairs ADD COLUMN notes TEXT');
            debugPrint('DB upgrade: added notes to repairs');
          } catch (e) {
            debugPrint('DB upgrade error (repairs notes): $e');
          }
        }
        if (oldV < 42) {
          // Thêm cột deleted vào suppliers và repair_partners cho soft delete
          try {
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB upgrade: added deleted to suppliers');
          } catch (e) {
            debugPrint('DB upgrade error (suppliers deleted): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_partners ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB upgrade: added deleted to repair_partners');
          } catch (e) {
            debugPrint('DB upgrade error (repair_partners deleted): $e');
          }
        }
        if (oldV < 43) {
          // Thêm cột createdBy vào bảng debts để lưu người tạo công nợ
          try {
            await db.execute('ALTER TABLE debts ADD COLUMN createdBy TEXT');
            debugPrint('DB upgrade: added createdBy to debts');
          } catch (e) {
            debugPrint('DB upgrade error (debts createdBy): $e');
          }
        }
        if (oldV < 44) {
          // Thêm cột shopId vào bảng debt_payments cho data isolation
          try {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN shopId TEXT',
            );
            debugPrint('DB upgrade: added shopId to debt_payments');
          } catch (e) {
            debugPrint('DB upgrade error (debt_payments shopId): $e');
          }
        }
        if (oldV < 45) {
          // Thêm cột isSynced và shopId vào audit_logs để đồng bộ cloud
          try {
            await db.execute(
              'ALTER TABLE audit_logs ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('DB upgrade: added isSynced to audit_logs');
          } catch (e) {
            debugPrint('DB upgrade error (audit_logs isSynced): $e');
          }
          try {
            await db.execute('ALTER TABLE audit_logs ADD COLUMN shopId TEXT');
            debugPrint('DB upgrade: added shopId to audit_logs');
          } catch (e) {
            debugPrint('DB upgrade error (audit_logs shopId): $e');
          }
        }
        if (oldV < 46) {
          // Thêm các cột sync cho repair_parts (kho linh kiện)
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN firestoreId TEXT UNIQUE',
            );
            debugPrint('DB upgrade: added firestoreId to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts firestoreId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('DB upgrade: added isSynced to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts isSynced): $e');
          }
          try {
            await db.execute('ALTER TABLE repair_parts ADD COLUMN shopId TEXT');
            debugPrint('DB upgrade: added shopId to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB upgrade: added deleted to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts deleted): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN supplierId INTEGER',
            );
            debugPrint('DB upgrade: added supplierId to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts supplierId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN paymentMethod TEXT',
            );
            debugPrint('DB upgrade: added paymentMethod to repair_parts');
          } catch (e) {
            debugPrint('DB upgrade error (repair_parts paymentMethod): $e');
          }
        }
        if (oldV < 47) {
          // v47: Đảm bảo tất cả các cột cần thiết trong repair_parts đều tồn tại
          // (sửa lỗi migration v46 không chạy trên một số thiết bị)
          debugPrint('DB upgrade v47: Ensuring repair_parts columns exist...');
          final cols = await db.rawQuery('PRAGMA table_info(repair_parts)');
          final colNames = cols.map((c) => c['name'] as String).toSet();

          if (!colNames.contains('firestoreId')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN firestoreId TEXT',
              );
              debugPrint('v47: added firestoreId to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts firestoreId): $e');
            }
          }
          if (!colNames.contains('isSynced')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN isSynced INTEGER DEFAULT 0',
              );
              debugPrint('v47: added isSynced to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts isSynced): $e');
            }
          }
          if (!colNames.contains('shopId')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN shopId TEXT',
              );
              debugPrint('v47: added shopId to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts shopId): $e');
            }
          }
          if (!colNames.contains('deleted')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN deleted INTEGER DEFAULT 0',
              );
              debugPrint('v47: added deleted to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts deleted): $e');
            }
          }
          if (!colNames.contains('supplierId')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN supplierId INTEGER',
              );
              debugPrint('v47: added supplierId to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts supplierId): $e');
            }
          }
          if (!colNames.contains('paymentMethod')) {
            try {
              await db.execute(
                'ALTER TABLE repair_parts ADD COLUMN paymentMethod TEXT',
              );
              debugPrint('v47: added paymentMethod to repair_parts');
            } catch (e) {
              debugPrint('v47 error (repair_parts paymentMethod): $e');
            }
          }
          debugPrint('DB upgrade v47: repair_parts columns check completed');
        }
        if (oldV < 48) {
          // v48: Thêm các cột còn thiếu cho bảng expenses và debts
          debugPrint(
            'DB upgrade v48: Ensuring expenses and debts columns exist...',
          );

          // Kiểm tra và thêm cột cho expenses
          final expCols = await db.rawQuery('PRAGMA table_info(expenses)');
          final expColNames = expCols.map((c) => c['name'] as String).toSet();

          if (!expColNames.contains('description')) {
            try {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN description TEXT',
              );
              debugPrint('v48: added description to expenses');
            } catch (e) {
              debugPrint('v48 error (expenses description): $e');
            }
          }
          if (!expColNames.contains('createdAt')) {
            try {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN createdAt INTEGER',
              );
              debugPrint('v48: added createdAt to expenses');
            } catch (e) {
              debugPrint('v48 error (expenses createdAt): $e');
            }
          }
          if (!expColNames.contains('shopId')) {
            try {
              await db.execute('ALTER TABLE expenses ADD COLUMN shopId TEXT');
              debugPrint('v48: added shopId to expenses');
            } catch (e) {
              debugPrint('v48 error (expenses shopId): $e');
            }
          }
          if (!expColNames.contains('relatedPartId')) {
            try {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN relatedPartId TEXT',
              );
              debugPrint('v48: added relatedPartId to expenses');
            } catch (e) {
              debugPrint('v48 error (expenses relatedPartId): $e');
            }
          }

          // Kiểm tra và thêm cột cho debts
          final debtCols = await db.rawQuery('PRAGMA table_info(debts)');
          final debtColNames = debtCols.map((c) => c['name'] as String).toSet();

          if (!debtColNames.contains('shopId')) {
            try {
              await db.execute('ALTER TABLE debts ADD COLUMN shopId TEXT');
              debugPrint('v48: added shopId to debts');
            } catch (e) {
              debugPrint('v48 error (debts shopId): $e');
            }
          }
          if (!debtColNames.contains('relatedPartId')) {
            try {
              await db.execute(
                'ALTER TABLE debts ADD COLUMN relatedPartId TEXT',
              );
              debugPrint('v48: added relatedPartId to debts');
            } catch (e) {
              debugPrint('v48 error (debts relatedPartId): $e');
            }
          }

          debugPrint(
            'DB upgrade v48: expenses and debts columns check completed',
          );
        }
        if (oldV < 49) {
          // v49: Thêm bảng adjustment_entries cho bút toán điều chỉnh và cập nhật cash_closings
          debugPrint(
            'DB upgrade v49: Creating adjustment_entries table and updating cash_closings...',
          );

          // Tạo bảng bút toán điều chỉnh
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS adjustment_entries(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                shopId TEXT,
                adjustmentType TEXT,
                originalEntityType TEXT,
                originalEntityId TEXT,
                originalDate INTEGER,
                adjustmentDate INTEGER,
                description TEXT,
                reason TEXT,
                oldValues TEXT,
                newValues TEXT,
                costDelta INTEGER DEFAULT 0,
                debtDelta INTEGER DEFAULT 0,
                cashDelta INTEGER DEFAULT 0,
                bankDelta INTEGER DEFAULT 0,
                supplierId INTEGER,
                supplierName TEXT,
                createdBy TEXT,
                createdAt INTEGER,
                approvedBy TEXT,
                approvedAt INTEGER,
                status TEXT DEFAULT 'PENDING',
                isSynced INTEGER DEFAULT 0
              )
            ''');
            debugPrint('v49: created adjustment_entries table');
          } catch (e) {
            debugPrint('v49 error (adjustment_entries): $e');
          }

          // Thêm cột isLocked và lockedBy, lockedAt cho cash_closings
          try {
            final cols = await db.rawQuery('PRAGMA table_info(cash_closings)');
            final colNames = cols.map((c) => c['name'] as String).toSet();

            if (!colNames.contains('isLocked')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN isLocked INTEGER DEFAULT 0',
              );
              debugPrint('v49: added isLocked to cash_closings');
            }
            if (!colNames.contains('lockedBy')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN lockedBy TEXT',
              );
              debugPrint('v49: added lockedBy to cash_closings');
            }
            if (!colNames.contains('lockedAt')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN lockedAt INTEGER',
              );
              debugPrint('v49: added lockedAt to cash_closings');
            }
            if (!colNames.contains('shopId')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN shopId TEXT',
              );
              debugPrint('v49: added shopId to cash_closings');
            }
            if (!colNames.contains('firestoreId')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN firestoreId TEXT UNIQUE',
              );
              debugPrint('v49: added firestoreId to cash_closings');
            }
            if (!colNames.contains('isSynced')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN isSynced INTEGER DEFAULT 0',
              );
              debugPrint('v49: added isSynced to cash_closings');
            }
            // Thêm closedBy và closedAt để ghi nhận ai đã chốt
            if (!colNames.contains('closedBy')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN closedBy TEXT',
              );
              debugPrint('v49: added closedBy to cash_closings');
            }
            if (!colNames.contains('closedAt')) {
              await db.execute(
                'ALTER TABLE cash_closings ADD COLUMN closedAt INTEGER',
              );
              debugPrint('v49: added closedAt to cash_closings');
            }
          } catch (e) {
            debugPrint('v49 error (cash_closings columns): $e');
          }

          // Thêm cột lockedDateKey cho expenses để biết ngày đã chốt
          try {
            final cols = await db.rawQuery('PRAGMA table_info(expenses)');
            final colNames = cols.map((c) => c['name'] as String).toSet();
            if (!colNames.contains('lockedDateKey')) {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN lockedDateKey TEXT',
              );
              debugPrint('v49: added lockedDateKey to expenses');
            }
            if (!colNames.contains('isAdjustment')) {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN isAdjustment INTEGER DEFAULT 0',
              );
              debugPrint('v49: added isAdjustment to expenses');
            }
            if (!colNames.contains('adjustmentRef')) {
              await db.execute(
                'ALTER TABLE expenses ADD COLUMN adjustmentRef TEXT',
              );
              debugPrint('v49: added adjustmentRef to expenses');
            }
          } catch (e) {
            debugPrint('v49 error (expenses adjustment columns): $e');
          }

          // Thêm cột isAdjustment và adjustmentRef cho debts
          try {
            final cols = await db.rawQuery('PRAGMA table_info(debts)');
            final colNames = cols.map((c) => c['name'] as String).toSet();
            if (!colNames.contains('isAdjustment')) {
              await db.execute(
                'ALTER TABLE debts ADD COLUMN isAdjustment INTEGER DEFAULT 0',
              );
              debugPrint('v49: added isAdjustment to debts');
            }
            if (!colNames.contains('adjustmentRef')) {
              await db.execute(
                'ALTER TABLE debts ADD COLUMN adjustmentRef TEXT',
              );
              debugPrint('v49: added adjustmentRef to debts');
            }
          } catch (e) {
            debugPrint('v49 error (debts adjustment columns): $e');
          }

          // Tự động khóa các cash_closings đã có
          try {
            await db.execute('''
              UPDATE cash_closings 
              SET isLocked = 1, lockedAt = createdAt 
              WHERE isLocked IS NULL OR isLocked = 0
            ''');
            debugPrint('v49: locked all existing cash_closings');
          } catch (e) {
            debugPrint('v49 error (lock existing closings): $e');
          }

          debugPrint('DB upgrade v49: adjustment system completed');
        }
        if (oldV < 50) {
          // v50: Tạo bảng sync_queue để track pending sync operations
          debugPrint('DB upgrade v50: Creating sync_queue table...');

          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sync_queue(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entityType TEXT NOT NULL,
                entityId INTEGER NOT NULL,
                firestoreId TEXT,
                operation TEXT NOT NULL,
                data TEXT,
                createdAt INTEGER NOT NULL,
                retryCount INTEGER DEFAULT 0,
                lastError TEXT,
                status TEXT DEFAULT 'pending'
              )
            ''');
            debugPrint('v50: created sync_queue table');
          } catch (e) {
            debugPrint('v50 error (sync_queue): $e');
          }

          // Tạo index để query nhanh
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sync_queue_entity ON sync_queue(entityType, entityId)',
            );
            debugPrint('v50: created sync_queue indexes');
          } catch (e) {
            debugPrint('v50 error (sync_queue indexes): $e');
          }

          debugPrint('DB upgrade v50: sync_queue system completed');
        }
        if (oldV < 51) {
          // v51: Thêm cột isSynced, shopId, deleted vào bảng attendance
          debugPrint(
            'DB upgrade v51: Adding isSynced, shopId, deleted to attendance...',
          );

          try {
            await db.execute(
              'ALTER TABLE attendance ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('v51: added isSynced to attendance');
          } catch (e) {
            debugPrint('v51 error (attendance isSynced): $e');
          }
          try {
            await db.execute('ALTER TABLE attendance ADD COLUMN shopId TEXT');
            debugPrint('v51: added shopId to attendance');
          } catch (e) {
            debugPrint('v51 error (attendance shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE attendance ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('v51: added deleted to attendance');
          } catch (e) {
            debugPrint('v51 error (attendance deleted): $e');
          }

          debugPrint('DB upgrade v51: attendance columns completed');
        }
        if (oldV < 52) {
          // v52: Thêm cột createdAt vào bảng debt_payments
          debugPrint('DB upgrade v52: Adding createdAt to debt_payments...');
          try {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN createdAt INTEGER',
            );
            debugPrint('v52: added createdAt to debt_payments');
          } catch (e) {
            debugPrint('v52 error (debt_payments createdAt): $e');
          }
          debugPrint('DB upgrade v52: debt_payments createdAt completed');
        }
        if (oldV < 53) {
          // v53: Thêm cột updatedAt vào bảng debt_payments để hỗ trợ sync
          debugPrint('DB upgrade v53: Adding updatedAt to debt_payments...');
          try {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('v53: added updatedAt to debt_payments');
          } catch (e) {
            debugPrint('v53 error (debt_payments updatedAt): $e');
          }
          debugPrint('DB upgrade v53: debt_payments updatedAt completed');
        }
        if (oldV < 54) {
          // v54: Thêm cột summary vào bảng audit_logs để hỗ trợ sync từ Firestore
          debugPrint('DB upgrade v54: Adding summary to audit_logs...');
          try {
            await db.execute('ALTER TABLE audit_logs ADD COLUMN summary TEXT');
            debugPrint('v54: added summary to audit_logs');
          } catch (e) {
            debugPrint('v54 error (audit_logs summary): $e');
          }
          debugPrint('DB upgrade v54: audit_logs summary completed');
        }
        if (oldV < 55) {
          // v55: Thêm các cột còn thiếu vào bảng audit_logs để hỗ trợ sync từ Firestore
          debugPrint('DB upgrade v55: Adding missing columns to audit_logs...');
          final columnsToAdd = [
            'role',
            'email',
            'payload',
            'entityType',
            'entityId',
          ];
          for (final col in columnsToAdd) {
            try {
              await db.execute('ALTER TABLE audit_logs ADD COLUMN $col TEXT');
              debugPrint('v55: added $col to audit_logs');
            } catch (e) {
              debugPrint('v55 error (audit_logs $col): $e');
            }
          }
          debugPrint('DB upgrade v55: audit_logs columns completed');
        }
        if (oldV < 56) {
          // v56: Thêm cột debtType vào bảng debt_payments để phân biệt thu nợ KH vs trả nợ shop
          debugPrint('DB upgrade v56: Adding debtType to debt_payments...');
          try {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN debtType TEXT',
            );
            debugPrint('v56: added debtType to debt_payments');
          } catch (e) {
            debugPrint('v56 error (debt_payments debtType): $e');
          }
          debugPrint('DB upgrade v56: debtType column completed');
        }
        if (oldV < 57) {
          // v57: Thêm cột discount, bankName2, loanAmount2 vào bảng sales
          debugPrint(
            'DB upgrade v57: Adding discount, bankName2, loanAmount2 to sales...',
          );
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN discount INTEGER DEFAULT 0',
            );
            debugPrint('v57: added discount to sales');
          } catch (e) {
            debugPrint('v57 error (sales discount): $e');
          }
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN bankName2 TEXT');
            debugPrint('v57: added bankName2 to sales');
          } catch (e) {
            debugPrint('v57 error (sales bankName2): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN loanAmount2 INTEGER DEFAULT 0',
            );
            debugPrint('v57: added loanAmount2 to sales');
          } catch (e) {
            debugPrint('v57 error (sales loanAmount2): $e');
          }
          debugPrint('DB upgrade v57: sales columns completed');
        }
        if (oldV < 58) {
          // v58: Thêm cột downPaymentMethod vào bảng sales
          debugPrint('DB upgrade v58: Adding downPaymentMethod to sales...');
          try {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN downPaymentMethod TEXT',
            );
            debugPrint('v58: added downPaymentMethod to sales');
          } catch (e) {
            debugPrint('v58 error (sales downPaymentMethod): $e');
          }
          debugPrint('DB upgrade v58: completed');
        }
        if (oldV < 59) {
          // v59: Thêm cột isPending và pendingSupplier vào bảng products cho tính năng Kho Tạm
          debugPrint(
            'DB upgrade v59: Adding isPending and pendingSupplier to products...',
          );
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN isPending INTEGER DEFAULT 0',
            );
            debugPrint('v59: added isPending to products');
          } catch (e) {
            debugPrint('v59 error (products isPending): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE products ADD COLUMN pendingSupplier TEXT',
            );
            debugPrint('v59: added pendingSupplier to products');
          } catch (e) {
            debugPrint('v59 error (products pendingSupplier): $e');
          }
          debugPrint('DB upgrade v59: completed');
        }
        if (oldV < 60) {
          // v60: Thêm bảng sales_returns và sales_return_items cho tính năng Trả hàng
          // CHỈ THÊM MỚI - KHÔNG SỬA LOGIC CŨ
          debugPrint('DB upgrade v60: Adding sales_returns tables...');
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sales_returns(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                salesOrderId INTEGER,
                salesOrderFirestoreId TEXT,
                customerName TEXT,
                customerPhone TEXT,
                returnDate INTEGER,
                totalReturnAmount INTEGER DEFAULT 0,
                totalReturnCost INTEGER DEFAULT 0,
                refundMethod TEXT DEFAULT 'TIỀN MẶT',
                note TEXT,
                createdAt INTEGER,
                createdBy TEXT,
                approvedBy TEXT,
                approvedAt INTEGER,
                status TEXT DEFAULT 'APPROVED',
                shopId TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            debugPrint('v60: created sales_returns table');
          } catch (e) {
            debugPrint('v60 error (sales_returns): $e');
          }
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS sales_return_items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                salesReturnId INTEGER,
                salesReturnFirestoreId TEXT,
                productId INTEGER,
                productFirestoreId TEXT,
                productName TEXT,
                productImei TEXT,
                quantity INTEGER DEFAULT 1,
                price INTEGER DEFAULT 0,
                cost INTEGER DEFAULT 0,
                amount INTEGER DEFAULT 0,
                shopId TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            debugPrint('v60: created sales_return_items table');
          } catch (e) {
            debugPrint('v60 error (sales_return_items): $e');
          }
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_returns_shopId ON sales_returns(shopId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_returns_salesOrderId ON sales_returns(salesOrderId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_return_items_salesReturnId ON sales_return_items(salesReturnId)',
            );
            debugPrint('v60: created indexes for sales_returns');
          } catch (e) {
            debugPrint('v60 error (indexes): $e');
          }
          debugPrint('DB upgrade v60: completed');
        }
        if (oldV < 61) {
          // v61: Thêm bảng financial_activity_log để theo dõi mọi hoạt động tài chính
          debugPrint('DB upgrade v61: Adding financial_activity_log table...');
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS financial_activity_log(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                activityType TEXT NOT NULL,
                amount INTEGER NOT NULL,
                direction TEXT NOT NULL,
                paymentMethod TEXT,
                referenceType TEXT,
                referenceId TEXT,
                title TEXT NOT NULL,
                description TEXT,
                customerName TEXT,
                phone TEXT,
                productInfo TEXT,
                balanceAfterCash INTEGER,
                balanceAfterBank INTEGER,
                createdAt INTEGER NOT NULL,
                createdBy TEXT,
                shopId TEXT,
                isSynced INTEGER DEFAULT 0,
                extraData TEXT
              )
            ''');
            debugPrint('v61: created financial_activity_log table');
          } catch (e) {
            debugPrint('v61 error (financial_activity_log): $e');
          }
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_financial_activity_shopId ON financial_activity_log(shopId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_financial_activity_createdAt ON financial_activity_log(createdAt)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_financial_activity_type ON financial_activity_log(activityType)',
            );
            debugPrint('v61: created indexes for financial_activity_log');
          } catch (e) {
            debugPrint('v61 error (indexes): $e');
          }
          debugPrint('DB upgrade v61: completed');
        }
        if (oldV < 62) {
          // v62: Thêm các cột còn thiếu vào bảng work_schedules
          debugPrint(
            'DB upgrade v62: Adding missing columns to work_schedules...',
          );
          try {
            await db.execute(
              'ALTER TABLE work_schedules ADD COLUMN holidays TEXT',
            );
            debugPrint('v62: added holidays column');
          } catch (e) {
            debugPrint('v62 error (holidays): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE work_schedules ADD COLUMN weekdayOtRate INTEGER DEFAULT 150',
            );
            debugPrint('v62: added weekdayOtRate column');
          } catch (e) {
            debugPrint('v62 error (weekdayOtRate): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE work_schedules ADD COLUMN weekendOtRate INTEGER DEFAULT 200',
            );
            debugPrint('v62: added weekendOtRate column');
          } catch (e) {
            debugPrint('v62 error (weekendOtRate): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE work_schedules ADD COLUMN holidayOtRate INTEGER DEFAULT 300',
            );
            debugPrint('v62: added holidayOtRate column');
          } catch (e) {
            debugPrint('v62 error (holidayOtRate): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE work_schedules ADD COLUMN shopId TEXT',
            );
            debugPrint('v62: added shopId column');
          } catch (e) {
            debugPrint('v62 error (shopId): $e');
          }
          debugPrint('DB upgrade v62: completed');
        }
        if (oldV < 63) {
          // v63: Mở rộng payroll_settings để hỗ trợ nhiều loại hoa hồng và phụ cấp
          debugPrint('DB upgrade v63: Extending payroll_settings...');
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN saleCommType TEXT DEFAULT "percent"',
            );
            debugPrint('v63: added saleCommType column');
          } catch (e) {
            debugPrint('v63 error (saleCommType): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN repairCommType TEXT DEFAULT "percent"',
            );
            debugPrint('v63: added repairCommType column');
          } catch (e) {
            debugPrint('v63 error (repairCommType): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN transportAllowance INTEGER DEFAULT 0',
            );
            debugPrint('v63: added transportAllowance column');
          } catch (e) {
            debugPrint('v63 error (transportAllowance): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN mealAllowance INTEGER DEFAULT 0',
            );
            debugPrint('v63: added mealAllowance column');
          } catch (e) {
            debugPrint('v63 error (mealAllowance): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN phoneAllowance INTEGER DEFAULT 0',
            );
            debugPrint('v63: added phoneAllowance column');
          } catch (e) {
            debugPrint('v63 error (phoneAllowance): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN targetBonus INTEGER DEFAULT 0',
            );
            debugPrint('v63: added targetBonus column');
          } catch (e) {
            debugPrint('v63 error (targetBonus): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE payroll_settings ADD COLUMN monthlyTarget INTEGER DEFAULT 0',
            );
            debugPrint('v63: added monthlyTarget column');
          } catch (e) {
            debugPrint('v63 error (monthlyTarget): $e');
          }
          debugPrint('DB upgrade v63: completed');
        }
        if (oldV < 64) {
          // v64: Thêm bảng employee_salary_settings để lưu cài đặt lương cho từng nhân viên
          debugPrint(
            'DB upgrade v64: Adding employee_salary_settings table...',
          );
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS employee_salary_settings(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firestoreId TEXT UNIQUE,
                staffId TEXT NOT NULL,
                staffName TEXT,
                shopId TEXT,
                baseSalary REAL DEFAULT 0,
                dailyRate REAL DEFAULT 0,
                salaryType TEXT DEFAULT "monthly",
                saleCommType TEXT DEFAULT "percent",
                saleCommValue REAL DEFAULT 1.0,
                repairCommType TEXT DEFAULT "percent",
                repairCommValue REAL DEFAULT 10.0,
                transportAllowance REAL DEFAULT 0,
                mealAllowance REAL DEFAULT 0,
                phoneAllowance REAL DEFAULT 0,
                otherAllowance REAL DEFAULT 0,
                otherAllowanceNote TEXT,
                monthlyTarget REAL DEFAULT 0,
                targetBonusPercent REAL DEFAULT 0,
                standardHoursPerDay REAL DEFAULT 8.0,
                overtimeRate REAL DEFAULT 150,
                createdAt INTEGER,
                updatedAt INTEGER,
                updatedBy TEXT,
                isActive INTEGER DEFAULT 1,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            // Index để query nhanh theo staffId và shopId
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_employee_salary_staff ON employee_salary_settings(staffId)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_employee_salary_shop ON employee_salary_settings(shopId)',
            );
            debugPrint('v64: created employee_salary_settings table');
          } catch (e) {
            debugPrint('v64 error (employee_salary_settings): $e');
          }
          debugPrint('DB upgrade v64: completed');
        }
        if (oldV < 65) {
          // v65: Thêm cột pendingDeliveryApproval vào repairs để chờ duyệt giao máy
          debugPrint(
            'DB upgrade v65: Adding pendingDeliveryApproval column...',
          );
          try {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN pendingDeliveryApproval INTEGER DEFAULT 0',
            );
            debugPrint('v65: added pendingDeliveryApproval column to repairs');
          } catch (e) {
            debugPrint('v65 error (pendingDeliveryApproval): $e');
          }
          debugPrint('DB upgrade v65: completed');
        }
        if (oldV < 66) {
          // v66: Thêm cột partnerName và updatedAt vào repair_partner_payments để hiển thị trong chốt quỹ
          debugPrint(
            'DB upgrade v66: Adding partnerName and updatedAt columns to repair_partner_payments...',
          );
          try {
            await db.execute(
              'ALTER TABLE repair_partner_payments ADD COLUMN partnerName TEXT',
            );
            debugPrint(
              'v66: added partnerName column to repair_partner_payments',
            );
          } catch (e) {
            debugPrint('v66 error (partnerName): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE repair_partner_payments ADD COLUMN updatedAt INTEGER',
            );
            debugPrint(
              'v66: added updatedAt column to repair_partner_payments',
            );
          } catch (e) {
            debugPrint('v66 error (updatedAt): $e');
          }
          debugPrint('DB upgrade v66: completed');
        }
        if (oldV < 67) {
          // v67: Add payment_intents table for persistent payment intent storage
          debugPrint('DB upgrade v67: Creating payment_intents table...');
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS payment_intents(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                intentId TEXT UNIQUE NOT NULL,
                type TEXT NOT NULL,
                amount INTEGER NOT NULL,
                description TEXT,
                status TEXT DEFAULT 'pending',
                personName TEXT,
                personPhone TEXT,
                referenceId TEXT,
                referenceType TEXT,
                paymentMethod TEXT,
                createdBy TEXT,
                createdAt INTEGER,
                paidBy TEXT,
                paidAt INTEGER,
                notes TEXT,
                metadata TEXT,
                shopId TEXT,
                isSynced INTEGER DEFAULT 0
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_payment_intents_status ON payment_intents(status)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_payment_intents_type ON payment_intents(type)',
            );
            debugPrint('v67: created payment_intents table');
          } catch (e) {
            debugPrint('v67 error (payment_intents): $e');
          }
          debugPrint('DB upgrade v67: completed');
        }
        if (oldV < 68) {
          // v68: Add deleted and debtType columns to debts table for proper filtering
          debugPrint(
            'DB upgrade v68: Adding deleted and debtType to debts table...',
          );
          try {
            await db.execute(
              'ALTER TABLE debts ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('v68: added deleted column to debts');
          } catch (e) {
            debugPrint('v68 error (deleted): $e');
          }
          try {
            await db.execute('ALTER TABLE debts ADD COLUMN debtType TEXT');
            debugPrint('v68: added debtType column to debts');
          } catch (e) {
            debugPrint('v68 error (debtType): $e');
          }
          try {
            await db.execute('ALTER TABLE debts ADD COLUMN linkedType TEXT');
            debugPrint('v68: added linkedType column to debts');
          } catch (e) {
            debugPrint('v68 error (linkedType): $e');
          }
          debugPrint('DB upgrade v68: completed');
        }
        debugPrint('DB upgrade completed');
      },
      onOpen: (db) async {
        // Ensure paymentMethod column exists (defensive migration)
        try {
          final cols = await db.rawQuery('PRAGMA table_info(products)');
          final hasPaymentMethod = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'paymentMethod',
          );
          final hasModel = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'model',
          );
          final hasUpdatedAt = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'updatedAt',
          );
          final hasLabelInfo = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'labelInfo',
          );
          final hasIsPending = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'isPending',
          );

          if (!hasPaymentMethod) {
            await db.execute(
              'ALTER TABLE products ADD COLUMN paymentMethod TEXT',
            );
            debugPrint('DB: added paymentMethod column');
          }
          if (!hasModel) {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
            debugPrint('DB: added model column');
          }
          if (!hasUpdatedAt) {
            await db.execute(
              'ALTER TABLE products ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('DB: added updatedAt column');
          }
          if (!hasLabelInfo) {
            await db.execute('ALTER TABLE products ADD COLUMN labelInfo TEXT');
            debugPrint('DB: added labelInfo column');
          }
          if (!hasIsPending) {
            await db.execute(
              'ALTER TABLE products ADD COLUMN isPending INTEGER DEFAULT 0',
            );
            debugPrint('DB: added isPending column');
          }

          // Ensure sku column exists (v81)
          final hasSku = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'sku',
          );
          if (!hasSku) {
            await db.execute('ALTER TABLE products ADD COLUMN sku TEXT');
            debugPrint('DB onOpen: added sku column to products');
          }
        } catch (e) {
          debugPrint('DB onOpen check error: $e');
        }

        // Ensure payroll_settings schema is complete for all app versions.
        try {
          await _ensurePayrollSettingsColumns(db, logScope: 'DB onOpen');
        } catch (e) {
          debugPrint('DB onOpen check error (payroll_settings): $e');
        }

        // Ensure labelInfo column exists in quick_input_codes table
        try {
          final cols = await db.rawQuery(
            'PRAGMA table_info(quick_input_codes)',
          );
          final has = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'labelInfo',
          );
          if (!has) {
            await db.execute(
              'ALTER TABLE quick_input_codes ADD COLUMN labelInfo TEXT',
            );
            debugPrint('DB: added labelInfo column to quick_input_codes');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (quick_input_codes labelInfo): $e');
        }

        // Ensure checkedBy/createdAt columns exist in inventory_checks table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(inventory_checks)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('checkedBy')) {
            await db.execute(
              'ALTER TABLE inventory_checks ADD COLUMN checkedBy TEXT',
            );
            debugPrint('DB: added checkedBy column to inventory_checks');
          }
          if (!colNames.contains('createdAt')) {
            await db.execute(
              'ALTER TABLE inventory_checks ADD COLUMN createdAt INTEGER',
            );
            debugPrint('DB: added createdAt column to inventory_checks');
          }
        } catch (e) {
          debugPrint(
            'DB onOpen check error (inventory_checks checkedBy/createdAt): $e',
          );
        }

        // Ensure stockEntryId column exists in repair_parts table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(repair_parts)');
          final has = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'stockEntryId',
          );
          if (!has) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN stockEntryId TEXT',
            );
            debugPrint('DB: added stockEntryId column to repair_parts');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (repair_parts stockEntryId): $e');
        }

        // Ensure model column exists in products table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(products)');
          final has = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'model',
          );
          if (!has) {
            await db.execute('ALTER TABLE products ADD COLUMN model TEXT');
            debugPrint('DB: added model column to products');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (products model): $e');
        }

        // Ensure repair_parts table exists with all columns
        try {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS repair_parts(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partName TEXT, compatibleModels TEXT, cost INTEGER, price INTEGER, quantity INTEGER, updatedAt INTEGER, createdAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0, supplierId INTEGER, paymentMethod TEXT, createdBy TEXT)',
          );
          debugPrint('DB: ensured repair_parts table exists');

          // Ensure all sync columns exist in repair_parts (for old DBs)
          final cols = await db.rawQuery('PRAGMA table_info(repair_parts)');
          final colNames = cols.map((c) => c['name'] as String).toSet();

          if (!colNames.contains('firestoreId')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN firestoreId TEXT',
            );
            debugPrint('DB onOpen: added firestoreId to repair_parts');
          }
          if (!colNames.contains('isSynced')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added isSynced to repair_parts');
          }
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE repair_parts ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to repair_parts');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to repair_parts');
          }
          if (!colNames.contains('supplierId')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN supplierId INTEGER',
            );
            debugPrint('DB onOpen: added supplierId to repair_parts');
          }
          if (!colNames.contains('paymentMethod')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN paymentMethod TEXT',
            );
            debugPrint('DB onOpen: added paymentMethod to repair_parts');
          }
          if (!colNames.contains('createdBy')) {
            await db.execute(
              'ALTER TABLE repair_parts ADD COLUMN createdBy TEXT',
            );
            debugPrint('DB onOpen: added createdBy to repair_parts');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (repair_parts): $e');
        }

        // Ensure services, shopId columns exist in repairs table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(repairs)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('services')) {
            await db.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
            debugPrint('DB onOpen: added services to repairs');
          }
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE repairs ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to repairs');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to repairs');
          }
          if (!colNames.contains('createdByUid')) {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN createdByUid TEXT',
            );
            debugPrint('DB onOpen: added createdByUid to repairs');
          }
          if (!colNames.contains('repairedByUid')) {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN repairedByUid TEXT',
            );
            debugPrint('DB onOpen: added repairedByUid to repairs');
          }
          if (!colNames.contains('deliveredByUid')) {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN deliveredByUid TEXT',
            );
            debugPrint('DB onOpen: added deliveredByUid to repairs');
          }
          if (!colNames.contains('requestedDeliveryPrice')) {
            await db.execute(
              'ALTER TABLE repairs ADD COLUMN requestedDeliveryPrice INTEGER',
            );
            debugPrint('DB onOpen: added requestedDeliveryPrice to repairs');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (repairs columns): $e');
        }

        // Ensure shopId, deleted columns exist in sales table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(sales)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE sales ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to sales');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE sales ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to sales');
          }
          if (!colNames.contains('sellerUid')) {
            await db.execute('ALTER TABLE sales ADD COLUMN sellerUid TEXT');
            debugPrint('DB onOpen: added sellerUid to sales');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (sales columns): $e');
        }

        // Ensure isSynced, shopId, deleted columns exist in attendance table (defensive migration)
        try {
          final cols = await db.rawQuery('PRAGMA table_info(attendance)');
          final colNames = cols.map((c) => c['name'] as String).toSet();

          if (!colNames.contains('isSynced')) {
            await db.execute(
              'ALTER TABLE attendance ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added isSynced to attendance');
          }
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE attendance ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to attendance');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE attendance ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to attendance');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (attendance columns): $e');
        }

        // Ensure missing columns exist in customers table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(customers)');
          final hasEmail = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'email',
          );
          final hasNotes = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'notes',
          );
          final hasLastVisitAt = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'lastVisitAt',
          );
          final hasUpdatedAt = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'updatedAt',
          );

          if (!hasEmail) {
            await db.execute('ALTER TABLE customers ADD COLUMN email TEXT');
            debugPrint('DB: added email column to customers');
          }
          if (!hasNotes) {
            await db.execute('ALTER TABLE customers ADD COLUMN notes TEXT');
            debugPrint('DB: added notes column to customers');
          }
          if (!hasLastVisitAt) {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN lastVisitAt INTEGER',
            );
            debugPrint('DB: added lastVisitAt column to customers');
          }
          if (!hasUpdatedAt) {
            await db.execute(
              'ALTER TABLE customers ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('DB: added updatedAt column to customers');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (customers): $e');
        }

        // Ensure firestoreId column exists in supplier_import_history table
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_import_history',
          column: 'firestoreId',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_import_history',
          column: 'shopId',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        // Add new columns for importedByUid, referenceId, createdAt
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_import_history',
          column: 'importedByUid',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_import_history',
          column: 'referenceId',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_import_history',
          column: 'createdAt',
          definition: 'INTEGER',
          logScope: 'DB onOpen',
        );
        await _ensureUniqueIndexExists(
          executor: db,
          indexName: 'idx_supplier_import_history_firestoreId_unique',
          table: 'supplier_import_history',
          column: 'firestoreId',
          logScope: 'DB onOpen',
        );

        // Ensure firestoreId column exists in supplier_product_prices table
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_product_prices',
          column: 'firestoreId',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'supplier_product_prices',
          column: 'shopId',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureUniqueIndexExists(
          executor: db,
          indexName: 'idx_supplier_product_prices_firestoreId_unique',
          table: 'supplier_product_prices',
          column: 'firestoreId',
          logScope: 'DB onOpen',
        );

        // Ensure missing columns exist in suppliers table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(suppliers)');
          final hasEmail = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'email',
          );
          final hasNote = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'note',
          );
          final hasActive = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'active',
          );
          final hasFavorite = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'favorite',
          );
          final hasUpdatedAt = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'updatedAt',
          );

          if (!hasEmail) {
            await db.execute('ALTER TABLE suppliers ADD COLUMN email TEXT');
            debugPrint('DB: added email column to suppliers');
          }
          if (!hasNote) {
            await db.execute('ALTER TABLE suppliers ADD COLUMN note TEXT');
            debugPrint('DB: added note column to suppliers');
          }
          if (!hasActive) {
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN active INTEGER DEFAULT 1',
            );
            debugPrint('DB: added active column to suppliers');
          }
          if (!hasFavorite) {
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN favorite INTEGER DEFAULT 0',
            );
            debugPrint('DB: added favorite column to suppliers');
          }
          if (!hasUpdatedAt) {
            await db.execute(
              'ALTER TABLE suppliers ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('DB: added updatedAt column to suppliers');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (suppliers columns): $e');
        }

        // Ensure createdBy column exists in debts table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(debts)');
          final hasCreatedBy = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'createdBy',
          );
          if (!hasCreatedBy) {
            await db.execute('ALTER TABLE debts ADD COLUMN createdBy TEXT');
            debugPrint('DB: added createdBy column to debts');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (debts createdBy): $e');
        }

        // Ensure shopId, relatedPartId, and updatedAt columns exist in debts table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(debts)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE debts ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to debts');
          }
          if (!colNames.contains('relatedPartId')) {
            await db.execute('ALTER TABLE debts ADD COLUMN relatedPartId TEXT');
            debugPrint('DB onOpen: added relatedPartId to debts');
          }
          // BUG-004 FIX: Thêm cột updatedAt cho sync conflict resolution
          if (!colNames.contains('updatedAt')) {
            await db.execute('ALTER TABLE debts ADD COLUMN updatedAt INTEGER');
            debugPrint('DB onOpen: added updatedAt to debts');
          }
        } catch (e) {
          debugPrint(
            'DB onOpen check error (debts shopId/relatedPartId/updatedAt): $e',
          );
        }

        // Ensure description, createdAt, createdBy, shopId, relatedPartId columns exist in expenses table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(expenses)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('description')) {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN description TEXT',
            );
            debugPrint('DB onOpen: added description to expenses');
          }
          if (!colNames.contains('createdAt')) {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN createdAt INTEGER',
            );
            debugPrint('DB onOpen: added createdAt to expenses');
          }
          if (!colNames.contains('createdBy')) {
            await db.execute('ALTER TABLE expenses ADD COLUMN createdBy TEXT');
            debugPrint('DB onOpen: added createdBy to expenses');
          }
          if (!colNames.contains('shopId')) {
            await db.execute('ALTER TABLE expenses ADD COLUMN shopId TEXT');
            debugPrint('DB onOpen: added shopId to expenses');
          }
          if (!colNames.contains('relatedPartId')) {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN relatedPartId TEXT',
            );
            debugPrint('DB onOpen: added relatedPartId to expenses');
          }
          if (!colNames.contains('scope')) {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN scope TEXT DEFAULT "SHOP"',
            );
            debugPrint('DB onOpen: added scope to expenses');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (expenses columns): $e');
        }

        // Ensure isLocked, lockedBy, lockedAt, shopId, firestoreId, isSynced columns exist in cash_closings table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(cash_closings)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('isLocked')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN isLocked INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added isLocked to cash_closings');
          }
          if (!colNames.contains('lockedBy')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN lockedBy TEXT',
            );
            debugPrint('DB onOpen: added lockedBy to cash_closings');
          }
          if (!colNames.contains('lockedAt')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN lockedAt INTEGER',
            );
            debugPrint('DB onOpen: added lockedAt to cash_closings');
          }
          if (!colNames.contains('unlockedBy')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN unlockedBy TEXT',
            );
            debugPrint('DB onOpen: added unlockedBy to cash_closings');
          }
          if (!colNames.contains('unlockedAt')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN unlockedAt INTEGER',
            );
            debugPrint('DB onOpen: added unlockedAt to cash_closings');
          }
          if (!colNames.contains('shopId')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN shopId TEXT',
            );
            debugPrint('DB onOpen: added shopId to cash_closings');
          }
          if (!colNames.contains('firestoreId')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN firestoreId TEXT',
            );
            debugPrint('DB onOpen: added firestoreId to cash_closings');
          }
          if (!colNames.contains('isSynced')) {
            await db.execute(
              'ALTER TABLE cash_closings ADD COLUMN isSynced INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added isSynced to cash_closings');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (cash_closings columns): $e');
        }

        // Ensure deleted column exists in expenses table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(expenses)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE expenses ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to expenses');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (expenses columns): $e');
        }

        // Ensure shopId, deleted columns exist in purchase_orders table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(purchase_orders)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('shopId')) {
            await db.execute(
              'ALTER TABLE purchase_orders ADD COLUMN shopId TEXT',
            );
            debugPrint('DB onOpen: added shopId to purchase_orders');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE purchase_orders ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to purchase_orders');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (purchase_orders columns): $e');
        }

        // Ensure deleted column exists in sales_returns table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(sales_returns)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE sales_returns ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to sales_returns');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (sales_returns columns): $e');
        }

        // Ensure Home cashflow columns exist in debt_payments table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(debt_payments)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('shopId')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN shopId TEXT',
            );
            debugPrint('DB onOpen: added shopId to debt_payments');
          }
          if (!colNames.contains('createdAt')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN createdAt INTEGER',
            );
            debugPrint('DB onOpen: added createdAt to debt_payments');
          }
          if (!colNames.contains('updatedAt')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('DB onOpen: added updatedAt to debt_payments');
          }
          if (!colNames.contains('debtType')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN debtType TEXT',
            );
            debugPrint('DB onOpen: added debtType to debt_payments');
          }
          if (!colNames.contains('personName')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN personName TEXT',
            );
            debugPrint('DB onOpen: added personName to debt_payments');
          }
          if (!colNames.contains('receivedBy')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN receivedBy TEXT',
            );
            debugPrint('DB onOpen: added receivedBy to debt_payments');
          }
          if (!colNames.contains('totalDebt')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN totalDebt INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added totalDebt to debt_payments');
          }
          if (!colNames.contains('alreadyPaid')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN alreadyPaid INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added alreadyPaid to debt_payments');
          }
          if (!colNames.contains('customerName')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN customerName TEXT',
            );
            debugPrint('DB onOpen: added customerName to debt_payments');
          }
          if (!colNames.contains('deleted')) {
            await db.execute(
              'ALTER TABLE debt_payments ADD COLUMN deleted INTEGER DEFAULT 0',
            );
            debugPrint('DB onOpen: added deleted to debt_payments');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (debt_payments columns): $e');
        }

        // Tạo index cho bảng products để tăng tốc query
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_createdAt ON products(createdAt DESC)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_deleted ON products(deleted)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_type ON products(type)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_quantity ON products(quantity)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_status ON products(status)',
          );
          debugPrint('DB: created indexes for products table');
        } catch (e) {
          debugPrint('DB onOpen check error (products indexes): $e');
        }

        // avatarUrl cho khách hàng, nhà cung cấp, đối tác sửa chữa
        await _ensureColumnExists(
          executor: db,
          table: 'customers',
          column: 'avatarUrl',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'customers',
          column: 'coverUrl',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'customers',
          column: 'coverAlignX',
          definition: 'REAL DEFAULT 0',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'customers',
          column: 'coverAlignY',
          definition: 'REAL DEFAULT 0',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'suppliers',
          column: 'avatarUrl',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
        await _ensureColumnExists(
          executor: db,
          table: 'repair_partners',
          column: 'avatarUrl',
          definition: 'TEXT',
          logScope: 'DB onOpen',
        );
      },
    );
    await _forceFixMissingColumns(db);
return db;
  }

  // --- HÀM HỖ TRỢ CHUNG ---
  dynamic _normalizeSqliteValue(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _normalizeSqliteValue(item)),
      );
    }
    if (value is List) {
      return value.map(_normalizeSqliteValue).toList();
    }
    return value;
  }

  Map<String, dynamic> _sanitizeForSqlite(Map<String, dynamic> input) {
    final sanitized = <String, dynamic>{};
    input.forEach((key, value) {
      final normalized = _normalizeSqliteValue(value);
      if (normalized is Map || normalized is List) {
        sanitized[key] = jsonEncode(normalized);
      } else {
        sanitized[key] = normalized;
      }
    });
    return sanitized;
  }

  Future<void> _upsert(
    String table,
    Map<String, dynamic> map,
    String firestoreId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> existing = await txn.query(
        table,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );
      Map<String, dynamic> data = _sanitizeForSqlite(
        Map<String, dynamic>.from(map),
      );
      data.remove('id');
      // Ensure a stable key is persisted locally to avoid re-insert duplicates
      // when callers pass fallback keys but map['firestoreId'] is null/empty.
      final existingFirestoreId = (data['firestoreId'] ?? '').toString().trim();
      if (existingFirestoreId.isEmpty) {
        data['firestoreId'] = firestoreId;
      }
      data.remove(
        '_encrypted',
      ); // Field metadata của Firestore, không lưu SQLite
      // Strip any Firestore fields not in SQLite schema
      await _filterToTableColumns(table, data, executor: txn);
      if (existing.isNotEmpty) {
        await txn.update(
          table,
          data,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert(table, data);
      }
    });
  }

  // --- REPAIRS ---
  Future<void> upsertRepair(Repair r) async {
    final db = await database;
    final firestoreId = r.firestoreId ?? "${r.createdAt}_${r.phone}";

    await db.transaction((txn) async {
      final existing = await txn.query(
        'repairs',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );

      Map<String, dynamic> data = Map<String, dynamic>.from(r.toMap());
      data.remove('id');
      // Persist normalized firestoreId to keep repair upserts idempotent.
      final existingFirestoreId = (data['firestoreId'] ?? '').toString().trim();
      if (existingFirestoreId.isEmpty) {
        data['firestoreId'] = firestoreId;
      }

      // Check if services column exists
      final cols = await txn.rawQuery('PRAGMA table_info(repairs)');
      final hasServices = cols.any(
        (c) => (c['name'] ?? c['name'.toString()]) == 'services',
      );

      if (!hasServices) {
        // Remove services from data if column doesn't exist
        data.remove('services');
        debugPrint('DB WARNING: services column not found, removing from data');

        // Try to add the column
        try {
          await txn.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
          debugPrint('DB: Added services column to repairs');
          // Re-add services to data now that column exists
          data['services'] = r.toMap()['services'];
        } catch (e) {
          debugPrint('DB: Could not add services column: $e');
        }
      }

      if (existing.isNotEmpty) {
        await txn.update(
          'repairs',
          data,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert('repairs', data);
      }
    });
  }

  Future<int> insertRepair(Repair r) async {
    await upsertRepair(r);
    return 1;
  }

  Future<int> updateRepair(Repair r) async {
    final db = await database;
    Map<String, dynamic> data = Map<String, dynamic>.from(r.toMap());

    // Check if services column exists
    final cols = await db.rawQuery('PRAGMA table_info(repairs)');
    final hasServices = cols.any(
      (c) => (c['name'] ?? c['name'.toString()]) == 'services',
    );

    if (!hasServices) {
      data.remove('services');
      debugPrint('DB WARNING (updateRepair): services column not found');
      // Try to add the column
      try {
        await db.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
        debugPrint('DB: Added services column to repairs');
        data['services'] = r.toMap()['services'];
      } catch (e) {
        debugPrint('DB: Could not add services column: $e');
      }
    }

    return db.update('repairs', data, where: 'id = ?', whereArgs: [r.id]);
  }

  Future<int> deleteRepair(int id) async =>
      (await database).delete('repairs', where: 'id = ?', whereArgs: [id]);
  Future<int> deleteRepairByFirestoreId(String fId) async => (await database)
      .delete('repairs', where: 'firestoreId = ?', whereArgs: [fId]);

  /// Search repairs by query string using SQL LIKE on key columns.
  /// Searches both original query and Vietnamese-normalized query for accent-insensitive matching.
  /// Returns max [limit] results ordered by createdAt DESC.
  Future<List<Repair>> searchRepairs(
    String query,
    String normalizedQuery, {
    int limit = 25,
  }) async {
    final db = await database;
    final like = '%$query%';
    final likeNorm = '%$normalizedQuery%';
    final maps = await db.rawQuery(
      '''
      SELECT * FROM repairs
      WHERE (customerName LIKE ? OR customerName LIKE ?
        OR phone LIKE ?
        OR model LIKE ? OR model LIKE ?
        OR issue LIKE ? OR issue LIKE ?
        OR address LIKE ? OR address LIKE ?)
      ORDER BY createdAt DESC
      LIMIT ?
    ''',
      [
        like,
        likeNorm,
        like,
        like,
        likeNorm,
        like,
        likeNorm,
        like,
        likeNorm,
        limit,
      ],
    );
    return List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
  }

  /// Search sales by query string using SQL LIKE on key columns.
  Future<List<SaleOrder>> searchSales(
    String query,
    String normalizedQuery, {
    int limit = 25,
  }) async {
    final db = await database;
    final like = '%$query%';
    final likeNorm = '%$normalizedQuery%';
    final maps = await db.rawQuery(
      '''
      SELECT * FROM sales
      WHERE (customerName LIKE ? OR customerName LIKE ?
        OR phone LIKE ?
        OR productNames LIKE ? OR productNames LIKE ?
        OR productImeis LIKE ?)
      ORDER BY soldAt DESC
      LIMIT ?
    ''',
      [like, likeNorm, like, like, likeNorm, like, limit],
    );
    return List.generate(maps.length, (i) => SaleOrder.fromMap(maps[i]));
  }

  /// Search products by query string using SQL LIKE on key columns.
  Future<List<Product>> searchProducts(
    String query,
    String normalizedQuery, {
    int limit = 25,
  }) async {
    final db = await database;
    final shopId = await _getScopedShopId('searchProducts');
    if (shopId == null) return [];

    final like = '%$query%';
    final likeNorm = '%$normalizedQuery%';
    final maps = await db.rawQuery(
      '''
      SELECT * FROM products
      WHERE (deleted = 0 OR deleted IS NULL)
        AND shopId = ?
        AND (name LIKE ? OR name LIKE ?
          OR imei LIKE ?
          OR description LIKE ? OR description LIKE ?
          OR color LIKE ? OR color LIKE ?
          OR capacity LIKE ? OR capacity LIKE ?)
      ORDER BY createdAt DESC
      LIMIT ?
    ''',
      [
        shopId,
        like,
        likeNorm,
        like,
        like,
        likeNorm,
        like,
        likeNorm,
        like,
        likeNorm,
        limit,
      ],
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Get repairs with pagination support for lazy loading
  /// Returns [limit] repairs starting from [offset], ordered by createdAt DESC
  Future<List<Repair>> getRepairsPaged(int limit, int offset) async {
    final maps = await (await database).query(
      'repairs',
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
  }

  /// Get total count of repairs for pagination
  Future<int> getRepairsCount() async {
    final result = await (await database).rawQuery(
      'SELECT COUNT(*) as count FROM repairs',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Repair>> getAllRepairs() async {
    final maps = await (await database).query(
      'repairs',
      orderBy: 'createdAt DESC',
    );
    final repairs = List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
    debugPrint("DB_TRACE: getAllRepairs returned ${repairs.length} repairs");
    return repairs;
  }

  /// Get ALL repairs within a createdAt date range (all statuses)
  Future<List<Repair>> getRepairsByCreatedAtRange(
    int startMs,
    int endMs,
  ) async {
    final db = await database;
    final maps = await db.query(
      'repairs',
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
  }

  /// Get delivered repairs within a date range, for financial report optimization
  /// Uses COALESCE(deliveredAt, createdAt) to handle NULL deliveredAt
  Future<List<Repair>> getDeliveredRepairsByDateRange(
    int startMs,
    int endMs,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    final List<Map<String, dynamic>> maps;
    if (shopId != null && shopId.isNotEmpty) {
      maps = await db.query(
        'repairs',
        where:
            '(shopId = ? OR shopId IS NULL) AND COALESCE(deliveredAt, createdAt) >= ? AND COALESCE(deliveredAt, createdAt) <= ? AND status = 4 AND deleted = 0',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'createdAt DESC',
      );
    } else {
      maps = await db.query(
        'repairs',
        where:
            'COALESCE(deliveredAt, createdAt) >= ? AND COALESCE(deliveredAt, createdAt) <= ? AND status = 4 AND deleted = 0',
        whereArgs: [startMs, endMs],
        orderBy: 'createdAt DESC',
      );
    }
    return List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
  }

  Future<Repair?> getRepairById(int id) async {
    final res = await (await database).query(
      'repairs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? Repair.fromMap(res.first) : null;
  }

  Future<Repair?> getRepairByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'repairs',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? Repair.fromMap(res.first) : null;
  }

  Future<List<Repair>> getRepairsByImei(String imei) async {
    final res = await (await database).query(
      'repairs',
      where: 'imei = ? AND deleted = 0',
      whereArgs: [imei],
      orderBy: 'createdAt DESC',
    );
    return List.generate(res.length, (i) => Repair.fromMap(res[i]));
  }

  // --- SALES ---
  Future<void> upsertSale(SaleOrder s) async =>
      _upsert('sales', s.toMap(), s.firestoreId ?? "sale_${s.soldAt}");
  Future<int> insertSale(SaleOrder s) async {
    await upsertSale(s);
    return 1;
  }

  Future<int> updateSale(SaleOrder s) async => (await database).update(
    'sales',
    s.toMap(),
    where: 'id = ?',
    whereArgs: [s.id],
  );
  Future<int> deleteSale(int id) async =>
      (await database).delete('sales', where: 'id = ?', whereArgs: [id]);
  Future<int> deleteSaleByFirestoreId(String fId) async => (await database)
      .delete('sales', where: 'firestoreId = ?', whereArgs: [fId]);

  /// Get sales with pagination support for lazy loading
  /// Returns [limit] sales starting from [offset], ordered by soldAt DESC
  Future<List<SaleOrder>> getSalesPaged(int limit, int offset) async {
    final maps = await (await database).query(
      'sales',
      orderBy: 'soldAt DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => SaleOrder.fromMap(maps[i]));
  }

  /// Get total count of sales for pagination
  Future<int> getSalesCount() async {
    final result = await (await database).rawQuery(
      'SELECT COUNT(*) as count FROM sales',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<SaleOrder>> getAllSales() async {
    final maps = await (await database).query('sales', orderBy: 'soldAt DESC');
    final sales = List.generate(maps.length, (i) => SaleOrder.fromMap(maps[i]));
    debugPrint("DB_TRACE: getAllSales returned ${sales.length} sales");
    return sales;
  }

  /// Get sales within a date range (by soldAt), for financial report optimization
  Future<List<SaleOrder>> getSalesByDateRange(int startMs, int endMs) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'soldAt >= ? AND soldAt <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'soldAt DESC',
    );
    return List.generate(maps.length, (i) => SaleOrder.fromMap(maps[i]));
  }

  Future<SaleOrder?> getSaleByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'sales',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? SaleOrder.fromMap(res.first) : null;
  }

  // --- PRODUCTS ---
  Future<void> upsertProduct(Product p) async =>
      _upsert('products', p.toMap(), p.firestoreId ?? "prod_${p.createdAt}");
  Future<int> updateProduct(Product p) async => (await database).update(
    'products',
    p.toMap(),
    where: 'id = ?',
    whereArgs: [p.id],
  );
  Future<int> deleteProduct(int id) async =>
      (await database).delete('products', where: 'id = ?', whereArgs: [id]);
  Future<int> deleteProductByFirestoreId(String fId) async => (await database)
      .delete('products', where: 'firestoreId = ?', whereArgs: [fId]);

  /// Soft delete product (hide from inventory list only)
  Future<int> softDeleteProduct(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return updateProductMap(id, {
      'deleted': 1,
      'status': 0,
      'isSynced': 0,
      'updatedAt': now,
    });
  }

  /// Cập nhật sản phẩm bằng map (dùng cho soft delete với các trường tùy chỉnh)
  Future<int> updateProductMap(int id, Map<String, dynamic> data) async {
    return (await database).update(
      'products',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Lấy công nợ liên quan đến sản phẩm (theo linkedId hoặc note chứa productId)
  Future<List<Map<String, dynamic>>> getDebtsByProductId(
    String productId,
  ) async {
    if (productId.isEmpty) return [];
    final db = await database;
    // Tìm công nợ có linkedId = productId hoặc note chứa productId
    // Lưu ý: Bảng debts không có cột deleted
    final debts = await db.query(
      'debts',
      where: "linkedId = ? OR note LIKE ?",
      whereArgs: [productId, '%$productId%'],
    );
    return debts;
  }

  /// Soft delete công nợ - thực tế là xóa hẳn vì bảng debts không có cột deleted
  Future<int> softDeleteDebt(int debtId, {String? reason}) async {
    // Bảng debts không có cột deleted, nên phải xóa thật
    return (await database).delete(
      'debts',
      where: 'id = ?',
      whereArgs: [debtId],
    );
  }

  /// Xóa lịch sử nhập hàng theo product
  /// Lưu ý: Bảng supplier_import_history không có cột deleted, nên phải xóa thật
  Future<int> deleteImportHistoryByProduct(String productId) async {
    if (productId.isEmpty) return 0;
    // Xóa thật vì bảng không có cột deleted
    return (await database).delete(
      'supplier_import_history',
      where: "imei LIKE ? OR productName LIKE ?",
      whereArgs: ['%$productId%', '%$productId%'],
    );
  }

  /// Lấy chi phí liên quan đến sản phẩm (theo relatedPartId hoặc title/note chứa productId/imei)
  Future<List<Map<String, dynamic>>> getExpensesByProductId(
    String productId, {
    String? imei,
  }) async {
    if (productId.isEmpty && (imei == null || imei.isEmpty)) return [];
    final db = await database;

    String where = "relatedPartId = ?";
    List<dynamic> args = [productId];

    if (imei != null && imei.isNotEmpty) {
      where += " OR title LIKE ? OR note LIKE ?";
      args.addAll(['%$imei%', '%$imei%']);
    }

    return db.query('expenses', where: where, whereArgs: args);
  }

  /// Xóa chi phí theo ID
  Future<int> deleteExpense(int expenseId) async {
    return (await database).delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  /// Lấy đơn bán có chứa sản phẩm (theo productImeis)
  Future<List<Map<String, dynamic>>> getSalesByProductImei(String imei) async {
    if (imei.isEmpty) return [];
    final db = await database;
    return db.query(
      'sales',
      where: "productImeis LIKE ?",
      whereArgs: ['%$imei%'],
    );
  }

  Future<List<Product>> getInStockProducts() async {
    final shopId = await _getScopedShopId('getInStockProducts');
    if (shopId == null) return [];

    final maps = await (await database).query(
      'products',
      where:
          'shopId = ? AND status = 1 AND quantity > 0 AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId],
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Lấy repair_parts (phụ tùng sửa chữa) dưới dạng Product
  /// Dùng cho FastInventoryCheckView để kiểm kho phụ kiện
  Future<List<Product>> getRepairPartsAsProducts() async {
    final db = await database;
    final shopId = await _getScopedShopId('getRepairPartsAsProducts');
    if (shopId == null) return [];

    final parts = await db.query(
      'repair_parts',
      where: 'shopId = ? AND (deleted = 0 OR deleted IS NULL) AND quantity > 0',
      whereArgs: [shopId],
      orderBy: 'createdAt DESC',
    );
    return parts
        .map(
          (p) => Product(
            id: p['id'] as int?,
            firestoreId: p['firestoreId']?.toString(),
            name: p['partName']?.toString() ?? p['name']?.toString() ?? '',
            type: 'PHU_KIEN',
            quantity: (p['quantity'] as num?)?.toInt() ?? 0,
            cost: (p['cost'] as num?)?.toInt() ?? 0,
            price: (p['price'] as num?)?.toInt() ?? 0,
            createdAt:
                (p['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            status: 1,
            isSynced: p['isSynced'] == 1,
          ),
        )
        .toList();
  }

  /// Get products with pagination support for lazy loading
  /// Returns [limit] products starting from [offset], ordered by createdAt DESC
  Future<List<Product>> getProductsPaged(
    int limit,
    int offset, {
    String? type,
    bool inStockOnly = false,
  }) async {
    final shopId = await _getScopedShopId('getProductsPaged');
    if (shopId == null) return [];

    String where = 'shopId = ? AND (deleted = 0 OR deleted IS NULL)';
    List<dynamic> whereArgs = [shopId];

    if (type != null) {
      where += ' AND ${_typeWhereClause(type, whereArgs)}';
    }

    if (inStockOnly) {
      where += ' AND quantity > 0 AND (status = 1 OR status IS NULL)';
    }

    final maps = await (await database).query(
      'products',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Get total count of products for pagination
  Future<int> getProductsCount({String? type, bool inStockOnly = false}) async {
    final shopId = await _getScopedShopId('getProductsCount');
    if (shopId == null) return 0;

    String where = 'shopId = ? AND (deleted = 0 OR deleted IS NULL)';
    List<dynamic> args = [shopId];

    if (type != null) {
      where += ' AND ${_typeWhereClause(type, args)}';
    }

    if (inStockOnly) {
      where += ' AND quantity > 0 AND (status = 1 OR status IS NULL)';
    }

    String query = 'SELECT COUNT(*) as count FROM products WHERE $where';
    final result = await (await database).rawQuery(query, args);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get inventory summary (total quantity and capital) for all products
  /// This calculates from ALL products in DB, not just paginated data
  Future<Map<String, int>> getInventorySummary({String? type}) async {
    final shopId = await _getScopedShopId('getInventorySummary');
    if (shopId == null) {
      return {'totalQty': 0, 'totalCapital': 0};
    }

    const shopFilter = ' AND shopId = ?';
    List<dynamic> args = [shopId];

    String query =
        '''
      SELECT 
        COALESCE(SUM(quantity), 0) as totalQty,
        COALESCE(SUM(cost * quantity), 0) as totalCapital
      FROM products 
      WHERE quantity > 0 AND (status = 1 OR status IS NULL) AND (deleted = 0 OR deleted IS NULL)$shopFilter
    ''';

    if (type != null && type != 'TẤT CẢ') {
      final typeClause = _typeWhereClause(type, args);
      query =
          '''
        SELECT 
          COALESCE(SUM(quantity), 0) as totalQty,
          COALESCE(SUM(cost * quantity), 0) as totalCapital
        FROM products 
        WHERE quantity > 0 AND (status = 1 OR status IS NULL) AND (deleted = 0 OR deleted IS NULL)$shopFilter AND $typeClause
      ''';
    }

    final result = await (await database).rawQuery(query, args);
    if (result.isEmpty) {
      return {'totalQty': 0, 'totalCapital': 0};
    }

    return {
      'totalQty': (result.first['totalQty'] as num?)?.toInt() ?? 0,
      'totalCapital': (result.first['totalCapital'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<Product>> getAllProducts() async {
    final shopId = await _getScopedShopId('getAllProducts');
    if (shopId == null) return [];

    const whereClause = 'shopId = ? AND (deleted = 0 OR deleted IS NULL)';
    final whereArgs = [shopId];

    final maps = await (await database).query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Lấy sản phẩm theo loại (ĐITHOAI, PHỤ KIỆN, LINH KIỆN)
  Future<List<Product>> getProductsByType(
    String type, {
    bool inStockOnly = true,
  }) async {
    final shopId = await _getScopedShopId('getProductsByType');
    if (shopId == null) return [];

    List<dynamic> whereArgs = [];
    final typeClause = _typeWhereClause(type, whereArgs);
    String where =
        'shopId = ? AND $typeClause AND (deleted = 0 OR deleted IS NULL)';
    whereArgs.insert(0, shopId);

    if (inStockOnly) {
      where += ' AND quantity > 0 AND (status = 1 OR status IS NULL)';
    }

    final maps = await (await database).query(
      'products',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Lấy tất cả linh kiện (từ cả bảng repair_parts và products type='LINH KIỆN')
  /// Trả về dạng Map để tương thích với code cũ
  Future<List<Map<String, dynamic>>> getAllPartsUnified() async {
    final List<Map<String, dynamic>> result = [];

    // 1. Lấy từ bảng repair_parts (kho cũ)
    final oldParts = await getAllParts();
    for (var p in oldParts) {
      result.add({
        'id': p['id'],
        'source': 'repair_parts', // Đánh dấu nguồn
        'partName': p['partName'] ?? '',
        'compatibleModels': p['compatibleModels'] ?? '',
        'quantity': p['quantity'] ?? 0,
        'cost': p['cost'] ?? 0,
        'price': p['price'] ?? 0,
        'supplierId': p['supplierId'],
      });
    }

    // 2. Lấy từ bảng products với type = 'LINH KIỆN' (kho mới)
    final newParts = await getProductsByType('LINH KIỆN', inStockOnly: true);
    for (var p in newParts) {
      result.add({
        'id': p.id,
        'source': 'products', // Đánh dấu nguồn
        'partName': p.name,
        'compatibleModels': p.model ?? '',
        'quantity': p.quantity,
        'cost': p.cost,
        'price': p.price,
        'supplierId': null, // Products không có supplierId trực tiếp
      });
    }

    return result;
  }

  /// Trừ số lượng linh kiện từ nguồn phù hợp (repair_parts hoặc products)
  Future<bool> deductPartQuantityUnified(
    int partId,
    String source,
    int quantity,
  ) async {
    if (source == 'repair_parts') {
      return await deductPartQuantity(partId, quantity);
    } else if (source == 'products') {
      final product = await getProductById(partId);
      if (product == null || product.quantity < quantity) return false;
      await deductProductQuantity(partId, quantity);
      return true;
    }
    return false;
  }

  /// Trừ kho và cập nhật đơn sửa trong MỘT SQLite transaction duy nhất.
  /// Đảm bảo tính nguyên tử: nếu bất kỳ bước nào thất bại, toàn bộ sẽ rollback.
  ///
  /// [parts] – danh sách part info, mỗi phần tử cần: id (int), source (String), qty (int), name (String)
  /// [repair] – đơn sửa đã được cập nhật partsUsed/cost trong bộ nhớ, chưa ghi DB
  ///
  /// Trả về [AtomicPartsResult] với success flag và danh sách part cần sync Firestore sau khi commit.
  Future<AtomicPartsResult> deductPartsAndUpdateRepairAtomic({
    required List<Map<String, dynamic>> parts,
    required Repair repair,
  }) async {
    final db = await database;
    final shopId = await _getScopedShopId('deductPartsAndUpdateRepairAtomic');
    if (shopId == null) {
      return AtomicPartsResult(
        success: false,
        message: 'Không xác định được shop',
      );
    }

    // Chuẩn bị dữ liệu repair ngoài transaction (PRAGMA check, column validation)
    Map<String, dynamic> repairData = Map<String, dynamic>.from(repair.toMap());
    repairData.remove('id');
    final cols = await db.rawQuery('PRAGMA table_info(repairs)');
    final colNames = cols.map((c) => c['name'] as String).toSet();
    repairData.removeWhere((k, _) => !colNames.contains(k));

    final List<Map<String, dynamic>> partsToSync = [];
    String? failMessage;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;

        for (final part in parts) {
          final source = part['source'] as String;
          final partId = part['id'] as int;
          final qty = part['qty'] as int;
          final partName = part['name'] ?? 'linh kiện';

          if (source == 'repair_parts') {
            final rows = await txn.query(
              'repair_parts',
              where: 'id = ?',
              whereArgs: [partId],
              limit: 1,
            );
            if (rows.isEmpty) {
              failMessage = 'Không tìm thấy linh kiện "$partName"';
              throw Exception(failMessage);
            }
            final currentQty = rows.first['quantity'] as int? ?? 0;
            if (currentQty < qty) {
              failMessage = 'Không đủ số lượng: $partName (cần $qty, còn $currentQty)';
              throw Exception(failMessage);
            }
            final newQty = currentQty - qty;
            await txn.update(
              'repair_parts',
              {'quantity': newQty, 'updatedAt': now, 'isSynced': 0},
              where: 'id = ?',
              whereArgs: [partId],
            );
            partsToSync.add({
              ...part,
              'newQty': newQty,
              'firestoreId': rows.first['firestoreId'],
              'collection': 'repair_parts',
            });
          } else if (source == 'products') {
            final rows = await txn.query(
              'products',
              where: 'id = ? AND shopId = ?',
              whereArgs: [partId, shopId],
              limit: 1,
            );
            if (rows.isEmpty) {
              failMessage = 'Không tìm thấy sản phẩm "$partName"';
              throw Exception(failMessage);
            }
            final currentQty = rows.first['quantity'] as int? ?? 0;
            if (currentQty < qty) {
              failMessage = 'Không đủ số lượng: $partName (cần $qty, còn $currentQty)';
              throw Exception(failMessage);
            }
            final newQty = currentQty - qty;
            await txn.rawUpdate(
              'UPDATE products SET quantity = ?, updatedAt = ?, isSynced = 0 WHERE id = ? AND shopId = ?',
              [newQty, now, partId, shopId],
            );
            if (newQty <= 0) {
              await txn.rawUpdate(
                'UPDATE products SET status = 0 WHERE id = ? AND shopId = ?',
                [partId, shopId],
              );
            }
            partsToSync.add({
              ...part,
              'newQty': newQty,
              'firestoreId': rows.first['firestoreId'],
              'collection': 'products',
            });
          }
        }

        // Cập nhật đơn sửa trong cùng transaction.
        // Một số luồng mở chi tiết từ dữ liệu cloud chỉ có firestoreId, id local có thể null.
        int updatedRows = 0;
        final localId = repair.id;
        final firestoreId = (repair.firestoreId ?? '').trim();

        if (localId != null && localId > 0) {
          updatedRows = await txn.update(
            'repairs',
            repairData,
            where: 'id = ?',
            whereArgs: [localId],
          );
        }

        if (updatedRows == 0 && firestoreId.isNotEmpty) {
          updatedRows = await txn.update(
            'repairs',
            repairData,
            where: 'firestoreId = ?',
            whereArgs: [firestoreId],
          );
        }

        if (updatedRows == 0) {
          failMessage =
              'Không tìm thấy đơn sửa để cập nhật (id=${repair.id}, firestoreId=${repair.firestoreId})';
          throw Exception(failMessage);
        }
      });

      return AtomicPartsResult(success: true, partsToSync: partsToSync);
    } catch (e) {
      debugPrint('❌ deductPartsAndUpdateRepairAtomic rollback: $e');
      return AtomicPartsResult(
        success: false,
        message: failMessage ?? 'Lỗi khi trừ kho: $e',
      );
    }
  }

  /// Khôi phục số lượng linh kiện theo tên (tìm trong cả repair_parts và products type=LINH_KIEN)
  Future<bool> restorePartQuantityByNameUnified(
    String partName,
    int quantity,
  ) async {
    final shopId = await _getScopedShopId('restorePartQuantityByNameUnified');
    if (shopId == null) return false;

    // Try repair_parts first
    final restored = await restorePartQuantityByName(partName, quantity);
    if (restored) return true;

    // Fallback: try products table (type = LINH_KIEN)
    final db = await database;
    final products = await db.query(
      'products',
      where:
          'shopId = ? AND UPPER(name) = ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId, partName.toUpperCase()],
      limit: 1,
    );
    if (products.isEmpty) {
      debugPrint(
        '⚠️ restorePartQuantityByNameUnified: Not found in either table: $partName',
      );
      return false;
    }

    final productId = products.first['id'] as int;
    final firestoreId = (products.first['firestoreId'] ?? '').toString();
    final currentQty = (products.first['quantity'] as int? ?? 0);
    final newQty = currentQty + quantity;
    await addProductQuantity(productId, quantity);
    if (firestoreId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(firestoreId)
            .update({
              'quantity': newQty,
              'status': newQty <= 0 ? 0 : 1,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
        await db.rawUpdate(
          'UPDATE products SET isSynced = 1 WHERE id = ? AND shopId = ?',
          [productId, shopId],
        );
      } catch (e) {
        debugPrint('⚠️ Failed to sync restored product quantity immediately: $e');
      }
    }
    debugPrint('✅ Restored product quantity: $partName, +$quantity');
    return true;
  }

  Future<Product?> getProductByFirestoreId(String firestoreId) async {
    final shopId = await _getScopedShopId('getProductByFirestoreId');
    if (shopId == null) return null;

    final res = await (await database).query(
      'products',
      where:
          'firestoreId = ? AND shopId = ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [firestoreId, shopId],
      limit: 1,
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  Future<Product?> getProductById(int id) async {
    final shopId = await _getScopedShopId('getProductById');
    if (shopId == null) return null;

    final res = await (await database).query(
      'products',
      where: 'id = ? AND shopId = ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [id, shopId],
      limit: 1,
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  Future<int> updateProductStatus(int id, int status) async =>
      await (await database).rawUpdate(
        'UPDATE products SET status = ? WHERE id = ?',
        [status, id],
      );

  /// Trừ số lượng sản phẩm trong kho và sync ngay lập tức
  Future<void> deductProductQuantity(int id, int amount) async {
    final db = await database;
    final shopId = await _getScopedShopId('deductProductQuantity');
    if (shopId == null) return;

    // Lấy thông tin product trước để có firestoreId và quantity
    final productResult = await db.query(
      'products',
      where: 'id = ? AND shopId = ?',
      whereArgs: [id, shopId],
      limit: 1,
    );

    if (productResult.isEmpty) return;

    final product = productResult.first;
    final currentQty = (product['quantity'] as int?) ?? 0;
    final newQty = currentQty - amount;
    final firestoreId = product['firestoreId'] as String?;

    await db.rawUpdate(
      'UPDATE products SET quantity = quantity - ?, updatedAt = ?, isSynced = 0 WHERE id = ? AND shopId = ?',
      [amount, DateTime.now().millisecondsSinceEpoch, id, shopId],
    );
    await db.rawUpdate(
      'UPDATE products SET status = 0 WHERE id = ? AND shopId = ? AND quantity <= 0',
      [id, shopId],
    );

    // FIX: Sync ngay lập tức để tránh trường hợp 2 thiết bị bán cùng 1 sản phẩm
    if (firestoreId != null && firestoreId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(firestoreId)
            .update({
              'quantity': newQty < 0 ? 0 : newQty,
              'status': newQty <= 0 ? 0 : 1,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
        // Đánh dấu đã sync
        await db.rawUpdate(
          'UPDATE products SET isSynced = 1 WHERE id = ? AND shopId = ?',
          [id, shopId],
        );
        debugPrint('✅ Synced product quantity: $firestoreId, newQty: $newQty');
      } catch (e) {
        debugPrint('⚠️ Failed to sync product quantity immediately: $e');
        // Vẫn tiếp tục vì local đã update, sẽ sync sau
      }
    }
  }

  Future<void> addProductQuantity(int id, int amount) async {
    final db = await database;
    final shopId = await _getScopedShopId('addProductQuantity');
    if (shopId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE products SET quantity = quantity + ?, isSynced = 0, updatedAt = ? WHERE id = ? AND shopId = ?',
      [amount, now, id, shopId],
    );
    // Nếu sản phẩm đã bán hết (status = 0) và giờ có hàng lại, có thể cần cập nhật status
    await db.rawUpdate(
      'UPDATE products SET status = 1 WHERE id = ? AND shopId = ? AND status = 0 AND quantity > 0',
      [id, shopId],
    );
  }

  /// Lấy số lượng tồn kho hiện tại của sản phẩm (real-time từ DB)
  /// Dùng để kiểm tra trước khi bán, tránh 2 nhân viên bán cùng 1 món
  Future<int> getProductQuantityById(int id) async {
    final db = await database;
    final shopId = await _getScopedShopId('getProductQuantityById');
    if (shopId == null) return 0;

    final result = await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ? AND shopId = ?',
      whereArgs: [id, shopId],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return (result.first['quantity'] as int?) ?? 0;
  }

  Future<Product?> getProductByImei(String imei) async {
    final shopId = await _getScopedShopId('getProductByImei');
    if (shopId == null) return null;

    final res = await (await database).rawQuery(
      'SELECT * FROM products WHERE UPPER(imei) = UPPER(?) AND shopId = ? AND (deleted = 0 OR deleted IS NULL) LIMIT 1',
      [imei, shopId],
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  /// Tìm sản phẩm theo tên (case-insensitive, dùng cho phụ kiện không có IMEI)
  /// Ưu tiên sản phẩm cùng shopId, còn hàng (quantity > 0 hoặc status > 0)
  Future<Product?> getProductByName(String name) async {
    final shopId = await _getScopedShopId('getProductByName');
    if (shopId == null) return null;

    final db = await database;
    final res = await db.rawQuery(
      'SELECT * FROM products WHERE UPPER(name) = UPPER(?) AND shopId = ? AND (deleted IS NULL OR deleted != 1) ORDER BY quantity DESC LIMIT 1',
      [name, shopId],
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  // --- CUSTOMERS & SUPPLIERS ---
  Future<List<Map<String, dynamic>>>
  getCustomerSuggestions() async => (await database).rawQuery(
    'SELECT DISTINCT customerName, phone, address FROM (SELECT customerName, phone, address FROM repairs UNION SELECT customerName, phone, address FROM sales UNION SELECT name as customerName, phone, address FROM customers) ORDER BY customerName ASC LIMIT 200',
  );
  Future<List<Map<String, dynamic>>>
  getUniqueCustomersAll() async => (await database).rawQuery(
    "SELECT phone, customerName, address FROM (SELECT phone, customerName, address FROM repairs UNION SELECT phone, customerName, address FROM sales UNION SELECT phone, name as customerName, address FROM customers) as t WHERE phone IS NOT NULL AND phone != '' GROUP BY phone ORDER BY customerName ASC",
  );
  Future<List<Map<String, dynamic>>> getCustomersWithoutShop() async =>
      (await database).query(
        'customers',
        where: "shopId IS NULL OR shopId = ''",
      );
  Future<void> deleteCustomerData(String name, String phone) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'repairs',
        where: 'customerName = ? AND phone = ?',
        whereArgs: [name, phone],
      );
      await txn.delete(
        'sales',
        where: 'customerName = ? AND phone = ?',
        whereArgs: [name, phone],
      );
      await txn.delete(
        'customers',
        where: 'name = ? AND phone = ?',
        whereArgs: [name, phone],
      );
    });
  }

  Future<int> deleteCustomerByPhone(String phone) async => (await database)
      .delete('customers', where: 'phone = ?', whereArgs: [phone]);

  Future<int> insertSupplier(Map<String, dynamic> map) async {
    final dbInstance = await database;
    try {
      final id = await dbInstance.insert(
        'suppliers',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint(
        'DBHelper.insertSupplier: inserted id=$id, name=${map['name']}',
      );
      return id;
    } catch (e) {
      debugPrint('DBHelper.insertSupplier error: $e');
      return 0;
    }
  }

  Future<void> upsertSupplier(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    final name = data['name'] as String?;
    final shopId = data['shopId'] as String?;

    // Loại bỏ id vì SQLite auto-generate và _encrypted vì không có trong schema
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    cleanData.remove('email'); // Loại bỏ email nếu có
    // Strip any Firestore fields not in SQLite schema
    await _filterToTableColumns('suppliers', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      // Tìm theo firestoreId trước
      final existing = await db.query(
        'suppliers',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'suppliers',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        // Xóa duplicate cùng tên nhưng khác firestoreId (nếu có)
        if (name != null && shopId != null) {
          await db.delete(
            'suppliers',
            where:
                "name = ? AND shopId = ? AND firestoreId != ? AND (deleted = 0 OR deleted IS NULL)",
            whereArgs: [name, shopId, firestoreId],
          );
        }
        return;
      }

      // Nếu không tìm thấy theo firestoreId, tìm theo name + shopId (bất kể firestoreId)
      if (name != null && shopId != null) {
        final existingByName = await db.query(
          'suppliers',
          where: "name = ? AND shopId = ? AND (deleted = 0 OR deleted IS NULL)",
          whereArgs: [name, shopId],
          limit: 1,
        );
        if (existingByName.isNotEmpty) {
          // Update record cũ với firestoreId mới
          final existingId = existingByName.first['id'];
          await db.update(
            'suppliers',
            cleanData,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          // Xóa các bản duplicate khác cùng tên
          await db.delete(
            'suppliers',
            where:
                "name = ? AND shopId = ? AND id != ? AND (deleted = 0 OR deleted IS NULL)",
            whereArgs: [name, shopId, existingId],
          );
          return;
        }
      }

      // Không tìm thấy, insert mới
      await db.insert(
        'suppliers',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      // Không có firestoreId - tìm theo name + shopId trước
      if (name != null && shopId != null) {
        final existingByName = await db.query(
          'suppliers',
          where: "name = ? AND shopId = ? AND (deleted = 0 OR deleted IS NULL)",
          whereArgs: [name, shopId],
          limit: 1,
        );
        if (existingByName.isNotEmpty) {
          await db.update(
            'suppliers',
            cleanData,
            where: 'id = ?',
            whereArgs: [existingByName.first['id']],
          );
          return;
        }
      }
      await db.insert(
        'suppliers',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> deleteSupplierByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'suppliers',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final db = await database;
    final shopId = await _getScopedShopId('getSuppliers');
    if (shopId == null) return [];

    final res = await db.query(
      'suppliers',
      where: 'shopId = ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId],
      orderBy: 'name ASC',
    );
    debugPrint('DBHelper.getSuppliers: found ${res.length} suppliers');
    return res;
  }

  /// Dọn dẹp NCC trùng lặp - giữ lại bản có firestoreId, xóa bản duplicate
  Future<int> deduplicateSuppliers() async {
    final db = await database;
    // Tìm các nhóm NCC trùng tên + shopId
    final duplicates = await db.rawQuery('''
      SELECT name, shopId, COUNT(*) as cnt, 
             GROUP_CONCAT(id) as ids,
             GROUP_CONCAT(COALESCE(firestoreId, '')) as fids
      FROM suppliers 
      WHERE (deleted = 0 OR deleted IS NULL)
      GROUP BY LOWER(name), shopId 
      HAVING cnt > 1
    ''');

    int removed = 0;
    for (final group in duplicates) {
      final ids = (group['ids'] as String).split(',').map(int.parse).toList();
      final fids = (group['fids'] as String).split(',');

      // Ưu tiên giữ bản có firestoreId, nếu không thì giữ id nhỏ nhất (cũ nhất)
      int keepId = ids.first;
      for (int i = 0; i < ids.length; i++) {
        if (fids[i].isNotEmpty) {
          keepId = ids[i];
          break;
        }
      }

      // Merge: cập nhật bản giữ lại với thông tin mới nhất
      final keepRow = await db.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [keepId],
      );
      if (keepRow.isEmpty) continue;

      // Xóa các bản duplicate
      for (final id in ids) {
        if (id != keepId) {
          await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
          removed++;
        }
      }
      debugPrint(
        '🔧 Dedup supplier: kept id=$keepId, removed ${ids.length - 1} duplicates for "${group['name']}"',
      );
    }
    if (removed > 0) {
      debugPrint('🔧 deduplicateSuppliers: removed $removed duplicates total');
    }
    return removed;
  }

  Future<int> deleteSupplier(int id) async =>
      (await database).delete('suppliers', where: 'id = ?', whereArgs: [id]);

  // --- FINANCE ---
  Future<void> upsertExpense(Expense e) async =>
      _upsert('expenses', e.toMap(), e.firestoreId ?? "exp_${e.date}");
  Future<int> insertExpense(Map<String, dynamic> e) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(e));
    cleanData['createdAt'] =
        cleanData['createdAt'] ??
        cleanData['date'] ??
        DateTime.now().millisecondsSinceEpoch;
    cleanData['date'] = cleanData['date'] ?? cleanData['createdAt'];
    cleanData['isSynced'] = cleanData['isSynced'] ?? 0;

    await _filterToTableColumns('expenses', cleanData, executor: db);
    return db.insert('expenses', cleanData);
  }

  /// Lấy tất cả expenses của shop hiện tại
  Future<List<Map<String, dynamic>>> getAllExpenses() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'expenses',
        where: 'shopId = ? OR shopId IS NULL',
        whereArgs: [shopId],
        orderBy: 'date DESC',
      );
    }
    // Fallback: nếu không có shopId thì trả về tất cả (super admin)
    return db.query('expenses', orderBy: 'date DESC');
  }

  /// Get expenses within a date range (by date field), for financial report optimization
  Future<List<Map<String, dynamic>>> getExpensesByDateRange(
    int startMs,
    int endMs,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'expenses',
        where:
            '(shopId = ? OR shopId IS NULL) AND COALESCE(date, createdAt) >= ? AND COALESCE(date, createdAt) <= ?',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'date DESC',
      );
    }
    return db.query(
      'expenses',
      where:
          'COALESCE(date, createdAt) >= ? AND COALESCE(date, createdAt) <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'date DESC',
    );
  }

  Future<List<Expense>> getAllExpensesForSync() async {
    final db = await database;
    final maps = await db.query('expenses', orderBy: 'date DESC');
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<void> updateExpense(Expense e) async {
    final db = await database;
    await db.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<int> deleteExpenseByFirestoreId(String fId) async => (await database)
      .delete('expenses', where: 'firestoreId = ?', whereArgs: [fId]);

  /// Lấy expense theo firestoreId - dùng cho conflict resolution
  Future<Expense?> getExpenseByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'expenses',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? Expense.fromMap(res.first) : null;
  }

  // --- SALVAGE PHONES (Kho máy xác) ---
  Future<void> upsertSalvagePhone(Map<String, dynamic> data) async {
    final fId =
        data['firestoreId'] ??
        'sp_${data['createdAt']}_${data['deviceName'].hashCode}';
    await _upsert('salvage_phones', data, fId);
  }

  Future<List<Map<String, dynamic>>> getAllSalvagePhones() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'salvage_phones',
        where: '(shopId = ? OR shopId IS NULL) AND deleted = 0',
        whereArgs: [shopId],
        orderBy: 'createdAt DESC',
      );
    }
    return db.query(
      'salvage_phones',
      where: 'deleted = 0',
      orderBy: 'createdAt DESC',
    );
  }

  Future<int> deleteSalvagePhoneByFirestoreId(String fId) async =>
      (await database).delete(
        'salvage_phones',
        where: 'firestoreId = ?',
        whereArgs: [fId],
      );

  Future<Map<String, dynamic>?> getSalvagePhoneByFirestoreId(
    String firestoreId,
  ) async {
    final res = await (await database).query(
      'salvage_phones',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> updateSalvagePhone(Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'salvage_phones',
      data,
      where: 'id = ?',
      whereArgs: [data['id']],
    );
  }

  Future<void> upsertDebt(Debt d) async =>
      _upsert('debts', d.toMap(), d.firestoreId ?? "debt_${d.createdAt}");
  Future<int> insertDebt(Map<String, dynamic> d) async =>
      (await database).insert('debts', d);
  Future<List<Map<String, dynamic>>> getAllDebts() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'debts',
        where: 'shopId = ? OR shopId IS NULL',
        whereArgs: [shopId],
        orderBy: 'status ASC, createdAt DESC',
      );
    }
    return db.query('debts', orderBy: 'status ASC, createdAt DESC');
  }

  /// Lấy công nợ được tạo trong khoảng thời gian (by createdAt) — dùng cho Finance V2 thay vì getAllDebts()
  Future<List<Map<String, dynamic>>> getDebtsByDateRange(
    int startMs,
    int endMs,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'debts',
        where:
            '(shopId = ? OR shopId IS NULL) AND createdAt >= ? AND createdAt <= ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'createdAt DESC',
      );
    }
    return db.query(
      'debts',
      where:
          'createdAt >= ? AND createdAt <= ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [startMs, endMs],
      orderBy: 'createdAt DESC',
    );
  }

  /// Snapshot công nợ cho Finance: lấy toàn bộ công nợ còn trong hệ thống (không giới hạn createdAt),
  /// sau đó tầng service sẽ tự tính remaining và phân loại phải thu/phải trả.
  Future<List<Map<String, dynamic>>> getDebtsForFinanceSnapshot() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'debts',
        where: '(shopId = ? OR shopId IS NULL) AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [shopId],
        orderBy: 'createdAt DESC',
      );
    }
    return db.query(
      'debts',
      where: '(deleted = 0 OR deleted IS NULL)',
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPurchaseDebts() async =>
      (await database).query(
        'purchase_orders',
        where: 'paymentMethod = ? AND status = ?',
        whereArgs: ['CÔNG NỢ', 'PENDING'],
        orderBy: 'createdAt DESC',
      );
  Future<int> updateDebtPaid(int id, int pay) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await (await database).rawUpdate(
      'UPDATE debts SET paidAmount = paidAmount + ?, status = CASE WHEN (paidAmount + ?) >= totalAmount THEN ? ELSE ? END, updatedAt = ?, isSynced = 0 WHERE id = ?',
      [pay, pay, 'paid', 'unpaid', now, id],
    );
  }

  Future<int> updateDebt(Map<String, dynamic> debt) async =>
      await (await database).update(
        'debts',
        debt,
        where: 'id = ?',
        whereArgs: [debt['id']],
      );
  Future<int> deleteDebtByFirestoreId(String fId) async => (await database)
      .delete('debts', where: 'firestoreId = ?', whereArgs: [fId]);

  /// Lấy debt theo firestoreId - dùng cho conflict resolution
  Future<Map<String, dynamic>?> getDebtByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'debts',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Lấy debt ID từ firestoreId
  Future<int?> getDebtIdByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'debts',
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first['id'] as int? : null;
  }

  /// Lấy ID của purchase_order theo firestoreId
  Future<int?> getPurchaseOrderIdByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'purchase_orders',
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first['id'] as int? : null;
  }

  /// Cập nhật firestoreId và isSynced cho debt sau khi sync lên cloud
  Future<void> updateDebtSynced(int id, String firestoreId) async {
    final db = await database;
    await db.update(
      'debts',
      {'firestoreId': firestoreId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertClosing(Map<String, dynamic> map) async {
    final db = await database;
    final dateKey = map['dateKey'];
    final existing = await db.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'cash_closings',
        map,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('cash_closings', map);
    }
  }

  /// Lấy ID của cash_closing theo firestoreId
  Future<int?> getCashClosingIdByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'cash_closings',
      columns: ['id'],
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first['id'] as int? : null;
  }

  /// Lấy chốt quỹ của ngày trước (để làm số dư đầu kỳ cho hôm nay)
  Future<Map<String, dynamic>?> getPreviousDayClosing(
    String todayDateKey,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      final res = await db.query(
        'cash_closings',
        where:
            '(dateKey < ? AND isLocked = 1) AND (shopId = ? OR shopId IS NULL)',
        whereArgs: [todayDateKey, shopId],
        orderBy: 'dateKey DESC',
        limit: 1,
      );
      return res.isNotEmpty ? res.first : null;
    }
    final res = await db.query(
      'cash_closings',
      where: 'dateKey < ? AND isLocked = 1',
      whereArgs: [todayDateKey],
      orderBy: 'dateKey DESC',
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Lấy chốt quỹ theo dateKey
  Future<Map<String, dynamic>?> getClosingByDateKey(String dateKey) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    debugPrint('🔍 [DB] getClosingByDateKey: dateKey=$dateKey, shopId=$shopId');

    if (shopId != null && shopId.isNotEmpty) {
      final res = await db.query(
        'cash_closings',
        where: 'dateKey = ? AND (shopId = ? OR shopId IS NULL)',
        whereArgs: [dateKey, shopId],
        limit: 1,
      );
      debugPrint(
        '🔍 [DB] getClosingByDateKey result: ${res.isNotEmpty ? 'FOUND' : 'NOT FOUND'} (with shopId filter)',
      );
      return res.isNotEmpty ? res.first : null;
    }
    final res = await db.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    debugPrint(
      '🔍 [DB] getClosingByDateKey result: ${res.isNotEmpty ? 'FOUND' : 'NOT FOUND'} (without shopId filter)',
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Lấy tất cả các chốt quỹ
  Future<List<Map<String, dynamic>>> getAllCashClosings() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return db.query(
        'cash_closings',
        where: 'shopId = ? OR shopId IS NULL',
        whereArgs: [shopId],
        orderBy: 'dateKey DESC',
      );
    }
    return db.query('cash_closings', orderBy: 'dateKey DESC');
  }

  /// FIX BUG-CC-002: Xóa chốt quỹ theo firestoreId (dùng cho sync)
  Future<int> deleteCashClosingByFirestoreId(String firestoreId) async {
    final db = await database;
    return db.delete(
      'cash_closings',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // --- ADJUSTMENT ENTRIES (Bút toán điều chỉnh) ---

  /// Upsert bút toán điều chỉnh (for sync)
  Future<void> upsertAdjustmentEntry(Map<String, dynamic> data) async {
    final firestoreId = data['firestoreId'] as String?;
    if (firestoreId == null) return;

    final db = await database;

    // Filter to valid schema columns
    final filteredData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    await _filterToTableColumns('adjustment_entries', filteredData);

    final existing = await db.query(
      'adjustment_entries',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'adjustment_entries',
        filteredData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert('adjustment_entries', filteredData);
    }
  }

  /// Xóa bút toán điều chỉnh theo firestoreId (for sync)
  Future<int> deleteAdjustmentEntryByFirestoreId(String firestoreId) async {
    final db = await database;
    return db.delete(
      'adjustment_entries',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  /// Upsert chốt quỹ
  Future<void> upsertCashClosing(Map<String, dynamic> data) async {
    final dateKey = data['dateKey'] as String?;
    if (dateKey == null) return;

    final db = await database;

    // Filter to valid schema columns
    final filteredData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    await _filterToTableColumns('cash_closings', filteredData);

    debugPrint(
      'upsertCashClosing: filtered data keys=${filteredData.keys.toList()}',
    );

    // FIX: Use dateKey + shopId as unique key to avoid overwriting other shops' data
    final shopId = data['shopId'] as String? ?? UserService.getShopIdSync();
    String whereClause;
    List<dynamic> whereArgs;
    if (shopId != null && shopId.isNotEmpty) {
      whereClause = 'dateKey = ? AND (shopId = ? OR shopId IS NULL)';
      whereArgs = [dateKey, shopId];
      // Ensure shopId is in the data
      if (!filteredData.containsKey('shopId')) {
        filteredData['shopId'] = shopId;
      }
    } else {
      whereClause = 'dateKey = ?';
      whereArgs = [dateKey];
    }

    final existing = await db.query(
      'cash_closings',
      where: whereClause,
      whereArgs: whereArgs,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'cash_closings',
        filteredData,
        where: whereClause,
        whereArgs: whereArgs,
      );
    } else {
      await db.insert('cash_closings', filteredData);
    }
  }

  // --- ATTENDANCE & WORK SCHEDULES ---
  Future<void> upsertAttendance(Attendance a) async => _upsert(
    'attendance',
    a.toMap(),
    a.firestoreId ?? "att_${a.dateKey}_${a.userId}",
  );
  Future<int> insertAttendance(Attendance a) async {
    await upsertAttendance(a);
    return 1;
  }

  Future<int> updateAttendance(Attendance a) async => (await database).update(
    'attendance',
    a.toMap(),
    where: 'id = ?',
    whereArgs: [a.id],
  );
  Future<int> deleteAttendanceByFirestoreId(String fId) async =>
      (await database).delete(
        'attendance',
        where: 'firestoreId = ?',
        whereArgs: [fId],
      );
  Future<List<Attendance>> getAllAttendance() async {
    final maps = await (await database).query(
      'attendance',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<Attendance?> getAttendance(String dateKey, String userId) async {
    final res = await (await database).query(
      'attendance',
      where: 'dateKey = ? AND userId = ?',
      whereArgs: [dateKey, userId],
      limit: 1,
    );
    return res.isNotEmpty ? Attendance.fromMap(res.first) : null;
  }

  Future<List<Attendance>> getAttendanceByUser(
    String userId, {
    int? limit,
  }) async {
    final maps = await (await database).query(
      'attendance',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<List<Attendance>> getAttendanceByDateRange(
    String start,
    String end,
  ) async {
    final maps = await (await database).query(
      'attendance',
      where: 'dateKey BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'dateKey DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  Future<Map<String, dynamic>?> getWorkSchedule(String userId) async {
    final res = await (await database).query(
      'work_schedules',
      where: 'userId = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> upsertWorkSchedule(
    String userId,
    Map<String, dynamic> schedule,
  ) async {
    final db = await database;
    final data = _sanitizeForSqlite({
      'userId': userId,
      ...schedule,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _filterToTableColumns('work_schedules', data);
    await db.insert(
      'work_schedules',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- LEAVE REQUESTS ---
  Future<void> upsertLeaveRequest(LeaveRequest lr) async => _upsert(
    'leave_requests',
    lr.toMap(),
    lr.firestoreId ?? "lr_${lr.userId}_${lr.startDate}",
  );

  Future<int> insertLeaveRequest(LeaveRequest lr) async {
    await upsertLeaveRequest(lr);
    return 1;
  }

  Future<int> updateLeaveRequest(LeaveRequest lr) async =>
      (await database).update(
        'leave_requests',
        lr.toMap(),
        where: 'id = ?',
        whereArgs: [lr.id],
      );

  Future<int> deleteLeaveRequestByFirestoreId(String fId) async =>
      (await database).delete(
        'leave_requests',
        where: 'firestoreId = ?',
        whereArgs: [fId],
      );

  Future<List<LeaveRequest>> getAllLeaveRequests() async {
    final shopId = UserService.getShopIdSync();
    String where = 'deleted = 0';
    List<dynamic> args = [];
    if (shopId != null && shopId.isNotEmpty) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    final maps = await (await database).query(
      'leave_requests',
      where: where,
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => LeaveRequest.fromMap(m)).toList();
  }

  Future<List<LeaveRequest>> getLeaveRequestsByUser(String userId) async {
    final shopId = UserService.getShopIdSync();
    String where = 'userId = ? AND deleted = 0';
    List<dynamic> args = [userId];
    if (shopId != null && shopId.isNotEmpty) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    final maps = await (await database).query(
      'leave_requests',
      where: where,
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => LeaveRequest.fromMap(m)).toList();
  }

  Future<List<LeaveRequest>> getLeaveRequestsByStatus(String status) async {
    final shopId = UserService.getShopIdSync();
    String where = 'status = ? AND deleted = 0';
    List<dynamic> args = [status];
    if (shopId != null && shopId.isNotEmpty) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    final maps = await (await database).query(
      'leave_requests',
      where: where,
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => LeaveRequest.fromMap(m)).toList();
  }

  Future<List<LeaveRequest>> getLeaveRequestsByDateRange(
    String start,
    String end,
  ) async {
    final shopId = UserService.getShopIdSync();
    String where =
        'deleted = 0 AND ((startDate BETWEEN ? AND ?) OR (endDate BETWEEN ? AND ?))';
    List<dynamic> args = [start, end, start, end];
    if (shopId != null && shopId.isNotEmpty) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    final maps = await (await database).query(
      'leave_requests',
      where: where,
      whereArgs: args,
      orderBy: 'startDate ASC',
    );
    return maps.map((m) => LeaveRequest.fromMap(m)).toList();
  }

  Future<List<Attendance>> getPendingAttendanceRequests() async {
    final shopId = UserService.getShopIdSync();
    String where = 'status = ? AND deleted = 0';
    List<dynamic> args = ['pending'];
    if (shopId != null && shopId.isNotEmpty) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    final maps = await (await database).query(
      'attendance',
      where: where,
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => Attendance.fromMap(m)).toList();
  }

  // --- PURCHASE ORDERS ---
  Future<List<PurchaseOrder>> getAllPurchaseOrders() async {
    final db = await database;
    final results = await db.query(
      'purchase_orders',
      orderBy: 'createdAt DESC',
    );
    return results.map((row) => PurchaseOrder.fromMap(row)).toList();
  }

  Future<String> generateNextOrderCode() async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM purchase_orders',
    );
    int count = Sqflite.firstIntValue(res) ?? 0;
    return "PO-${(count + 1).toString().padLeft(4, '0')}";
  }

  Future<void> insertPurchaseOrder(PurchaseOrder order) async =>
      (await database).insert('purchase_orders', order.toMap());
  Future<void> updatePurchaseOrder(PurchaseOrder order) async =>
      (await database).update(
        'purchase_orders',
        order.toMap(),
        where: 'firestoreId = ?',
        whereArgs: [order.firestoreId],
      );

  /// Upsert purchase order (for sync)
  Future<void> upsertPurchaseOrder(Map<String, dynamic> data) async {
    final firestoreId = data['firestoreId'] as String?;
    if (firestoreId == null) return;

    final db = await database;

    // Filter to valid schema columns
    final filteredData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    await _filterToTableColumns('purchase_orders', filteredData);

    final existing = await db.query(
      'purchase_orders',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'purchase_orders',
        filteredData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert('purchase_orders', filteredData);
    }
  }

  /// Delete purchase order by firestoreId (for sync)
  Future<int> deletePurchaseOrderByFirestoreId(String firestoreId) async {
    final db = await database;
    return db.delete(
      'purchase_orders',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // --- INVENTORY CHECKS ---
  Future<List<Map<String, dynamic>>> getInventoryChecks({
    String? checkType,
    bool? isCompleted,
  }) async {
    final db = await database;
    String where = '1=1';
    List<Object> args = [];
    if (checkType != null) {
      where += ' AND type = ?';
      args.add(checkType);
    }
    if (isCompleted != null) {
      where += ' AND isCompleted = ?';
      args.add(isCompleted ? 1 : 0);
    }
    return await db.query(
      'inventory_checks',
      where: where,
      whereArgs: args,
      orderBy: 'checkDate DESC',
    );
  }

  Future<int> insertInventoryCheck(dynamic data) async {
    final db = await database;
    final map = (data is Map<String, dynamic>)
        ? data
        : (data as dynamic).toMap();
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(map));
    cleanData['createdAt'] =
        cleanData['createdAt'] ??
        cleanData['checkDate'] ??
        DateTime.now().millisecondsSinceEpoch;
    cleanData['checkDate'] = cleanData['checkDate'] ?? cleanData['createdAt'];
    cleanData['isSynced'] = cleanData['isSynced'] ?? 0;

    await _filterToTableColumns('inventory_checks', cleanData, executor: db);
    return await db.insert('inventory_checks', cleanData);
  }

  Future<int> updateInventoryCheck(dynamic data) async {
    final db = await database;
    final map = (data is Map<String, dynamic>)
        ? data
        : (data as dynamic).toMap();
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(map));
    await _filterToTableColumns('inventory_checks', cleanData, executor: db);

    return await db.update(
      'inventory_checks',
      cleanData,
      where: 'id = ?',
      whereArgs: [cleanData['id']],
    );
  }

  Future<List<Map<String, dynamic>>> getItemsForInventoryCheck(
    String type,
  ) async {
    final db = await database;
    final shopId = await _getScopedShopId('getItemsForInventoryCheck');
    if (shopId == null) return [];

    if (type == 'DIEN_THOAI') {
      return await db.query(
        'products',
        where:
            'shopId = ? AND status = 1 AND type = ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [shopId, 'DIEN_THOAI'],
      );
    } else if (type == 'LINH_KIEN') {
      // Linh kiện - match cả giá trị cũ 'LINH KIỆN' và mới 'LINH_KIEN'
      return await db.query(
        'products',
        where:
            'shopId = ? AND status = 1 AND (type = ? OR type = ?) AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [shopId, 'LINH KIỆN', 'LINH_KIEN'],
      );
    }
    // PHU_KIEN - gộp cả hai nguồn:
    // 1. Products có type = PHU_KIEN hoặc PHỤ KIỆN
    // 2. repair_parts (phụ tùng kho sửa chữa)
    final List<Map<String, dynamic>> results = [];

    // Phụ kiện từ bảng products (match cả format cũ và mới)
    final productPK = await db.query(
      'products',
      where:
          'shopId = ? AND status = 1 AND (type = ? OR type = ?) AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId, 'PHU_KIEN', 'PHỤ KIỆN'],
    );
    results.addAll(productPK);

    // Phụ tùng từ bảng repair_parts (map partName → name để UI đọc được)
    final parts = await db.query(
      'repair_parts',
      where: 'shopId = ? AND (deleted = 0 OR deleted IS NULL) AND quantity > 0',
      whereArgs: [shopId],
    );
    for (final p in parts) {
      results.add({...p, 'name': p['partName'] ?? p['name'] ?? ''});
    }

    return results;
  }

  // --- PARTS HELPERS ---
  Future<List<Map<String, dynamic>>> getAllParts() async {
    final db = await database;
    final shopId = await _getScopedShopId('getAllParts');
    if (shopId == null) return [];

    // Return all repair parts, excluding soft-deleted items
    // Sắp xếp theo thời gian nhập mới nhất lên đầu
    return await db.query(
      'repair_parts',
      where: 'shopId = ? AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId],
      orderBy: 'createdAt DESC',
    );
  }

  Future<int> insertPart(Map<String, dynamic> part) async {
    final db = await database;
    final data = Map<String, dynamic>.from(part);
    data['createdAt'] =
        data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
    data['updatedAt'] = data['updatedAt'] ?? data['createdAt'];
    data['isSynced'] = 0; // Mới tạo, cần sync
    // CRITICAL: Đảm bảo có shopId hợp lệ trước khi ghi
    try {
      data['shopId'] = await _ensureValidShopId(data['shopId']);
    } catch (e) {
      debugPrint('❌ insertPart: $e');
      rethrow;
    }
    return await db.insert('repair_parts', data);
  }

  /// Lấy phụ tùng theo ID
  Future<Map<String, dynamic>?> getPartById(int id) async {
    final db = await database;
    final res = await db.query(
      'repair_parts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Cập nhật phụ tùng
  Future<int> updatePart(int id, Map<String, dynamic> data) async {
    final db = await database;
    data['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    data['isSynced'] = 0; // Có thay đổi, cần sync lại
    return await db.update(
      'repair_parts',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Trừ số lượng phụ tùng trong kho và sync ngay lập tức
  Future<bool> deductPartQuantity(int partId, int quantity) async {
    final db = await database;
    final part = await getPartById(partId);
    if (part == null) return false;

    final currentQty = part['quantity'] as int? ?? 0;
    if (currentQty < quantity) return false; // Không đủ hàng

    final newQty = currentQty - quantity;
    final now = DateTime.now().millisecondsSinceEpoch;
    final firestoreId = part['firestoreId'] as String?;

    await db.update(
      'repair_parts',
      {
        'quantity': newQty,
        'updatedAt': now,
        'isSynced': 0, // Cần sync lại khi có thay đổi
      },
      where: 'id = ?',
      whereArgs: [partId],
    );

    // FIX: Sync ngay lập tức để tránh trường hợp 2 thiết bị dùng cùng 1 part
    if (firestoreId != null && firestoreId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('repair_parts')
            .doc(firestoreId)
            .update({
              'quantity': newQty,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
        // Đánh dấu đã sync
        await db.update(
          'repair_parts',
          {'isSynced': 1},
          where: 'id = ?',
          whereArgs: [partId],
        );
        debugPrint('✅ Synced part quantity: $firestoreId, newQty: $newQty');
      } catch (e) {
        debugPrint('⚠️ Failed to sync part quantity immediately: $e');
        // Vẫn return true vì local đã update, sẽ sync sau
      }
    }

    return true;
  }

  /// Khôi phục số lượng phụ tùng theo tên (khi xóa đơn sửa chữa)
  Future<bool> restorePartQuantityByName(String partName, int quantity) async {
    final db = await database;

    // Tìm phụ tùng theo tên trong bảng repair_parts (không phân biệt chữ hoa/thường)
    final parts = await db.rawQuery(
      'SELECT * FROM repair_parts WHERE UPPER(name) = ? AND (deleted = 0 OR deleted IS NULL) LIMIT 1',
      [partName.toUpperCase()],
    );

    if (parts.isEmpty) {
      debugPrint('⚠️ restorePartQuantityByName: Part not found: $partName');
      return false;
    }

    final part = parts.first;
    final partId = part['id'] as int;
    final currentQty = part['quantity'] as int? ?? 0;
    final newQty = currentQty + quantity;
    final firestoreId = part['firestoreId'] as String?;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'repair_parts',
      {'quantity': newQty, 'updatedAt': now, 'isSynced': 0},
      where: 'id = ?',
      whereArgs: [partId],
    );

    // Sync ngay lập tức
    if (firestoreId != null && firestoreId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('repair_parts')
            .doc(firestoreId)
            .update({
              'quantity': newQty,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
        await db.update(
          'repair_parts',
          {'isSynced': 1},
          where: 'id = ?',
          whereArgs: [partId],
        );
        debugPrint(
          '✅ Restored part quantity: $partName, +$quantity => $newQty',
        );
      } catch (e) {
        debugPrint('⚠️ Failed to sync restored part quantity: $e');
      }
    }

    return true;
  }

  /// Upsert repair part từ cloud
  Future<void> upsertRepairPart(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    if (firestoreId == null) {
      debugPrint(
        'DB WARNING: upsertRepairPart called with null firestoreId, data=$data',
      );
      return;
    }

    try {
      final existing = await db.query(
        'repair_parts',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );

      final Map<String, dynamic> cleanData = Map<String, dynamic>.from(data);
      cleanData.remove('id');
      cleanData.remove(
        '_encrypted',
      ); // Field metadata của Firestore, không lưu SQLite
      // Strip any Firestore fields not in SQLite schema
      await _filterToTableColumns('repair_parts', cleanData);
      cleanData['updatedAt'] =
          cleanData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch;
      cleanData['createdAt'] =
          cleanData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;

      // Convert Firestore boolean → SQLite integer
      if (cleanData['deleted'] is bool) {
        cleanData['deleted'] = cleanData['deleted'] == true ? 1 : 0;
      }
      // Nếu cloud không gửi deleted (record chưa xóa), đặt = 0
      cleanData['deleted'] ??= 0;
      if (cleanData['isSynced'] is bool) {
        cleanData['isSynced'] = cleanData['isSynced'] == true ? 1 : 0;
      }

      // Ensure numeric fields are integers
      if (cleanData['cost'] != null) {
        cleanData['cost'] = (cleanData['cost'] is int)
            ? cleanData['cost']
            : (cleanData['cost'] as num).toInt();
      }
      if (cleanData['price'] != null) {
        cleanData['price'] = (cleanData['price'] is int)
            ? cleanData['price']
            : (cleanData['price'] as num).toInt();
      }
      if (cleanData['quantity'] != null) {
        cleanData['quantity'] = (cleanData['quantity'] is int)
            ? cleanData['quantity']
            : (cleanData['quantity'] as num).toInt();
      }

      if (existing.isEmpty) {
        await db.insert('repair_parts', cleanData);
        debugPrint('DB: Inserted repair_part $firestoreId');
      } else {
        await db.update(
          'repair_parts',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        debugPrint('DB: Updated repair_part $firestoreId');
      }
    } catch (e, stack) {
      debugPrint('DB ERROR: upsertRepairPart failed for $firestoreId: $e');
      debugPrint('DB ERROR stack: $stack');
      debugPrint('DB ERROR data: $data');
      rethrow;
    }
  }

  /// Xóa repair part theo firestoreId
  Future<void> deleteRepairPartByFirestoreId(String firestoreId) async {
    final db = await database;
    await db.delete(
      'repair_parts',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  /// Lấy danh sách repair parts chưa sync
  Future<List<Map<String, dynamic>>> getUnsyncedRepairParts() async {
    final db = await database;
    return await db.query(
      'repair_parts',
      where: 'isSynced = 0 OR isSynced IS NULL',
    );
  }

  /// Đánh dấu repair part đã sync
  Future<void> updateRepairPartSynced(int id, String firestoreId) async {
    final db = await database;
    await db.update(
      'repair_parts',
      {'isSynced': 1, 'firestoreId': firestoreId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- AUDIT LOGS ---
  Future<void> logAction({
    required String userId,
    required String userName,
    required String action,
    required String type,
    String? targetId,
    String? desc,
    String? fId,
    String? shopId,
  }) async {
    // Tự động lấy shopId nếu không được truyền vào
    final String? effectiveShopId =
        shopId ?? await UserService.getCurrentShopId();
    final String firestoreId =
        fId ?? "log_${DateTime.now().millisecondsSinceEpoch}_$userId";
    await _upsert('audit_logs', {
      'userId': userId,
      'userName': userName,
      'action': action,
      'targetType': type,
      'targetId': targetId,
      'description': desc,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'firestoreId': firestoreId,
      'isSynced': 0,
      'shopId': effectiveShopId,
    }, firestoreId);
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({
    int limit = 100,
    int offset = 0,
    String? shopId,
    String? searchQuery,
  }) async {
    final db = await database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();

    final conditions = <String>[];
    final args = <dynamic>[];

    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      conditions.add('(shopId = ? OR shopId IS NULL)');
      args.add(effectiveShopId);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      conditions.add(
        '(action LIKE ? OR userName LIKE ? OR description LIKE ? OR targetType LIKE ? OR targetId LIKE ?)',
      );
      args.addAll([q, q, q, q, q]);
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');
    return await db.query(
      'audit_logs',
      where: whereClause,
      whereArgs: whereClause == null ? null : args,
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Lấy các audit logs chưa sync lên cloud
  Future<List<Map<String, dynamic>>> getUnsyncedAuditLogs() async {
    final db = await database;
    return await db.query(
      'audit_logs',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'createdAt ASC',
    );
  }

  /// Upsert audit log từ cloud
  Future<void> upsertAuditLog(Map<String, dynamic> log) async {
    final firestoreId = log['firestoreId'] as String?;
    if (firestoreId == null || firestoreId.isEmpty) return;
    await _upsert('audit_logs', log, firestoreId);
  }

  /// Insert audit log mới vào local DB
  Future<void> insertAuditLog(Map<String, dynamic> log) async {
    final db = await database;
    await db.insert(
      'audit_logs',
      log,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Đánh dấu audit log đã sync
  Future<void> updateAuditLogSynced(String firestoreId) async {
    final db = await database;
    await db.update(
      'audit_logs',
      {'isSynced': 1},
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  /// Xoá audit log theo firestoreId
  Future<void> deleteAuditLogByFirestoreId(String firestoreId) async {
    final db = await database;
    await db.delete(
      'audit_logs',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // --- PAYROLL SETTINGS ---
  Future<Map<String, dynamic>> getPayrollSettings() async {
    final db = await database;
    await _ensurePayrollSettingsColumns(db, logScope: 'getPayrollSettings');
    final res = await db.query('payroll_settings', limit: 1);
    if (res.isEmpty) {
      return {
        'baseSalary': 0,
        'saleCommPercent': 1.0,
        'saleCommType': 'percent',
        'saleCommTier1Max': 10000000,
        'saleCommTier1Value': 20000,
        'saleCommTier2Max': 50000000,
        'saleCommTier2Value': 50000,
        'saleCommTier3Value': 100000,
        'repairProfitPercent': 10.0,
        'repairCommType': 'percent',
        'transportAllowance': 0,
        'mealAllowance': 0,
        'phoneAllowance': 0,
        'otherAllowance': 0,
        'otherAllowanceNote': '',
        'targetBonus': 0,
        'monthlyTarget': 0,
      };
    }
    return res.first;
  }

  Future<void> savePayrollSettings(Map<String, dynamic> data) async {
    final db = await database;
    await _ensurePayrollSettingsColumns(db, logScope: 'savePayrollSettings');

    final payload = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    await _filterToTableColumns('payroll_settings', payload, executor: db);
    payload['updatedAt'] ??= DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete('payroll_settings');
      await txn.insert('payroll_settings', payload);
    });
  }

  // --- PAYROLL LOCKS ---
  Future<bool> isPayrollMonthLocked(String monthKey) async {
    final db = await database;
    final res = await db.query(
      'payroll_locks',
      where: 'monthKey = ?',
      whereArgs: [monthKey],
      limit: 1,
    );
    if (res.isEmpty) return false;
    return (res.first['locked'] ?? 0) == 1;
  }

  Future<void> setPayrollMonthLock(
    String monthKey, {
    required bool locked,
    String? lockedBy,
    String? note,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = {
      'monthKey': monthKey,
      'locked': locked ? 1 : 0,
      'lockedBy': lockedBy,
      'lockedAt': now,
      'note': note,
    };
    await db.insert(
      'payroll_locks',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPayrollLocks({int limit = 100}) async {
    final db = await database;
    return await db.query(
      'payroll_locks',
      orderBy: 'lockedAt DESC',
      limit: limit,
    );
  }

  // --- EMPLOYEE SALARY SETTINGS ---
  /// Lấy tất cả cài đặt lương nhân viên (cho shop hiện tại)
  Future<List<Map<String, dynamic>>> getEmployeeSalarySettings() async {
    final db = await database;
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    return await db.query(
      'employee_salary_settings',
      where: 'shopId = ? AND isActive = 1',
      whereArgs: [shopId],
      orderBy: 'staffName ASC',
    );
  }

  /// Lấy cài đặt lương của một nhân viên theo staffId
  Future<Map<String, dynamic>?> getEmployeeSalarySettingByStaffId(
    String staffId,
  ) async {
    final db = await database;
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return null;

    final results = await db.query(
      'employee_salary_settings',
      where: 'shopId = ? AND staffId = ? AND isActive = 1',
      whereArgs: [shopId, staffId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return results.first;
  }

  /// Lưu hoặc cập nhật cài đặt lương nhân viên
  Future<int> saveEmployeeSalarySettings(Map<String, dynamic> data) async {
    final db = await database;
    final staffId = data['staffId'] as String?;
    if (staffId == null || staffId.isEmpty) {
      debugPrint('❌ staffId is required for employee salary settings');
      return -1;
    }

    // Tạo bản copy và loại bỏ 'id' vì là AUTO INCREMENT
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');

    // Đảm bảo có shopId
    final shopId = cleanData['shopId'] ?? await UserService.getCurrentShopId();
    cleanData['shopId'] = shopId;
    cleanData['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    cleanData['isSynced'] = 0;

    // Đảm bảo createdAt là INTEGER
    if (cleanData['createdAt'] is DateTime) {
      cleanData['createdAt'] =
          (cleanData['createdAt'] as DateTime).millisecondsSinceEpoch;
    } else if (cleanData['createdAt'] is String) {
      final parsed = DateTime.tryParse(cleanData['createdAt'] as String);
      cleanData['createdAt'] =
          parsed?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    }

    // Check existing
    final existing = await db.query(
      'employee_salary_settings',
      where: 'shopId = ? AND staffId = ?',
      whereArgs: [shopId, staffId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update - loại bỏ createdAt để giữ nguyên giá trị cũ
      cleanData.remove('createdAt');
      await db.update(
        'employee_salary_settings',
        cleanData,
        where: 'shopId = ? AND staffId = ?',
        whereArgs: [shopId, staffId],
      );
      return existing.first['id'] as int;
    } else {
      // Insert
      cleanData['createdAt'] =
          cleanData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;
      cleanData['isActive'] = 1;
      return await db.insert('employee_salary_settings', cleanData);
    }
  }

  /// Upsert từ Firestore
  Future<void> upsertEmployeeSalarySettings(Map<String, dynamic> data) async {
    final firestoreId = data['firestoreId'] as String?;
    final staffId = data['staffId'] as String?;
    if (firestoreId == null && staffId == null) return;

    final db = await database;

    // Chuyển đổi các giá trị về đúng kiểu
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    // Handle Timestamp/DateTime → milliseconds (not covered by _sanitizeForSqlite)
    for (final key in cleanData.keys.toList()) {
      final v = data[key];
      if (v is Timestamp) cleanData[key] = v.millisecondsSinceEpoch;
      if (v is DateTime) cleanData[key] = v.millisecondsSinceEpoch;
    }
    cleanData['isSynced'] = 1;
    await _filterToTableColumns('employee_salary_settings', cleanData);

    // Try update by firestoreId first
    if (firestoreId != null) {
      final existing = await db.query(
        'employee_salary_settings',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'employee_salary_settings',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }

    // Try update by staffId + shopId
    if (staffId != null && cleanData['shopId'] != null) {
      final existing = await db.query(
        'employee_salary_settings',
        where: 'staffId = ? AND shopId = ?',
        whereArgs: [staffId, cleanData['shopId']],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'employee_salary_settings',
          cleanData,
          where: 'staffId = ? AND shopId = ?',
          whereArgs: [staffId, cleanData['shopId']],
        );
        return;
      }
    }

    // Insert new
    await db.insert(
      'employee_salary_settings',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lấy các cài đặt chưa sync để đẩy lên cloud
  Future<List<Map<String, dynamic>>> getUnsyncedEmployeeSalarySettings() async {
    final db = await database;
    return await db.query('employee_salary_settings', where: 'isSynced = 0');
  }

  /// Đánh dấu đã sync
  Future<void> markEmployeeSalarySettingsSynced(String firestoreId) async {
    final db = await database;
    await db.update(
      'employee_salary_settings',
      {'isSynced': 1, 'firestoreId': firestoreId},
      where: 'firestoreId = ? OR (firestoreId IS NULL AND staffId = ?)',
      whereArgs: [firestoreId, firestoreId.split('_').skip(1).take(1).join()],
    );
  }

  /// Xóa cài đặt lương (soft delete)
  Future<void> deleteEmployeeSalarySettings(String staffId) async {
    final db = await database;
    final shopId = await UserService.getCurrentShopId();
    await db.update(
      'employee_salary_settings',
      {
        'isActive': 0,
        'isSynced': 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'staffId = ? AND shopId = ?',
      whereArgs: [staffId, shopId],
    );
  }

  /// Xóa cài đặt lương by firestoreId (for sync)
  Future<void> deleteEmployeeSalarySettingsByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    await db.delete(
      'employee_salary_settings',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // --- SYSTEM ---
  Future<void> updateOrderStatusFromDebt(
    String linkedId,
    int newPaidAmount,
  ) async {
    final db = await database;
    if (linkedId.startsWith('sale_')) {
      await db.rawUpdate(
        'UPDATE sales SET downPayment = ?, paymentMethod = CASE WHEN ? >= totalPrice THEN "ĐÃ THANH TOÁN" ELSE paymentMethod END WHERE firestoreId = ?',
        [newPaidAmount, newPaidAmount, linkedId],
      );
    } else if (linkedId.startsWith('rep_')) {
      await db.rawUpdate(
        'UPDATE repairs SET paymentMethod = "ĐÃ THANH TOÁN" WHERE firestoreId = ?',
        [linkedId],
      );
    }
  }

  Future<void> cleanDuplicateData() async {
    final db = await database;
    await db.execute(
      'DELETE FROM repairs WHERE id NOT IN (SELECT MIN(id) FROM repairs GROUP BY firestoreId)',
    );
    await db.execute(
      'DELETE FROM products WHERE id NOT IN (SELECT MIN(id) FROM products GROUP BY firestoreId)',
    );
    await db.execute(
      'DELETE FROM sales WHERE id NOT IN (SELECT MIN(id) FROM sales GROUP BY firestoreId)',
    );
  }

  /// Remove duplicated local shadow rows created by old sync flows.
  ///
  /// Pattern cleaned:
  /// - row A: firestoreId is NULL/empty (local shadow)
  /// - row B: same business payload but has firestoreId (cloud canonical)
  ///
  /// This keeps unsynced local-only rows intact because deletion only happens
  /// when a canonical cloud row already exists.
  Future<int> cleanupCloudShadowDuplicates() async {
    final db = await database;
    int totalDeleted = 0;

    // Repairs: match by stable identity fields.
    totalDeleted += await db.rawDelete('''
      DELETE FROM repairs
      WHERE (firestoreId IS NULL OR TRIM(firestoreId) = '')
        AND EXISTS (
          SELECT 1 FROM repairs r2
          WHERE r2.id != repairs.id
            AND r2.firestoreId IS NOT NULL
            AND TRIM(r2.firestoreId) != ''
            AND IFNULL(r2.createdAt, -1) = IFNULL(repairs.createdAt, -1)
            AND IFNULL(r2.phone, '') = IFNULL(repairs.phone, '')
            AND IFNULL(r2.model, '') = IFNULL(repairs.model, '')
            AND IFNULL(r2.customerName, '') = IFNULL(repairs.customerName, '')
        )
    ''');

    // Sales: match by sold time + customer + product identifiers.
    totalDeleted += await db.rawDelete('''
      DELETE FROM sales
      WHERE (firestoreId IS NULL OR TRIM(firestoreId) = '')
        AND EXISTS (
          SELECT 1 FROM sales s2
          WHERE s2.id != sales.id
            AND s2.firestoreId IS NOT NULL
            AND TRIM(s2.firestoreId) != ''
            AND IFNULL(s2.soldAt, -1) = IFNULL(sales.soldAt, -1)
            AND IFNULL(s2.phone, '') = IFNULL(sales.phone, '')
            AND IFNULL(s2.productImeis, '') = IFNULL(sales.productImeis, '')
            AND IFNULL(s2.totalPrice, -1) = IFNULL(sales.totalPrice, -1)
        )
    ''');

    // Products: prioritize IMEI match for strong identity.
    totalDeleted += await db.rawDelete('''
      DELETE FROM products
      WHERE (firestoreId IS NULL OR TRIM(firestoreId) = '')
        AND IFNULL(TRIM(imei), '') != ''
        AND EXISTS (
          SELECT 1 FROM products p2
          WHERE p2.id != products.id
            AND p2.firestoreId IS NOT NULL
            AND TRIM(p2.firestoreId) != ''
            AND IFNULL(p2.imei, '') = IFNULL(products.imei, '')
        )
    ''');

    if (totalDeleted > 0) {
      debugPrint(
        'DB cleanup: removed $totalDeleted cloud-shadow duplicate rows',
      );
    }
    return totalDeleted;
  }

  /// Count all unsynced records across critical tables
  /// Returns a map of tableName -> count of unsynced records
  Future<Map<String, int>> countAllUnsyncedData() async {
    final db = await database;
    final tables = [
      'sales',
      'products',
      'repairs',
      'expenses',
      'debts',
      'customers',
      'purchase_orders',
      'debt_payments',
      'attendance',
    ];
    final result = <String, int>{};
    for (final t in tables) {
      try {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) as c FROM $t WHERE isSynced = 0 OR isSynced IS NULL',
        );
        final count = Sqflite.firstIntValue(rows) ?? 0;
        if (count > 0) result[t] = count;
      } catch (_) {}
    }
    return result;
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      final existingTablesRows = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final existingTables = existingTablesRows
          .map((row) => row['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();

      // All tables in the database - MUST be kept in sync with onCreate
      final tables = [
        'repairs',
        'products',
        'sales',
        'suppliers',
        'expenses',
        'debts',
        'customers',
        'attendance',
        'audit_logs',
        'inventory_checks',
        'cash_closings',
        'payroll_settings',
        'purchase_orders',
        'work_schedules',
        'debt_payments',
        'quick_input_codes',
        'supplier_import_history',
        'supplier_product_prices',
        // Missing tables - added to fix incomplete data clear
        'repair_parts',
        'supplier_payments',
        'repair_partner_payments',
        'payroll_locks',
        'repair_partners',
        'partner_repair_history',
        'sync_queue',
        'adjustment_entries',
        'sales_returns',
        'payment_intents',
        'payment_requests',
      ];
      for (var t in tables) {
        if (!existingTables.contains(t)) {
          continue;
        }
        await txn.delete(t);
      }
    });
  }

  /// Xóa dữ liệu local theo shopId cụ thể
  /// Dùng khi xóa shop mà không muốn ảnh hưởng data shop khác
  Future<void> deleteDataByShopId(String shopId) async {
    final db = await database;

    // Chỉ các bảng CÓ cột shopId trong schema (đã kiểm tra CREATE TABLE)
    // repairs, sales, purchase_orders, cash_closings KHÔNG có cột shopId
    final tablesWithShopId = [
      'products',
      'customers',
      'suppliers',
      'expenses',
      'debts',
      'attendance',
      'audit_logs',
      'work_schedules',
      'debt_payments',
      'quick_input_codes',
      'repair_parts',
      'supplier_payments',
      'repair_partner_payments',
      'repair_partners',
      'partner_repair_history',
      'supplier_product_prices',
      'supplier_import_history',
    ];

    await db.transaction((txn) async {
      for (var table in tablesWithShopId) {
        try {
          final count = await txn.delete(
            table,
            where: 'shopId = ?',
            whereArgs: [shopId],
          );
          if (count > 0) {
            debugPrint('deleteDataByShopId: Deleted $count rows from $table');
          }
        } catch (e) {
          // Table may not have shopId column or not exist
          debugPrint('deleteDataByShopId: $table error: $e');
        }
      }
    });

    debugPrint('deleteDataByShopId: Completed for shop $shopId');
  }

  /// Dọn dữ liệu của shop khác khỏi local DB để tránh lẫn tenant.
  /// Giữ lại các hàng có shopId NULL để không làm mất dữ liệu legacy chưa gán shop.
  Future<void> purgeDataOutsideShop(String currentShopId) async {
    if (currentShopId.isEmpty) return;

    final db = await database;
    final tablesWithShopId = [
      'products',
      'customers',
      'suppliers',
      'expenses',
      'debts',
      'attendance',
      'audit_logs',
      'work_schedules',
      'debt_payments',
      'quick_input_codes',
      'repair_parts',
      'supplier_payments',
      'repair_partner_payments',
      'repair_partners',
      'partner_repair_history',
      'supplier_product_prices',
      'supplier_import_history',
      'payment_intents',
      'payment_requests',
    ];

    await db.transaction((txn) async {
      for (final table in tablesWithShopId) {
        try {
          final deleted = await txn.delete(
            table,
            where: 'shopId IS NOT NULL AND shopId != ?',
            whereArgs: [currentShopId],
          );
          if (deleted > 0) {
            debugPrint(
              'purgeDataOutsideShop: deleted $deleted rows from $table (not in $currentShopId)',
            );
          }
        } catch (e) {
          debugPrint('purgeDataOutsideShop: $table error: $e');
        }
      }
    });
  }

  // --- LỊCH SỬ TRẢ NỢ ---
  Future<void> upsertDebtPayment(Map<String, dynamic> p) async {
    final firestoreId = p['firestoreId'] ?? "debt_payment_${p['paidAt']}";
    await _upsert('debt_payments', p, firestoreId);
  }

  Future<int> insertDebtPayment(Map<String, dynamic> p) async {
    final db = await database;
    return await db.insert('debt_payments', p);
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(int debtId) async {
    final db = await database;
    return await db.query(
      'debt_payments',
      where: 'debtId = ?',
      whereArgs: [debtId],
      orderBy: 'paidAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAllDebtPaymentsWithDetails() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return await db.rawQuery(
        '''
        SELECT p.*,
          COALESCE(NULLIF(p.debtType, ''), d.type, '') as debtType,
          COALESCE(d.personName, p.customerName, '') as personName
        FROM debt_payments p
        LEFT JOIN debts d
          ON (p.debtId IS NOT NULL AND p.debtId = d.id)
          OR (p.debtFirestoreId IS NOT NULL AND p.debtFirestoreId != '' AND p.debtFirestoreId = d.firestoreId)
        WHERE p.shopId = ? OR p.shopId IS NULL
        ORDER BY p.paidAt DESC
      ''',
        [shopId],
      );
    }
    return await db.rawQuery('''
      SELECT p.*,
        COALESCE(NULLIF(p.debtType, ''), d.type, '') as debtType,
        COALESCE(d.personName, p.customerName, '') as personName
      FROM debt_payments p
      LEFT JOIN debts d
        ON (p.debtId IS NOT NULL AND p.debtId = d.id)
        OR (p.debtFirestoreId IS NOT NULL AND p.debtFirestoreId != '' AND p.debtFirestoreId = d.firestoreId)
      ORDER BY p.paidAt DESC
    ''');
  }

  /// Get debt payments within a date range with debt info, for financial report optimization
  /// Replaces the N+1 pattern: getAllDebts() → for each debt getDebtPayments()
  Future<List<Map<String, dynamic>>> getDebtPaymentsWithDebtInfoByDateRange(
    int startMs,
    int endMs,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return await db.rawQuery(
        '''
        SELECT p.*, d.type as debtType, d.personName as debtPersonName
        FROM debt_payments p
        INNER JOIN debts d ON p.debtId = d.id
        WHERE p.paidAt >= ? AND p.paidAt <= ?
          AND (p.shopId = ? OR p.shopId IS NULL)
        ORDER BY p.paidAt DESC
      ''',
        [startMs, endMs, shopId],
      );
    }
    return await db.rawQuery(
      '''
      SELECT p.*, d.type as debtType, d.personName as debtPersonName
      FROM debt_payments p
      INNER JOIN debts d ON p.debtId = d.id
      WHERE p.paidAt >= ? AND p.paidAt <= ?
      ORDER BY p.paidAt DESC
    ''',
      [startMs, endMs],
    );
  }

  /// Debt payments for cash-flow dashboards.
  /// Resolves debt type from the payment row first, then falls back to the linked debt.
  Future<List<Map<String, dynamic>>> getDebtPaymentsForCashFlowByDateRange(
    int startMs,
    int endMs,
  ) async {
    final shopId = UserService.getShopIdSync();
    final db = await database;

    final selectSql = '''
      SELECT
        p.id,
        p.firestoreId,
        p.amount,
        p.paidAt,
        p.paymentMethod,
        p.shopId,
        p.debtId,
        p.debtFirestoreId,
        p.debtType,
        COALESCE(NULLIF(p.debtType, ''), d.type, '') as resolvedDebtType,
        COALESCE(d.personName, '') as debtPersonName
      FROM debt_payments p
      LEFT JOIN debts d
        ON (p.debtId IS NOT NULL AND p.debtId = d.id)
        OR (
          (p.debtId IS NULL OR p.debtId = 0)
          AND p.debtFirestoreId IS NOT NULL
          AND p.debtFirestoreId != ''
          AND p.debtFirestoreId = d.firestoreId
        )
      WHERE p.paidAt >= ? AND p.paidAt < ?
        AND COALESCE(p.deleted, 0) != 1
    ''';

    if (shopId != null && shopId.isNotEmpty) {
      return await db.rawQuery(
        '''
        $selectSql
          AND (
            p.shopId = ?
            OR (
              p.shopId IS NULL
              AND d.shopId = ?
            )
          )
        ORDER BY p.paidAt DESC
        ''',
        [startMs, endMs, shopId, shopId],
      );
    }

    return await db.rawQuery(
      '''
      $selectSql
      ORDER BY p.paidAt DESC
      ''',
      [startMs, endMs],
    );
  }

  /// Lấy tất cả debt payments để sync
  Future<List<Map<String, dynamic>>> getAllDebtPaymentsForSync() async {
    final db = await database;
    return await db.query('debt_payments', orderBy: 'paidAt DESC');
  }

  /// Cập nhật trạng thái synced cho debt payment
  Future<void> updateDebtPaymentSynced(int id, String firestoreId) async {
    final db = await database;
    await db.update(
      'debt_payments',
      {'firestoreId': firestoreId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Xóa debt payment theo firestoreId (dùng cho soft-delete sync)
  Future<int> deleteDebtPaymentByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'debt_payments',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // Quick Input Codes methods
  Future<List<QuickInputCode>> getQuickInputCodes() async {
    final db = await database;

    // Ensure table exists (defensive check)
    try {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS quick_input_codes(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
      );
    } catch (e) {
      debugPrint('DB: ensure quick_input_codes table error: $e');
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'quick_input_codes',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => QuickInputCode.fromMap(maps[i]));
  }

  Future<int> insertQuickInputCode(QuickInputCode code) async {
    final db = await database;
    // Generate firestoreId if not present to prevent duplicates on sync
    if (code.firestoreId == null || code.firestoreId!.isEmpty) {
      code.firestoreId =
          "qic_${code.createdAt}_${code.name.replaceAll(' ', '_')}";
    }
    // Use upsert to prevent duplicates with same firestoreId
    final existing = await db.query(
      'quick_input_codes',
      where: 'firestoreId = ?',
      whereArgs: [code.firestoreId],
      limit: 1,
    );
    final data = code.toMap();
    data.remove('id');
    if (existing.isNotEmpty) {
      return await db.update(
        'quick_input_codes',
        data,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    return await db.insert('quick_input_codes', data);
  }

  Future<int> updateQuickInputCode(QuickInputCode code) async {
    final db = await database;
    return await db.update(
      'quick_input_codes',
      code.toMap(),
      where: 'id = ?',
      whereArgs: [code.id],
    );
  }

  Future<int> deleteQuickInputCode(int id) async {
    final db = await database;
    return await db.delete(
      'quick_input_codes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleQuickInputCodeActive(int id, bool isActive) async {
    final db = await database;
    return await db.update(
      'quick_input_codes',
      {'isActive': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteQuickInputCodeByFirestoreId(String fId) async =>
      (await database).delete(
        'quick_input_codes',
        where: 'firestoreId = ?',
        whereArgs: [fId],
      );

  Future<void> upsertQuickInputCode(QuickInputCode code) async => _upsert(
    'quick_input_codes',
    code.toMap(),
    code.firestoreId ?? "qic_${code.createdAt}_${code.name}",
  );

  Future<List<QuickInputCode>> getUnsyncedQuickInputCodes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'quick_input_codes',
      where: 'isSynced = 0',
    );
    return List.generate(maps.length, (i) => QuickInputCode.fromMap(maps[i]));
  }

  Future<int> getUnsyncedQuickInputCodesCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM quick_input_codes WHERE isSynced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Supplier Product Prices methods
  Future<void> insertSupplierProductPrice(Map<String, dynamic> price) async {
    final firestoreId =
        price['firestoreId'] ??
        "price_${DateTime.now().millisecondsSinceEpoch}_${price['supplierId'] ?? 'unknown'}_${price['productName']?.replaceAll(' ', '_') ?? 'unknown'}";
    price['firestoreId'] = firestoreId;
    await _upsert('supplier_product_prices', price, firestoreId);
  }

  /// FIX BUG-001: Upsert supplier_product_prices cho real-time sync
  Future<void> upsertSupplierProductPrice(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    // Loại bỏ id vì SQLite auto-generate
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('supplier_product_prices', cleanData);

    if (firestoreId == null) {
      await db.insert(
        'supplier_product_prices',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }
    final existing = await db.query(
      'supplier_product_prices',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
    if (existing.isEmpty) {
      await db.insert(
        'supplier_product_prices',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        'supplier_product_prices',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    }
  }

  /// FIX BUG-001: Delete supplier_product_prices bằng firestoreId (cho soft delete sync)
  Future<int> deleteSupplierProductPriceByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    return await db.delete(
      'supplier_product_prices',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<int> updateSupplierProductPrice(
    int id,
    Map<String, dynamic> price,
  ) async {
    final db = await database;
    return await db.update(
      'supplier_product_prices',
      price,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getSupplierProductPrices(
    int supplierId,
  ) async {
    final db = await database;
    return await db.query(
      'supplier_product_prices',
      where: 'supplierId = ? AND isActive = 1',
      whereArgs: [supplierId],
      orderBy: 'lastUpdated DESC',
    );
  }

  Future<Map<String, dynamic>?> getSupplierProductPrice(
    int supplierId,
    String productName,
    String productBrand,
    String? productModel,
  ) async {
    final db = await database;
    final results = await db.query(
      'supplier_product_prices',
      where:
          'supplierId = ? AND productName = ? AND productBrand = ? AND (productModel = ? OR productModel IS NULL) AND isActive = 1',
      whereArgs: [supplierId, productName, productBrand, productModel],
      orderBy: 'lastUpdated DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> deactivateSupplierProductPrice(
    int supplierId,
    String productName,
    String productBrand,
    String? productModel,
  ) async {
    final db = await database;
    return await db.update(
      'supplier_product_prices',
      {'isActive': 0},
      where:
          'supplierId = ? AND productName = ? AND productBrand = ? AND (productModel = ? OR productModel IS NULL)',
      whereArgs: [supplierId, productName, productBrand, productModel],
    );
  }

  // Supplier Import History methods
  Future<int> insertSupplierImportHistory(Map<String, dynamic> history) async {
    final db = await database;
    final ts = history['importDate'] ?? DateTime.now().millisecondsSinceEpoch;
    final supplierId = history['supplierId'] ?? 'unknown';
    final imei = (history['imei'] ?? 'no_imei').toString();
    final productName = (history['productName'] ?? 'no_product').toString();
    final productHash = productName.hashCode;
    final firestoreId =
        history['firestoreId'] ??
        "import_${ts}_${supplierId}_${productHash}_$imei";
    history['firestoreId'] = firestoreId;
    return await db.insert(
      'supplier_import_history',
      history,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lấy tất cả lịch sử nhập hàng để hiển thị trong chốt quỹ
  Future<List<Map<String, dynamic>>> getAllSupplierImportHistory() async {
    final db = await database;
    return await db.query(
      'supplier_import_history',
      orderBy: 'importDate DESC',
    );
  }

  /// Get ALL supplier import history within a date range (for revenue view)
  Future<List<Map<String, dynamic>>> getAllSupplierImportHistoryByDateRange(
    int startMs,
    int endMs,
  ) async {
    final db = await database;
    return await db.query(
      'supplier_import_history',
      where: 'importDate >= ? AND importDate <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'importDate DESC',
    );
  }

  /// Lấy tất cả thanh toán NCC để hiển thị trong chốt quỹ
  Future<List<Map<String, dynamic>>> getAllSupplierPayments() async {
    final shopId = UserService.getShopIdSync();
    final db = await database;
    if (shopId != null && shopId.isNotEmpty) {
      return await db.query(
        'supplier_payments',
        where:
            '(deleted = 0 OR deleted IS NULL) AND (shopId = ? OR shopId IS NULL)',
        whereArgs: [shopId],
        orderBy: 'paidAt DESC',
      );
    }
    return await db.query(
      'supplier_payments',
      where: 'deleted = 0 OR deleted IS NULL',
      orderBy: 'paidAt DESC',
    );
  }

  /// Get supplier payments within a date range (by paidAt)
  Future<List<Map<String, dynamic>>> getSupplierPaymentsByDateRange(
    int startMs,
    int endMs,
  ) async {
    final db = await database;
    final shopId = UserService.getShopIdSync();
    if (shopId != null && shopId.isNotEmpty) {
      return await db.query(
        'supplier_payments',
        where:
            '(deleted = 0 OR deleted IS NULL) AND (shopId = ? OR shopId IS NULL) AND paidAt >= ? AND paidAt <= ?',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'paidAt DESC',
      );
    }
    return await db.query(
      'supplier_payments',
      where: '(deleted = 0 OR deleted IS NULL) AND paidAt >= ? AND paidAt <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'paidAt DESC',
    );
  }

  /// Lấy tất cả supplier_payments (kể cả deleted) cho sync
  Future<List<Map<String, dynamic>>> getSupplierPaymentsForSync() async {
    final db = await database;
    return await db.query('supplier_payments');
  }

  Future<List<Map<String, dynamic>>> getSupplierImportHistory(
    int supplierId, {
    int? limit,
    int? offset,
    String? supplierName,
  }) async {
    final db = await database;

    // Query theo cả supplierId và supplierName (fallback nếu supplierId = 0 hoặc không tìm thấy)
    String whereClause;
    List<dynamic> whereArgs;

    if (supplierName != null && supplierName.isNotEmpty) {
      // Tìm theo supplierId HOẶC supplierName (case-insensitive)
      // GROUP BY id để loại bỏ duplicate hoàn toàn
      whereClause = '(supplierId = ? OR UPPER(supplierName) = UPPER(?))';
      whereArgs = [supplierId, supplierName];
    } else {
      whereClause = 'supplierId = ?';
      whereArgs = [supplierId];
    }

    // Cleanup duplicates for this supplier to avoid future double-counting
    await db.rawDelete(
      '''
      DELETE FROM supplier_import_history
      WHERE id NOT IN (
        SELECT MIN(id) FROM supplier_import_history
        WHERE $whereClause
        GROUP BY
          COALESCE(referenceId, ''),
          productName,
          IFNULL(imei, ''),
          importDate,
          totalAmount,
          quantity,
          costPrice,
          supplierName
      )
      AND $whereClause
      ''',
      [...whereArgs, ...whereArgs],
    );

    // Dùng subquery với GROUP BY khóa tự nhiên để loại duplicate thực sự
    // Ưu tiên referenceId khi có (nhập kho chuẩn), fallback theo fingerprint dữ liệu
    String query =
        '''
      SELECT * FROM supplier_import_history
      WHERE id IN (
        SELECT MIN(id) FROM supplier_import_history
        WHERE $whereClause
        GROUP BY
          COALESCE(referenceId, ''),
          productName,
          IFNULL(imei, ''),
          importDate,
          totalAmount,
          quantity,
          costPrice,
          supplierName
      )
      ORDER BY importDate DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }

    return await db.rawQuery(query, whereArgs);
  }

  Future<List<Map<String, dynamic>>> getSupplierImportHistoryByDateRange(
    int supplierId,
    int startDate,
    int endDate,
  ) async {
    final db = await database;
    return await db.query(
      'supplier_import_history',
      where: 'supplierId = ? AND importDate >= ? AND importDate <= ?',
      whereArgs: [supplierId, startDate, endDate],
      orderBy: 'importDate DESC',
    );
  }

  /// Lấy TẤT CẢ import history theo khoảng ngày (không filter supplierId)
  Future<List<Map<String, dynamic>>> getAllImportHistoryByDateRange(
    int startMs,
    int endMs,
  ) async {
    final db = await database;
    final shopId = UserService.getShopIdSync();
    if (shopId != null && shopId.isNotEmpty) {
      return await db.query(
        'supplier_import_history',
        where:
            '(shopId = ? OR shopId IS NULL) AND importDate >= ? AND importDate <= ?',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'importDate DESC',
      );
    }
    return await db.query(
      'supplier_import_history',
      where: 'importDate >= ? AND importDate <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'importDate DESC',
    );
  }

  /// Lấy repair_partner_payments theo khoảng ngày
  Future<List<Map<String, dynamic>>> getRepairPartnerPaymentsByDateRange(
    int startMs,
    int endMs,
  ) async {
    final db = await database;
    final shopId = UserService.getShopIdSync();
    if (shopId != null && shopId.isNotEmpty) {
      return await db.query(
        'repair_partner_payments',
        where:
            '(deleted = 0 OR deleted IS NULL) AND (shopId = ? OR shopId IS NULL) AND paidAt >= ? AND paidAt <= ?',
        whereArgs: [shopId, startMs, endMs],
        orderBy: 'paidAt DESC',
      );
    }
    return await db.query(
      'repair_partner_payments',
      where: '(deleted = 0 OR deleted IS NULL) AND paidAt >= ? AND paidAt <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'paidAt DESC',
    );
  }

  Future<Map<String, dynamic>?> getSupplierImportStats(
    int supplierId, {
    String? shopId,
  }) async {
    final db = await database;
    String whereClause = 'supplierId = ?';
    List<dynamic> whereArgs = [supplierId];

    if (shopId != null) {
      whereClause += ' AND shopId = ?';
      whereArgs.add(shopId);
    }

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as totalImports,
        SUM(totalAmount) as totalAmount,
        SUM(quantity) as totalQuantity,
        AVG(costPrice) as avgPrice,
        MIN(costPrice) as minPrice,
        MAX(costPrice) as maxPrice,
        MAX(importDate) as lastImportDate,
        MIN(importDate) as firstImportDate,
        COUNT(DISTINCT productName) as uniqueProducts
      FROM (
        SELECT
          MIN(id) as id,
          totalAmount,
          quantity,
          costPrice,
          importDate,
          productName
        FROM supplier_import_history
        WHERE $whereClause
        GROUP BY
          COALESCE(referenceId, ''),
          productName,
          IFNULL(imei, ''),
          importDate,
          totalAmount,
          quantity,
          costPrice,
          supplierName
      ) t
    ''', whereArgs);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSupplierImportHistory() async {
    final db = await database;
    return await db.query('supplier_import_history', where: 'isSynced = 0');
  }

  /// FIX BUG-001: Upsert supplier_import_history cho real-time sync
  Future<void> upsertSupplierImportHistory(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    // Loại bỏ id vì SQLite auto-generate
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('supplier_import_history', cleanData);

    if (firestoreId == null) {
      await db.insert(
        'supplier_import_history',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    // 1) Update by firestoreId if exists
    final existing = await db.query(
      'supplier_import_history',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      // Preserve local supplierId if Firestore supplierId is string
      final existingSupplierId = existing.first['supplierId'];
      final newSupplierId = cleanData['supplierId'];
      if (existingSupplierId is int && newSupplierId is String) {
        cleanData['supplierId'] = existingSupplierId;
      }

      await db.update(
        'supplier_import_history',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      return;
    }

    // 2) De-dup by natural keys (referenceId if available, else import fingerprint)
    final referenceId = cleanData['referenceId'];
    final productName = cleanData['productName'];
    final imei = cleanData['imei'] ?? '';
    final importDate = cleanData['importDate'];
    final totalAmount = cleanData['totalAmount'];
    final quantity = cleanData['quantity'];
    final costPrice = cleanData['costPrice'];
    final supplierName = cleanData['supplierName'];

    String whereClause;
    List<dynamic> whereArgs;

    if (referenceId != null && referenceId.toString().isNotEmpty) {
      whereClause =
          "referenceId = ? AND productName = ? AND IFNULL(imei, '') = ? AND importDate = ?";
      whereArgs = [referenceId, productName, imei, importDate];
    } else {
      whereClause =
          "productName = ? AND IFNULL(imei, '') = ? AND importDate = ? AND totalAmount = ? AND quantity = ? AND costPrice = ? AND supplierName = ?";
      whereArgs = [
        productName,
        imei,
        importDate,
        totalAmount,
        quantity,
        costPrice,
        supplierName,
      ];
    }

    final dup = await db.query(
      'supplier_import_history',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    if (dup.isNotEmpty) {
      // Merge duplicate: update existing row with firestoreId and latest data
      final existingId = dup.first['id'] as int?;
      final existingSupplierId = dup.first['supplierId'];
      final newSupplierId = cleanData['supplierId'];
      if (existingSupplierId is int && newSupplierId is String) {
        cleanData['supplierId'] = existingSupplierId;
      }

      if (existingId != null) {
        await db.update(
          'supplier_import_history',
          cleanData,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return;
      }
    }

    // 3) Insert new
    await db.insert(
      'supplier_import_history',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// FIX BUG-001: Delete supplier_import_history bằng firestoreId (cho soft delete sync)
  Future<int> deleteSupplierImportHistoryByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    return await db.delete(
      'supplier_import_history',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<int> markSupplierImportHistorySynced(String firestoreId) async {
    final db = await database;
    return await db.update(
      'supplier_import_history',
      {'isSynced': 1},
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<void> updateSupplierStats(
    int supplierId,
    int addAmount,
    int addCount,
  ) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE suppliers SET importCount = importCount + ?, totalAmount = totalAmount + ? WHERE id = ?',
      [addCount, addAmount, supplierId],
    );
  }

  // ==================== Import Order methods ====================

  Future<String> generateNextImportOrderCode() async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM import_orders',
    );
    int count = Sqflite.firstIntValue(res) ?? 0;
    return "NK-${(count + 1).toString().padLeft(4, '0')}";
  }

  Future<int> insertImportOrder(Map<String, dynamic> data) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('import_orders', cleanData);
    return await db.insert(
      'import_orders',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> insertImportOrderItem(Map<String, dynamic> data) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('import_order_items', cleanData);
    return await db.insert(
      'import_order_items',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getImportOrders({
    String? shopId,
    int? startDate,
    int? endDate,
    String? status,
  }) async {
    final db = await database;
    String where = 'deleted = 0';
    List<dynamic> whereArgs = [];

    if (shopId != null) {
      where += ' AND shopId = ?';
      whereArgs.add(shopId);
    }
    if (startDate != null) {
      where += ' AND importDate >= ?';
      whereArgs.add(startDate);
    }
    if (endDate != null) {
      where += ' AND importDate <= ?';
      whereArgs.add(endDate);
    }
    if (status != null) {
      where += ' AND status = ?';
      whereArgs.add(status);
    }

    return await db.query(
      'import_orders',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'importDate DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getImportOrderItems(
    String importOrderFirestoreId,
  ) async {
    final db = await database;
    return await db.query(
      'import_order_items',
      where: 'importOrderFirestoreId = ? AND deleted = 0',
      whereArgs: [importOrderFirestoreId],
    );
  }

  Future<Map<String, dynamic>?> getImportOrderByStockEntryId(
    String stockEntryId,
  ) async {
    final db = await database;
    final results = await db.query(
      'import_orders',
      where: 'stockEntryId = ? AND deleted = 0',
      whereArgs: [stockEntryId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> upsertImportOrder(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'] as String?;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('import_orders', cleanData);

    if (firestoreId == null) {
      await db.insert(
        'import_orders',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final existing = await db.query(
      'import_orders',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'import_orders',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert(
        'import_orders',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> upsertImportOrderItem(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'] as String?;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    await _filterToTableColumns('import_order_items', cleanData);

    if (firestoreId == null) {
      await db.insert(
        'import_order_items',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final existing = await db.query(
      'import_order_items',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'import_order_items',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert(
        'import_order_items',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> deleteImportOrderByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'import_orders',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<int> deleteImportOrderItemByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'import_order_items',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // Repair Partner methods
  Future<List<Map<String, dynamic>>> getRepairPartners() async {
    final db = await database;
    return await db.query(
      'repair_partners',
      where: 'active = 1',
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertRepairPartner(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    // Loại bỏ id vì SQLite auto-generate và các field không thuộc schema SQLite
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');
    cleanData.remove(
      '_encrypted',
    ); // Field metadata của Firestore, không lưu SQLite

    // Sanitize and filter to valid columns
    final sanitized = _sanitizeForSqlite(cleanData);
    cleanData
      ..clear()
      ..addAll(sanitized);
    await _filterToTableColumns('repair_partners', cleanData);

    if (firestoreId == null) {
      await db.insert(
        'repair_partners',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }
    final existing = await db.query(
      'repair_partners',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
    if (existing.isEmpty) {
      await db.insert(
        'repair_partners',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        'repair_partners',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    }
  }

  Future<int> deleteRepairPartnerByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'repair_partners',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<int> insertRepairPartner(Map<String, dynamic> partner) async {
    final db = await database;
    return await db.insert('repair_partners', partner);
  }

  Future<int> updateRepairPartner(int id, Map<String, dynamic> partner) async {
    final db = await database;
    return await db.update(
      'repair_partners',
      partner,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepairPartner(int id) async {
    final db = await database;
    return await db.update(
      'repair_partners',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Partner Repair History methods
  Future<int> insertPartnerRepairHistory(Map<String, dynamic> history) async {
    final db = await database;
    return await db.insert('partner_repair_history', history);
  }

  /// Upsert partner_repair_history from Firestore sync.
  /// Resolves partnerId from partnerFirestoreId when available.
  Future<void> upsertPartnerRepairHistory(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    await _filterToTableColumns('partner_repair_history', cleanData);

    // Resolve local partnerId from partnerFirestoreId if available
    final partnerFsId = cleanData['partnerFirestoreId'];
    if (partnerFsId != null && partnerFsId.toString().isNotEmpty) {
      final partners = await db.query(
        'repair_partners',
        columns: ['id'],
        where: 'firestoreId = ?',
        whereArgs: [partnerFsId],
      );
      if (partners.isNotEmpty) {
        cleanData['partnerId'] = partners.first['id'];
      }
    }

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'partner_repair_history',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'partner_repair_history',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }
    await db.insert(
      'partner_repair_history',
      cleanData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deletePartnerRepairHistoryByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    return await db.delete(
      'partner_repair_history',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<int> updatePartnerRepairHistory(
    int id,
    Map<String, dynamic> history,
  ) async {
    final db = await database;
    return await db.update(
      'partner_repair_history',
      history,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getPartnerRepairHistory({
    int? partnerId,
    String? partnerFirestoreId,
    String? repairOrderId,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (repairOrderId != null) {
      whereClause = 'repairOrderId = ?';
      whereArgs = [repairOrderId];
    } else if (partnerFirestoreId != null &&
        partnerFirestoreId.isNotEmpty &&
        partnerId != null) {
      // Query bằng OR: tìm theo partnerFirestoreId HOẶC partnerId (record cũ chưa có partnerFirestoreId)
      whereClause = '(partnerFirestoreId = ? OR partnerId = ?)';
      whereArgs = [partnerFirestoreId, partnerId];
    } else if (partnerFirestoreId != null && partnerFirestoreId.isNotEmpty) {
      whereClause = 'partnerFirestoreId = ?';
      whereArgs = [partnerFirestoreId];
    } else if (partnerId != null) {
      whereClause = 'partnerId = ?';
      whereArgs = [partnerId];
    }

    return await db.query(
      'partner_repair_history',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'sentAt DESC',
    );
  }

  Future<Map<String, dynamic>?> getPartnerRepairStats(
    int partnerId, {
    String? shopId,
    String? partnerFirestoreId,
  }) async {
    final db = await database;
    String whereClause;
    List<dynamic> whereArgs;

    // Query bằng OR: tìm theo partnerFirestoreId HOẶC partnerId (record cũ chưa có partnerFirestoreId)
    if (partnerFirestoreId != null && partnerFirestoreId.isNotEmpty) {
      whereClause = '(partnerFirestoreId = ? OR partnerId = ?)';
      whereArgs = [partnerFirestoreId, partnerId];
    } else {
      whereClause = 'partnerId = ?';
      whereArgs = [partnerId];
    }

    if (shopId != null) {
      whereClause += ' AND shopId = ?';
      whereArgs.add(shopId);
    }

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as totalRepairs,
        COALESCE(SUM(partnerCost), 0) as totalCost,
        COALESCE(AVG(partnerCost), 0) as avgCost,
        MAX(sentAt) as lastRepairDate
      FROM partner_repair_history
      WHERE $whereClause
    ''', whereArgs);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getSupplierPayments(int supplierId) async {
    final db = await database;
    return await db.query(
      'supplier_payments',
      where: 'supplierId = ?',
      whereArgs: [supplierId],
      orderBy: 'paidAt DESC',
    );
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final db = await database;
    return await db.update(
      'suppliers',
      supplier,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateSupplierImportHistory(
    int id,
    Map<String, dynamic> history,
  ) async {
    final db = await database;
    return await db.update(
      'supplier_import_history',
      history,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertSupplierProductPrices(Map<String, dynamic> prices) async {
    final db = await database;
    return await db.insert('supplier_product_prices', prices);
  }

  Future<int> updateSupplierProductPrices(
    int id,
    Map<String, dynamic> prices,
  ) async {
    final db = await database;
    return await db.update(
      'supplier_product_prices',
      prices,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> getSupplierStatistics(
    String supplierId,
    String shopId, {
    String? supplierName,
  }) async {
    final db = await database;

    // Query theo cả supplierId và supplierName để bắt được các record lưu với supplierId = 0
    String whereClause;
    List<dynamic> whereArgs;

    if (supplierName != null && supplierName.isNotEmpty) {
      whereClause =
          '(sih.supplierId = ? OR UPPER(sih.supplierName) = UPPER(?)) AND sih.shopId = ?';
      whereArgs = [supplierId, supplierName, shopId];
    } else {
      whereClause = 'sih.supplierId = ? AND sih.shopId = ?';
      whereArgs = [supplierId, shopId];
    }

    final result = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT sih.id) as totalImports,
        COALESCE(SUM(sih.totalAmount), 0) as totalImportValue,
        COALESCE(SUM(sp.amount), 0) as totalPaid
      FROM supplier_import_history sih
      LEFT JOIN supplier_payments sp ON sih.supplierId = sp.supplierId
      WHERE $whereClause
    ''', whereArgs);
    return result.isNotEmpty ? result.first : {};
  }

  // Supplier Payment methods
  Future<int> insertSupplierPayment(Map<String, dynamic> payment) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    return await db.insert('supplier_payments', cleanData);
  }

  Future<int> updateSupplierPayment(
    int id,
    Map<String, dynamic> payment,
  ) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    return await db.update(
      'supplier_payments',
      cleanData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteSupplierPayment(int id) async {
    final db = await database;
    return await db.delete(
      'supplier_payments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteSupplierPaymentByFirestoreId(String firestoreId) async {
    final db = await database;
    return await db.delete(
      'supplier_payments',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<void> upsertSupplierPayment(Map<String, dynamic> payment) async {
    final db = await database;
    final firestoreId = payment['firestoreId'];

    // Loại bỏ id vì SQLite auto-generate
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    await _filterToTableColumns('supplier_payments', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'supplier_payments',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'supplier_payments',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }
    await db.insert('supplier_payments', cleanData);
  }

  // Repair Partner Payment methods
  Future<List<Map<String, dynamic>>> getRepairPartnerPaymentsForSync() async {
    final db = await database;
    return await db.query('repair_partner_payments');
  }

  Future<int> insertRepairPartnerPayment(Map<String, dynamic> payment) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    return await db.insert('repair_partner_payments', cleanData);
  }

  Future<int> updateRepairPartnerPayment(
    int id,
    Map<String, dynamic> payment,
  ) async {
    final db = await database;
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    return await db.update(
      'repair_partner_payments',
      cleanData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepairPartnerPayment(int id) async {
    final db = await database;
    return await db.delete(
      'repair_partner_payments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteRepairPartnerPaymentByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    return await db.delete(
      'repair_partner_payments',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<Map<String, dynamic>?> getRepairPartnerPaymentByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'repair_partner_payments',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> upsertRepairPartnerPayment(Map<String, dynamic> payment) async {
    final db = await database;
    final firestoreId = payment['firestoreId'];

    // Loại bỏ id vì SQLite auto-generate
    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(payment));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    await _filterToTableColumns('repair_partner_payments', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'repair_partner_payments',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'repair_partner_payments',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }
    await db.insert('repair_partner_payments', cleanData);
  }

  // ========== CUSTOMER METHODS ==========
  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    final data = _sanitizeForSqlite(Map<String, dynamic>.from(customer));
    data.remove('id');
    data.remove('_encrypted');

    final phone = (data['phone'] ?? '').toString().trim();
    final shopId = (data['shopId'] ?? '').toString().trim();

    // Prevent duplicates by reusing existing customer with same shopId+phone.
    if (phone.isNotEmpty) {
      final existing = await db.query(
        'customers',
        where: shopId.isNotEmpty ? 'shopId = ? AND phone = ?' : 'phone = ?',
        whereArgs: shopId.isNotEmpty ? [shopId, phone] : [phone],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = (existing.first['id'] as num).toInt();
        await db.update(
          'customers',
          data,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    }

    try {
      return await db.insert('customers', data);
    } catch (e) {
      // Fallback for old DBs still carrying global unique(phone).
      final msg = e.toString();
      if (msg.contains('UNIQUE constraint failed: customers.phone') &&
          phone.isNotEmpty) {
        final existingByPhone = await db.query(
          'customers',
          where: 'phone = ?',
          whereArgs: [phone],
          limit: 1,
        );
        if (existingByPhone.isNotEmpty) {
          final existingId = (existingByPhone.first['id'] as num).toInt();
          await db.update(
            'customers',
            data,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          return existingId;
        }
      }
      rethrow;
    }
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> customer) async {
    final db = await database;
    return await db.update(
      'customers',
      customer,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchCustomers(
    String query,
    String? shopId,
  ) async {
    final db = await database;
    if (shopId == null) {
      // Super admin: search all customers
      return await db.query(
        'customers',
        where: 'deleted = 0 AND (name LIKE ? OR phone LIKE ?)',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'name ASC',
      );
    } else {
      return await db.query(
        'customers',
        where: 'shopId = ? AND deleted = 0 AND (name LIKE ? OR phone LIKE ?)',
        whereArgs: [shopId, '%$query%', '%$query%'],
        orderBy: 'name ASC',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerByPhone(
    String phone,
    String? shopId,
  ) async {
    final db = await database;
    if (shopId == null) {
      // Super admin: search all customers
      return await db.query(
        'customers',
        where: 'phone = ? AND deleted = 0',
        whereArgs: [phone],
      );
    } else {
      return await db.query(
        'customers',
        where: 'shopId = ? AND phone = ? AND deleted = 0',
        whereArgs: [shopId, phone],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getCustomerSalesHistory(
    String phone,
    String? shopId,
  ) async {
    final db = await database;
    return await db.query(
      'sales',
      where: 'phone = ?',
      whereArgs: [phone],
      orderBy: 'soldAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCustomerRepairsHistory(
    String phone,
    String? shopId,
  ) async {
    final db = await database;
    return await db.query(
      'repairs',
      where: 'phone = ?',
      whereArgs: [phone],
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    final shopId = await _getScopedShopId('getCustomers');
    if (shopId == null) return [];

    return await db.query(
      'customers',
      where: 'shopId = ? AND deleted = 0',
      whereArgs: [shopId],
      orderBy: 'name ASC',
    );
  }

  Future<void> upsertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    final firestoreId = customer['firestoreId'];

    // Loại bỏ id vì SQLite auto-generate và _encrypted vì không có trong schema
    final cleanData = Map<String, dynamic>.from(customer);
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    // Strip any Firestore fields not in SQLite schema
    await _filterToTableColumns('customers', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'customers',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'customers',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }

    final phone = (cleanData['phone'] ?? '').toString().trim();
    final shopId = (cleanData['shopId'] ?? '').toString().trim();
    if (phone.isNotEmpty) {
      final existingByShopPhone = await db.query(
        'customers',
        where: shopId.isNotEmpty ? 'shopId = ? AND phone = ?' : 'phone = ?',
        whereArgs: shopId.isNotEmpty ? [shopId, phone] : [phone],
        limit: 1,
      );
      if (existingByShopPhone.isNotEmpty) {
        final existingId = (existingByShopPhone.first['id'] as num).toInt();
        await db.update(
          'customers',
          cleanData,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return;
      }
    }

    try {
      await db.insert('customers', cleanData);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('UNIQUE constraint failed: customers.phone') &&
          phone.isNotEmpty) {
        final existingByPhone = await db.query(
          'customers',
          where: 'phone = ?',
          whereArgs: [phone],
          limit: 1,
        );
        if (existingByPhone.isNotEmpty) {
          final existingId = (existingByPhone.first['id'] as num).toInt();
          await db.update(
            'customers',
            cleanData,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          return;
        }
      }
      rethrow;
    }
  }

  Future<void> deleteCustomerByFirestoreId(String firestoreId) async {
    final db = await database;
    await db.delete(
      'customers',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  // =====================================================
  // === SALES RETURNS METHODS (CHỈ THÊM MỚI - v60) ===
  // =====================================================

  /// Thêm phiếu trả hàng mới
  Future<int> insertSalesReturn(Map<String, dynamic> data) async {
    final db = await database;
    final shopId = await _ensureValidShopId(data['shopId'] as String?);
    final insertData = Map<String, dynamic>.from(data);
    insertData['shopId'] = shopId;
    insertData.remove('_encrypted');
    insertData.remove('deleted');
    insertData.remove('updatedAt');
    final firestoreId = (insertData['firestoreId'] as String?)?.trim();
    if (firestoreId != null && firestoreId.isNotEmpty) {
      final existing = await db.query(
        'sales_returns',
        columns: ['id'],
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return (existing.first['id'] as num?)?.toInt() ?? 0;
      }
    }
    return await db.insert(
      'sales_returns',
      insertData,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Cập nhật phiếu trả hàng
  Future<int> updateSalesReturn(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'sales_returns',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Lấy phiếu trả hàng theo ID
  Future<Map<String, dynamic>?> getSalesReturnById(int id) async {
    final db = await database;
    final result = await db.query(
      'sales_returns',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Lấy danh sách phiếu trả hàng theo shop
  Future<List<Map<String, dynamic>>> getSalesReturns({
    String? shopId,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();

    String? where;
    List<dynamic>? whereArgs;
    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      where = 'shopId = ?';
      whereArgs = [effectiveShopId];
    }

    return await db.query(
      'sales_returns',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'returnDate DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Lấy phiếu trả hàng theo đơn bán gốc
  Future<List<Map<String, dynamic>>> getSalesReturnsBySalesOrderId(
    int salesOrderId,
  ) async {
    final db = await database;
    return await db.query(
      'sales_returns',
      where: 'salesOrderId = ?',
      whereArgs: [salesOrderId],
      orderBy: 'returnDate DESC',
    );
  }

  /// Thêm chi tiết sản phẩm trả hàng
  Future<int> insertSalesReturnItem(Map<String, dynamic> data) async {
    final db = await database;
    final shopId = await _ensureValidShopId(data['shopId'] as String?);
    final insertData = Map<String, dynamic>.from(data);
    insertData['shopId'] = shopId;
    insertData.remove('_encrypted');
    insertData.remove('deleted');
    insertData.remove('updatedAt');
    final firestoreId = (insertData['firestoreId'] as String?)?.trim();
    if (firestoreId != null && firestoreId.isNotEmpty) {
      final existing = await db.query(
        'sales_return_items',
        columns: ['id'],
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return (existing.first['id'] as num?)?.toInt() ?? 0;
      }
    }
    return await db.insert(
      'sales_return_items',
      insertData,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Lấy chi tiết sản phẩm trả hàng theo phiếu trả
  Future<List<Map<String, dynamic>>> getSalesReturnItems(
    int salesReturnId,
  ) async {
    final db = await database;
    return await db.query(
      'sales_return_items',
      where: 'salesReturnId = ?',
      whereArgs: [salesReturnId],
    );
  }

  /// Tính tổng số lượng đã trả của một sản phẩm từ một đơn bán
  Future<int> getTotalReturnedQuantity(
    int salesOrderId,
    String productImei,
  ) async {
    final db = await database;
    // Lấy tất cả phiếu trả của đơn bán này
    final returns = await db.query(
      'sales_returns',
      columns: ['id'],
      where: 'salesOrderId = ? AND status != ?',
      whereArgs: [salesOrderId, 'CANCELLED'],
    );
    if (returns.isEmpty) return 0;

    final returnIds = returns.map((r) => r['id'] as int).toList();

    // Tính tổng quantity từ các item có productImei tương ứng (case-insensitive)
    int total = 0;
    for (final returnId in returnIds) {
      final items = await db.query(
        'sales_return_items',
        columns: ['quantity'],
        where: 'salesReturnId = ? AND UPPER(productImei) = ?',
        whereArgs: [returnId, productImei.toUpperCase()],
      );
      for (final item in items) {
        total += (item['quantity'] as int? ?? 0);
      }
    }
    return total;
  }

  /// Tính tổng số lượng đã trả của một sản phẩm theo productId (cho phụ kiện không có IMEI)
  Future<int> getTotalReturnedQuantityByProductId(
    int salesOrderId,
    int productId,
  ) async {
    final db = await database;
    // Lấy tất cả phiếu trả của đơn bán này
    final returns = await db.query(
      'sales_returns',
      columns: ['id'],
      where: 'salesOrderId = ? AND status != ?',
      whereArgs: [salesOrderId, 'CANCELLED'],
    );
    if (returns.isEmpty) return 0;

    final returnIds = returns.map((r) => r['id'] as int).toList();

    // Tính tổng quantity từ các item có productId tương ứng
    int total = 0;
    for (final returnId in returnIds) {
      final items = await db.query(
        'sales_return_items',
        columns: ['quantity'],
        where: 'salesReturnId = ? AND productId = ?',
        whereArgs: [returnId, productId],
      );
      for (final item in items) {
        total += (item['quantity'] as int? ?? 0);
      }
    }
    return total;
  }

  /// Xóa phiếu trả hàng và các item của nó
  Future<void> deleteSalesReturn(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'sales_return_items',
        where: 'salesReturnId = ?',
        whereArgs: [id],
      );
      await txn.delete('sales_returns', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Get all returned quantities for a sale order, grouped by product IMEI/name.
  /// Returns a map: { 'IMEI_or_productName' : totalReturnedQty }
  Future<Map<String, int>> getReturnedQuantitiesForSale(
    int salesOrderId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        CASE
          WHEN sri.productImei IS NOT NULL
               AND TRIM(sri.productImei) != ''
               AND UPPER(TRIM(sri.productImei)) != 'NO_IMEI'
               AND UPPER(TRIM(sri.productImei)) NOT LIKE 'PKX%'
          THEN UPPER(TRIM(sri.productImei))
          ELSE UPPER(TRIM(sri.productName))
        END AS returnKey,
        SUM(sri.quantity) as totalQty
      FROM sales_return_items sri
      INNER JOIN sales_returns sr ON sr.id = sri.salesReturnId
      WHERE sr.salesOrderId = ? AND sr.status != 'CANCELLED'
      GROUP BY returnKey
    ''',
      [salesOrderId],
    );
    final result = <String, int>{};
    for (final row in rows) {
      final key = (row['returnKey'] as String?)?.trim().toUpperCase() ?? '';
      if (key.isEmpty) continue;
      result[key] =
          (result[key] ?? 0) + ((row['totalQty'] as num?)?.toInt() ?? 0);
    }
    return result;
  }

  /// Upsert phiếu trả hàng (dùng cho sync từ Firestore)
  Future<void> upsertSalesReturn(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'] as String?;
    if (firestoreId == null || firestoreId.isEmpty) {
      await insertSalesReturn(data);
      return;
    }

    final existing = await db.query(
      'sales_returns',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );

    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    // Convert Timestamp objects to int
    if (cleanData['returnDate'] is! int && cleanData['returnDate'] != null) {
      try {
        cleanData['returnDate'] =
            (cleanData['returnDate'] as dynamic).millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (cleanData['createdAt'] is! int && cleanData['createdAt'] != null) {
      try {
        cleanData['createdAt'] =
            (cleanData['createdAt'] as dynamic).millisecondsSinceEpoch;
      } catch (_) {}
    }
    if (cleanData['approvedAt'] is! int && cleanData['approvedAt'] != null) {
      try {
        cleanData['approvedAt'] =
            (cleanData['approvedAt'] as dynamic).millisecondsSinceEpoch;
      } catch (_) {}
    }
    await _filterToTableColumns('sales_returns', cleanData);

    if (existing.isNotEmpty) {
      await db.update(
        'sales_returns',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert('sales_returns', cleanData);
    }
  }

  /// Upsert chi tiết sản phẩm trả hàng (dùng cho sync từ Firestore)
  Future<void> upsertSalesReturnItem(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'] as String?;
    if (firestoreId == null || firestoreId.isEmpty) {
      await insertSalesReturnItem(data);
      return;
    }

    final existing = await db.query(
      'sales_return_items',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );

    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    await _filterToTableColumns('sales_return_items', cleanData);

    if (existing.isNotEmpty) {
      await db.update(
        'sales_return_items',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert('sales_return_items', cleanData);
    }
  }

  /// Lấy thống kê tổng trả hàng theo khoảng thời gian
  Future<Map<String, dynamic>> getSalesReturnStats({
    required int startDate,
    required int endDate,
    String? shopId,
  }) async {
    final db = await database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();

    String whereClause = 'returnDate >= ? AND returnDate <= ? AND status = ?';
    List<dynamic> whereArgs = [startDate, endDate, 'APPROVED'];

    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      whereClause += ' AND shopId = ?';
      whereArgs.add(effectiveShopId);
    }

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalReturns,
        COALESCE(SUM(totalReturnAmount), 0) as totalReturnAmount,
        COALESCE(SUM(totalReturnCost), 0) as totalReturnCost
      FROM sales_returns
      WHERE $whereClause
    ''', whereArgs);

    if (result.isNotEmpty) {
      return {
        'totalReturns': result.first['totalReturns'] ?? 0,
        'totalReturnAmount': result.first['totalReturnAmount'] ?? 0,
        'totalReturnCost': result.first['totalReturnCost'] ?? 0,
      };
    }
    return {'totalReturns': 0, 'totalReturnAmount': 0, 'totalReturnCost': 0};
  }

  // ========== FINANCIAL ACTIVITY LOG METHODS ==========

  /// Insert một activity mới vào log
  Future<int> insertFinancialActivity(Map<String, dynamic> data) async {
    final db = await database;
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    cleanData.remove('deleted');
    cleanData.remove('updatedAt');

    // Đảm bảo có shopId
    if (cleanData['shopId'] == null ||
        (cleanData['shopId'] as String).isEmpty) {
      cleanData['shopId'] = UserService.getShopIdSync();
    }

    return await db.insert('financial_activity_log', cleanData);
  }

  /// Lấy danh sách activity với bộ lọc
  Future<List<Map<String, dynamic>>> getFinancialActivities({
    int? startDate,
    int? endDate,
    String? activityType,
    String? direction,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
    String? shopId,
  }) async {
    final db = await database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();

    List<String> conditions = [];
    List<dynamic> args = [];

    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      conditions.add('(shopId = ? OR shopId IS NULL)');
      args.add(effectiveShopId);
    }

    if (startDate != null) {
      conditions.add('createdAt >= ?');
      args.add(startDate);
    }

    if (endDate != null) {
      conditions.add('createdAt <= ?');
      args.add(endDate);
    }

    if (activityType != null && activityType.isNotEmpty) {
      conditions.add('activityType = ?');
      args.add(activityType);
    }

    if (direction != null && direction.isNotEmpty) {
      conditions.add('direction = ?');
      args.add(direction);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add(
        '(title LIKE ? OR customerName LIKE ? OR phone LIKE ? OR description LIKE ?)',
      );
      final q = '%$searchQuery%';
      args.addAll([q, q, q, q]);
    }

    final whereClause = conditions.isNotEmpty
        ? conditions.join(' AND ')
        : '1=1';

    return await db.rawQuery(
      '''
      SELECT * FROM financial_activity_log
      WHERE $whereClause
      ORDER BY createdAt DESC
      LIMIT ? OFFSET ?
    ''',
      [...args, limit, offset],
    );
  }

  /// Lấy tổng hợp activity theo khoảng thời gian
  Future<Map<String, dynamic>> getFinancialActivitySummary({
    required int startDate,
    required int endDate,
    String? shopId,
  }) async {
    final db = await database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();

    String whereClause = 'createdAt >= ? AND createdAt <= ?';
    List<dynamic> args = [startDate, endDate];

    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      whereClause += ' AND shopId = ?';
      args.add(effectiveShopId);
    }

    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalCount,
        SUM(CASE WHEN direction = 'IN' THEN amount ELSE 0 END) as totalIn,
        SUM(CASE WHEN direction = 'OUT' THEN amount ELSE 0 END) as totalOut,
        SUM(CASE WHEN direction = 'DEBT' THEN amount ELSE 0 END) as totalDebt,
        SUM(CASE WHEN activityType = 'SALE' THEN 1 ELSE 0 END) as saleCount,
        SUM(CASE WHEN activityType = 'EXPENSE' THEN 1 ELSE 0 END) as expenseCount,
        SUM(CASE WHEN activityType = 'PURCHASE' THEN 1 ELSE 0 END) as purchaseCount,
        SUM(CASE WHEN activityType = 'DEBT_COLLECT' THEN 1 ELSE 0 END) as debtCollectCount,
        SUM(CASE WHEN activityType = 'DEBT_PAY' THEN 1 ELSE 0 END) as debtPayCount,
        SUM(CASE WHEN activityType = 'SETTLEMENT' THEN 1 ELSE 0 END) as settlementCount
      FROM financial_activity_log
      WHERE $whereClause
    ''', args);

    if (result.isNotEmpty) {
      return {
        'totalCount': result.first['totalCount'] ?? 0,
        'totalIn': result.first['totalIn'] ?? 0,
        'totalOut': result.first['totalOut'] ?? 0,
        'totalDebt': result.first['totalDebt'] ?? 0,
        'saleCount': result.first['saleCount'] ?? 0,
        'expenseCount': result.first['expenseCount'] ?? 0,
        'purchaseCount': result.first['purchaseCount'] ?? 0,
        'debtCollectCount': result.first['debtCollectCount'] ?? 0,
        'debtPayCount': result.first['debtPayCount'] ?? 0,
        'settlementCount': result.first['settlementCount'] ?? 0,
      };
    }
    return {
      'totalCount': 0,
      'totalIn': 0,
      'totalOut': 0,
      'totalDebt': 0,
      'saleCount': 0,
      'expenseCount': 0,
      'purchaseCount': 0,
      'debtCollectCount': 0,
      'debtPayCount': 0,
      'settlementCount': 0,
    };
  }

  /// Xóa activity cũ hơn N ngày (để tối ưu DB)
  Future<int> deleteOldFinancialActivities(int daysOld) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    return await db.delete(
      'financial_activity_log',
      where: 'createdAt < ?',
      whereArgs: [cutoff],
    );
  }

  /// Kiểm tra activity đã tồn tại chưa (theo referenceType + referenceId)
  Future<bool> financialActivityExists(
    String referenceType,
    String referenceId,
  ) async {
    final db = await database;
    final result = await db.query(
      'financial_activity_log',
      where: 'referenceType = ? AND referenceId = ?',
      whereArgs: [referenceType, referenceId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Upsert activity (dùng cho sync)
  Future<void> upsertFinancialActivity(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'] as String?;
    if (firestoreId == null || firestoreId.isEmpty) {
      await insertFinancialActivity(data);
      return;
    }

    final existing = await db.query(
      'financial_activity_log',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );

    final cleanData = _sanitizeForSqlite(Map<String, dynamic>.from(data));
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    await _filterToTableColumns('financial_activity_log', cleanData);

    if (existing.isNotEmpty) {
      await db.update(
        'financial_activity_log',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    } else {
      await db.insert('financial_activity_log', cleanData);
    }
  }

  /// Lấy các financial activities chưa được sync lên cloud
  Future<List<Map<String, dynamic>>> getUnsyncedFinancialActivities() async {
    final db = await database;
    return await db.query(
      'financial_activity_log',
      where: 'isSynced = 0 OR isSynced IS NULL',
      orderBy: 'createdAt DESC',
    );
  }

  /// Đánh dấu financial activity đã sync
  Future<void> updateFinancialActivitySynced(int id, String firestoreId) async {
    final db = await database;
    await db.update(
      'financial_activity_log',
      {'firestoreId': firestoreId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove duplicate financial activities:
  /// 1. Entries with NULL firestoreId that have a matching referenceType+referenceId
  ///    already covered by an entry WITH firestoreId
  /// 2. Keep only the latest entry for each referenceType+referenceId combo
  Future<int> deduplicateFinancialActivities() async {
    final db = await database;
    int totalDeleted = 0;

    // Step 1: Remove NULL firestoreId entries that duplicate an existing entry
    // with the same referenceType+referenceId
    final nullEntries = await db.rawQuery('''
      SELECT a.id FROM financial_activity_log a
      WHERE a.firestoreId IS NULL
        AND a.referenceType IS NOT NULL
        AND a.referenceId IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM financial_activity_log b
          WHERE b.referenceType = a.referenceType
            AND b.referenceId = a.referenceId
            AND b.firestoreId IS NOT NULL
            AND b.id != a.id
        )
    ''');
    for (final row in nullEntries) {
      await db.delete(
        'financial_activity_log',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      totalDeleted++;
    }

    // Step 2: For remaining NULL firestoreId duplicates (same referenceType+referenceId),
    // keep only the latest one
    final dupGroups = await db.rawQuery('''
      SELECT referenceType, referenceId, COUNT(*) as cnt, MAX(id) as keepId
      FROM financial_activity_log
      WHERE firestoreId IS NULL
        AND referenceType IS NOT NULL
        AND referenceId IS NOT NULL
      GROUP BY referenceType, referenceId
      HAVING cnt > 1
    ''');
    for (final group in dupGroups) {
      final deleted = await db.rawDelete(
        '''
        DELETE FROM financial_activity_log
        WHERE firestoreId IS NULL
          AND referenceType = ?
          AND referenceId = ?
          AND id != ?
      ''',
        [group['referenceType'], group['referenceId'], group['keepId']],
      );
      totalDeleted += deleted;
    }

    if (totalDeleted > 0) {
      debugPrint(
        '🧹 Dedup: removed $totalDeleted duplicate financial activities',
      );
    }
    return totalDeleted;
  }

  // =====================================================================
  // PAYMENT INTENTS METHODS
  // =====================================================================

  /// Insert a new payment intent
  Future<int> insertPaymentIntent(Map<String, dynamic> data) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    return await db.insert('payment_intents', data);
  }

  /// Get all payment intents (for loading on app start) - filtered by current shopId
  Future<List<Map<String, dynamic>>> getAllPaymentIntents() async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) {
      return []; // No shopId = return empty list
    }
    return await db.query(
      'payment_intents',
      where: 'shopId = ?',
      whereArgs: [shopId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Get pending payment intents (filtered by current shopId)
  Future<List<Map<String, dynamic>>> getPendingPaymentIntents() async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) {
      // No shopId = return empty list (new shop or not logged in)
      return [];
    }
    return await db.query(
      'payment_intents',
      where: 'UPPER(status) = ? AND shopId = ?',
      whereArgs: [
        'PENDING',
        shopId,
      ], // Must match PaymentIntentStatus.pending.code = 'PENDING'
      orderBy: 'createdAt DESC',
    );
  }

  /// Get payment intents by status - filtered by current shopId
  Future<List<Map<String, dynamic>>> getPaymentIntentsByStatus(
    String status,
  ) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) {
      return []; // No shopId = return empty list
    }
    return await db.query(
      'payment_intents',
      where: 'UPPER(status) = ? AND shopId = ?',
      whereArgs: [status.toUpperCase().trim(), shopId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Get payment intent by intentId
  Future<Map<String, dynamic>?> getPaymentIntentByIntentId(
    String intentId,
  ) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final results = await db.query(
      'payment_intents',
      where: 'intentId = ?',
      whereArgs: [intentId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update payment intent
  Future<int> updatePaymentIntent(
    String intentId,
    Map<String, dynamic> data,
  ) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    return await db.update(
      'payment_intents',
      data,
      where: 'intentId = ?',
      whereArgs: [intentId],
    );
  }

  /// Update payment intent status
  Future<int> updatePaymentIntentStatus(
    String intentId,
    String status, {
    String? paidBy,
    int? paidAt,
    String? paymentMethod,
  }) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final normalizedStatus = status.toUpperCase().trim();
    final data = <String, dynamic>{'status': normalizedStatus};
    if (paidBy != null) data['paidBy'] = paidBy;
    if (paidAt != null) data['paidAt'] = paidAt;
    if (paymentMethod != null) data['paymentMethod'] = paymentMethod;
    return await db.update(
      'payment_intents',
      data,
      where: 'intentId = ?',
      whereArgs: [intentId],
    );
  }

  /// Delete payment intent
  Future<int> deletePaymentIntent(String intentId) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    return await db.delete(
      'payment_intents',
      where: 'intentId = ?',
      whereArgs: [intentId],
    );
  }

  /// Delete all payment intents linked to a reference (e.g. sale firestoreId)
  Future<int> deletePaymentIntentsByReferenceId(String referenceId) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    return await db.delete(
      'payment_intents',
      where: 'referenceId = ?',
      whereArgs: [referenceId],
    );
  }

  /// Get payment intents history (completed/cancelled/failed) - filtered by current shopId
  Future<List<Map<String, dynamic>>> getPaymentIntentsHistory({
    int limit = 100,
  }) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) {
      // No shopId = return empty list (new shop or not logged in)
      return [];
    }
    return await db.query(
      'payment_intents',
      where: 'UPPER(status) != ? AND shopId = ?',
      whereArgs: [
        'PENDING',
        shopId,
      ], // Must match PaymentIntentStatus.pending.code = 'PENDING'
      orderBy: 'paidAt DESC, createdAt DESC',
      limit: limit,
    );
  }

  /// Get payment intents by type - filtered by current shopId
  Future<List<Map<String, dynamic>>> getPaymentIntentsByType(
    String type, {
    String? status,
  }) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) {
      return []; // No shopId = return empty list
    }
    if (status != null) {
      return await db.query(
        'payment_intents',
        where: 'type = ? AND UPPER(status) = ? AND shopId = ?',
        whereArgs: [type, status.toUpperCase().trim(), shopId],
        orderBy: 'createdAt DESC',
      );
    }
    return await db.query(
      'payment_intents',
      where: 'type = ? AND shopId = ?',
      whereArgs: [type, shopId],
      orderBy: 'createdAt DESC',
    );
  }

  // ============================================================================
  // PAYMENT INTENTS - SYNC SUPPORT
  // ============================================================================

  /// Get payment intents that need to be synced to cloud
  Future<List<Map<String, dynamic>>> getPaymentIntentsForSync() async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final shopId = await _getCurrentShopId();
    if (shopId == null) return [];
    return await db.query(
      'payment_intents',
      where:
          'shopId = ? AND (isSynced = 0 OR isSynced IS NULL OR firestoreId IS NULL)',
      whereArgs: [shopId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Upsert payment intent from cloud sync
  Future<void> upsertPaymentIntent(Map<String, dynamic> data) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);

    final sanitized = _sanitizeForSqlite(data);
    await _filterToTableColumns('payment_intents', sanitized);
    final intentId = sanitized['intentId'];
    final firestoreId = sanitized['firestoreId'];

    if (intentId == null && firestoreId == null) {
      debugPrint('upsertPaymentIntent: No intentId or firestoreId, skipping');
      return;
    }

    // Try to find existing by intentId first, then firestoreId
    final existing = await db.query(
      'payment_intents',
      where: 'intentId = ? OR firestoreId = ?',
      whereArgs: [intentId, firestoreId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update existing
      final localId = existing.first['id'];
      await db.update(
        'payment_intents',
        sanitized,
        where: 'id = ?',
        whereArgs: [localId],
      );
    } else {
      // Insert new
      await db.insert(
        'payment_intents',
        sanitized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Update payment intent sync status after cloud sync
  Future<void> updatePaymentIntentSynced(
    int localId,
    String firestoreId,
  ) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    await db.update(
      'payment_intents',
      {'firestoreId': firestoreId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Delete payment intent by firestoreId (for soft delete from cloud)
  Future<void> deletePaymentIntentByFirestoreId(String firestoreId) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    await db.delete(
      'payment_intents',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  /// Get payment intent by firestoreId
  Future<Map<String, dynamic>?> getPaymentIntentByFirestoreId(
    String firestoreId,
  ) async {
    final db = await database;
    await _ensurePaymentIntentsSchema(db);
    final results = await db.query(
      'payment_intents',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ============ PAYMENT REQUESTS (Yêu cầu đóng tiền) ============

  Future<void> upsertPaymentRequest(Map<String, dynamic> data) async {
    final db = await database;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_requests(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firestoreId TEXT UNIQUE,
          shopId TEXT,
          senderId TEXT,
          senderName TEXT,
          customerName TEXT,
          customerPhone TEXT,
          customerAddress TEXT,
          customerNote TEXT,
          paymentType TEXT,
          paymentTypeLabel TEXT,
          amount REAL,
          accountNumber TEXT,
          bankName TEXT,
          description TEXT,
          imageUrls TEXT,
          status TEXT DEFAULT 'pending',
          processedBy TEXT,
          processedByName TEXT,
          rejectReason TEXT,
          paymentMethod TEXT,
          processedAt INTEGER,
          createdAt INTEGER,
          updatedAt INTEGER,
          isSynced INTEGER DEFAULT 0,
          deleted INTEGER DEFAULT 0
        )
      ''');
    } catch (e) {
      debugPrint('DB: ensure payment_requests table error: $e');
    }

    final sanitized = _sanitizeForSqlite(data);
    await _filterToTableColumns('payment_requests', sanitized);
    final firestoreId = sanitized['firestoreId'];

    if (firestoreId == null) {
      debugPrint('upsertPaymentRequest: No firestoreId, skipping');
      return;
    }

    // Convert imageUrls list to JSON string
    if (sanitized['imageUrls'] is List) {
      sanitized['imageUrls'] = (sanitized['imageUrls'] as List).join(',');
    }

    final existing = await db.query(
      'payment_requests',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localId = existing.first['id'];
      await db.update(
        'payment_requests',
        sanitized,
        where: 'id = ?',
        whereArgs: [localId],
      );
    } else {
      await db.insert(
        'payment_requests',
        sanitized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deletePaymentRequestByFirestoreId(String firestoreId) async {
    final db = await database;
    await db.delete(
      'payment_requests',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentRequestsByPhone(
    String phone,
    String? shopId,
  ) async {
    final db = await database;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS payment_requests(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firestoreId TEXT UNIQUE,
          shopId TEXT,
          senderId TEXT,
          senderName TEXT,
          customerName TEXT,
          customerPhone TEXT,
          customerAddress TEXT,
          customerNote TEXT,
          paymentType TEXT,
          paymentTypeLabel TEXT,
          amount REAL,
          accountNumber TEXT,
          bankName TEXT,
          description TEXT,
          imageUrls TEXT,
          status TEXT DEFAULT 'pending',
          processedBy TEXT,
          processedByName TEXT,
          rejectReason TEXT,
          paymentMethod TEXT,
          processedAt INTEGER,
          createdAt INTEGER,
          updatedAt INTEGER,
          isSynced INTEGER DEFAULT 0,
          deleted INTEGER DEFAULT 0
        )
      ''');
    } catch (e) {
      debugPrint('DB: ensure payment_requests table error: $e');
    }

    String where = 'customerPhone = ? AND (deleted = 0 OR deleted IS NULL)';
    List<dynamic> args = [phone];
    if (shopId != null) {
      where += ' AND shopId = ?';
      args.add(shopId);
    }
    return await db.query(
      'payment_requests',
      where: where,
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
  }

  // ============ DEBUG & CLEANUP FUNCTIONS ============

  /// Debug: Xem chi tiết các repair_parts chưa sync
  Future<List<Map<String, dynamic>>>
  debugGetUnsyncedRepairPartsDetails() async {
    final db = await database;
    return await db.query(
      'repair_parts',
      where:
          '(isSynced = 0 OR isSynced IS NULL) AND (deleted = 0 OR deleted IS NULL)',
    );
  }

  /// Cleanup: Xóa các repair_parts bị stuck (không có firestoreId và isSynced = 0)
  /// Chỉ xóa records orphan (firestoreId = null) để tránh mất dữ liệu
  Future<int> cleanupOrphanRepairParts() async {
    final db = await database;
    final orphans = await db.query(
      'repair_parts',
      where:
          "(firestoreId IS NULL OR firestoreId = '') AND (isSynced = 0 OR isSynced IS NULL)",
    );

    if (orphans.isEmpty) {
      debugPrint('DB: Không có orphan repair_parts cần cleanup');
      return 0;
    }

    debugPrint('DB: Tìm thấy ${orphans.length} orphan repair_parts:');
    for (var part in orphans) {
      debugPrint(
        '  - id=${part['id']}, partName=${part['partName']}, createdAt=${part['createdAt']}',
      );
    }

    // Xóa orphans
    final deleted = await db.delete(
      'repair_parts',
      where:
          "(firestoreId IS NULL OR firestoreId = '') AND (isSynced = 0 OR isSynced IS NULL)",
    );
    debugPrint('DB: Đã xóa $deleted orphan repair_parts');
    return deleted;
  }

  /// Force sync: Đánh dấu tất cả repair_parts có firestoreId là đã sync
  /// (Dùng khi records đã có trên cloud nhưng local bị stuck isSynced = 0)
  Future<int> forceMarkRepairPartsSynced() async {
    final db = await database;
    final result = await db.update(
      'repair_parts',
      {'isSynced': 1},
      where:
          "firestoreId IS NOT NULL AND firestoreId != '' AND (isSynced = 0 OR isSynced IS NULL)",
    );
    debugPrint('DB: Force marked $result repair_parts as synced');
    return result;
  }

  /// Fix repair_parts bị stuck deleted=1 do bug soft-delete cũ
  /// Records có firestoreId nhưng bị đánh deleted=1 nhầm → reset về deleted=0
  /// Real-time sync sẽ xử lý đúng nếu record thực sự bị xóa trên cloud
  Future<int> fixStuckDeletedRepairParts() async {
    final db = await database;
    final stuck = await db.query(
      'repair_parts',
      where: "deleted = 1 AND firestoreId IS NOT NULL AND firestoreId != ''",
    );
    if (stuck.isEmpty) return 0;

    debugPrint('DB: Found ${stuck.length} repair_parts stuck with deleted=1:');
    for (var p in stuck) {
      debugPrint(
        '  - firestoreId=${p['firestoreId']}, partName=${p['partName']}',
      );
    }

    final fixed = await db.update(
      'repair_parts',
      {'deleted': 0, 'isSynced': 1},
      where: "deleted = 1 AND firestoreId IS NOT NULL AND firestoreId != ''",
    );
    debugPrint('DB: Fixed $fixed stuck deleted repair_parts → deleted=0');
    return fixed;
  }

  // === MULTI-INDUSTRY EXPANSION - Phase 1 (v75) ===

  /// Raw update helper cho sync service
  Future<int> rawUpdate(String sql, List<dynamic> args) async {
    final db = await database;
    return await db.rawUpdate(sql, args);
  }

  /// Upsert ProductCategory từ sync
  Future<void> upsertProductCategory(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];

    // Clean data
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');

    // Ensure timestamps are integers
    if (cleanData['createdAt'] is String) {
      cleanData['createdAt'] = DateTime.tryParse(
        cleanData['createdAt'],
      )?.millisecondsSinceEpoch;
    }
    if (cleanData['updatedAt'] is String) {
      cleanData['updatedAt'] = DateTime.tryParse(
        cleanData['updatedAt'],
      )?.millisecondsSinceEpoch;
    }

    // Convert booleans to int for SQLite
    for (final key in [
      'trackExpiry',
      'trackSerial',
      'hasVariants',
      'hasWarranty',
      'isActive',
      'isSynced',
    ]) {
      if (cleanData[key] is bool) {
        cleanData[key] = cleanData[key] == true ? 1 : 0;
      }
    }

    // Convert customFields map to JSON string
    if (cleanData['customFields'] is Map) {
      final map = cleanData['customFields'] as Map;
      final pairs = map.entries.map((e) => '"${e.key}":"${e.value}"');
      cleanData['customFields'] = '{${pairs.join(',')}}';
    }

    await _filterToTableColumns('product_categories', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'product_categories',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'product_categories',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }
    // Insert new
    await db.insert('product_categories', cleanData);
  }

  /// Upsert ProductVariant từ sync
  Future<void> upsertProductVariant(Map<String, dynamic> data) async {
    final db = await database;
    final firestoreId = data['firestoreId'];

    // Clean data
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');

    // Ensure timestamps are integers
    if (cleanData['createdAt'] is String) {
      cleanData['createdAt'] = DateTime.tryParse(
        cleanData['createdAt'],
      )?.millisecondsSinceEpoch;
    }
    if (cleanData['updatedAt'] is String) {
      cleanData['updatedAt'] = DateTime.tryParse(
        cleanData['updatedAt'],
      )?.millisecondsSinceEpoch;
    }

    // Convert booleans to int for SQLite
    if (cleanData['isActive'] is bool) {
      cleanData['isActive'] = cleanData['isActive'] == true ? 1 : 0;
    }
    if (cleanData['isSynced'] is bool) {
      cleanData['isSynced'] = cleanData['isSynced'] == true ? 1 : 0;
    }

    await _filterToTableColumns('product_variants', cleanData);

    if (firestoreId != null && firestoreId.toString().isNotEmpty) {
      final existing = await db.query(
        'product_variants',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
      if (existing.isNotEmpty) {
        await db.update(
          'product_variants',
          cleanData,
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
        );
        return;
      }
    }
    // Insert new
    await db.insert('product_variants', cleanData);
  }

  /// Lấy danh sách ProductCategory theo shopId
  Future<List<Map<String, dynamic>>> getProductCategories(String shopId) async {
    final db = await database;
    return await db.query(
      'product_categories',
      where: 'shopId = ? AND isActive = 1',
      whereArgs: [shopId],
      orderBy: 'sortOrder ASC, name ASC',
    );
  }

  /// Lấy danh sách ProductVariant theo productId
  Future<List<Map<String, dynamic>>> getProductVariants(
    String productId,
  ) async {
    final db = await database;
    return await db.query(
      'product_variants',
      where: 'productId = ? AND isActive = 1',
      whereArgs: [productId],
      orderBy: 'size ASC, color ASC',
    );
  }

  /// Lấy danh sách sản phẩm sắp hết hạn
  Future<List<Map<String, dynamic>>> getExpiringProducts({
    required String shopId,
    int warningDays = 7,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final warningDate = DateTime.now()
        .add(Duration(days: warningDays))
        .millisecondsSinceEpoch;

    return await db.query(
      'products',
      where:
          'shopId = ? AND expiryDate IS NOT NULL AND expiryDate > ? AND expiryDate <= ? AND status = 1 AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId, now, warningDate],
      orderBy: 'expiryDate ASC',
    );
  }

  /// Lấy danh sách sản phẩm đã hết hạn
  Future<List<Map<String, dynamic>>> getExpiredProducts(String shopId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.query(
      'products',
      where:
          'shopId = ? AND expiryDate IS NOT NULL AND expiryDate <= ? AND status = 1 AND (deleted = 0 OR deleted IS NULL)',
      whereArgs: [shopId, now],
      orderBy: 'expiryDate ASC',
    );
  }
}
