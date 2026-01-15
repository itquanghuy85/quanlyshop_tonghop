import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import 'user_service.dart';

/// Service ghi nhật ký hoạt động tài chính
/// Tự động gọi khi có các thay đổi tài chính: bán hàng, chi phí, thu nợ, tất toán...
class FinancialActivityService {
  static final DBHelper _db = DBHelper();

  /// Ghi log bán hàng
  static Future<void> logSale({
    required String firestoreId,
    required int totalPrice,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required String productNames,
    required String sellerName,
    int? soldAt,
    bool isInstallment = false,
    int downPayment = 0,
    String? downPaymentMethod,
    String? bankName,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = soldAt ?? DateTime.now().millisecondsSinceEpoch;

      final activity = FinancialActivity.fromSale(
        firestoreId: firestoreId,
        amount: totalPrice,
        paymentMethod: paymentMethod,
        customerName: customerName,
        phone: phone,
        productNames: productNames,
        sellerName: sellerName,
        createdAt: now,
        shopId: shopId,
        isInstallment: isInstallment,
        downPayment: downPayment,
        downPaymentMethod: downPaymentMethod,
        bankName: bankName,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged SALE - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logSale error: $e');
    }
  }

  /// Ghi log chi phí
  static Future<void> logExpense({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String title,
    required String category,
    String? note,
    int? createdAt,
    String? createdBy,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromExpense(
        firestoreId: firestoreId,
        amount: amount,
        paymentMethod: paymentMethod,
        title: title,
        category: category,
        note: note,
        createdAt: now,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged EXPENSE - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logExpense error: $e');
    }
  }

  /// Ghi log nhập hàng
  static Future<void> logPurchase({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String productName,
    required String supplierName,
    required int quantity,
    int? createdAt,
    String? createdBy,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromPurchase(
        firestoreId: firestoreId,
        amount: amount,
        paymentMethod: paymentMethod,
        productName: productName,
        supplierName: supplierName,
        quantity: quantity,
        createdAt: now,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged PURCHASE - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logPurchase error: $e');
    }
  }

  /// Ghi log thu nợ khách hàng
  static Future<void> logDebtCollection({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    int? createdAt,
    String? createdBy,
    String? note,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromDebtCollection(
        firestoreId: firestoreId,
        amount: amount,
        paymentMethod: paymentMethod,
        customerName: customerName,
        phone: phone,
        createdAt: now,
        createdBy: user,
        shopId: shopId,
        note: note,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint(
        '📝 FinancialActivity: Logged DEBT_COLLECT - ${activity.title}',
      );
    } catch (e) {
      debugPrint('❌ FinancialActivity logDebtCollection error: $e');
    }
  }

  /// Ghi log tất toán ngân hàng
  static Future<void> logSettlement({
    required String saleFirestoreId,
    required int amount,
    required String bankName,
    required String customerName,
    required String productNames,
    int? settlementFee,
    int? createdAt,
    String? createdBy,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromSettlement(
        saleFirestoreId: saleFirestoreId,
        amount: amount,
        bankName: bankName,
        customerName: customerName,
        productNames: productNames,
        createdAt: now,
        settlementFee: settlementFee ?? 0,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged SETTLEMENT - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logSettlement error: $e');
    }
  }

  /// Ghi log thanh toán NCC
  static Future<void> logSupplierPayment({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String supplierName,
    int? createdAt,
    String? createdBy,
    String? note,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromSupplierPayment(
        firestoreId: firestoreId,
        amount: amount,
        paymentMethod: paymentMethod,
        supplierName: supplierName,
        createdAt: now,
        note: note,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged DEBT_PAY - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logSupplierPayment error: $e');
    }
  }

  /// Ghi log sửa chữa (thu tiền)
  static Future<void> logRepair({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required String deviceModel,
    int? createdAt,
    String? createdBy,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity.fromRepair(
        firestoreId: firestoreId,
        amount: amount,
        paymentMethod: paymentMethod,
        customerName: customerName,
        phone: phone,
        deviceModel: deviceModel,
        createdAt: now,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged REPAIR - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logRepair error: $e');
    }
  }

  /// Ghi log tùy chỉnh
  static Future<void> logCustomActivity({
    required String activityType,
    required int amount,
    required String direction, // IN, OUT, DEBT
    required String paymentMethod,
    required String title,
    String? description,
    String? customerName,
    String? phone,
    String? productInfo,
    String? referenceType,
    String? referenceId,
    int? createdAt,
    String? createdBy,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
      final user = createdBy ?? await UserService.getCurrentUserName();

      final activity = FinancialActivity(
        activityType: activityType,
        amount: amount,
        direction: direction,
        paymentMethod: paymentMethod,
        title: title,
        description: description,
        customerName: customerName,
        phone: phone,
        productInfo: productInfo,
        referenceType: referenceType,
        referenceId: referenceId,
        createdAt: now,
        createdBy: user,
        shopId: shopId,
      );

      await _db.insertFinancialActivity(activity.toMap());
      debugPrint('📝 FinancialActivity: Logged CUSTOM - ${activity.title}');
    } catch (e) {
      debugPrint('❌ FinancialActivity logCustomActivity error: $e');
    }
  }

  /// Xóa log cũ (tối ưu DB)
  static Future<int> cleanOldLogs({int daysOld = 365}) async {
    try {
      final deleted = await _db.deleteOldFinancialActivities(daysOld);
      debugPrint('🗑️ FinancialActivity: Cleaned $deleted old logs');
      return deleted;
    } catch (e) {
      debugPrint('❌ FinancialActivity cleanOldLogs error: $e');
      return 0;
    }
  }
}
