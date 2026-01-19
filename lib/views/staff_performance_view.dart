import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/salary_breakdown_model.dart';
import '../services/salary_calculation_service.dart';
import '../services/salary_slip_pdf_service.dart';
import '../theme/app_colors.dart';
import 'hr_salary_settings_view.dart';
import 'hr/shop_deduction_settings_view.dart';
import 'hr/add_custom_adjustment_dialog.dart';

/// Trang DOANH SỐ & LƯƠNG NHÂN VIÊN - Tính tự động từ chấm công + doanh số
class StaffPerformanceView extends StatefulWidget {
  const StaffPerformanceView({super.key});
  @override
  State<StaffPerformanceView> createState() => _StaffPerformanceViewState();
}

class _StaffPerformanceViewState extends State<StaffPerformanceView> {
  bool _loading = true;
  List<SalaryBreakdown> _salaryReports = [];
  DateTime _selectedMonth = DateTime.now();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);

    final results = await SalaryCalculationService.calculateAllStaffSalaries(
      month: _selectedMonth.month,
      year: _selectedMonth.year,
    );

    setState(() {
      _salaryReports = results;
      _loading = false;
    });
  }

  /// Xử lý action in bảng lương
  Future<void> _handlePrintAction(String action) async {
    if (_salaryReports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có dữ liệu để in'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Hiện loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang tạo PDF...'),
                ],
              ),
            ),
          ),
        ),
      );

      switch (action) {
        case 'print_all':
          await SalarySlipPdfService.printAllStaffSalary(
            _salaryReports,
            _selectedMonth.month,
            _selectedMonth.year,
          );
          break;
        case 'share_all':
          await SalarySlipPdfService.shareAllStaffSalary(
            _salaryReports,
            _selectedMonth.month,
            _selectedMonth.year,
          );
          break;
      }

      if (mounted) Navigator.of(context).pop(); // Đóng loading
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Đóng loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Quay lại',
        ),
        title: const Text(
          "BẢNG LƯƠNG NHÂN VIÊN",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Nút in bảng lương
          PopupMenuButton<String>(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'In bảng lương',
            onSelected: (value) => _handlePrintAction(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'print_all',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('In bảng lương tổng hợp'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share_all',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Chia sẻ PDF tổng hợp'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ShopDeductionSettingsView(),
              ),
            ).then((_) => _loadReport()),
            icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
            tooltip: 'Cài đặt Khấu trừ/Thuế',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HRSalarySettingsView()),
            ).then((_) => _loadReport()),
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Cài đặt lương',
          ),
          IconButton(
            onPressed: () => _selectMonth(context),
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            tooltip: 'Chọn tháng',
          ),
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMonthHeader(),
                _buildTotalSummary(),
                Expanded(
                  child: _salaryReports.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _salaryReports.length,
                          itemBuilder: (ctx, i) =>
                              _buildStaffSalaryCard(_salaryReports[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month - 1,
                );
              });
              _loadReport();
            },
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Text(
            'THÁNG ${_selectedMonth.month.toString().padLeft(2, '0')} / ${_selectedMonth.year}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month + 1,
                );
              });
              _loadReport();
            },
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSummary() {
    final totalSalary = _salaryReports.fold(
      0.0,
      (sum, r) => sum + r.totalSalary,
    );
    final totalRevenue = _salaryReports.fold(
      0.0,
      (sum, r) => sum + r.totalRevenue,
    );
    final totalProfit = _salaryReports.fold(
      0.0,
      (sum, r) => sum + r.totalProfit,
    );

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.people, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                '${_salaryReports.length} NHÂN VIÊN',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _buildSummaryItem(
                '💰 TỔNG LƯƠNG',
                '${_currencyFormat.format(totalSalary)}đ',
                Colors.green,
              ),
              const SizedBox(width: 12),
              _buildSummaryItem(
                '📊 DOANH SỐ',
                '${_currencyFormat.format(totalRevenue)}đ',
                Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildSummaryItem(
                '📈 LỢI NHUẬN',
                '${_currencyFormat.format(totalProfit)}đ',
                Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Không có dữ liệu nhân viên',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tháng ${_selectedMonth.month}/${_selectedMonth.year}',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          Text(
            'Hãy thêm nhân viên vào shop trước',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSalaryCard(SalaryBreakdown data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              data.staffName.isNotEmpty ? data.staffName[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          title: Text(
            data.staffName.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMiniChip('${data.workDays} ngày', Colors.blue),
              const SizedBox(width: 4),
              _buildMiniChip('${data.totalOrders} đơn', Colors.purple),
              const SizedBox(width: 4),
              // Nút thêm thưởng/trừ - dùng icon only để tránh overflow
              InkWell(
                onTap: () async {
                  final result = await showAddCustomAdjustmentDialog(
                    context,
                    staffId: data.staffId,
                    staffName: data.staffName,
                    month: _selectedMonth.month,
                    year: _selectedMonth.year,
                  );
                  if (result == true) {
                    _loadReport();
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withAlpha(100)),
                  ),
                  child: const Icon(
                    Icons.add_circle_outline,
                    size: 14,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'THỰC NHẬN',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_currencyFormat.format(data.totalSalary)}đ',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          children: [_buildDetailSection(data)],
        ),
      ),
    );
  }

  Widget _buildMiniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailSection(SalaryBreakdown data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === BẢNG TỔNG HỢP ===
          _buildSectionTitle('📋 BẢNG TÍNH LƯƠNG CHI TIẾT'),
          const SizedBox(height: 8),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'KHOẢN MỤC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'CÔNG THỨC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'THÀNH TIỀN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          // Rows
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                // === THU NHẬP ===
                _buildSectionHeader('THU NHẬP', Colors.green),

                // 1. Lương cơ bản
                _buildTableRow(
                  '💰 Lương cơ bản',
                  _getBaseSalaryFormula(data),
                  data.calculatedBaseSalary,
                  isHighlight: true,
                ),

                // 2. Hoa hồng bán hàng
                if (data.saleOrderCount > 0 || data.calculatedSaleComm > 0)
                  _buildTableRow(
                    '🛒 HH bán hàng',
                    _getSaleCommFormula(data),
                    data.calculatedSaleComm,
                    subText:
                        '${data.saleOrderCount} đơn × DS ${_currencyFormat.format(data.saleRevenue)}đ',
                  ),

                // 3. Hoa hồng sửa chữa
                if (data.repairOrderCount > 0 || data.calculatedRepairComm > 0)
                  _buildTableRow(
                    '🔧 HH sửa chữa',
                    _getRepairCommFormula(data),
                    data.calculatedRepairComm,
                    subText:
                        '${data.repairOrderCount} đơn × LN ${_currencyFormat.format(data.repairProfit)}đ',
                  ),

                // 4. Tiền OT
                if (data.overtimeHours > 0)
                  _buildTableRow(
                    '⏰ Tiền OT',
                    '${data.overtimeHours.toStringAsFixed(1)}h × ${(data.overtimeRate / 100).toStringAsFixed(1)}x',
                    data.calculatedOT,
                  ),

                // 5. Thưởng doanh số
                if (data.calculatedBonus > 0)
                  _buildTableRow(
                    '🎯 Thưởng target',
                    'Đạt ${_currencyFormat.format(data.monthlyTarget)}đ',
                    data.calculatedBonus,
                    isBonus: true,
                  ),

                // 6. Phụ cấp
                if (data.calculatedAllowance > 0)
                  _buildTableRow(
                    '🎁 Phụ cấp',
                    _getAllowanceDetails(data),
                    data.calculatedAllowance,
                  ),

                // 7. Thưởng tùy chỉnh
                for (final bonus in data.customBonuses)
                  _buildTableRow(
                    '🎉 ${bonus.name}',
                    bonus.note ?? 'Thưởng',
                    bonus.amount,
                    isBonus: true,
                  ),

                // TỔNG THU NHẬP (GROSS)
                _buildSubtotalRow(
                  '📊 TỔNG GROSS',
                  data.grossIncome,
                  Colors.blue,
                ),

                // === KHẤU TRỪ ===
                if (data.totalDeductions > 0) ...[
                  _buildSectionHeader('KHẤU TRỪ', Colors.red),

                  // Trừ đi muộn
                  if (data.lateDeduction > 0)
                    _buildTableRow(
                      '⚠️ Trừ đi muộn',
                      '${data.lateDays} lần',
                      -data.lateDeduction,
                      isNegative: true,
                    ),

                  // Trừ về sớm
                  if (data.earlyLeaveDeduction > 0)
                    _buildTableRow(
                      '⚠️ Trừ về sớm',
                      '${data.earlyLeaveDays} lần',
                      -data.earlyLeaveDeduction,
                      isNegative: true,
                    ),

                  // Trừ nghỉ quá phép
                  if (data.absenceDeduction > 0)
                    _buildTableRow(
                      '❌ Nghỉ quá phép',
                      '${data.absentDays} ngày',
                      -data.absenceDeduction,
                      isNegative: true,
                    ),

                  // Trừ tùy chỉnh
                  for (final deduct in data.customDeductions)
                    _buildTableRow(
                      '📌 ${deduct.name}',
                      deduct.note ?? 'Khấu trừ',
                      -deduct.amount,
                      isNegative: true,
                    ),

                  // Bảo hiểm xã hội
                  if (data.socialInsurance > 0)
                    _buildTableRow(
                      '🏥 BHXH',
                      '8% lương đóng BH',
                      -data.socialInsurance,
                      isNegative: true,
                    ),

                  // Bảo hiểm y tế
                  if (data.healthInsurance > 0)
                    _buildTableRow(
                      '💊 BHYT',
                      '1.5% lương đóng BH',
                      -data.healthInsurance,
                      isNegative: true,
                    ),

                  // Bảo hiểm thất nghiệp
                  if (data.unemploymentInsurance > 0)
                    _buildTableRow(
                      '📋 BHTN',
                      '1% lương đóng BH',
                      -data.unemploymentInsurance,
                      isNegative: true,
                    ),

                  // Thuế TNCN
                  if (data.personalIncomeTax > 0)
                    _buildTableRow(
                      '💸 Thuế TNCN',
                      'TN chịu thuế: ${_currencyFormat.format(data.taxableIncome)}đ',
                      -data.personalIncomeTax,
                      isNegative: true,
                    ),

                  // TỔNG KHẤU TRỪ
                  _buildSubtotalRow(
                    '➖ TỔNG KHẤU TRỪ',
                    -data.totalDeductions,
                    Colors.red,
                  ),
                ],

                // TỔNG LƯƠNG THỰC NHẬN (NET)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.green.shade200, width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 3,
                        child: Text(
                          '💵 THỰC NHẬN (NET)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Expanded(flex: 2, child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${_currencyFormat.format(data.totalSalary)}đ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.green.shade700,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // === THÔNG TIN CHẤM CÔNG ===
          _buildSectionTitle('📅 THÔNG TIN CHẤM CÔNG'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                _buildInfoItem('Ngày công', '${data.workDays}', Colors.blue),
                _buildInfoItem(
                  'Giờ làm',
                  '${data.totalWorkHours.toStringAsFixed(1)}h',
                  Colors.indigo,
                ),
                _buildInfoItem(
                  'Giờ OT',
                  '${data.overtimeHours.toStringAsFixed(1)}h',
                  Colors.purple,
                ),
                _buildInfoItem(
                  'Muộn',
                  '${data.lateDays}',
                  data.lateDays > 0 ? Colors.orange : Colors.green,
                ),
                _buildInfoItem(
                  'Nghỉ',
                  '${data.absentDays}',
                  data.absentDays > 0 ? Colors.red : Colors.green,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // === DOANH SỐ CHI TIẾT ===
          _buildSectionTitle('📊 DOANH SỐ CHI TIẾT'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRevenueCard(
                  '🛒 BÁN HÀNG',
                  data.saleOrderCount,
                  data.saleRevenue,
                  data.saleProfit,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRevenueCard(
                  '🔧 SỬA CHỮA',
                  data.repairOrderCount,
                  data.repairRevenue,
                  data.repairProfit,
                  Colors.teal,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // === CÀI ĐẶT ÁP DỤNG ===
          _buildSectionTitle('⚙️ CÀI ĐẶT LƯƠNG ÁP DỤNG'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildSettingRow(
                  'Loại lương',
                  _getSalaryTypeLabel(data.salaryType),
                ),
                _buildSettingRow(
                  'Lương cơ bản',
                  '${_currencyFormat.format(data.baseSalary)}đ/${_getSalaryUnit(data.salaryType)}',
                ),
                _buildSettingRow(
                  'HH bán hàng',
                  data.saleCommType == 'percent'
                      ? '${data.saleCommValue}% doanh số'
                      : '${_currencyFormat.format(data.saleCommValue)}đ/đơn',
                ),
                _buildSettingRow(
                  'HH sửa chữa',
                  data.repairCommType == 'percent'
                      ? '${data.repairCommValue}% lợi nhuận'
                      : '${_currencyFormat.format(data.repairCommValue)}đ/đơn',
                ),
                _buildSettingRow(
                  'Hệ số OT',
                  '${(data.overtimeRate / 100).toStringAsFixed(1)}x',
                ),
                if (data.monthlyTarget > 0)
                  _buildSettingRow(
                    'Thưởng target',
                    '${data.targetBonusPercent}% khi đạt ${_currencyFormat.format(data.monthlyTarget)}đ',
                  ),
              ],
            ),
          ),

          // === GHI CHÚ TÍNH TOÁN ===
          if (data.calculationNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionTitle('📝 GHI CHÚ TÍNH TOÁN'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: data.calculationNotes
                    .map(
                      (note) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          // === NÚT IN PHIẾU LƯƠNG ===
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _printIndividualSlip(data),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('In phiếu lương'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareIndividualSlip(data),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Chia sẻ PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// In phiếu lương cá nhân
  Future<void> _printIndividualSlip(SalaryBreakdown data) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang tạo phiếu lương...'),
                ],
              ),
            ),
          ),
        ),
      );

      await SalarySlipPdfService.printSalarySlip(data);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Chia sẻ phiếu lương cá nhân
  Future<void> _shareIndividualSlip(SalaryBreakdown data) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Đang tạo PDF...'),
                ],
              ),
            ),
          ),
        ),
      );

      await SalarySlipPdfService.shareSalarySlip(data);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border(bottom: BorderSide(color: color.withAlpha(50))),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 10,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSubtotalRow(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border(
          top: BorderSide(color: color.withAlpha(50)),
          bottom: BorderSide(color: color.withAlpha(50)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${amount < 0 ? "" : ""}${_currencyFormat.format(amount.abs())}đ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    String label,
    String formula,
    double amount, {
    String? subText,
    bool isHighlight = false,
    bool isNegative = false,
    bool isBonus = false,
  }) {
    Color bgColor = Colors.transparent;
    if (isHighlight) bgColor = Colors.blue.shade50;
    if (isBonus) bgColor = Colors.amber.shade50;
    if (isNegative) bgColor = Colors.red.shade50;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subText != null)
                  Text(
                    subText,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formula,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${isNegative ? "-" : ""}${_currencyFormat.format(amount.abs())}đ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isNegative
                    ? Colors.red
                    : (isBonus ? Colors.amber.shade800 : Colors.black87),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard(
    String title,
    int count,
    double revenue,
    double profit,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text('$count đơn', style: const TextStyle(fontSize: 11)),
          const Divider(height: 12),
          Text(
            'DS: ${_currencyFormat.format(revenue)}đ',
            style: const TextStyle(fontSize: 10),
          ),
          Text(
            'LN: ${_currencyFormat.format(profit)}đ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: profit > 0 ? Colors.green.shade700 : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            '• $label: ',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // === HELPER FUNCTIONS ===

  String _getBaseSalaryFormula(SalaryBreakdown data) {
    switch (data.salaryType) {
      case 'daily':
        return '${_currencyFormat.format(data.baseSalary)}đ × ${data.workDays}';
      case 'hourly':
        return '${_currencyFormat.format(data.baseSalary)}đ × ${data.totalWorkHours.toStringAsFixed(0)}h';
      default:
        return 'Cố định/tháng';
    }
  }

  String _getSaleCommFormula(SalaryBreakdown data) {
    if (data.saleCommType == 'percent') {
      return '${data.saleCommValue}% DS';
    }
    return '${_currencyFormat.format(data.saleCommValue)}đ × ${data.saleOrderCount}';
  }

  String _getRepairCommFormula(SalaryBreakdown data) {
    if (data.repairCommType == 'percent') {
      return '${data.repairCommValue}% LN';
    }
    return '${_currencyFormat.format(data.repairCommValue)}đ × ${data.repairOrderCount}';
  }

  String _getAllowanceDetails(SalaryBreakdown data) {
    final parts = <String>[];
    if (data.transportAllowance > 0) parts.add('Xăng');
    if (data.mealAllowance > 0) parts.add('Ăn');
    if (data.phoneAllowance > 0) parts.add('ĐT');
    if (data.otherAllowance > 0) parts.add('Khác');
    return parts.isEmpty ? 'Tổng các khoản' : parts.join('+');
  }

  String _getSalaryTypeLabel(String type) {
    switch (type) {
      case 'daily':
        return 'Theo ngày';
      case 'hourly':
        return 'Theo giờ';
      default:
        return 'Theo tháng';
    }
  }

  String _getSalaryUnit(String type) {
    switch (type) {
      case 'daily':
        return 'ngày';
      case 'hourly':
        return 'giờ';
      default:
        return 'tháng';
    }
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedMonth) {
      setState(() => _selectedMonth = picked);
      _loadReport();
    }
  }
}
