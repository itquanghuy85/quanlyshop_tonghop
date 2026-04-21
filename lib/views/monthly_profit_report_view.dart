import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/daily_financial_analysis_service.dart';
import '../services/user_service.dart';
import '../services/category_service.dart';
import '../core/utils/money_utils.dart';
import '../theme/app_colors.dart';
import '../widgets/responsive_wrapper.dart';

/// Monthly profit report — shows revenue, cost, expenses, profit per month
class MonthlyProfitReportView extends StatefulWidget {
  const MonthlyProfitReportView({super.key});

  @override
  State<MonthlyProfitReportView> createState() =>
      _MonthlyProfitReportViewState();
}

class _MonthlyProfitReportViewState extends State<MonthlyProfitReportView> {
  final DBHelper _db = DBHelper();
  bool _isLoading = true;
  int _selectedYear = DateTime.now().year;

  // Monthly data: index 0 = Jan, 11 = Dec
  List<_MonthData> _months = [];

  // Summary
  int _yearRevenue = 0;
  int _yearProfit = 0;
  int _yearTotalIn = 0;
  int _yearTotalOut = 0;
  bool _hasPermission = false;
  bool _canViewCostPrice = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadData();
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _hasPermission = perms['allowViewRevenue'] ?? false;
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final dbConn = await _db.database;
    final shopId = UserService.getShopIdSync();
    final settings = await CategoryService().getShopSettings();
    final enableRepair = settings?.enableRepair ?? true;

    final now = DateTime.now();
    // Determine months to load: all 12 if past year, up to current month if this year
    final monthCount = _selectedYear < now.year ? 12 : now.month;

    final months = <_MonthData>[];
    int yearRevenue = 0, yearProfit = 0, yearTotalIn = 0, yearTotalOut = 0;

    for (int m = 1; m <= monthCount; m++) {
      final startDate = DateTime(_selectedYear, m, 1);
      final endDate = DateTime(_selectedYear, m + 1, 1);
      final startMs = startDate.millisecondsSinceEpoch;
      final endMs = endDate.millisecondsSinceEpoch;

      // Batch query all collections for this month
      final batch = await Future.wait([
        // [0] sales
        dbConn.query(
          'sales',
          columns: [
            'totalPrice',
            'totalCost',
            'discount',
            'paymentMethod',
            'isInstallment',
            'downPayment',
            'downPaymentMethod',
            'settlementReceivedAt',
            'settlementAmount',
            'loanAmount',
            'loanAmount2',
            'soldAt',
          ],
          where: 'soldAt >= ? AND soldAt < ?',
          whereArgs: [startMs, endMs],
        ),
        // [1] settlements
        dbConn.query(
          'sales',
          columns: [
            'totalPrice',
            'totalCost',
            'discount',
            'downPayment',
            'settlementAmount',
            'loanAmount',
            'loanAmount2',
            'soldAt',
          ],
          where:
              'isInstallment = 1 AND settlementReceivedAt IS NOT NULL AND settlementReceivedAt >= ? AND settlementReceivedAt < ?',
          whereArgs: [startMs, endMs],
        ),
        // [2] repairs
        dbConn.query(
          'repairs',
          columns: ['price', 'cost', 'paymentMethod', 'deliveredAt'],
          where:
              'status = 4 AND deliveredAt IS NOT NULL AND deliveredAt >= ? AND deliveredAt < ?',
          whereArgs: [startMs, endMs],
        ),
        // [3] expenses
        dbConn.query(
          'expenses',
          columns: ['amount', 'category', 'type', 'paymentMethod'],
          where: shopId != null && shopId.isNotEmpty
              ? '(date >= ? AND date < ?) AND (shopId = ? OR shopId IS NULL)'
              : 'date >= ? AND date < ?',
          whereArgs: shopId != null && shopId.isNotEmpty
              ? [startMs, endMs, shopId]
              : [startMs, endMs],
        ),
        // [4] debtPayments
        _db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs),
        // [5] supplierPayments
        dbConn.query(
          'supplier_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where:
              'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          whereArgs: [startMs, endMs],
        ),
        // [6] repairPartnerPayments
        dbConn.query(
          'repair_partner_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where:
              'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          whereArgs: [startMs, endMs],
        ),
        // [7] supplierImports
        dbConn.query(
          'supplier_import_history',
          columns: [
            'totalAmount',
            'costPrice',
            'paymentMethod',
            'importDate',
            'createdAt',
          ],
          where:
              '((importDate IS NOT NULL AND importDate >= ? AND importDate < ?) OR (importDate IS NULL AND createdAt >= ? AND createdAt < ?))',
          whereArgs: [startMs, endMs, startMs, endMs],
        ),
        // [8] repairPartsCostFund
        dbConn.query(
          'repairs',
          columns: ['cost', 'costRecordedAmount', 'costPaymentMethod'],
          where:
              'costRecordedInFund = 1 AND costRecordedAt IS NOT NULL AND costRecordedAt >= ? AND costRecordedAt < ?',
          whereArgs: [startMs, endMs],
        ),
        // [9] salesReturns
        dbConn
            .query(
              'sales_returns',
              columns: [
                'totalReturnAmount',
                'totalReturnCost',
                'refundMethod',
                'returnDate',
              ],
              where: 'returnDate >= ? AND returnDate < ? AND status = ?',
              whereArgs: [startMs, endMs, 'APPROVED'],
            )
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final analysis = DailyFinancialAnalysisService.analyze(
        sales: batch[0] as List<Map<String, dynamic>>,
        settlementSales: batch[1] as List<Map<String, dynamic>>,
        repairs: batch[2] as List<Map<String, dynamic>>,
        expenses: batch[3] as List<Map<String, dynamic>>,
        debtPayments: batch[4] as List<Map<String, dynamic>>,
        supplierPayments: batch[5] as List<Map<String, dynamic>>,
        repairPartnerPayments: batch[6] as List<Map<String, dynamic>>,
        supplierImports: batch[7] as List<Map<String, dynamic>>,
        repairPartsCostFundRows: batch[8] as List<Map<String, dynamic>>,
        salesReturns: batch[9] as List<Map<String, dynamic>>,
        enableRepair: enableRepair,
      );

      final revenue =
          analysis.saleIncome +
          analysis.settlementIncome +
          analysis.repairIncome;

      months.add(
        _MonthData(
          month: m,
          revenue: revenue,
          saleCost: analysis.saleCost,
          repairCost: analysis.repairCost,
          expenseOut: analysis.expenseOut,
          netProfit: analysis.netProfit,
          totalIn: analysis.totalIn,
          totalOut: analysis.totalOut,
          saleIncome: analysis.saleIncome,
          settlementIncome: analysis.settlementIncome,
          repairIncome: analysis.repairIncome,
          debtCollected: analysis.debtCollected,
          importOut: analysis.importOut,
          supplierPaid: analysis.supplierPaid,
        ),
      );

      yearRevenue += revenue;
      yearProfit += analysis.netProfit;
      yearTotalIn += analysis.totalIn;
      yearTotalOut += analysis.totalOut;
    }

    if (mounted) {
      setState(() {
        _months = months;
        _yearRevenue = yearRevenue;
        _yearProfit = yearProfit;
        _yearTotalIn = yearTotalIn;
        _yearTotalOut = yearTotalOut;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Báo cáo lợi nhuận'),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo lợi nhuận'),
        centerTitle: true,
        actions: [
          // Year picker
          TextButton.icon(
            onPressed: _pickYear,
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(
              '$_selectedYear',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ResponsiveCenter(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.responsive.horizontalPadding,
                    vertical: 16,
                  ),
                  children: [
                    _buildYearSummary(),
                    const SizedBox(height: 16),
                    _buildBarChart(),
                    const SizedBox(height: 16),
                    _buildMonthlyTable(),
                  ],
                ),
              ),
            ),
    );
  }

  void _pickYear() async {
    final now = DateTime.now();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Chọn năm'),
          content: SizedBox(
            width: 200,
            height: 250,
            child: ListView.builder(
              itemCount: 5,
              itemBuilder: (ctx, i) {
                final year = now.year - i;
                final selected = year == _selectedYear;
                return ListTile(
                  title: Text(
                    '$year',
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, year),
                );
              },
            ),
          ),
        );
      },
    );
    if (picked != null && picked != _selectedYear) {
      _selectedYear = picked;
      _loadData();
    }
  }

  Widget _buildYearSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _yearProfit >= 0
              ? [const Color(0xFF1565C0), const Color(0xFF42A5F5)]
              : [const Color(0xFFc62828), const Color(0xFFef5350)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'TỔNG KẾT NĂM $_selectedYear',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryItem('Doanh thu', _yearRevenue, Colors.white),
              ),
              Expanded(
                child: _summaryItem(
                  'Lợi nhuận',
                  _yearProfit,
                  _yearProfit >= 0 ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _summaryItem('Tổng thu', _yearTotalIn, Colors.white70),
              ),
              Expanded(
                child: _summaryItem('Tổng chi', _yearTotalOut, Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          MoneyUtils.formatCompact(amount),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart() {
    if (_months.isEmpty) return const SizedBox();

    final maxVal = _months.fold<int>(0, (prev, m) {
      final v = m.revenue > m.netProfit.abs() ? m.revenue : m.netProfit.abs();
      return v > prev ? v : prev;
    });
    if (maxVal == 0) return const SizedBox();

    final monthNames = [
      'T1',
      'T2',
      'T3',
      'T4',
      'T5',
      'T6',
      'T7',
      'T8',
      'T9',
      'T10',
      'T11',
      'T12',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.indigo.shade400, size: 18),
              const SizedBox(width: 6),
              Text(
                'BIẾN ĐỘNG THEO THÁNG',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade600,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Legend
          Row(
            children: [
              _legendDot(Colors.blue, 'Doanh thu'),
              const SizedBox(width: 12),
              _legendDot(Colors.green, 'Lợi nhuận'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _months.map((m) {
                final revenueH = maxVal > 0
                    ? (m.revenue / maxVal * 130).clamp(0, 130).toDouble()
                    : 0.0;
                final profitH = maxVal > 0
                    ? (m.netProfit.abs() / maxVal * 130)
                          .clamp(0, 130)
                          .toDouble()
                    : 0.0;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _showMonthDetail(m),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 8,
                                height: revenueH.clamp(0, 120),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade400,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 1),
                              Container(
                                width: 8,
                                height: profitH.clamp(0, 120),
                                decoration: BoxDecoration(
                                  color: m.netProfit >= 0
                                      ? Colors.green.shade400
                                      : Colors.red.shade400,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Month labels row (outside SizedBox to avoid overflow)
          Row(
            children: _months.map((m) {
              return Expanded(
                child: Text(
                  monthNames[m.month - 1],
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildMonthlyTable() {
    final monthNames = [
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: const [
                SizedBox(
                  width: 70,
                  child: Text(
                    'Tháng',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Doanh thu',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Chi phí',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Lợi nhuận',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          // Rows
          ..._months.map((m) {
            final isProfit = m.netProfit >= 0;
            return InkWell(
              onTap: () => _showMonthDetail(m),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: Text(
                        monthNames[m.month - 1],
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        MoneyUtils.formatCompact(m.revenue),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade700,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        MoneyUtils.formatCompact(
                          _canViewCostPrice
                              ? (m.expenseOut + m.saleCost + m.repairCost)
                              : m.expenseOut,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${isProfit ? '+' : ''}${MoneyUtils.formatCompact(m.netProfit)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isProfit
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Total row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 70,
                  child: Text(
                    'TỔNG',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: Text(
                    MoneyUtils.formatCompact(_yearRevenue),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    MoneyUtils.formatCompact(
                      _months.fold<int>(
                        0,
                        (s, m) => s + m.expenseOut + m.saleCost + m.repairCost,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade600,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${_yearProfit >= 0 ? '+' : ''}${MoneyUtils.formatCompact(_yearProfit)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _yearProfit >= 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthDetail(_MonthData m) {
    final monthNames = [
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${monthNames[m.month - 1]} / $_selectedYear',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // THU section
                  _detailSection('📥 THU', Colors.green, [
                    _detailRow('Bán hàng', m.saleIncome),
                    _detailRow('Tất toán NH', m.settlementIncome),
                    _detailRow('Sửa chữa', m.repairIncome),
                    _detailRow('Thu nợ KH', m.debtCollected),
                  ]),
                  const SizedBox(height: 12),
                  // CHI section
                  _detailSection('📤 CHI', Colors.red, [
                    _detailRow('Chi phí', m.expenseOut),
                    _detailRow('Nhập hàng', m.importOut),
                    _detailRow('Trả nợ NCC', m.supplierPaid),
                  ]),
                  const SizedBox(height: 12),
                  // GIÁ VỐN section
                  if (_canViewCostPrice)
                    _detailSection('📦 GIÁ VỐN', Colors.orange, [
                      _detailRow('Giá vốn bán', m.saleCost),
                      _detailRow('Giá vốn SC', m.repairCost),
                    ]),
                  const SizedBox(height: 12),
                  // TỔNG KẾT
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.netProfit >= 0
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: m.netProfit >= 0
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '💰 LỢI NHUẬN RÒNG',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${m.netProfit >= 0 ? '+' : ''}${MoneyUtils.formatCompact(m.netProfit)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: m.netProfit >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Tổng thu',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                MoneyUtils.formatCompact(m.totalIn),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Tổng chi',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                MoneyUtils.formatCompact(m.totalOut),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Quỹ ròng',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                MoneyUtils.formatCompact(
                                  m.totalIn - m.totalOut,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailSection(String title, Color color, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _detailRow(String label, int amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          Text(
            MoneyUtils.formatCompact(amount),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _MonthData {
  final int month;
  final int revenue;
  final int saleCost;
  final int repairCost;
  final int expenseOut;
  final int netProfit;
  final int totalIn;
  final int totalOut;
  final int saleIncome;
  final int settlementIncome;
  final int repairIncome;
  final int debtCollected;
  final int importOut;
  final int supplierPaid;

  const _MonthData({
    required this.month,
    required this.revenue,
    required this.saleCost,
    required this.repairCost,
    required this.expenseOut,
    required this.netProfit,
    required this.totalIn,
    required this.totalOut,
    required this.saleIncome,
    required this.settlementIncome,
    required this.repairIncome,
    required this.debtCollected,
    required this.importOut,
    required this.supplierPaid,
  });
}
