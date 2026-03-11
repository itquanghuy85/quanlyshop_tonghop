import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../data/db_helper.dart';
import '../models/payment_request_model.dart';
import 'user_service.dart';
import 'stock_entry_service.dart';

/// Category cho mỗi loại nhắc nhở
enum ReminderCategory {
  repairApproval,    // Duyệt giao máy sửa
  repairAssignment,  // Máy cần sửa (thợ)  
  deliveryTask,      // Giao máy cho khách (nhân viên)
  activeDebt,        // Công nợ chưa thu/trả
  pendingStock,      // Hàng chờ xác nhận nhập kho
  pendingPurchase,   // Đơn nhập chờ duyệt
  salesReturn,       // Đơn trả hàng chờ duyệt
  paymentRequest,    // Yêu cầu đóng tiền chờ duyệt
  paymentIntent,     // Lệnh chi chờ thực hiện
}

/// Độ ưu tiên
enum ReminderPriority { urgent, high, normal }

/// Model cho 1 nhóm task nhắc nhở
class TaskReminder {
  final ReminderCategory category;
  final ReminderPriority priority;
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;
  /// Tổng giá trị tiền (nếu có) — dùng cho debt/payment
  final int? totalAmount;

  const TaskReminder({
    required this.category,
    required this.priority,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
    this.totalAmount,
  });
}

/// Service tổng hợp tất cả task cần nhắc nhở theo role & permission
class ReminderService {
  static final DBHelper _db = DBHelper();

  /// Load tất cả reminder theo role và permission hiện tại.
  /// Returns danh sách đã sort theo priority.
  static Future<List<TaskReminder>> loadReminders({
    required String role,
    required Map<String, bool> permissions,
  }) async {
    final reminders = <TaskReminder>[];
    final isOwnerOrManager = _isOwnerOrManager(role);
    final isTechnician = role == 'technician';
    final canViewRepairs = isOwnerOrManager || permissions['allowViewRepairs'] == true;
    final canViewSales = isOwnerOrManager || permissions['allowViewSales'] == true;
    final canViewInventory = isOwnerOrManager || permissions['allowViewInventory'] == true;
    final canViewDebts = isOwnerOrManager || permissions['allowViewDebts'] == true;

    // Parallel load tất cả data sources
    final futures = <String, Future>{};

    if (canViewRepairs) {
      futures['repairApproval'] = _countPendingApproval();
      futures['repairNeedWork'] = _countRepairsNeedWork();
      futures['repairDone'] = _countRepairsDoneForDelivery();
    }
    if (isTechnician) {
      futures['technicianRepairs'] = _countTechnicianRepairs();
    }
    if (canViewDebts) {
      futures['debts'] = _loadActiveDebts();
    }
    if (canViewInventory) {
      futures['pendingStock'] = _countPendingStock();
      futures['pendingPurchase'] = _countPendingPurchaseOrders();
    }
    if (canViewSales) {
      futures['salesReturn'] = _countPendingSalesReturns();
    }
    if (isOwnerOrManager) {
      futures['paymentRequest'] = _countPendingPaymentRequests();
      futures['paymentIntent'] = _countPendingPaymentIntents();
    }

    // Await all
    final results = <String, dynamic>{};
    final keys = futures.keys.toList();
    final values = await Future.wait(futures.values);
    for (var i = 0; i < keys.length; i++) {
      results[keys[i]] = values[i];
    }

    // Build reminders from results
    // 1. Repair Approval (owner/manager)
    if (results.containsKey('repairApproval')) {
      final count = results['repairApproval'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.repairApproval,
          priority: ReminderPriority.urgent,
          title: 'Chờ duyệt giao máy',
          subtitle: '$count đơn sửa xong chờ duyệt giao',
          count: count,
          icon: Icons.approval_rounded,
          color: const Color(0xFFE65100),
        ));
      }
    }

    // 2. Payment Requests (owner/manager)
    if (results.containsKey('paymentRequest')) {
      final count = results['paymentRequest'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.paymentRequest,
          priority: ReminderPriority.urgent,
          title: 'Yêu cầu đóng tiền',
          subtitle: '$count yêu cầu chờ xử lý',
          count: count,
          icon: Icons.payment_rounded,
          color: const Color(0xFFC62828),
        ));
      }
    }

    // 3. Technician repairs
    if (results.containsKey('technicianRepairs')) {
      final count = results['technicianRepairs'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.repairAssignment,
          priority: ReminderPriority.urgent,
          title: 'Máy cần sửa',
          subtitle: '$count máy đang chờ bạn sửa',
          count: count,
          icon: Icons.build_circle_rounded,
          color: const Color(0xFF1565C0),
        ));
      }
    }

    // 4. Repairs need work (received, not started)
    if (results.containsKey('repairNeedWork')) {
      final count = results['repairNeedWork'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.repairAssignment,
          priority: ReminderPriority.high,
          title: 'Máy chờ sửa',
          subtitle: '$count máy nhận vào chưa sửa',
          count: count,
          icon: Icons.phone_android_rounded,
          color: const Color(0xFF1976D2),
        ));
      }
    }

    // 5. Repairs done - ready for delivery (employee)
    if (results.containsKey('repairDone')) {
      final count = results['repairDone'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.deliveryTask,
          priority: ReminderPriority.high,
          title: 'Giao máy cho khách',
          subtitle: '$count máy sửa xong chờ giao',
          count: count,
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF2E7D32),
        ));
      }
    }

    // 6. Active debts
    if (results.containsKey('debts')) {
      final debtInfo = results['debts'] as _DebtSummary;
      if (debtInfo.customerOwes > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.activeDebt,
          priority: ReminderPriority.high,
          title: 'Công nợ khách hàng',
          subtitle: '${debtInfo.customerOwesCount} khách còn nợ',
          count: debtInfo.customerOwesCount,
          icon: Icons.person_pin_rounded,
          color: const Color(0xFFE65100),
          totalAmount: debtInfo.customerOwes,
        ));
      }
      if (debtInfo.shopOwes > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.activeDebt,
          priority: ReminderPriority.high,
          title: 'Shop nợ NCC',
          subtitle: '${debtInfo.shopOwesCount} khoản chưa trả',
          count: debtInfo.shopOwesCount,
          icon: Icons.store_rounded,
          color: const Color(0xFFF57C00),
          totalAmount: debtInfo.shopOwes,
        ));
      }
    }

    // 7. Sales Returns pending
    if (results.containsKey('salesReturn')) {
      final count = results['salesReturn'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.salesReturn,
          priority: ReminderPriority.normal,
          title: 'Trả hàng chờ duyệt',
          subtitle: '$count đơn trả hàng chờ xác nhận',
          count: count,
          icon: Icons.assignment_return_rounded,
          color: const Color(0xFF7B1FA2),
        ));
      }
    }

    // 8. Pending stock (nhập kho chờ xác nhận)
    if (results.containsKey('pendingStock')) {
      final count = results['pendingStock'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.pendingStock,
          priority: ReminderPriority.normal,
          title: 'Nhập kho chờ xác nhận',
          subtitle: '$count phiếu nhập hàng chờ duyệt',
          count: count,
          icon: Icons.inventory_2_rounded,
          color: const Color(0xFF00838F),
        ));
      }
    }

    // 9. Pending purchase orders
    if (results.containsKey('pendingPurchase')) {
      final count = results['pendingPurchase'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.pendingPurchase,
          priority: ReminderPriority.normal,
          title: 'Đơn nhập chờ duyệt',
          subtitle: '$count đơn hàng nhập chờ xác nhận',
          count: count,
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF4527A0),
        ));
      }
    }

    // 10. Payment intents
    if (results.containsKey('paymentIntent')) {
      final count = results['paymentIntent'] as int;
      if (count > 0) {
        reminders.add(TaskReminder(
          category: ReminderCategory.paymentIntent,
          priority: ReminderPriority.normal,
          title: 'Lệnh chi chờ thực hiện',
          subtitle: '$count lệnh chi/thu chưa hoàn thành',
          count: count,
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF558B2F),
        ));
      }
    }

    // Sort: urgent → high → normal, then by count desc
    reminders.sort((a, b) {
      final priComp = a.priority.index.compareTo(b.priority.index);
      if (priComp != 0) return priComp;
      return b.count.compareTo(a.count);
    });

    return reminders;
  }

  /// Total badge count cho icon nhắc nhở trên Home
  static Future<int> getTotalReminderCount({
    required String role,
    required Map<String, bool> permissions,
  }) async {
    final reminders = await loadReminders(role: role, permissions: permissions);
    return reminders.fold<int>(0, (total, r) => total + r.count);
  }

  // ============ PRIVATE QUERY HELPERS ============

  static bool _isOwnerOrManager(String role) =>
      role == 'owner' || role == 'manager' || role == 'admin' ||
      UserService.isCurrentUserSuperAdmin();

  /// Đếm đơn sửa chờ duyệt giao (status=3, pendingDeliveryApproval=1)
  static Future<int> _countPendingApproval() async {
    try {
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = 'status = 3 AND pendingDeliveryApproval = 1 AND (deleted = 0 OR deleted IS NULL)';
      List<dynamic> args = [];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countPendingApproval error: $e');
      return 0;
    }
  }

  /// Đếm máy nhận vào chưa sửa (status=1)
  static Future<int> _countRepairsNeedWork() async {
    try {
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = 'status = 1 AND (deleted = 0 OR deleted IS NULL)';
      List<dynamic> args = [];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countRepairsNeedWork error: $e');
      return 0;
    }
  }

  /// Đếm máy sửa xong chờ giao (status=3, pendingDeliveryApproval != 1 hoặc null)
  static Future<int> _countRepairsDoneForDelivery() async {
    try {
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = 'status = 3 AND (pendingDeliveryApproval = 0 OR pendingDeliveryApproval IS NULL) AND (deleted = 0 OR deleted IS NULL)';
      List<dynamic> args = [];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countRepairsDoneForDelivery error: $e');
      return 0;
    }
  }

  /// Đếm máy được assign cho thợ hiện tại (status 1 or 2, repairedBy = current uid)
  static Future<int> _countTechnicianRepairs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 0;
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = 'status IN (1, 2) AND repairedBy = ? AND (deleted = 0 OR deleted IS NULL)';
      List<dynamic> args = [uid];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countTechnicianRepairs error: $e');
      return 0;
    }
  }

  /// Load tổng hợp công nợ active
  static Future<_DebtSummary> _loadActiveDebts() async {
    try {
      final allDebts = await _db.getAllDebts();
      int customerOwes = 0, customerOwesCount = 0;
      int shopOwes = 0, shopOwesCount = 0;

      for (final d in allDebts) {
        final status = (d['status'] ?? '').toString().toUpperCase();
        if (status == 'PAID' || status == 'CANCELLED') continue;

        final total = (d['totalAmount'] as num?)?.toInt() ?? 0;
        final paid = (d['paidAmount'] as num?)?.toInt() ?? 0;
        final remain = total - paid;
        if (remain <= 0) continue;

        final type = (d['type'] ?? '').toString().toUpperCase();
        if (type == 'CUSTOMER_OWES' || type == 'OTHER_CUSTOMER_OWES' || type == 'OWE') {
          customerOwes += remain;
          customerOwesCount++;
        } else if (type == 'SHOP_OWES' || type == 'OTHER_SHOP_OWES' || type == 'OWED') {
          shopOwes += remain;
          shopOwesCount++;
        }
      }
      return _DebtSummary(
        customerOwes: customerOwes,
        customerOwesCount: customerOwesCount,
        shopOwes: shopOwes,
        shopOwesCount: shopOwesCount,
      );
    } catch (e) {
      debugPrint('ReminderService._loadActiveDebts error: $e');
      return const _DebtSummary();
    }
  }

  /// Đếm phiếu nhập kho draft (chờ xác nhận) — Firestore
  static Future<int> _countPendingStock() async {
    try {
      return await StockEntryService().getPendingCount();
    } catch (e) {
      debugPrint('ReminderService._countPendingStock error: $e');
      return 0;
    }
  }

  /// Đếm đơn nhập hàng PENDING trong SQLite
  static Future<int> _countPendingPurchaseOrders() async {
    try {
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = "status = 'PENDING' AND (deleted = 0 OR deleted IS NULL)";
      List<dynamic> args = [];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_orders WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countPendingPurchaseOrders error: $e');
      return 0;
    }
  }

  /// Đếm đơn trả hàng PENDING trong SQLite
  static Future<int> _countPendingSalesReturns() async {
    try {
      final db = await _db.database;
      final shopId = UserService.getShopIdSync();
      String where = "status = 'PENDING' AND (deleted = 0 OR deleted IS NULL)";
      List<dynamic> args = [];
      if (shopId != null && shopId.isNotEmpty) {
        where += ' AND (shopId = ? OR shopId IS NULL)';
        args.add(shopId);
      }
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_returns WHERE $where', args);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countPendingSalesReturns error: $e');
      return 0;
    }
  }

  /// Đếm yêu cầu đóng tiền pending — Firestore real-time
  static Future<int> _countPendingPaymentRequests() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;
      final snap = await FirebaseFirestore.instance
          .collection('payment_requests')
          .where('shopId', isEqualTo: shopId)
          .where('deleted', isEqualTo: false)
          .where('status', isEqualTo: PaymentRequestStatus.pending.name)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint('ReminderService._countPendingPaymentRequests error: $e');
      return 0;
    }
  }

  /// Đếm Payment Intent PENDING trong SQLite
  static Future<int> _countPendingPaymentIntents() async {
    try {
      final list = await _db.getPendingPaymentIntents();
      return list.length;
    } catch (e) {
      debugPrint('ReminderService._countPendingPaymentIntents error: $e');
      return 0;
    }
  }
}

/// Internal DTO cho debt summary
class _DebtSummary {
  final int customerOwes;
  final int customerOwesCount;
  final int shopOwes;
  final int shopOwesCount;

  const _DebtSummary({
    this.customerOwes = 0,
    this.customerOwesCount = 0,
    this.shopOwes = 0,
    this.shopOwesCount = 0,
  });
}
