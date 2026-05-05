import '../data/db_helper.dart';
import 'user_service.dart';
import 'package:flutter/foundation.dart';

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
      await _db.ensureRepairsShopIdBackfilled(preferredShopId: shopId);
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(2000, 1, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác') as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(cost) as totalCost,
          SUM(price) - SUM(cost) as grossProfit,
          ROUND(AVG(price - cost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(cost)) / NULLIF(SUM(price), 0), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND COALESCE(deliveredAt, finishedAt, createdAt) BETWEEN ? AND ?
          AND deleted = 0
          AND status IN (3, 4)
        GROUP BY COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác')
        ORDER BY totalRevenue DESC
        LIMIT ?
      ''';

      debugPrint('[TopServices][revenue][SQL_RAW]\n$query');
      debugPrint('[TopServices][revenue][ARGS] shopId=$shopId startMs=$startMs endMs=$endMs limit=$limit');
      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('[TopServices][revenue][RESULT_COUNT] ${results.length}');
      debugPrint('[TopServices][revenue][RESULT_RAW] $results');
      return results;
    } catch (e) {
      debugPrint('[TopServices][revenue][ERROR] $e');
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
      await _db.ensureRepairsShopIdBackfilled(preferredShopId: shopId);
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(2000, 1, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác') as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(cost) as totalCost,
          SUM(price) - SUM(cost) as grossProfit,
          ROUND(AVG(price - cost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(cost)) / NULLIF(SUM(price), 0), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND COALESCE(deliveredAt, finishedAt, createdAt) BETWEEN ? AND ?
          AND deleted = 0
          AND status IN (3, 4)
        GROUP BY COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác')
        ORDER BY grossProfit DESC
        LIMIT ?
      ''';

      debugPrint('[TopServices][profit][SQL_RAW]\n$query');
      debugPrint('[TopServices][profit][ARGS] shopId=$shopId startMs=$startMs endMs=$endMs limit=$limit');
      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('[TopServices][profit][RESULT_COUNT] ${results.length}');
      debugPrint('[TopServices][profit][RESULT_RAW] $results');
      return results;
    } catch (e) {
      debugPrint('[TopServices][profit][ERROR] $e');
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
      await _db.ensureRepairsShopIdBackfilled(preferredShopId: shopId);
      final db = await _db.database;

      final startMs = (startDate ?? DateTime(2000, 1, 1))
          .millisecondsSinceEpoch;
      final endMs = (endDate ?? DateTime.now()).millisecondsSinceEpoch;

      const query = '''
        SELECT 
          COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác') as serviceName,
          COUNT(*) as count,
          SUM(price) as totalRevenue,
          SUM(cost) as totalCost,
          SUM(price) - SUM(cost) as grossProfit,
          ROUND(AVG(price - cost), 0) as avgProfitPerJob,
          ROUND(100.0 * (SUM(price) - SUM(cost)) / NULLIF(SUM(price), 0), 1) as profitMarginPct
        FROM repairs
        WHERE shopId = ? 
          AND COALESCE(deliveredAt, finishedAt, createdAt) BETWEEN ? AND ?
          AND deleted = 0
          AND status IN (3, 4)
        GROUP BY COALESCE(NULLIF(TRIM(issue), ''), NULLIF(TRIM(services), ''), NULLIF(TRIM(model), ''), 'Khác')
        ORDER BY count DESC
        LIMIT ?
      ''';

      debugPrint('[TopServices][frequency][SQL_RAW]\n$query');
      debugPrint('[TopServices][frequency][ARGS] shopId=$shopId startMs=$startMs endMs=$endMs limit=$limit');
      final results = await db.rawQuery(query, [shopId, startMs, endMs, limit]);
      debugPrint('[TopServices][frequency][RESULT_COUNT] ${results.length}');
      debugPrint('[TopServices][frequency][RESULT_RAW] $results');
      return results;
    } catch (e) {
      debugPrint('[TopServices][frequency][ERROR] $e');
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
      return results;
    } catch (e) {
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
      return [];
    }
  }
}
