import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import 'user_service.dart';

/// Quản lý phân khúc khách hàng: VIP, thường xuyên, cần chăm sóc, mất tích
/// - Tự động phân loại dựa trên tần suất mua + giá trị đơn
/// - Hỗ trợ manual tagging
class CustomerSegmentService {
  static final _db = FirebaseFirestore.instance;
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

      // Lấy tất cả khách hàng có giao dịch
      final customers = await _localDb.rawQuery(
        'SELECT DISTINCT customerName, phone FROM repairs WHERE shopId = ? AND deletedAt IS NULL',
        [shopId],
      );

      final segments = <String, int>{};

      for (final customer in customers) {
        final name = customer['customerName'] as String;
        final phone = customer['phone'] as String;

        final segment = await _calculateSegment(shopId, name, phone);
        segments[segment] = (segments[segment] ?? 0) + 1;

        // Cập nhật segment trong customers table
        await _localDb.rawUpdate(
          'UPDATE customers SET segment = ? WHERE shopId = ? AND (name = ? OR phone = ?)',
          [segment, shopId, name, phone],
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
      final now = DateTime.now().millisecondsSinceEpoch;
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final churnDate = DateTime.now().subtract(Duration(days: _churnDays)).millisecondsSinceEpoch;

      // Tổng doanh thu từ khách này
      final totalSpentResult = await _localDb.rawQuery(
        '''SELECT COALESCE(SUM(price), 0) as total FROM repairs 
           WHERE shopId = ? AND (customerName = ? OR phone = ?) AND deletedAt IS NULL''',
        [shopId, customerName, phone],
      );
      final totalSpent = (totalSpentResult.first['total'] as int?) ?? 0;

      // Số lần mua
      final purchaseCountResult = await _localDb.rawQuery(
        '''SELECT COUNT(*) as count FROM repairs 
           WHERE shopId = ? AND (customerName = ? OR phone = ?) AND deletedAt IS NULL''',
        [shopId, customerName, phone],
      );
      final purchaseCount = (purchaseCountResult.first['count'] as int?) ?? 0;

      // Số lần mua trong 30 ngày
      final recentCountResult = await _localDb.rawQuery(
        '''SELECT COUNT(*) as count FROM repairs 
           WHERE shopId = ? AND (customerName = ? OR phone = ?) 
           AND deliveredAt >= ? AND deletedAt IS NULL''',
        [shopId, customerName, phone, thirtyDaysAgo],
      );
      final recentCount = (recentCountResult.first['count'] as int?) ?? 0;

      // Lần mua cuối cùng
      final lastPurchaseResult = await _localDb.rawQuery(
        '''SELECT MAX(deliveredAt) as lastDate FROM repairs 
           WHERE shopId = ? AND (customerName = ? OR phone = ?) AND deletedAt IS NULL''',
        [shopId, customerName, phone],
      );
      final lastPurchaseDate = (lastPurchaseResult.first['lastDate'] as int?) ?? 0;

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

      final results = await _localDb.rawQuery(
        '''SELECT id, name, phone, email, totalSpent, totalRepairs, lastVisitAt, segment 
           FROM customers 
           WHERE shopId = ? AND segment = ? AND deletedAt IS NULL
           ORDER BY totalSpent DESC''',
        [shopId, segment],
      );

      return results;
    } catch (e) {
      debugPrint('❌ Error fetching customers by segment: $e');
      return [];
    }
  }

  /// Lấy tóm tắt phân khúc
  static Future<Map<String, int>> getSegmentSummary() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return {};

      final results = await _localDb.rawQuery(
        '''SELECT segment, COUNT(*) as count FROM customers 
           WHERE shopId = ? AND deletedAt IS NULL GROUP BY segment''',
        [shopId],
      );

      final summary = <String, int>{};
      for (final row in results) {
        summary[row['segment'] as String] = row['count'] as int;
      }

      return summary;
    } catch (e) {
      debugPrint('❌ Error fetching segment summary: $e');
      return {};
    }
  }

  /// Đánh dấu khách hàng là VIP (manual override)
  static Future<bool> markCustomerAsVip(String phone) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return false;

      await _localDb.rawUpdate(
        'UPDATE customers SET segment = ? WHERE shopId = ? AND phone = ?',
        [segmentVip, shopId, phone],
      );

      debugPrint('✅ Marked $phone as VIP');
      return true;
    } catch (e) {
      debugPrint('❌ Error marking VIP: $e');
      return false;
    }
  }

  /// Ghi chú riêng cho khách hàng VIP
  static Future<bool> addVipNote(String phone, String note) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return false;

      await _localDb.rawUpdate(
        'UPDATE customers SET vipNotes = ? WHERE shopId = ? AND phone = ?',
        [note, shopId, phone],
      );

      debugPrint('✅ Added VIP note for $phone');
      return true;
    } catch (e) {
      debugPrint('❌ Error adding VIP note: $e');
      return false;
    }
  }

  /// Khách hàng churn cần chăm sóc lại
  static Future<List<Map<String, dynamic>>> getChurnCustomersForCampaign({
    int limit = 20,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final results = await _localDb.rawQuery(
        '''SELECT id, name, phone, email, lastVisitAt, totalSpent 
           FROM customers 
           WHERE shopId = ? AND segment = ? AND deletedAt IS NULL
           ORDER BY lastVisitAt ASC
           LIMIT ?''',
        [shopId, segmentChurn, limit],
      );

      return results;
    } catch (e) {
      debugPrint('❌ Error fetching churn customers: $e');
      return [];
    }
  }
}
