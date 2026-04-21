import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import '../services/daily_activity_report_service.dart';
import '../utils/money_utils.dart';
import '../utils/excel_export_helper.dart';
import '../services/unified_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../services/label_settings_service.dart';
import '../theme/app_colors.dart';

class DailyActivityReportView extends StatefulWidget {
  const DailyActivityReportView({super.key});

  @override
  State<DailyActivityReportView> createState() =>
      _DailyActivityReportViewState();
}

class _DailyActivityReportViewState extends State<DailyActivityReportView> {
  DateTime _selectedDate = DateTime.now();
  DailyActivityReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await DailyActivityReportService.loadReport(_selectedDate);
      if (mounted) {
        setState(() {
          _report = report;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi tải dữ liệu: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null && picked != _selectedDate) {
      _selectedDate = picked;
      _loadReport();
    }
  }

  void _goToPreviousDay() {
    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    _loadReport();
  }

  void _goToNextDay() {
    final now = DateTime.now();
    final nextDay = _selectedDate.add(const Duration(days: 1));
    if (nextDay.isBefore(DateTime(now.year, now.month, now.day + 1))) {
      _selectedDate = nextDay;
      _loadReport();
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo hoạt động ngày'),
        actions: [
          if (_report != null) ...[
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'In báo cáo',
              onPressed: _printReport,
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Xuất Excel',
              onPressed: _exportExcel,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: AppColors.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadReport,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(onRefresh: _loadReport, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final dayLabel = _isToday
        ? 'Hôm nay'
        : DateFormat('EEEE', 'vi').format(_selectedDate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _goToPreviousDay,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    dayLabel,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : _goToNextDay,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final r = _report!;
    final enableRepair = r.shopSettings.enableRepair;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummaryCards(r),
        const SizedBox(height: 12),
        _buildCashFlowSection(r),
        const SizedBox(height: 8),
        _buildSalesSection(r),
        if (enableRepair) ...[
          const SizedBox(height: 8),
          _buildRepairsSection(r),
        ],
        const SizedBox(height: 8),
        _buildExpensesSection(r),
        const SizedBox(height: 8),
        _buildImportsSection(r),
        const SizedBox(height: 8),
        _buildDebtsSection(r),
        const SizedBox(height: 8),
        _buildStaffSection(r),
        const SizedBox(height: 8),
        _buildActivityLogSection(r),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== SUMMARY CARDS ====================
  Widget _buildSummaryCards(DailyActivityReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TỔNG QUAN',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _summaryCard(
              'Doanh thu',
              MoneyUtils.formatCompactCurrency(r.financial.totalIn),
              Icons.trending_up,
              AppColors.success,
            ),
            const SizedBox(width: 8),
            _summaryCard(
              'Chi phí',
              MoneyUtils.formatCompactCurrency(r.financial.totalOut),
              Icons.trending_down,
              AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _summaryCard(
              'Lợi nhuận',
              MoneyUtils.formatCompactCurrency(r.financial.netProfit),
              Icons.account_balance_wallet,
              r.financial.netProfit >= 0 ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 8),
            _summaryCard(
              'Giao dịch',
              '${r.totalTransactions}',
              Icons.receipt_long,
              AppColors.info,
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CASH FLOW ====================
  Widget _buildCashFlowSection(DailyActivityReport r) {
    final f = r.financial;
    return _sectionCard(
      title: 'Luồng tiền',
      icon: Icons.swap_horiz,
      color: AppColors.info,
      trailing: Text(
        'Lãi: ${MoneyUtils.formatCompactCurrency(f.netProfit)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: f.netProfit >= 0 ? AppColors.success : AppColors.error,
        ),
      ),
      child: Column(
        children: [
          if (r.previousClosingTotal > 0)
            _cashFlowRow(
              'Đầu ngày (tồn quỹ)',
              r.previousClosingTotal,
              Colors.blueGrey,
            ),
          _cashFlowRow('Bán hàng', f.saleIncome, AppColors.success),
          if (f.settlementIncome > 0)
            _cashFlowRow(
              'Thu tất toán trả góp',
              f.settlementIncome,
              AppColors.success,
            ),
          if (r.shopSettings.enableRepair && f.repairIncome > 0)
            _cashFlowRow('Sửa chữa', f.repairIncome, AppColors.success),
          if (f.debtCollected > 0)
            _cashFlowRow('Thu nợ', f.debtCollected, AppColors.success),
          if (f.miscIncome > 0)
            _cashFlowRow('Thu khác', f.miscIncome, AppColors.success),
          const Divider(height: 16),
          if (f.expenseOut > 0)
            _cashFlowRow('Chi phí', -f.expenseOut, AppColors.error),
          if (f.importOut > 0)
            _cashFlowRow('Nhập hàng', -f.importOut, AppColors.error),
          if (f.supplierPaid > 0)
            _cashFlowRow('Trả NCC', -f.supplierPaid, AppColors.error),
          if (r.shopSettings.enableRepair && f.partnerPaid > 0)
            _cashFlowRow('Trả ĐT sửa chữa', -f.partnerPaid, AppColors.error),
          if (f.saleCost > 0)
            _cashFlowRow('Giá vốn bán hàng', -f.saleCost, AppColors.error),
          if (r.shopSettings.enableRepair && f.repairCost > 0)
            _cashFlowRow('Giá vốn sửa chữa', -f.repairCost, AppColors.error),
          if (f.refundOut > 0)
            _cashFlowRow('Hoàn trả', -f.refundOut, AppColors.error),
        ],
      ),
    );
  }

  Widget _cashFlowRow(String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            '${amount >= 0 ? '+' : ''}${MoneyUtils.formatCompactCurrency(amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SALES ====================
  Widget _buildSalesSection(DailyActivityReport r) {
    final sales = r.sales;
    final returns = r.salesReturns;
    final saleProfit = r.totalSaleRevenue - r.totalSaleCost;
    return _sectionCard(
      title: 'Bán hàng (${sales.length})',
      icon: Icons.shopping_cart,
      color: AppColors.success,
      trailing: Text(
        '${MoneyUtils.formatCompactCurrency(r.totalSaleRevenue)}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.success,
        ),
      ),
      child: Column(
        children: [
          if (sales.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vốn: ${MoneyUtils.formatCompactCurrency(r.totalSaleCost)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Text(
                    'Lãi: ${MoneyUtils.formatCompactCurrency(saleProfit)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: saleProfit >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
          ],
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có đơn bán hàng',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            ...sales.take(20).map((s) => _saleRow(s)),
            if (sales.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... và ${sales.length - 20} đơn khác',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
          ],
          if (returns.isNotEmpty) ...[
            const Divider(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Trả hàng (${returns.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...returns.take(10).map((r) => _returnRow(r)),
          ],
        ],
      ),
    );
  }

  Widget _saleRow(Map<String, dynamic> s) {
    final totalPrice = (s['totalPrice'] as int?) ?? 0;
    final discount = (s['discount'] as int?) ?? 0;
    final amount = totalPrice - discount;
    final cost = (s['totalCost'] as int?) ?? 0;
    final profit = amount - cost;
    final customerName = s['customerName'] ?? 'Khách lẻ';
    final productNames = s['productNames'] ?? '';
    final time = _fmtTime(s['soldAt'] as int?);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              time,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                if (productNames.isNotEmpty)
                  Text(
                    productNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                if (profit != 0)
                  Text(
                    'Lãi: ${MoneyUtils.formatCompactCurrency(profit)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: profit >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${MoneyUtils.formatCompactCurrency(amount)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _returnRow(Map<String, dynamic> r) {
    final amount = (r['refundAmount'] as int?) ?? 0;
    final reason = r['reason'] ?? '';
    final time = _fmtTime(r['returnDate'] as int?);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              time,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              reason.isNotEmpty ? reason : 'Trả hàng',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            '-${MoneyUtils.formatCompactCurrency(amount)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== REPAIRS ====================
  Widget _buildRepairsSection(DailyActivityReport r) {
    final repairs = r.repairsDelivered;
    final deliveredCount = r.repairsDelivered.length;
    // Compute delivered repair totals
    final deliveredRevenue = r.repairsDelivered.fold<int>(
      0,
      (s, e) => s + ((e['price'] as int?) ?? 0),
    );
    final deliveredCost = r.repairsDelivered.fold<int>(
      0,
      (s, e) => s + ((e['cost'] as int?) ?? 0),
    );
    final deliveredProfit = deliveredRevenue - deliveredCost;
    return _sectionCard(
      title: 'Sửa chữa đã giao ($deliveredCount)',
      icon: Icons.build,
      color: AppColors.secondary,
      trailing: r.pendingRepairs > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${r.pendingRepairs} chờ',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            )
          : null,
      child: Column(
        children: [
          if (deliveredCount > 0) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'DT giao: ${MoneyUtils.formatCompactCurrency(deliveredRevenue)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Text(
                    'Lãi: ${MoneyUtils.formatCompactCurrency(deliveredProfit)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: deliveredProfit >= 0
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
          ],
          if (repairs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có đơn sửa chữa',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            ...repairs.take(30).map((re) => _repairRow(re)),
            if (repairs.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... và ${repairs.length - 30} đơn khác',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
          ],
          if (r.pendingApprovals > 0) ...[
            const Divider(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  '${r.pendingApprovals} đơn chờ duyệt giao',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _repairRow(Map<String, dynamic> re) {
    final status = (re['status'] as int?) ?? 1;
    final statusLabel = _repairStatusLabel(status);
    final statusColor = _repairStatusColor(status);
    final customer = re['customerName'] ?? 'N/A';
    final device = re['model'] ?? '';
    final issue = re['issue'] ?? '';
    final price = (re['price'] as int?) ?? 0;
    final cost = (re['cost'] as int?) ?? 0;
    final profit = price - cost;
    final createdAt = re['createdAt'] as int?;
    final deliveredAt = re['deliveredAt'] as int?;
    final time = _fmtTime(status == 4 ? deliveredAt : createdAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              time,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                if (device.isNotEmpty)
                  Text(
                    device,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                if (issue.isNotEmpty)
                  Text(
                    issue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                if (status == 4 && profit != 0)
                  Text(
                    'Lãi: ${MoneyUtils.formatCompactCurrency(profit)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: profit >= 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
              ],
            ),
          ),
          if (price > 0)
            Text(
              '${MoneyUtils.formatCompactCurrency(price)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
        ],
      ),
    );
  }

  // ==================== EXPENSES ====================
  Widget _buildExpensesSection(DailyActivityReport r) {
    final expList = r.expensesOnly;
    final incList = r.incomeOnly;
    final totalExp = expList.fold<int>(
      0,
      (s, e) => s + ((e['amount'] as int?) ?? 0),
    );
    final totalInc = incList.fold<int>(
      0,
      (s, e) => s + ((e['amount'] as int?) ?? 0),
    );
    return _sectionCard(
      title: 'Chi phí & Thu khác',
      icon: Icons.account_balance,
      color: Colors.deepOrange,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (totalInc > 0)
            Text(
              '+${MoneyUtils.formatCompactCurrency(totalInc)} ',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (totalExp > 0)
            Text(
              '-${MoneyUtils.formatCompactCurrency(totalExp)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      child: Column(
        children: [
          if (expList.isEmpty && incList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có khoản chi/thu nào',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            ...incList.map((e) => _expenseRow(e, isIncome: true)),
            ...expList.map((e) => _expenseRow(e, isIncome: false)),
          ],
        ],
      ),
    );
  }

  Widget _expenseRow(Map<String, dynamic> e, {required bool isIncome}) {
    final amount = (e['amount'] as int?) ?? 0;
    final desc = e['title'] ?? e['description'] ?? e['note'] ?? '';
    final category = e['category'] ?? '';
    final time = _fmtTime(e['date'] as int?);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              time,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.isNotEmpty ? desc : (isIncome ? 'Thu' : 'Chi'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                if (category.isNotEmpty)
                  Text(
                    category,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          Text(
            '${isIncome ? '+' : '-'}${MoneyUtils.formatCompactCurrency(amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isIncome ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== IMPORTS ====================
  Widget _buildImportsSection(DailyActivityReport r) {
    final imports = r.supplierImports;
    return _sectionCard(
      title: 'Nhập hàng (${imports.length})',
      icon: Icons.inventory,
      color: Colors.teal,
      trailing: imports.isNotEmpty
          ? Text(
              '${MoneyUtils.formatCompactCurrency(r.totalImportValue)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            )
          : null,
      child: Column(
        children: [
          if (imports.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có nhập hàng',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...imports.take(20).map((im) {
              final supplier = im['supplierName'] ?? 'N/A';
              final productName = im['productName'] ?? '';
              final qty = (im['quantity'] as int?) ?? 0;
              final total = (im['totalAmount'] as int?) ?? 0;
              final time = _fmtTime(
                (im['importDate'] as int?) ?? (im['createdAt'] as int?),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (productName.isNotEmpty)
                            Text(
                              qty > 1 ? '$productName x$qty' : productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${MoneyUtils.formatCompactCurrency(total)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== DEBTS ====================
  Widget _buildDebtsSection(DailyActivityReport r) {
    final payments = r.debtPayments;
    final supplied = r.supplierPayments;
    final partner = r.partnerPayments;
    final totalCollected = payments.fold<int>(
      0,
      (s, e) => s + ((e['amount'] as int?) ?? 0),
    );
    return _sectionCard(
      title: 'Công nợ',
      icon: Icons.account_balance_wallet,
      color: Colors.indigo,
      trailing: totalCollected > 0
          ? Text(
              '+${MoneyUtils.formatCompactCurrency(totalCollected)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview
          if (r.debtOverview.isNotEmpty) ...[
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if ((r.debtOverview['customerRemain'] ?? 0) > 0)
                  _debtChip(
                    'KH nợ',
                    r.debtOverview['customerRemain']!,
                    AppColors.error,
                  ),
                if ((r.debtOverview['supplierRemain'] ?? 0) > 0)
                  _debtChip(
                    'Nợ NCC',
                    r.debtOverview['supplierRemain']!,
                    Colors.orange,
                  ),
                if ((r.debtOverview['partnerRemain'] ?? 0) > 0)
                  _debtChip(
                    'Nợ ĐT',
                    r.debtOverview['partnerRemain']!,
                    Colors.indigo,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // Customer debt payments
          if (payments.isEmpty && supplied.isEmpty && partner.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có giao dịch nợ',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            if (payments.isNotEmpty) ...[
              const Text(
                'Thu nợ khách:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...payments.take(15).map((p) {
                final amount = (p['amount'] as int?) ?? 0;
                final name =
                    p['customerName'] ??
                    p['debtPersonName'] ??
                    p['personName'] ??
                    'N/A';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '+${MoneyUtils.formatCompactCurrency(amount)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (supplied.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Trả nợ NCC:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...supplied.take(10).map((p) {
                final amount = (p['amount'] as int?) ?? 0;
                final name = p['supplierName'] ?? 'N/A';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '-${MoneyUtils.formatCompactCurrency(amount)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (partner.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Trả đối tác:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...partner.take(10).map((p) {
                final amount = (p['amount'] as int?) ?? 0;
                final name = p['partnerName'] ?? 'N/A';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '-${MoneyUtils.formatCompactCurrency(amount)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _debtChip(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: ${MoneyUtils.formatCompactCurrency(amount)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ==================== STAFF ====================
  Widget _buildStaffSection(DailyActivityReport r) {
    final att = r.attendance;
    final checkedIn = att.where((a) => a.checkInAt != null).length;
    return _sectionCard(
      title: 'Nhân viên ($checkedIn/${att.length})',
      icon: Icons.people,
      color: Colors.purple,
      child: Column(
        children: [
          if (att.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Không có dữ liệu chấm công',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...att.map((a) {
              final checkIn = a.checkInAt != null
                  ? _fmtTime(a.checkInAt)
                  : '--:--';
              final checkOut = a.checkOutAt != null
                  ? _fmtTime(a.checkOutAt)
                  : '--:--';
              final late = a.isLate == 1;
              final early = a.isEarlyLeave == 1;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (late)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Trễ',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    if (early)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Sớm',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    Text(
                      '$checkIn → $checkOut',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== ACTIVITY LOG ====================
  Widget _buildActivityLogSection(DailyActivityReport r) {
    final logs = r.auditLogs;
    return _sectionCard(
      title: 'Nhật ký hoạt động (${logs.length})',
      icon: Icons.history,
      color: Colors.blueGrey,
      initiallyExpanded: false,
      child: Column(
        children: [
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chưa có bản ghi hoạt động trong ngày đã chọn.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mục này hiển thị các phát sinh như bán hàng, sửa chữa, thu/chi và thao tác quản trị.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...logs.take(50).map((log) {
              final desc = log['description'] ?? log['activityType'] ?? '';
              final time = _fmtTime(log['createdAt'] as int?);
              final direction = log['direction'] ?? '';
              final amount = (log['amount'] as int?) ?? 0;
              final isIn = direction == 'IN';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (amount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${isIn ? '+' : '-'}${MoneyUtils.formatCompactCurrency(amount)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isIn ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==================== SHARED ====================
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    Widget? trailing,
    bool initiallyExpanded = true,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(icon, color: color, size: 22),
          title: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          trailing: trailing ?? const Icon(Icons.expand_more, size: 20),
          children: [child],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================
  String _fmtTime(int? ms) {
    if (ms == null || ms == 0) return '';
    return DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String _repairStatusLabel(int status) {
    switch (status) {
      case 1:
        return 'Đã nhận';
      case 2:
        return 'Đang sửa';
      case 3:
        return 'Đã sửa';
      case 4:
        return 'Đã giao';
      default:
        return 'N/A';
    }
  }

  Color _repairStatusColor(int status) {
    switch (status) {
      case 1:
        return AppColors.repairReceived;
      case 2:
        return AppColors.repairRepairing;
      case 3:
        return AppColors.repairDone;
      case 4:
        return AppColors.repairDelivered;
      default:
        return Colors.grey;
    }
  }

  // ==================== EXCEL EXPORT ====================
  Future<void> _exportExcel() async {
    if (_report == null) return;
    try {
      await ExcelExportHelper.exportDailyActivityReport(
        context: context,
        report: _report!,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xuất Excel: $e')));
      }
    }
  }

  // ==================== PRINT ====================
  Future<void> _printReport() async {
    if (_report == null) return;

    // Show printer selection dialog (same as invoice printing)
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return; // User cancelled

    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;

    try {
      final r = _report!;
      final f = r.financial;
      final dateStr = DateFormat('dd/MM/yyyy').format(r.date);
      final lines = StringBuffer();

      // Shop info header
      final shopInfo = await LabelSettingsService().getShopLabelSettings();
      if (shopInfo.shopName.isNotEmpty) {
        lines.writeln('[C][B]${shopInfo.shopName}');
      }
      if (shopInfo.address.isNotEmpty) {
        lines.writeln('[C]${shopInfo.address}');
      }
      if (shopInfo.hotline.isNotEmpty) {
        lines.writeln('[C]SDT: ${shopInfo.hotline}');
      }
      lines.writeln('');
      lines.writeln('[C][B]BAO CAO NGAY');
      lines.writeln('[C]$dateStr');
      lines.writeln('[C]================================');
      lines.writeln('');

      // Summary
      lines.writeln('[C][B]--- TỔNG QUAN ---');
      lines.writeln(
        'Doanh thu:  ${MoneyUtils.formatCompactCurrency(f.totalIn)}d',
      );
      lines.writeln(
        'Chi phi:    ${MoneyUtils.formatCompactCurrency(f.totalOut)}d',
      );
      lines.writeln(
        'Loi nhuan:  ${MoneyUtils.formatCompactCurrency(f.netProfit)}d',
      );
      lines.writeln('Giao dich:  ${r.totalTransactions}');
      lines.writeln('');

      // Sales
      lines.writeln('[C][B]--- BAN HANG (${r.sales.length}) ---');
      lines.writeln(
        'Tong: ${MoneyUtils.formatCompactCurrency(r.totalSaleRevenue)}d',
      );
      lines.writeln('Lai:  ${MoneyUtils.formatCompactCurrency(f.saleProfit)}d');
      for (final s in r.sales.take(15)) {
        final total =
            ((s['totalPrice'] as int?) ?? 0) - ((s['discount'] as int?) ?? 0);
        final cost = (s['totalCost'] as int?) ?? 0;
        final profit = total - cost;
        final name = s['customerName'] ?? 'Khach le';
        lines.writeln('  $name: ${MoneyUtils.formatCompactCurrency(total)}d');
        if (profit != 0) {
          lines.writeln(
            '    Lai: ${MoneyUtils.formatCompactCurrency(profit)}d',
          );
        }
      }
      if (r.sales.length > 15) {
        lines.writeln('  ...+${r.sales.length - 15} don khac');
      }
      lines.writeln('');

      // Repairs (only delivered)
      if (r.shopSettings.enableRepair) {
        lines.writeln(
          '[C][B]--- SUA CHUA DA GIAO (${r.repairsDelivered.length}) ---',
        );
        lines.writeln(
          'Tong thu: ${MoneyUtils.formatCompactCurrency(f.repairIncome)}d',
        );
        lines.writeln(
          'Lai:      ${MoneyUtils.formatCompactCurrency(f.repairProfit)}d',
        );
        for (final re in r.repairsDelivered.take(15)) {
          final cust = re['customerName'] ?? 'N/A';
          final price = (re['price'] as int?) ?? 0;
          final cost = (re['cost'] as int?) ?? 0;
          lines.writeln('  $cust: ${MoneyUtils.formatCompactCurrency(price)}d');
          if ((price - cost) != 0) {
            lines.writeln(
              '    Lai: ${MoneyUtils.formatCompactCurrency(price - cost)}d',
            );
          }
        }
        lines.writeln('');
      }

      // Expenses (CHI)
      final expOnly = r.expensesOnly;
      if (expOnly.isNotEmpty) {
        final totalExp = expOnly.fold<int>(
          0,
          (s, e) => s + ((e['amount'] as int?) ?? 0),
        );
        lines.writeln('[C][B]--- CHI PHI (${expOnly.length}) ---');
        lines.writeln(
          'Tong chi: ${MoneyUtils.formatCompactCurrency(totalExp)}d',
        );
        for (final e in expOnly.take(10)) {
          final cat = e['category'] ?? 'Chi phi';
          final detail = e['title'] ?? e['description'] ?? e['note'] ?? '';
          final amt = (e['amount'] as int?) ?? 0;
          lines.writeln('  $cat: ${MoneyUtils.formatCompactCurrency(amt)}d');
          if (detail.isNotEmpty) {
            lines.writeln('    $detail');
          }
        }
        lines.writeln('');
      }

      // Income (THU)
      final incOnly = r.incomeOnly;
      if (incOnly.isNotEmpty) {
        final totalInc = incOnly.fold<int>(
          0,
          (s, e) => s + ((e['amount'] as int?) ?? 0),
        );
        lines.writeln('[C][B]--- THU KHAC (${incOnly.length}) ---');
        lines.writeln(
          'Tong thu: ${MoneyUtils.formatCompactCurrency(totalInc)}d',
        );
        for (final e in incOnly.take(10)) {
          final cat = e['category'] ?? 'Thu';
          final detail = e['title'] ?? e['description'] ?? e['note'] ?? '';
          final amt = (e['amount'] as int?) ?? 0;
          lines.writeln('  $cat: ${MoneyUtils.formatCompactCurrency(amt)}d');
          if (detail.isNotEmpty) {
            lines.writeln('    $detail');
          }
        }
        lines.writeln('');
      }

      // Debt payments (CONG NO)
      final debtPay = r.debtPayments;
      final suppPay = r.supplierPayments;
      final partPay = r.partnerPayments;
      if (debtPay.isNotEmpty || suppPay.isNotEmpty || partPay.isNotEmpty) {
        lines.writeln('[C][B]--- CONG NO ---');
        for (final p in debtPay.take(10)) {
          final name =
              p['customerName'] ?? p['debtPersonName'] ?? p['personName'] ?? '';
          final amt = (p['amount'] as int?) ?? 0;
          lines.writeln(
            '  Thu no KH: ${MoneyUtils.formatCompactCurrency(amt)}d',
          );
          if (name.isNotEmpty) lines.writeln('    $name');
        }
        for (final p in suppPay.take(10)) {
          final amt = (p['amount'] as int?) ?? 0;
          lines.writeln('  Tra NCC: ${MoneyUtils.formatCompactCurrency(amt)}d');
          final name = p['supplierName'] ?? '';
          if (name.isNotEmpty) lines.writeln('    $name');
        }
        for (final p in partPay.take(10)) {
          final amt = (p['amount'] as int?) ?? 0;
          lines.writeln(
            '  Tra doi tac: ${MoneyUtils.formatCompactCurrency(amt)}d',
          );
          final name = p['partnerName'] ?? '';
          if (name.isNotEmpty) lines.writeln('    $name');
        }
        lines.writeln('');
      }

      // Imports (NHAP HANG)
      final imports = r.supplierImports;
      if (imports.isNotEmpty) {
        lines.writeln('[C][B]--- NHAP HANG (${imports.length}) ---');
        lines.writeln(
          'Tong: ${MoneyUtils.formatCompactCurrency(r.totalImportValue)}d',
        );
        for (final im in imports.take(10)) {
          final total = (im['totalAmount'] as int?) ?? 0;
          final supplier = im['supplierName'] ?? 'N/A';
          final product = im['productName'] ?? '';
          final qty = (im['quantity'] as int?) ?? 0;
          lines.writeln(
            '  $supplier: ${MoneyUtils.formatCompactCurrency(total)}d',
          );
          if (product.isNotEmpty) {
            lines.writeln('    ${qty > 1 ? '$product x$qty' : product}');
          }
        }
        lines.writeln('');
      }

      // Staff (NHAN VIEN)
      final att = r.attendance;
      if (att.isNotEmpty) {
        lines.writeln('[C][B]--- NHAN VIEN (${att.length}) ---');
        for (final a in att) {
          final name = a.name ?? '';
          final inTime = a.checkInAt != null
              ? DateFormat(
                  'HH:mm',
                ).format(DateTime.fromMillisecondsSinceEpoch(a.checkInAt!))
              : '--:--';
          final outTime = a.checkOutAt != null
              ? DateFormat(
                  'HH:mm',
                ).format(DateTime.fromMillisecondsSinceEpoch(a.checkOutAt!))
              : '--:--';
          final late = a.isLate == 1 ? ' (Tre)' : '';
          lines.writeln('  $name: $inTime-$outTime$late');
        }
        lines.writeln('');
      }

      // Cash flow summary
      lines.writeln('[C][B]--- LUONG TIEN ---');
      if (f.saleIncome > 0) {
        lines.writeln(
          'Ban hang:     +${MoneyUtils.formatCompactCurrency(f.saleIncome)}d',
        );
      }
      if (r.shopSettings.enableRepair && f.repairIncome > 0) {
        lines.writeln(
          'Sua chua:     +${MoneyUtils.formatCompactCurrency(f.repairIncome)}d',
        );
      }
      if (f.debtCollected > 0) {
        lines.writeln(
          'Thu no:       +${MoneyUtils.formatCompactCurrency(f.debtCollected)}d',
        );
      }
      if (f.expenseOut > 0) {
        lines.writeln(
          'Chi phi:      -${MoneyUtils.formatCompactCurrency(f.expenseOut)}d',
        );
      }
      if (f.importOut > 0) {
        lines.writeln(
          'Nhap hang:    -${MoneyUtils.formatCompactCurrency(f.importOut)}d',
        );
      }
      lines.writeln('');

      lines.writeln('[C]================================');
      lines.writeln(
        '[C][B]LOI NHUAN: ${MoneyUtils.formatCompactCurrency(f.netProfit)}d',
      );
      lines.writeln('[C]================================');
      lines.writeln('');
      lines.writeln(
        '[C]In luc ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}',
      );

      final success = await UnifiedPrinterService.printTextReceipt(
        lines.toString(),
        paper: PaperSize.mm58,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Đã gửi lệnh in' : 'Không thể in, kiểm tra máy in',
            ),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi in: $e')));
      }
    }
  }
}
