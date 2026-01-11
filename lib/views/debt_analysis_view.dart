import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class DebtAnalysisView extends StatefulWidget {
  const DebtAnalysisView({super.key});

  @override
  State<DebtAnalysisView> createState() => _DebtAnalysisViewState();
}

class _DebtAnalysisViewState extends State<DebtAnalysisView> {
  final db = DBHelper();
  bool _isLoading = true;
  String _analysisResult = '';
  
  // Thống kê tổng quan
  int _totalRecords = 0;
  int _homeViewTotal = 0;
  int _customerOwesTotal = 0;
  int _shopOwesTotal = 0;
  int _customerOwesCount = 0;
  int _shopOwesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAndAnalyze();
  }

  Future<void> _loadAndAnalyze() async {
    setState(() => _isLoading = true);
    
    final debts = await db.getAllDebts();
    StringBuffer analysis = StringBuffer();

    int homeTotal = 0;
    int customerTotal = 0;
    int shopTotal = 0;
    int customerCount = 0;
    int shopCount = 0;

    analysis.writeln('=== PHÂN TÍCH DỮ LIỆU NỢ ===\n');
    analysis.writeln('Tổng số records: ${debts.length}\n');

    // Logic Home View (tất cả nợ còn lại > 0)
    analysis.writeln('--- LOGIC HOME VIEW (tất cả nợ) ---');
    for (var d in debts) {
      final int total = d['totalAmount'] ?? 0;
      final int paid = d['paidAmount'] ?? 0;
      final int remain = total - paid;
      if (remain > 0) {
        homeTotal += remain;
        analysis.writeln('ID ${d['id']}: ${d['personName']} - Total: $total, Paid: $paid, Remain: $remain');
      }
    }
    analysis.writeln('TỔNG HOME VIEW: $homeTotal đ\n');

    // Logic Debt View (theo loại)
    final customerOwes = debts.where((d) => 
      (d['type'] == 'CUSTOMER_OWES' || d['type'] == 'OWE') && 
      (d['status'] != 'paid')
    ).toList();
    final shopOwes = debts.where((d) => 
      (d['type'] == 'SHOP_OWES' || d['type'] == 'OWED') && 
      (d['status'] != 'paid')
    ).toList();

    analysis.writeln('--- LOGIC DEBT VIEW (theo loại, status != paid) ---');
    analysis.writeln('Khách nợ (${customerOwes.length} records):');
    for (var d in customerOwes) {
      final int total = d['totalAmount'] as int;
      final int paid = d['paidAmount'] as int? ?? 0;
      final int remain = total - paid;
      if (remain > 0) {
        customerTotal += remain;
        customerCount++;
        analysis.writeln('  ID ${d['id']}: ${d['personName']} - Total: $total, Paid: $paid, Remain: $remain, Status: ${d['status']}');
      }
    }

    analysis.writeln('\nShop nợ NCC (${shopOwes.length} records):');
    for (var d in shopOwes) {
      final int total = d['totalAmount'] as int;
      final int paid = d['paidAmount'] as int? ?? 0;
      final int remain = total - paid;
      if (remain > 0) {
        shopTotal += remain;
        shopCount++;
        analysis.writeln('  ID ${d['id']}: ${d['personName']} - Total: $total, Paid: $paid, Remain: $remain, Status: ${d['status']}');
      }
    }

    analysis.writeln('\nTỔNG DEBT VIEW: ${customerTotal + shopTotal} đ (Khách: $customerTotal + Shop: $shopTotal)\n');

    // Chi tiết tất cả records
    analysis.writeln('--- TẤT CẢ RECORDS ---');
    for (var d in debts) {
      analysis.writeln('ID ${d['id']}: ${d['personName']} (${d['type']}) - Total: ${d['totalAmount']}, Paid: ${d['paidAmount'] ?? 0}, Status: ${d['status']}, Phone: ${d['phone']}');
    }

    setState(() {
      _totalRecords = debts.length;
      _homeViewTotal = homeTotal;
      _customerOwesTotal = customerTotal;
      _shopOwesTotal = shopTotal;
      _customerOwesCount = customerCount;
      _shopOwesCount = shopCount;
      _analysisResult = analysis.toString();
      _isLoading = false;
    });
  }

  String _formatCurrency(int amount) {
    return '${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: Text(
          'Phân tích dữ liệu nợ',
          style: AppTextStyles.headline5.copyWith(color: AppColors.onPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAndAnalyze,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Đang phân tích dữ liệu...',
                    style: AppTextStyles.body1.copyWith(color: AppColors.onSurface),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAndAnalyze,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thống kê tổng quan
                    _buildSummarySection(),
                    const SizedBox(height: 20),
                    
                    // Chi tiết phân tích
                    _buildDetailSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummarySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'TỔNG QUAN',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Tổng số records
          _buildStatRow(
            icon: Icons.list_alt_rounded,
            label: 'Tổng số records',
            value: '$_totalRecords',
            color: AppColors.info,
          ),
          const Divider(height: 24),
          
          // Home View Total
          _buildStatRow(
            icon: Icons.home_rounded,
            label: 'Tổng nợ (Home View)',
            value: _formatCurrency(_homeViewTotal),
            color: AppColors.warning,
          ),
          const Divider(height: 24),
          
          // Khách nợ
          _buildStatRow(
            icon: Icons.person_rounded,
            label: 'Khách nợ ($_customerOwesCount)',
            value: _formatCurrency(_customerOwesTotal),
            color: AppColors.error,
          ),
          const Divider(height: 24),
          
          // Shop nợ
          _buildStatRow(
            icon: Icons.store_rounded,
            label: 'Shop nợ NCC ($_shopOwesCount)',
            value: _formatCurrency(_shopOwesTotal),
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body1.copyWith(color: AppColors.onSurface),
          ),
        ),
        Text(
          value,
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'CHI TIẾT PHÂN TÍCH',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: SelectableText(
              _analysisResult,
              style: AppTextStyles.caption.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.5,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}