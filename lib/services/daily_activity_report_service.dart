import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/shop_settings_model.dart';
import 'category_service.dart';
import 'daily_financial_analysis_service.dart';
import 'debt_summary_service.dart';
import 'user_service.dart';

/// Aggregated daily activity data for the report view.
class DailyActivityReport {
  final DateTime date;
  final DailyFinancialAnalysis financial;
  final ShopSettings shopSettings;

  // Sales
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> salesReturns;
  int get totalSaleOrders => sales.length;
  int get totalSaleRevenue => sales.fold(0, (s, e) {
    final total = (e['totalPrice'] as int?) ?? 0;
    final discount = (e['discount'] as int?) ?? 0;
    return s + total - discount;
  });
  int get totalSaleCost => sales.fold(0, (s, e) => s + ((e['totalCost'] as int?) ?? 0));

  // Repairs
  final List<Map<String, dynamic>> repairsCreated;
  final List<Map<String, dynamic>> repairsDelivered;
  final List<Map<String, dynamic>> allRepairsToday;
  final int pendingRepairs;
  final int pendingApprovals;

  // Inventory
  final List<Map<String, dynamic>> supplierImports;
  int get totalImportValue => supplierImports.fold(0, (s, e) => s + ((e['totalAmount'] as int?) ?? 0));

  // Expenses
  final List<Map<String, dynamic>> expenses;
  List<Map<String, dynamic>> get expensesOnly => expenses.where((e) => (e['type'] ?? 'CHI') == 'CHI').toList();
  List<Map<String, dynamic>> get incomeOnly => expenses.where((e) => e['type'] == 'THU').toList();

  // Debts
  final List<Map<String, dynamic>> debtPayments;
  final List<Map<String, dynamic>> supplierPayments;
  final List<Map<String, dynamic>> partnerPayments;
  final Map<String, int> debtOverview;

  // Staff
  final List<Attendance> attendance;

  // Activity log
  final List<Map<String, dynamic>> auditLogs;

  // Previous closing
  final int previousClosingTotal;

  const DailyActivityReport({
    required this.date,
    required this.financial,
    required this.shopSettings,
    required this.sales,
    required this.salesReturns,
    required this.repairsCreated,
    required this.repairsDelivered,
    required this.allRepairsToday,
    required this.pendingRepairs,
    required this.pendingApprovals,
    required this.supplierImports,
    required this.expenses,
    required this.debtPayments,
    required this.supplierPayments,
    required this.partnerPayments,
    required this.debtOverview,
    required this.attendance,
    required this.auditLogs,
    required this.previousClosingTotal,
  });

  int get totalTransactions =>
      sales.length +
      repairsCreated.length +
      repairsDelivered.length +
      expensesOnly.length +
      incomeOnly.length +
      debtPayments.length +
      supplierImports.length +
      supplierPayments.length +
      partnerPayments.length +
      salesReturns.length;
}

class DailyActivityReportService {
  static final _db = DBHelper();
  static final _debtService = DebtSummaryService();

  /// Load all daily activity data for [date].
  static Future<DailyActivityReport> loadReport(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final startMs = dayStart.millisecondsSinceEpoch;
    final endMs = dayEnd.millisecondsSinceEpoch;
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    // Load shop settings
    final shopId = await UserService.getCurrentShopId() ?? '';
    ShopSettings shopSettings;
    try {
      shopSettings = await CategoryService().getShopSettings() ??
          ShopSettings.electronics(shopId);
    } catch (_) {
      shopSettings = ShopSettings.electronics(shopId);
    }

    final db = await _db.database;

    // shopId filter pattern: (shopId = ? OR shopId IS NULL)
    final hasShop = shopId.isNotEmpty;
    final shopFilter = hasShop ? ' AND (shopId = ? OR shopId IS NULL)' : '';
    final shopArg = hasShop ? [shopId] : <dynamic>[];

    // Batch parallel queries (all return List<Map<String, dynamic>>)
    final results = await Future.wait([
      // 0: Sales today
      db.query('sales', where: 'soldAt >= ? AND soldAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'soldAt DESC'),
      // 1: Settlement sales
      db.query('sales', where: 'settlementReceivedAt >= ? AND settlementReceivedAt < ? AND isInstallment = 1 AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg]),
      // 2: Delivered repairs
      db.query('repairs', where: 'status = 4 AND deliveredAt >= ? AND deliveredAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'deliveredAt DESC'),
      // 3: Created repairs today
      db.query('repairs', where: 'createdAt >= ? AND createdAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'createdAt DESC'),
      // 4: Expenses today
      db.query('expenses', where: 'date >= ? AND date < ?$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'date DESC'),
      // 5: Debt payments
      _db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs),
      // 6: Partner payments
      db.query('repair_partner_payments', where: 'paidAt >= ? AND paidAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'paidAt DESC'),
      // 7: Supplier payments
      db.query('supplier_payments', where: 'paidAt >= ? AND paidAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg], orderBy: 'paidAt DESC'),
      // 8: Supplier imports
      db.query('supplier_import_history', where: '((importDate >= ? AND importDate < ?) OR (createdAt >= ? AND createdAt < ?))$shopFilter', whereArgs: [startMs, endMs, startMs, endMs, ...shopArg], orderBy: 'createdAt DESC'),
      // 9: Repair parts cost fund
      db.query('repairs', where: 'costRecordedInFund = 1 AND costRecordedAt >= ? AND costRecordedAt < ? AND deleted != 1$shopFilter', whereArgs: [startMs, endMs, ...shopArg]),
      // 10: Sales returns
      db.query('sales_returns', where: 'returnDate >= ? AND returnDate < ? AND status = ?$shopFilter', whereArgs: [startMs, endMs, 'APPROVED', ...shopArg], orderBy: 'returnDate DESC'),
      // 11: Pending repairs count
      db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE status IN (1, 2) AND deleted != 1${hasShop ? " AND (shopId = ? OR shopId IS NULL)" : ""}', hasShop ? [shopId] : []),
      // 12: Pending approvals count
      db.rawQuery('SELECT COUNT(*) as cnt FROM repairs WHERE status = 3 AND pendingDeliveryApproval = 1 AND deleted != 1${hasShop ? " AND (shopId = ? OR shopId IS NULL)" : ""}', hasShop ? [shopId] : []),
    ]);

    // Separate queries with different return types
    final attendanceFuture = _db.getAttendanceByDateRange(dateKey, dateKey);
    final prevClosingFuture = _db.getPreviousDayClosing(dateKey);

    final sales = results[0];
    final settlementSales = results[1];
    final deliveredRepairs = results[2];
    final createdRepairs = results[3];
    final expenses = results[4];
    final debtPayments = results[5];
    final partnerPayments = results[6];
    final supplierPayments = results[7];
    final supplierImports = results[8];
    final repairPartsCostFund = results[9];
    final salesReturns = results[10];
    final pendingRepairs = results[11].first['cnt'] as int? ?? 0;
    final pendingApprovals = results[12].first['cnt'] as int? ?? 0;
    final attendance = await attendanceFuture;
    final prevClosing = await prevClosingFuture;

    // Only show delivered repairs (status 4) in daily report
    final allRepairsToday = List<Map<String, dynamic>>.from(deliveredRepairs)
      ..sort((a, b) {
        final ta = (a['deliveredAt'] as int?) ?? 0;
        final tb = (b['deliveredAt'] as int?) ?? 0;
        return tb.compareTo(ta); // newest first
      });

    // Audit logs for the day
    List<Map<String, dynamic>> auditLogs = [];
    try {
      auditLogs = await _db.getFinancialActivities(
        startDate: startMs,
        endDate: endMs,
        limit: 200,
      );
    } catch (e) {
      debugPrint('DailyActivityReport: audit log error: $e');
    }

    // Previous closing balance
    int prevClosingTotal = 0;
    if (prevClosing != null) {
      prevClosingTotal = ((prevClosing['cashEnd'] as int?) ?? 0) +
          ((prevClosing['bankEnd'] as int?) ?? 0);
    }

    // Debt overview
    Map<String, int> debtOverview = {};
    try {
      debtOverview = await _debtService.getDebtOverview();
    } catch (e) {
      debugPrint('DailyActivityReport: debt overview error: $e');
    }

    // Financial analysis
    final financial = DailyFinancialAnalysisService.analyze(
      sales: sales,
      settlementSales: settlementSales,
      repairs: deliveredRepairs,
      expenses: expenses,
      debtPayments: debtPayments,
      supplierPayments: supplierPayments,
      repairPartnerPayments: partnerPayments,
      supplierImports: supplierImports,
      repairPartsCostFundRows: repairPartsCostFund,
      salesReturns: salesReturns,
      enableRepair: shopSettings.enableRepair,
    );

    return DailyActivityReport(
      date: date,
      financial: financial,
      shopSettings: shopSettings,
      sales: sales,
      salesReturns: salesReturns,
      repairsCreated: createdRepairs,
      repairsDelivered: deliveredRepairs,
      allRepairsToday: allRepairsToday,
      pendingRepairs: pendingRepairs,
      pendingApprovals: pendingApprovals,
      supplierImports: supplierImports,
      expenses: expenses,
      debtPayments: debtPayments,
      supplierPayments: supplierPayments,
      partnerPayments: partnerPayments,
      debtOverview: debtOverview,
      attendance: attendance,
      auditLogs: auditLogs,
      previousClosingTotal: prevClosingTotal,
    );
  }
}
