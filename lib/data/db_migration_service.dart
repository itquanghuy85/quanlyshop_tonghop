import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

/// Dịch vụ migrations cho cơ sở dữ liệu
/// Thêm các column mới cho các tính năng bổ sung
class DBMigrationService {
  /// Áp dụng tất cả pending migrations
  /// Gọi từ main.dart hoặc AuthGate khi start app
  static Future<void> runPendingMigrations(Database db) async {
    try {
      // Migration 1: Thêm warranty_expiry và warranty_status vào repairs
      await _addWarrantyColumnsToRepairs(db);

      // Migration 2: Thêm segment và vipNotes vào customers
      await _addSegmentColumnsToCustomers(db);

      // Migration 3: Thêm warranty_reminder tracking
      await _createWarrantyRemindersTable(db);

      debugPrint('✅ All migrations applied successfully');
    } catch (e) {
      debugPrint('❌ Migration error: $e');
      rethrow;
    }
  }

  /// Migration 1: Thêm warranty_expiry (millisecondsSinceEpoch) vào repairs
  /// Để track chính xác khi bảo hành hết hạn
  static Future<void> _addWarrantyColumnsToRepairs(Database db) async {
    try {
      // Kiểm tra xem column đã tồn tại chưa
      final columns = await db.rawQuery("PRAGMA table_info(repairs)");
      final columnNames = (columns as List<Map>).map((c) => c['name']).toList();

      if (!columnNames.contains('warranty_expiry')) {
        await db.execute('ALTER TABLE repairs ADD COLUMN warranty_expiry INTEGER');
        debugPrint('✅ Added warranty_expiry column to repairs');
      }

      if (!columnNames.contains('warranty_status')) {
        await db.execute('ALTER TABLE repairs ADD COLUMN warranty_status TEXT');
        debugPrint('✅ Added warranty_status column to repairs');
      }
    } catch (e) {
      debugPrint('⚠️ Migration for repairs columns: $e');
    }
  }

  /// Migration 2: Thêm segment (VIP/FREQUENT/REGULAR/CHURN/NEW) vào customers
  static Future<void> _addSegmentColumnsToCustomers(Database db) async {
    try {
      final columns = await db.rawQuery("PRAGMA table_info(customers)");
      final columnNames = (columns as List<Map>).map((c) => c['name']).toList();

      if (!columnNames.contains('segment')) {
        await db.execute('ALTER TABLE customers ADD COLUMN segment TEXT DEFAULT "REGULAR"');
        debugPrint('✅ Added segment column to customers');
      }

      if (!columnNames.contains('vip_notes')) {
        await db.execute('ALTER TABLE customers ADD COLUMN vip_notes TEXT');
        debugPrint('✅ Added vip_notes column to customers');
      }

      if (!columnNames.contains('loyalty_points')) {
        await db.execute('ALTER TABLE customers ADD COLUMN loyalty_points INTEGER DEFAULT 0');
        debugPrint('✅ Added loyalty_points column to customers');
      }
    } catch (e) {
      debugPrint('⚠️ Migration for customers columns: $e');
    }
  }

  /// Migration 3: Tạo bảng warranty_reminders để track reminder history
  static Future<void> _createWarrantyRemindersTable(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS warranty_reminders(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firestoreId TEXT UNIQUE,
          repairId TEXT NOT NULL,
          customerName TEXT,
          model TEXT,
          warranty_expiry INTEGER,
          daysLeft INTEGER,
          remindedAt INTEGER,
          remindMethod TEXT,
          remindStatus TEXT DEFAULT "sent",
          shopId TEXT,
          createdAt INTEGER,
          updatedAt INTEGER
        )
      ''');
      debugPrint('✅ Created warranty_reminders table');
    } catch (e) {
      // Table có thể đã tồn tại
      debugPrint('ℹ️ warranty_reminders table: $e');
    }
  }
}
