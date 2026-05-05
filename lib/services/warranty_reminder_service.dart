import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import 'notification_service.dart';
import 'user_service.dart';

/// Quản lý nhắc nhở bảo hành sắp hết hạn
/// - Poll hàng ngày để tìm bảo hành gần hết
/// - Gửi FCM + in-app notification
class WarrantyReminderService {
  static final _db = FirebaseFirestore.instance;
  static final DBHelper _localDb = DBHelper();
  static bool _isRunning = false;

  /// Khởi động auto-reminder cho bảo hành
  /// Chạy mỗi ngày lúc 8h sáng + khi user mở app
  static Future<void> startWarrantyReminders() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      debugPrint('🛡️ Warranty reminder service started');
      
      // Chạy ngay khi mở app
      await checkAndNotifyExpiredWarranties();
      
      // Lên lịch chạy lại mỗi 24h
      Future.delayed(const Duration(hours: 24), startWarrantyReminders);
    } catch (e) {
      debugPrint('❌ Warranty reminder error: $e');
      _isRunning = false;
    }
  }

  /// Kiểm tra bảo hành sắp hết trong 7 ngày
  static Future<void> checkAndNotifyExpiredWarranties() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;
      final db = await _localDb.database;

      final now = DateTime.now().millisecondsSinceEpoch;
      final sevenDaysLater =
          DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;

      // Lấy repairs từ local DB có warranty sắp hết
      final repairs = await db.rawQuery(
        'SELECT * FROM repairs WHERE shopId = ? AND warranty_expiry > ? AND warranty_expiry < ? AND status = 4 AND deleted = 0',
        [shopId, now, sevenDaysLater],
      );

      for (final repairData in repairs) {
        final warrantyExpiry = (repairData['warranty_expiry'] as num?)?.toInt() ?? 0;
        final daysLeft = _daysUntilExpiry(warrantyExpiry);

        // Gửi notification nếu còn 7, 3, 1 ngày
        if (daysLeft == 7 || daysLeft == 3 || daysLeft == 1 || daysLeft == 0) {
          await _notifyWarrantyExpiring(repairData, daysLeft);
        }
      }

      debugPrint('✅ Checked ${repairs.length} repairs for warranty expiry');
    } catch (e) {
      debugPrint('❌ Error checking warranties: $e');
    }
  }

  /// Tính số ngày còn lại đến hết bảo hành
  static int _daysUntilExpiry(int warrantyUntilMs) {
    if (warrantyUntilMs == 0) return 999;
    final expiryDate = DateTime.fromMillisecondsSinceEpoch(warrantyUntilMs);
    final today = DateTime.now();
    return expiryDate.difference(today).inDays;
  }

  /// Gửi FCM + in-app notification cho bảo hành sắp hết
  static Future<void> _notifyWarrantyExpiring(
    Map<String, dynamic> repair,
    int daysLeft,
  ) async {
    try {
      final model = (repair['model'] as String?) ?? 'N/A';
      final customerName = (repair['customerName'] as String?) ?? 'Khách hàng';
      final repairId = (repair['firestoreId'] as String?) ?? '';

      const title = '🛡️ Bảo hành sắp hết hạn';
      final message = daysLeft == 0
          ? 'Máy $model của $customerName bảo hành HẾT HẠN HÔM NAY!'
          : 'Máy $model của $customerName bảo hành hết hạn trong $daysLeft ngày';

      await NotificationService.sendCloudNotification(
        title: title,
        body: message,
        type: 'system',
        data: {
          'targetType': 'repair',
          'targetId': repairId,
          'repairId': repairId,
          'daysLeft': daysLeft,
        },
      );

      try {
        await _db.collection('notification_queue').add({
          'title': title,
          'message': message,
          'type': 'warranty_expiring',
          'repairId': repairId,
          'daysLeft': daysLeft,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Failed to queue FCM: $e');
      }

      debugPrint('📢 Warranty reminder sent: $model ($customerName)');
    } catch (e) {
      debugPrint('❌ Error sending warranty notification: $e');
    }
  }

  /// Lấy danh sách bảo hành sắp hết trong N ngày
  /// Dùng để hiển thị dashboard widget
  static Future<List<Map<String, dynamic>>> getUpcomingExpiringWarranties({
    int daysAhead = 30,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      final db = await _localDb.database;

      final now = DateTime.now().millisecondsSinceEpoch;
      final futureDate = DateTime.now()
          .add(Duration(days: daysAhead))
          .millisecondsSinceEpoch;

      final results = await db.rawQuery(
        '''SELECT id, customerName, model, warranty_expiry, phone 
           FROM repairs 
           WHERE shopId = ? AND warranty_expiry > ? AND warranty_expiry < ? 
           AND status = 4 AND deleted = 0
           ORDER BY warranty_expiry ASC
           LIMIT 10''',
        [shopId, now, futureDate],
      );

      return results.map((r) {
        final daysLeft = _daysUntilExpiry((r['warranty_expiry'] as num?)?.toInt() ?? 0);
        return {
          ...r,
          'daysLeft': daysLeft,
          'status': daysLeft <= 1 ? 'expired' : daysLeft <= 7 ? 'urgent' : 'soon',
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Error fetching expiring warranties: $e');
      return [];
    }
  }

  /// Dừng warranty reminder service
  static void stop() {
    _isRunning = false;
    debugPrint('🛑 Warranty reminder service stopped');
  }
}
