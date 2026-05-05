import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import 'user_service.dart';

/// Báo cáo dịch vụ sửa chữa: Top 10 dịch vụ lãi nhất
/// - Tính toán lợi nhuận gộp từng dịch vụ
/// - Sắp xếp theo doanh thu, số lần thực hiện, lợi nhuận
class TopServicesReportService {
  static final DBHelper _db = DBHelper();

  /// Model cho mỗi dịch vụ trong báo cáo
  static const String tableName = 'repairs';

  /// Top 10 dịch vụ sửa theo doanh thu
  /// Dịch vụ được xác định bằng `issue` (vd: "Thay màn hình", "Thay pin", ...)
  static Future<List<Map<String, dynamic>>> getTopServicesByRevenue({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      // Query: group by issue, tính sum(price), sum(totalCost), count(*)
      const query = '''
        SELECT 
          issue as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(totalCost) as totalCost,
          SUM(price) - SUM(totalCost) as grossProfit,
          ROUND(AVG(price - totalCost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(totalCost)) / SUM(price), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND deliveredAt BETWEEN ? AND ?
          AND deletedAt IS NULL
          AND status = 4
        GROUP BY issue
        ORDER BY totalRevenue DESC
        LIMIT ?
      ''';

      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      
      debugPrint('📊 Top services by revenue: ${results.length} services found');
      return results;
    } catch (e) {
      debugPrint('❌ Error fetching top services by revenue: $e');
      return [];
    }
  }

  /// Top 10 dịch vụ theo lợi nhuận gộp
  static Future<List<Map<String, dynamic>>> getTopServicesByProfit({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          issue as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(totalCost) as totalCost,
          SUM(price) - SUM(totalCost) as grossProfit,
          ROUND(AVG(price - totalCost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(totalCost)) / SUM(price), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND deliveredAt BETWEEN ? AND ?
          AND deletedAt IS NULL
          AND status = 4
        GROUP BY issue
        ORDER BY grossProfit DESC
        LIMIT ?
      ''';

      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('💰 Top services by profit: ${results.length} services found');
      return results;
    } catch (e) {
      debugPrint('❌ Error fetching top services by profit: $e');
      return [];
    }
  }

  /// Top 10 dịch vụ theo số lần thực hiện
  static Future<List<Map<String, dynamic>>> getTopServicesByFrequency({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          issue as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(totalCost) as totalCost,
          SUM(price) - SUM(totalCost) as grossProfit,
          ROUND(AVG(price - totalCost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(totalCost)) / SUM(price), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND deliveredAt BETWEEN ? AND ?
          AND deletedAt IS NULL
          AND status = 4
        GROUP BY issue
        ORDER BY count DESC
        LIMIT ?
      ''';

      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('🔄 Top services by frequency: ${results.length} services found');
      return results;
    } catch (e) {
      debugPrint('❌ Error fetching top services by frequency: $e');
      return [];
    }
  }

  /// Dịch vụ yếu: có lợi nhuận thấp hoặc lỗ
  static Future<List<Map<String, dynamic>>> getLowProfitServices({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 5,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      // Dịch vụ có margin < 20% hoặc loss
      const query = '''
        SELECT 
          issue as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(totalCost) as totalCost,
          SUM(price) - SUM(totalCost) as grossProfit,
          ROUND(AVG(price - totalCost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(totalCost)) / SUM(price), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND deliveredAt BETWEEN ? AND ?
          AND deletedAt IS NULL
          AND status = 4
        GROUP BY issue
        HAVING profitMarginPct < 20
        ORDER BY profitMarginPct ASC
        LIMIT ?
      ''';

      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('⚠️ Low profit services: ${results.length} services found');
      return results;
    } catch (e) {
      debugPrint('❌ Error fetching low profit services: $e');
      return [];
    }
  }

  /// Lấy chi tiết tất cả repair từ một dịch vụ cụ thể
  /// Dùng khi user click vào dịch vụ muốn xem chi tiết
  static Future<List<Map<String, dynamic>>> getServiceDetails(
    String serviceName, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          id, customerName, model, price, totalCost, 
          (price - totalCost) as profit,
          ROUND(100.0 * (price - totalCost) / price, 1) as marginPct,
          deliveredAt, createdBy
        FROM repairs
        WHERE shopId = ? 
          AND issue = ?
          AND deliveredAt BETWEEN ? AND ?
          AND deletedAt IS NULL
          AND status = 4
        ORDER BY deliveredAt DESC
      ''';

      final results = await db.rawQuery(query, [shopId, serviceName, startMs, endMs]);
      return results;
    } catch (e) {
      debugPrint('❌ Error fetching service details: $e');
      return [];
    }
  }
}
