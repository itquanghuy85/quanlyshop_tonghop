import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/purchase_order_model.dart';
import '../models/attendance_model.dart';
import '../models/quick_input_code_model.dart';
import '../services/user_service.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  DBHelper._internal();
  factory DBHelper() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'repair_shop_v22.db');
    return await openDatabase(
      path,
      version: 56,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repairs(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, customerName TEXT, phone TEXT, model TEXT, issue TEXT, accessories TEXT, address TEXT, imagePath TEXT, deliveredImage TEXT, warranty TEXT, partsUsed TEXT, status INTEGER, price INTEGER, cost INTEGER, paymentMethod TEXT, createdAt INTEGER, startedAt INTEGER, finishedAt INTEGER, deliveredAt INTEGER, createdBy TEXT, repairedBy TEXT, deliveredBy TEXT, lastCaredAt INTEGER, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, color TEXT, imei TEXT, condition TEXT, services TEXT, notes TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS products(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, brand TEXT, imei TEXT, cost INTEGER, price INTEGER, condition TEXT, status INTEGER DEFAULT 1, description TEXT, images TEXT, warranty TEXT, createdAt INTEGER, supplier TEXT, type TEXT DEFAULT "DIEN_THOAI", quantity INTEGER DEFAULT 1, color TEXT, isSynced INTEGER DEFAULT 0, capacity TEXT, paymentMethod TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS sales(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, customerName TEXT, phone TEXT, address TEXT, productNames TEXT, productImeis TEXT, totalPrice INTEGER, totalCost INTEGER, paymentMethod TEXT, sellerName TEXT, soldAt INTEGER, notes TEXT, gifts TEXT, isInstallment INTEGER DEFAULT 0, downPayment INTEGER DEFAULT 0, loanAmount INTEGER DEFAULT 0, installmentTerm TEXT, bankName TEXT, warranty TEXT, settlementPlannedAt INTEGER, settlementReceivedAt INTEGER, settlementAmount INTEGER DEFAULT 0, settlementFee INTEGER DEFAULT 0, settlementNote TEXT, settlementCode TEXT, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, phone TEXT UNIQUE, email TEXT, address TEXT, notes TEXT, createdAt INTEGER, lastVisitAt INTEGER, updatedAt INTEGER, totalSpent INTEGER DEFAULT 0, totalRepairs INTEGER DEFAULT 0, totalRepairCost INTEGER DEFAULT 0, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, contactPerson TEXT, phone TEXT, email TEXT, address TEXT, note TEXT, items TEXT, importCount INTEGER DEFAULT 0, totalAmount INTEGER DEFAULT 0, active INTEGER DEFAULT 1, favorite INTEGER DEFAULT 0, createdAt INTEGER, updatedAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, title TEXT, description TEXT, amount INTEGER, category TEXT, date INTEGER, note TEXT, paymentMethod TEXT, createdAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, relatedPartId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS debts(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, personName TEXT, phone TEXT, totalAmount INTEGER, paidAmount INTEGER DEFAULT 0, type TEXT, status TEXT, createdAt INTEGER, note TEXT, isSynced INTEGER DEFAULT 0, linkedId TEXT, createdBy TEXT, shopId TEXT, relatedPartId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS attendance(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, email TEXT, name TEXT, dateKey TEXT, checkInAt INTEGER, checkOutAt INTEGER, overtimeOn INTEGER DEFAULT 0, photoIn TEXT, photoOut TEXT, note TEXT, status TEXT DEFAULT "pending", approvedBy TEXT, approvedAt INTEGER, rejectReason TEXT, locked INTEGER DEFAULT 0, createdAt INTEGER, location TEXT, isLate INTEGER DEFAULT 0, isEarlyLeave INTEGER DEFAULT 0, workSchedule TEXT, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS audit_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, userId TEXT, userName TEXT, action TEXT, targetType TEXT, targetId TEXT, description TEXT, createdAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, summary TEXT, role TEXT, email TEXT, payload TEXT, entityType TEXT, entityId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS inventory_checks(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, type TEXT, checkDate INTEGER, itemsJson TEXT, status TEXT, createdBy TEXT, isSynced INTEGER DEFAULT 0, isCompleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_partner_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partnerId INTEGER, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS cash_closings(id INTEGER PRIMARY KEY AUTOINCREMENT, dateKey TEXT UNIQUE, cashStart INTEGER DEFAULT 0, bankStart INTEGER DEFAULT 0, cashEnd INTEGER DEFAULT 0, bankEnd INTEGER DEFAULT 0, expectedCashDelta INTEGER DEFAULT 0, expectedBankDelta INTEGER DEFAULT 0, note TEXT, createdAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS payroll_settings(id INTEGER PRIMARY KEY AUTOINCREMENT, baseSalary INTEGER DEFAULT 0, saleCommPercent REAL DEFAULT 1.0, repairProfitPercent REAL DEFAULT 10.0, updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS payroll_locks(id INTEGER PRIMARY KEY AUTOINCREMENT, monthKey TEXT UNIQUE, locked INTEGER DEFAULT 0, lockedBy TEXT, lockedAt INTEGER, note TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS purchase_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, orderCode TEXT UNIQUE, supplierName TEXT, supplierPhone TEXT, supplierAddress TEXT, itemsJson TEXT, totalAmount INTEGER, totalCost INTEGER, createdAt INTEGER, createdBy TEXT, status TEXT DEFAULT "PENDING", paymentMethod TEXT, notes TEXT, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS work_schedules(id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT UNIQUE, startTime TEXT DEFAULT "08:00", endTime TEXT DEFAULT "17:00", breakTime INTEGER DEFAULT 1, maxOtHours INTEGER DEFAULT 4, workDays TEXT DEFAULT "[1,2,3,4,5,6]", updatedAt INTEGER)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS debt_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, debtId INTEGER, debtFirestoreId TEXT, debtType TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, createdBy TEXT, createdAt INTEGER, updatedAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS quick_input_codes(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, code TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_product_prices(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, productName TEXT, productBrand TEXT, productModel TEXT, costPrice INTEGER, lastUpdated INTEGER, createdAt INTEGER, isActive INTEGER DEFAULT 1, shopId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS supplier_import_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, supplierId INTEGER, supplierName TEXT, productName TEXT, productBrand TEXT, productModel TEXT, imei TEXT, quantity INTEGER, costPrice INTEGER, totalAmount INTEGER, paymentMethod TEXT, importDate INTEGER, importedBy TEXT, notes TEXT, isSynced INTEGER DEFAULT 0, shopId TEXT)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_partners(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, name TEXT, phone TEXT, note TEXT, active INTEGER DEFAULT 1, createdAt INTEGER, updatedAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS partner_repair_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, repairOrderId TEXT, partnerId INTEGER, customerName TEXT, deviceModel TEXT, issue TEXT, partnerCost INTEGER, repairContent TEXT, sentAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS repair_parts(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partName TEXT, compatibleModels TEXT, cost INTEGER, price INTEGER, quantity INTEGER, updatedAt INTEGER, createdAt INTEGER, isSynced INTEGER DEFAULT 0, shopId TEXT, deleted INTEGER DEFAULT 0, supplierId INTEGER, paymentMethod TEXT, createdBy TEXT)',
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
              'CREATE TABLE IF NOT EXISTS debt_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, debtId INTEGER, debtFirestoreId TEXT, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, createdBy TEXT, isSynced INTEGER DEFAULT 0)',
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
              'CREATE TABLE IF NOT EXISTS quick_input_codes(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, shopId TEXT, name TEXT, type TEXT, brand TEXT, model TEXT, capacity TEXT, color TEXT, condition TEXT, cost INTEGER, price INTEGER, description TEXT, supplier TEXT, paymentMethod TEXT, isActive INTEGER DEFAULT 1, createdAt INTEGER, isSynced INTEGER DEFAULT 0)',
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
              'CREATE TABLE IF NOT EXISTS repair_parts(id INTEGER PRIMARY KEY AUTOINCREMENT, partName TEXT, compatibleModels TEXT, cost INTEGER, price INTEGER, quantity INTEGER, updatedAt INTEGER, createdAt INTEGER)',
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
          try {
            await db.execute(
              'ALTER TABLE supplier_import_history ADD COLUMN shopId TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (supplier_import_history shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_product_prices ADD COLUMN shopId TEXT',
            );
          } catch (e) {
            debugPrint('DB upgrade error (supplier_product_prices shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_import_history ADD COLUMN firestoreId TEXT UNIQUE',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (supplier_import_history firestoreId): $e',
            );
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_product_prices ADD COLUMN firestoreId TEXT UNIQUE',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (supplier_product_prices firestoreId): $e',
            );
          }
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
              'CREATE TABLE IF NOT EXISTS partner_repair_history(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, repairOrderId TEXT, partnerId INTEGER, customerName TEXT, deviceModel TEXT, issue TEXT, partnerCost INTEGER, repairContent TEXT, sentAt INTEGER, shopId TEXT, isSynced INTEGER DEFAULT 0)',
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
              'CREATE TABLE IF NOT EXISTS repair_partner_payments(id INTEGER PRIMARY KEY AUTOINCREMENT, firestoreId TEXT UNIQUE, partnerId INTEGER, amount INTEGER, paidAt INTEGER, paymentMethod TEXT, note TEXT, shopId TEXT, isSynced INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)',
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
          try {
            await db.execute(
              'ALTER TABLE supplier_import_history ADD COLUMN firestoreId TEXT UNIQUE',
            );
            debugPrint(
              'DB upgrade: added firestoreId to supplier_import_history',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (supplier_import_history firestoreId): $e',
            );
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_import_history ADD COLUMN shopId TEXT',
            );
            debugPrint('DB upgrade: added shopId to supplier_import_history');
          } catch (e) {
            debugPrint('DB upgrade error (supplier_import_history shopId): $e');
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_product_prices ADD COLUMN firestoreId TEXT UNIQUE',
            );
            debugPrint(
              'DB upgrade: added firestoreId to supplier_product_prices',
            );
          } catch (e) {
            debugPrint(
              'DB upgrade error (supplier_product_prices firestoreId): $e',
            );
          }
          try {
            await db.execute(
              'ALTER TABLE supplier_product_prices ADD COLUMN shopId TEXT',
            );
            debugPrint('DB upgrade: added shopId to supplier_product_prices');
          } catch (e) {
            debugPrint('DB upgrade error (supplier_product_prices shopId): $e');
          }
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
        } catch (e) {
          debugPrint('DB onOpen check error: $e');
        }

        // Ensure checkedBy column exists in inventory_checks table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(inventory_checks)');
          final has = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'checkedBy',
          );
          if (!has) {
            await db.execute(
              'ALTER TABLE inventory_checks ADD COLUMN checkedBy TEXT',
            );
            debugPrint('DB: added checkedBy column to inventory_checks');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (inventory_checks checkedBy): $e');
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

        // Ensure services column exists in repairs table
        try {
          final cols = await db.rawQuery('PRAGMA table_info(repairs)');
          final hasServices = cols.any(
            (c) => (c['name'] ?? c['name'.toString()]) == 'services',
          );
          if (!hasServices) {
            await db.execute('ALTER TABLE repairs ADD COLUMN services TEXT');
            debugPrint('DB: added services column to repairs');
          }
        } catch (e) {
          debugPrint('DB onOpen check error (repairs services): $e');
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
        try {
          await db.execute(
            'ALTER TABLE supplier_import_history ADD COLUMN firestoreId TEXT UNIQUE',
          );
          debugPrint('DB: added firestoreId column to supplier_import_history');
        } catch (e) {
          debugPrint(
            'DB: firestoreId column already exists in supplier_import_history or error: $e',
          );
        }
        try {
          await db.execute(
            'ALTER TABLE supplier_import_history ADD COLUMN shopId TEXT',
          );
          debugPrint('DB: added shopId column to supplier_import_history');
        } catch (e) {
          debugPrint(
            'DB: shopId column already exists in supplier_import_history or error: $e',
          );
        }

        // Ensure firestoreId column exists in supplier_product_prices table
        try {
          await db.execute(
            'ALTER TABLE supplier_product_prices ADD COLUMN firestoreId TEXT UNIQUE',
          );
          debugPrint('DB: added firestoreId column to supplier_product_prices');
        } catch (e) {
          debugPrint(
            'DB: firestoreId column already exists in supplier_product_prices or error: $e',
          );
        }
        try {
          await db.execute(
            'ALTER TABLE supplier_product_prices ADD COLUMN shopId TEXT',
          );
          debugPrint('DB: added shopId column to supplier_product_prices');
        } catch (e) {
          debugPrint(
            'DB: shopId column already exists in supplier_product_prices or error: $e',
          );
        }

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

        // Ensure description, createdAt, shopId, relatedPartId columns exist in expenses table
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
      },
    );
  }

  // --- HÀM HỖ TRỢ CHUNG ---
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
      Map<String, dynamic> data = Map<String, dynamic>.from(map);
      data.remove('id');
      data.remove(
        '_encrypted',
      ); // Field metadata của Firestore, không lưu SQLite
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
  Future<List<Repair>> getAllRepairs() async {
    final maps = await (await database).query(
      'repairs',
      orderBy: 'createdAt DESC',
    );
    final repairs = List.generate(maps.length, (i) => Repair.fromMap(maps[i]));
    debugPrint("DB_TRACE: getAllRepairs returned ${repairs.length} repairs");
    for (var r in repairs) {
      final createdDate = DateTime.fromMillisecondsSinceEpoch(
        r.createdAt,
      ).toLocal();
      final deliveredDate = r.deliveredAt != null
          ? DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!).toLocal()
          : null;
      debugPrint(
        "DB_TRACE: Repair - id: ${r.id}, firestoreId: ${r.firestoreId}, status: ${r.status}, price: ${r.price}, totalCost: ${r.totalCost}, createdAt: ${r.createdAt} ($createdDate), deliveredAt: ${r.deliveredAt} ($deliveredDate)",
      );
    }
    return repairs;
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
  Future<List<SaleOrder>> getAllSales() async {
    final maps = await (await database).query('sales', orderBy: 'soldAt DESC');
    final sales = List.generate(maps.length, (i) => SaleOrder.fromMap(maps[i]));
    debugPrint("DB_TRACE: getAllSales returned ${sales.length} sales");
    for (var s in sales) {
      final soldDate = DateTime.fromMillisecondsSinceEpoch(s.soldAt).toLocal();
      debugPrint(
        "DB_TRACE: Sale - id: ${s.id}, firestoreId: ${s.firestoreId}, totalPrice: ${s.totalPrice}, totalCost: ${s.totalCost}, soldAt: ${s.soldAt} ($soldDate), customerName: ${s.customerName}",
      );
    }
    return sales;
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
  Future<List<Product>> getInStockProducts() async {
    final maps = await (await database).query(
      'products',
      where: 'status = 1 AND quantity > 0',
      orderBy: 'createdAt DESC',
    );
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  Future<List<Product>> getAllProducts() async {
    final maps = await (await database).query('products');
    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Lấy sản phẩm theo loại (DIEN_THOAI, PHỤ KIỆN, LINH KIỆN)
  Future<List<Product>> getProductsByType(
    String type, {
    bool inStockOnly = true,
  }) async {
    final maps = await (await database).query(
      'products',
      where: inStockOnly
          ? 'type = ? AND quantity > 0 AND (status = 1 OR status IS NULL)'
          : 'type = ?',
      whereArgs: [type],
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

  Future<Product?> getProductByFirestoreId(String firestoreId) async {
    final res = await (await database).query(
      'products',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1,
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  Future<Product?> getProductById(int id) async {
    final res = await (await database).query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  Future<int> updateProductStatus(int id, int status) async =>
      await (await database).rawUpdate(
        'UPDATE products SET status = ? WHERE id = ?',
        [status, id],
      );
  Future<void> deductProductQuantity(int id, int amount) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET quantity = quantity - ? WHERE id = ?',
      [amount, id],
    );
    await db.rawUpdate(
      'UPDATE products SET status = 0 WHERE id = ? AND quantity <= 0',
      [id],
    );
  }

  Future<void> addProductQuantity(int id, int amount) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET quantity = quantity + ? WHERE id = ?',
      [amount, id],
    );
    // Nếu sản phẩm đã bán hết (status = 0) và giờ có hàng lại, có thể cần cập nhật status
    await db.rawUpdate(
      'UPDATE products SET status = 1 WHERE id = ? AND status = 0 AND quantity > 0',
      [id],
    );
  }

  /// Lấy số lượng tồn kho hiện tại của sản phẩm (real-time từ DB)
  /// Dùng để kiểm tra trước khi bán, tránh 2 nhân viên bán cùng 1 món
  Future<int> getProductQuantityById(int id) async {
    final db = await database;
    final result = await db.query(
      'products',
      columns: ['quantity'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return (result.first['quantity'] as int?) ?? 0;
  }

  Future<Product?> getProductByImei(String imei) async {
    final res = await (await database).query(
      'products',
      where: 'imei = ?',
      whereArgs: [imei],
      limit: 1,
    );
    return res.isNotEmpty ? Product.fromMap(res.first) : null;
  }

  // --- CUSTOMERS & SUPPLIERS ---
  Future<List<Map<String, dynamic>>>
  getCustomerSuggestions() async => (await database).rawQuery(
    'SELECT DISTINCT customerName, phone, address FROM (SELECT customerName, phone, address FROM repairs UNION SELECT customerName, phone, address FROM sales UNION SELECT name as customerName, phone, address FROM customers) ORDER BY customerName ASC',
  );
  Future<List<Map<String, dynamic>>>
  getUniqueCustomersAll() async => (await database).rawQuery(
    'SELECT phone, customerName, address FROM (SELECT phone, customerName, address FROM repairs UNION SELECT phone, customerName, address FROM sales UNION SELECT phone, name as customerName, address FROM customers) as t WHERE phone IS NOT NULL AND phone != "" GROUP BY phone ORDER BY customerName ASC',
  );
  Future<List<Map<String, dynamic>>> getCustomersWithoutShop() async =>
      (await database).query(
        'customers',
        where: 'shopId IS NULL OR shopId = ""',
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
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');
    cleanData.remove('_encrypted');
    cleanData.remove('email'); // Loại bỏ email nếu có

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
        return;
      }

      // Nếu không tìm thấy theo firestoreId, tìm theo name + shopId (trường hợp insert local chưa có firestoreId)
      if (name != null && shopId != null) {
        final existingByName = await db.query(
          'suppliers',
          where:
              'name = ? AND shopId = ? AND (firestoreId IS NULL OR firestoreId = "")',
          whereArgs: [name, shopId],
        );
        if (existingByName.isNotEmpty) {
          // Update record cũ với firestoreId mới
          await db.update(
            'suppliers',
            cleanData,
            where: 'id = ?',
            whereArgs: [existingByName.first['id']],
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
      // Không có firestoreId, insert mới
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
    final res = await db.query(
      'suppliers',
      where: 'deleted = 0 OR deleted IS NULL',
      orderBy: 'name ASC',
    );
    debugPrint('DBHelper.getSuppliers: found ${res.length} suppliers');
    return res;
  }

  Future<int> deleteSupplier(int id) async =>
      (await database).delete('suppliers', where: 'id = ?', whereArgs: [id]);

  // --- FINANCE ---
  Future<void> upsertExpense(Expense e) async =>
      _upsert('expenses', e.toMap(), e.firestoreId ?? "exp_${e.date}");
  Future<int> insertExpense(Map<String, dynamic> e) async =>
      (await database).insert('expenses', e);
  Future<List<Map<String, dynamic>>> getAllExpenses() async =>
      (await database).query('expenses', orderBy: 'date DESC');
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

  Future<void> upsertDebt(Debt d) async =>
      _upsert('debts', d.toMap(), d.firestoreId ?? "debt_${d.createdAt}");
  Future<int> insertDebt(Map<String, dynamic> d) async =>
      (await database).insert('debts', d);
  Future<List<Map<String, dynamic>>> getAllDebts() async =>
      (await database).query('debts', orderBy: 'status ASC, createdAt DESC');
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
      'UPDATE debts SET paidAmount = paidAmount + ?, status = CASE WHEN (paidAmount + ?) >= totalAmount THEN "paid" ELSE "unpaid" END, updatedAt = ?, isSynced = 0 WHERE id = ?',
      [pay, pay, now, id],
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
    final db = await database;
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
    final db = await database;
    final res = await db.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Lấy tất cả các chốt quỹ
  Future<List<Map<String, dynamic>>> getAllCashClosings() async {
    final db = await database;
    return db.query('cash_closings', orderBy: 'dateKey DESC');
  }

  /// Upsert chốt quỹ
  Future<void> upsertCashClosing(Map<String, dynamic> data) async {
    final dateKey = data['dateKey'] as String?;
    if (dateKey == null) return;

    final db = await database;

    // Lấy danh sách các cột hợp lệ trong bảng cash_closings
    final cols = await db.rawQuery('PRAGMA table_info(cash_closings)');
    final validColumns = cols.map((c) => c['name'] as String).toSet();

    // Lọc chỉ giữ lại các trường có trong schema
    final filteredData = <String, dynamic>{};
    data.forEach((key, value) {
      if (validColumns.contains(key)) {
        filteredData[key] = value;
      }
    });

    debugPrint('upsertCashClosing: valid columns=$validColumns');
    debugPrint(
      'upsertCashClosing: filtered data keys=${filteredData.keys.toList()}',
    );

    final existing = await db.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'cash_closings',
        filteredData,
        where: 'dateKey = ?',
        whereArgs: [dateKey],
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
    await db.insert('work_schedules', {
      'userId': userId,
      ...schedule,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    return await db.insert('inventory_checks', map);
  }

  Future<int> updateInventoryCheck(dynamic data) async {
    final db = await database;
    final map = (data is Map<String, dynamic>)
        ? data
        : (data as dynamic).toMap();
    return await db.update(
      'inventory_checks',
      map,
      where: 'id = ?',
      whereArgs: [map['id']],
    );
  }

  Future<List<Map<String, dynamic>>> getItemsForInventoryCheck(
    String type,
  ) async {
    final db = await database;
    if (type == 'DIEN_THOAI') {
      return await db.query('products', where: 'status = 1');
    }
    return await db.query('repair_parts');
  }

  // --- PARTS HELPERS ---
  Future<List<Map<String, dynamic>>> getAllParts() async {
    final db = await database;
    // Return all repair parts, excluding soft-deleted items
    // Sắp xếp theo thời gian nhập mới nhất lên đầu
    return await db.query(
      'repair_parts',
      where: 'deleted = 0 OR deleted IS NULL',
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
    // Tự động lấy shopId nếu chưa có
    data['shopId'] = data['shopId'] ?? await UserService.getCurrentShopId();
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

  /// Trừ số lượng phụ tùng trong kho
  Future<bool> deductPartQuantity(int partId, int quantity) async {
    final db = await database;
    final part = await getPartById(partId);
    if (part == null) return false;

    final currentQty = part['quantity'] as int? ?? 0;
    if (currentQty < quantity) return false; // Không đủ hàng

    await db.update(
      'repair_parts',
      {
        'quantity': currentQty - quantity,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isSynced': 0, // Cần sync lại khi có thay đổi
      },
      where: 'id = ?',
      whereArgs: [partId],
    );
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
      cleanData['updatedAt'] =
          cleanData['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch;
      cleanData['createdAt'] =
          cleanData['createdAt'] ?? DateTime.now().millisecondsSinceEpoch;

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

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final db = await database;
    return await db.query('audit_logs', orderBy: 'createdAt DESC', limit: 100);
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
    final res = await db.query('payroll_settings', limit: 1);
    if (res.isEmpty) {
      return {
        'baseSalary': 0,
        'saleCommPercent': 1.0,
        'repairProfitPercent': 10.0,
      };
    }
    return res.first;
  }

  Future<void> savePayrollSettings(Map<String, dynamic> data) async {
    final db = await database;
    await db.delete('payroll_settings');
    await db.insert('payroll_settings', data);
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

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
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
      ];
      for (var t in tables) {
        try {
          await txn.delete(t);
        } catch (e) {
          // Table may not exist in older DB versions, ignore
          debugPrint('clearAllData: table $t not found or error: $e');
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
    final db = await database;
    return await db.rawQuery('''
      SELECT p.*, d.type as debtType, d.personName 
      FROM debt_payments p
      JOIN debts d ON p.debtId = d.id
      ORDER BY p.paidAt DESC
    ''');
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
    return await db.insert('quick_input_codes', code.toMap());
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
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');

    // Convert bool to int for SQLite
    if (cleanData['isSynced'] is bool) {
      cleanData['isSynced'] = (cleanData['isSynced'] as bool) ? 1 : 0;
    }
    if (cleanData['isActive'] is bool) {
      cleanData['isActive'] = (cleanData['isActive'] as bool) ? 1 : 0;
    }

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
    final firestoreId =
        history['firestoreId'] ??
        "import_${DateTime.now().millisecondsSinceEpoch}_${history['supplierId'] ?? 'unknown'}_${history['imei'] ?? 'no_imei'}";
    history['firestoreId'] = firestoreId;
    return await db.insert('supplier_import_history', history);
  }

  /// Lấy tất cả lịch sử nhập hàng để hiển thị trong chốt quỹ
  Future<List<Map<String, dynamic>>> getAllSupplierImportHistory() async {
    final db = await database;
    return await db.query(
      'supplier_import_history',
      orderBy: 'importDate DESC',
    );
  }

  /// Lấy tất cả thanh toán NCC để hiển thị trong chốt quỹ
  Future<List<Map<String, dynamic>>> getAllSupplierPayments() async {
    final db = await database;
    return await db.query(
      'supplier_payments',
      where: 'deleted = 0 OR deleted IS NULL',
      orderBy: 'paidAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getSupplierImportHistory(
    int supplierId, {
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    String query = 'supplierId = ?';
    List<dynamic> args = [supplierId];

    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
    }

    return await db.query(
      'supplier_import_history',
      where: query,
      whereArgs: args,
      orderBy: 'importDate DESC',
    );
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

  Future<Map<String, dynamic>?> getSupplierImportStats(int supplierId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
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
      FROM supplier_import_history
      WHERE supplierId = ?
    ''',
      [supplierId],
    );
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
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('id');

    // Convert bool to int for SQLite
    if (cleanData['isSynced'] is bool) {
      cleanData['isSynced'] = (cleanData['isSynced'] as bool) ? 1 : 0;
    }
    if (cleanData['deleted'] is bool) {
      cleanData['deleted'] = (cleanData['deleted'] as bool) ? 1 : 0;
    }

    if (firestoreId == null) {
      await db.insert(
        'supplier_import_history',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }
    final existing = await db.query(
      'supplier_import_history',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
    if (existing.isEmpty) {
      await db.insert(
        'supplier_import_history',
        cleanData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        'supplier_import_history',
        cleanData,
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );
    }
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

    // Convert bool to int for SQLite
    if (cleanData['active'] is bool) {
      cleanData['active'] = (cleanData['active'] as bool) ? 1 : 0;
    }
    if (cleanData['deleted'] is bool) {
      cleanData['deleted'] = (cleanData['deleted'] as bool) ? 1 : 0;
    }
    if (cleanData['isSynced'] is bool) {
      cleanData['isSynced'] = (cleanData['isSynced'] as bool) ? 1 : 0;
    }

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
    String? repairOrderId,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (partnerId != null) {
      whereClause = 'partnerId = ?';
      whereArgs = [partnerId];
    } else if (repairOrderId != null) {
      whereClause = 'repairOrderId = ?';
      whereArgs = [repairOrderId];
    }

    return await db.query(
      'partner_repair_history',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'sentAt DESC',
    );
  }

  Future<Map<String, dynamic>?> getPartnerRepairStats(int partnerId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(*) as totalRepairs,
        COALESCE(SUM(partnerCost), 0) as totalCost,
        COALESCE(AVG(partnerCost), 0) as avgCost,
        MAX(sentAt) as lastRepairDate
      FROM partner_repair_history
      WHERE partnerId = ?
    ''',
      [partnerId],
    );
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
    String shopId,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT sih.id) as totalImports,
        COALESCE(SUM(sih.totalAmount), 0) as totalImportValue,
        COALESCE(SUM(sp.amount), 0) as totalPaid
      FROM supplier_import_history sih
      LEFT JOIN supplier_payments sp ON sih.supplierId = sp.supplierId
      WHERE sih.supplierId = ? AND sih.shopId = ?
    ''',
      [supplierId, shopId],
    );
    return result.isNotEmpty ? result.first : {};
  }

  // Supplier Payment methods
  Future<int> insertSupplierPayment(Map<String, dynamic> payment) async {
    final db = await database;
    return await db.insert('supplier_payments', payment);
  }

  Future<int> updateSupplierPayment(
    int id,
    Map<String, dynamic> payment,
  ) async {
    final db = await database;
    return await db.update(
      'supplier_payments',
      payment,
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
    final cleanData = Map<String, dynamic>.from(payment);
    cleanData.remove('id');
    cleanData.remove('_encrypted');

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
  Future<int> insertRepairPartnerPayment(Map<String, dynamic> payment) async {
    final db = await database;
    return await db.insert('repair_partner_payments', payment);
  }

  Future<int> updateRepairPartnerPayment(
    int id,
    Map<String, dynamic> payment,
  ) async {
    final db = await database;
    return await db.update(
      'repair_partner_payments',
      payment,
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

  Future<void> upsertRepairPartnerPayment(Map<String, dynamic> payment) async {
    final db = await database;
    final firestoreId = payment['firestoreId'];

    // Loại bỏ id vì SQLite auto-generate
    final cleanData = Map<String, dynamic>.from(payment);
    cleanData.remove('id');
    cleanData.remove('_encrypted');

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
    return await db.insert('customers', customer);
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
    return await db.query('customers', orderBy: 'name ASC');
  }

  Future<void> upsertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    final firestoreId = customer['firestoreId'];

    // Loại bỏ id vì SQLite auto-generate và _encrypted vì không có trong schema
    final cleanData = Map<String, dynamic>.from(customer);
    cleanData.remove('id');
    cleanData.remove('_encrypted');

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
    await db.insert('customers', cleanData);
  }

  Future<void> deleteCustomerByFirestoreId(String firestoreId) async {
    final db = await database;
    await db.delete(
      'customers',
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
    );
  }
}
