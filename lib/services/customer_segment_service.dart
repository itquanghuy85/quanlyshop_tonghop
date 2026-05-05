import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../data/db_helper.dart';
import 'user_service.dart';

/// Quản lý phân khúc khách hàng: VIP, thường xuyên, cần chăm sóc, mất tích
/// - Tự động phân loại dựa trên tần suất mua + giá trị đơn
/// - Hỗ trợ manual tagging
class CustomerSegmentService {
  static final DBHelper _localDb = DBHelper();

  // Định nghĩa phân khúc
  static const String segmentVip = 'VIP';
  static const String segmentFrequent = 'FREQUENT'; // Thường xuyên
  static const String segmentRegular = 'REGULAR'; // Thường
  static const String segmentChurn = 'CHURN'; // Mất tích (không mua từ 60 ngày)
  static const String segmentNew = 'NEW'; // Mới

  // Tiêu chí phân khúc (có thể tùy chỉnh per shop)
  static const int _vipMinSpend = 10000000; // 10M VND
  static const int _vipMinCount = 5; // Ít nhất 5 giao dịch
  static const int _frequentMinCount = 3; // 3+ giao dịch trong 30 ngày
  static const int _churnDays = 60; // 60 ngày không mua

  /// Tự động phân khúc toàn bộ khách hàng
  /// Chạy mỗi tuần hoặc hàng ngày tối
  static Future<Map<String, int>> autoSegmentCustomers() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return {};

      final db = await _localDb.database;

      // Lấy tất cả khách hàng có giao dịch
      final customers = await db.query(
        'repairs',
        columns: ['customerName', 'phone'],
        distinct: true,
        where: 'shopId = ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [shopId],
      );

      final segments = <String, int>{};

      for (final customer in customers) {
        final name = customer['customerName'] as String?;
        final phone = customer['phone'] as String?;

        if (name == null || phone == null) continue;

        final segment = await _calculateSegment(shopId, name, phone);
        segments[segment] = (segments[segment] ?? 0) + 1;

        // Cập nhật segment trong customers table
        await db.update(
          'customers',
          {'segment': segment},
          where: 'shopId = ? AND (name = ? OR phone = ?)',
          whereArgs: [shopId, name, phone],
        );
      }

      debugPrint('✅ Auto-segmented ${customers.length} customers: $segments');
      return segments;
    } catch (e) {
      debugPrint('❌ Error auto-segmenting customers: $e');
      return {};
    }
  }

  /// Tính toán segment cho một khách hàng
  static Future<String> _calculateSegment(
    String shopId,
    String customerName,
    String phone,
  ) async {
    try {
      final churnDate = DateTime.now()
          .subtract(const Duration(days: _churnDays))
          .millisecondsSinceEpoch;

      final db = await _localDb.database;
      // Tổng doanh thu từ khách này
      final totalSpentResult = await db.rawQuery(
        'SELECT COALESCE(SUM(price), 0) as total FROM repairs WHERE shopId = ? AND (customerName = ? OR phone = ?)',
        [shopId, customerName, phone],
      );
      final totalSpent = Sqflite.firstIntValue(totalSpentResult) ?? 0;

      // Số lần mua
      final purchaseCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM repairs WHERE shopId = ? AND (customerName = ? OR phone = ?)',
        [shopId, customerName, phone],
      );
      final purchaseCount = Sqflite.firstIntValue(purchaseCountResult) ?? 0;

      // Lần mua cuối cùng
      final lastResults = await db.rawQuery(
        'SELECT MAX(COALESCE(deliveredAt, createdAt)) as lastDate FROM repairs WHERE shopId = ? AND (customerName = ? OR phone = ?)',
        [shopId, customerName, phone],
      );
      final lastPurchaseDate = Sqflite.firstIntValue(lastResults) ?? 0;

      // Calculate recent purchases count
      final recentCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM repairs WHERE shopId = ? AND (customerName = ? OR phone = ?) AND createdAt >= ?',
        [shopId, customerName, phone, DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch],
      );
      final recentCount = Sqflite.firstIntValue(recentCountResult) ?? 0;

      // Quyết định segment
      if (totalSpent >= _vipMinSpend && purchaseCount >= _vipMinCount) {
        return segmentVip;
      }
      
      if (lastPurchaseDate == 0 || lastPurchaseDate < churnDate) {
        return segmentChurn;
      }

      if (purchaseCount <= 1) {
        return segmentNew;
      }

      if (recentCount >= _frequentMinCount) {
        return segmentFrequent;
      }

      return segmentRegular;
    } catch (e) {
      debugPrint('❌ Error calculating segment: $e');
      return segmentRegular;
    }
  }

  /// Lấy danh sách khách hàng theo segment
  static Future<List<Map<String, dynamic>>> getCustomersBySegment(String segment) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final db = await _localDb.database;
      return await db.query(
        'customers',
        where: 'shopId = ? AND segment = ?',
        whereArgs: [shopId, segment],
        orderBy: 'totalSpent DESC',
      );
    } catch (e) {
      debugPrint('❌ Error fetching customers: $e');
      return [];
    }
  }

  /// Lấy tóm tắt phân khúc
  static Future<Map<String, int>> getSegmentSummary() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return {};

      final db = await _localDb.database;
      final results = await db.rawQuery(
        'SELECT segment, COUNT(*) as count FROM customers WHERE shopId = ? GROUP BY segment',
        [shopId],
      );

      final summary = <String, int>{};
      for (final row in results) {
        final segment = row['segment'] as String?;
        final count = (row['count'] as num?)?.toInt() ?? 0;
        if (segment != null) summary[segment] = count;
      }
      return summary;
    } catch (e) {
      debugPrint('❌ Error: $e');
      return {};
    }
  }

  /// Đánh dấu khách hàng là VIP
  static Future<void> markCustomerAsVip(String phone) async {
    try {
      final db = await _localDb.database;
      await db.update(
        'customers',
        {'segment': segmentVip},
        where: 'phone = ?',
        whereArgs: [phone],
      );
    } catch (e) {
      debugPrint('❌ Error marking VIP: $e');
    }
  }

  /// Thêm ghi chú VIP
  static Future<void> addVipNote(String phone, String note) async {
    try {
      final db = await _localDb.database;
      await db.update(
        'customers',
        {'vip_notes': note},
        where: 'phone = ?',
        whereArgs: [phone],
      );
    } catch (e) {
      debugPrint('❌ Error adding note: $e');
    }
  }

  /// Khách hàng churn cần chăm sóc lại
  static Future<List<Map<String, dynamic>>> getChurnCustomersForCampaign() async {
    return getCustomersBySegment(segmentChurn);
  }
}
