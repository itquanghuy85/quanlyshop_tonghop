import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';

class PayrollSettingsView extends StatefulWidget {
  const PayrollSettingsView({super.key});
  @override
  State<PayrollSettingsView> createState() => _PayrollSettingsViewState();
}

class _PayrollSettingsViewState extends State<PayrollSettingsView> {
  final db = DBHelper();
  final _fmt = NumberFormat('#,###');
  
  // Lương cơ bản
  final baseSalaryC = TextEditingController();
  
  // Hoa hồng bán hàng
  final saleCommC = TextEditingController();
  String _saleCommType = 'percent'; // 'percent' or 'fixed_per_order'
  
  // Hoa hồng sửa chữa
  final repairCommC = TextEditingController();
  String _repairCommType = 'percent'; // 'percent' or 'fixed_per_order'
  
  // Phụ cấp
  final transportAllowanceC = TextEditingController();
  final mealAllowanceC = TextEditingController();
  final phoneAllowanceC = TextEditingController();
  
  // Thưởng
  final targetBonusC = TextEditingController(); // Thưởng đạt chỉ tiêu
  final monthlyTargetC = TextEditingController(); // Chỉ tiêu doanh số/tháng
  
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    baseSalaryC.dispose();
    saleCommC.dispose();
    repairCommC.dispose();
    transportAllowanceC.dispose();
    mealAllowanceC.dispose();
    phoneAllowanceC.dispose();
    targetBonusC.dispose();
    monthlyTargetC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await db.getPayrollSettings();
    setState(() {
      baseSalaryC.text = _fmt.format(settings['baseSalary'] ?? 0);
      saleCommC.text = (settings['saleCommPercent'] ?? 1.0).toString();
      _saleCommType = settings['saleCommType'] ?? 'percent';
      repairCommC.text = (settings['repairProfitPercent'] ?? 10.0).toString();
      _repairCommType = settings['repairCommType'] ?? 'percent';
      transportAllowanceC.text = _fmt.format(settings['transportAllowance'] ?? 0);
      mealAllowanceC.text = _fmt.format(settings['mealAllowance'] ?? 0);
      phoneAllowanceC.text = _fmt.format(settings['phoneAllowance'] ?? 0);
      targetBonusC.text = _fmt.format(settings['targetBonus'] ?? 0);
      monthlyTargetC.text = _fmt.format(settings['monthlyTarget'] ?? 0);
      _loading = false;
    });
  }

  int _parseNumber(String text) {
    return int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  Future<void> _save() async {
    final data = {
      'baseSalary': _parseNumber(baseSalaryC.text),
      'saleCommPercent': double.tryParse(saleCommC.text) ?? 1.0,
      'saleCommType': _saleCommType,
      'repairProfitPercent': double.tryParse(repairCommC.text) ?? 10.0,
      'repairCommType': _repairCommType,
      'transportAllowance': _parseNumber(transportAllowanceC.text),
      'mealAllowance': _parseNumber(mealAllowanceC.text),
      'phoneAllowance': _parseNumber(phoneAllowanceC.text),
      'targetBonus': _parseNumber(targetBonusC.text),
      'monthlyTarget': _parseNumber(monthlyTargetC.text),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await db.savePayrollSettings(data);
    HapticFeedback.mediumImpact();
    NotificationService.showSnackBar("✅ ĐÃ LƯU CÀI ĐẶT LƯƠNG", color: Colors.green);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text("CÀI ĐẶT LƯƠNG & HOA HỒNG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text("LƯU"),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
      body: _loading 
          ? const Center(child: CircularProgressIndicator()) 
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // === LƯƠNG CƠ BẢN ===
                  _buildSectionHeader("💰 LƯƠNG CƠ BẢN", Colors.green),
                  _buildMoneyCard(
                    "Lương cơ bản / tháng", 
                    Icons.account_balance_wallet, 
                    baseSalaryC,
                    hint: "VD: 5,000,000",
                    helperText: "Lương cố định hàng tháng (chưa tính hoa hồng)",
                  ),
                  const SizedBox(height: 24),
                  
                  // === HOA HỒNG BÁN HÀNG ===
                  _buildSectionHeader("🛒 HOA HỒNG BÁN HÀNG", Colors.blue),
                  _buildCommissionCard(
                    title: "Hoa hồng bán máy/phụ kiện",
                    icon: Icons.shopping_bag,
                    controller: saleCommC,
                    commType: _saleCommType,
                    onTypeChanged: (val) => setState(() => _saleCommType = val!),
                    percentHint: "VD: 1 (= 1% doanh số)",
                    fixedHint: "VD: 50000 (= 50k/đơn)",
                  ),
                  const SizedBox(height: 24),
                  
                  // === HOA HỒNG SỬA CHỮA ===
                  _buildSectionHeader("🔧 HOA HỒNG SỬA CHỮA", Colors.orange),
                  _buildCommissionCard(
                    title: "Hoa hồng sửa chữa",
                    icon: Icons.build,
                    controller: repairCommC,
                    commType: _repairCommType,
                    onTypeChanged: (val) => setState(() => _repairCommType = val!),
                    percentHint: "VD: 10 (= 10% lợi nhuận)",
                    fixedHint: "VD: 30000 (= 30k/đơn)",
                    isRepair: true,
                  ),
                  const SizedBox(height: 24),
                  
                  // === PHỤ CẤP ===
                  _buildSectionHeader("📋 PHỤ CẤP HÀNG THÁNG", Colors.purple),
                  _buildMoneyCard(
                    "Phụ cấp xăng xe", 
                    Icons.local_gas_station, 
                    transportAllowanceC,
                    hint: "VD: 500,000",
                  ),
                  const SizedBox(height: 12),
                  _buildMoneyCard(
                    "Phụ cấp ăn trưa", 
                    Icons.restaurant, 
                    mealAllowanceC,
                    hint: "VD: 1,000,000",
                  ),
                  const SizedBox(height: 12),
                  _buildMoneyCard(
                    "Phụ cấp điện thoại", 
                    Icons.phone_android, 
                    phoneAllowanceC,
                    hint: "VD: 200,000",
                  ),
                  const SizedBox(height: 24),
                  
                  // === THƯỞNG CHỈ TIÊU ===
                  _buildSectionHeader("🎯 THƯỞNG ĐẠT CHỈ TIÊU", Colors.teal),
                  _buildMoneyCard(
                    "Chỉ tiêu doanh số / tháng", 
                    Icons.trending_up, 
                    monthlyTargetC,
                    hint: "VD: 100,000,000",
                    helperText: "Doanh số tối thiểu cần đạt",
                  ),
                  const SizedBox(height: 12),
                  _buildMoneyCard(
                    "Thưởng khi đạt chỉ tiêu", 
                    Icons.emoji_events, 
                    targetBonusC,
                    hint: "VD: 1,000,000",
                    helperText: "Thưởng thêm nếu đạt chỉ tiêu trên",
                  ),
                  const SizedBox(height: 24),
                  
                  // === PREVIEW CALCULATION ===
                  _buildPreviewSection(),
                  
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity, 
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded, color: Colors.white),
                      label: const Text("LƯU CÀI ĐẶT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2962FF), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
  
  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoneyCard(String title, IconData icon, TextEditingController ctrl, {String? hint, String? helperText}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blueGrey)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _ThousandsSeparatorFormatter(),
            ],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            decoration: InputDecoration(
              suffixText: 'đ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              hintText: hint,
              helperText: helperText,
              helperStyle: const TextStyle(fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCommissionCard({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String commType,
    required void Function(String?) onTypeChanged,
    required String percentHint,
    required String fixedHint,
    bool isRepair = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blueGrey)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Chọn loại hoa hồng
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: Text(isRepair ? '% lợi nhuận' : '% doanh số', style: const TextStyle(fontSize: 12)),
                  value: 'percent',
                  groupValue: commType,
                  onChanged: onTypeChanged,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Tiền/đơn', style: TextStyle(fontSize: 12)),
                  value: 'fixed_per_order',
                  groupValue: commType,
                  onChanged: onTypeChanged,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            decoration: InputDecoration(
              suffixText: commType == 'percent' ? '%' : 'đ/đơn',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              hintText: commType == 'percent' ? percentHint : fixedHint,
              helperText: commType == 'percent' 
                  ? (isRepair ? 'Tính trên lợi nhuận mỗi đơn sửa' : 'Tính trên tổng giá bán')
                  : 'Số tiền cố định cho mỗi đơn hoàn thành',
              helperStyle: const TextStyle(fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreviewSection() {
    final baseSalary = _parseNumber(baseSalaryC.text);
    final transportAllowance = _parseNumber(transportAllowanceC.text);
    final mealAllowance = _parseNumber(mealAllowanceC.text);
    final phoneAllowance = _parseNumber(phoneAllowanceC.text);
    final totalAllowance = transportAllowance + mealAllowance + phoneAllowance;
    
    // Example calculation
    const exampleSaleRevenue = 50000000; // 50tr doanh số bán
    const exampleRepairProfit = 10000000; // 10tr lợi nhuận sửa
    const exampleSaleOrders = 10; // 10 đơn bán
    const exampleRepairOrders = 20; // 20 đơn sửa
    
    double saleComm = 0;
    if (_saleCommType == 'percent') {
      final percent = double.tryParse(saleCommC.text) ?? 0;
      saleComm = exampleSaleRevenue * percent / 100;
    } else {
      final fixed = _parseNumber(saleCommC.text).toDouble();
      saleComm = fixed * exampleSaleOrders;
    }
    
    double repairComm = 0;
    if (_repairCommType == 'percent') {
      final percent = double.tryParse(repairCommC.text) ?? 0;
      repairComm = exampleRepairProfit * percent / 100;
    } else {
      final fixed = _parseNumber(repairCommC.text).toDouble();
      repairComm = fixed * exampleRepairOrders;
    }
    
    final totalComm = saleComm + repairComm;
    final totalSalary = baseSalary + totalAllowance + totalComm;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.green.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'VÍ DỤ TÍNH LƯƠNG',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Mẫu', style: TextStyle(fontSize: 10, color: Colors.blue)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Giả sử NV có: 10 đơn bán (50tr) + 20 đơn sửa (LN 10tr)',
            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
          const Divider(height: 20),
          _previewRow('Lương cơ bản', baseSalary),
          _previewRow('Phụ cấp', totalAllowance),
          _previewRow('Hoa hồng bán (${_saleCommType == 'percent' ? '${saleCommC.text}%' : '${saleCommC.text}đ/đơn'})', saleComm.toInt()),
          _previewRow('Hoa hồng sửa (${_repairCommType == 'percent' ? '${repairCommC.text}%' : '${repairCommC.text}đ/đơn'})', repairComm.toInt()),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TỔNG LƯƠNG DỰ KIẾN', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${_fmt.format(totalSalary)} đ',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _previewRow(String label, int amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          Text('${_fmt.format(amount)} đ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Formatter để thêm dấu phẩy ngăn cách hàng nghìn
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    
    final number = int.tryParse(newValue.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (number == null) return oldValue;
    
    final formatted = NumberFormat('#,###').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
