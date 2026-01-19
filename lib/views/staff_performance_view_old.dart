import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db_helper.dart';
import '../services/firestore_service.dart';
import 'hr_salary_settings_view.dart';

class StaffPerformanceView extends StatefulWidget {
  const StaffPerformanceView({super.key});
  @override
  State<StaffPerformanceView> createState() => _StaffPerformanceViewState();
}

class _StaffPerformanceViewState extends State<StaffPerformanceView> {
  final db = DBHelper();
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _filteredReports = [];
  DateTime _selectedMonth = DateTime.now();
  
  // === FILTERS ===
  String? _selectedStaffName;
  List<String> _allStaffNames = [];
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _useCustomDateRange = false;
  
  // === COMMISSION SETTINGS ===
  double _saleCommissionPercent = 1.0; // Default 1% doanh số bán
  double _repairCommissionPercent = 10.0; // Default 10% lợi nhuận sửa

  @override
  void initState() {
    super.initState();
    _loadCommissionSettings();
    _loadReport();
  }

  Future<void> _loadCommissionSettings() async {
    // Try load from Firestore shop defaults first
    final shopDefaults = await FirestoreService.getShopDefaultSalarySettings();
    if (shopDefaults != null) {
      setState(() {
        // Kiểm tra loại hoa hồng và lấy giá trị phù hợp
        if (shopDefaults['saleCommType'] == 'percent') {
          _saleCommissionPercent = (shopDefaults['saleCommValue'] ?? 1.0).toDouble();
        } else {
          // Nếu là fixed_per_order, dùng giá trị mặc định percent
          _saleCommissionPercent = 1.0;
        }
        
        if (shopDefaults['repairCommType'] == 'percent') {
          _repairCommissionPercent = (shopDefaults['repairCommValue'] ?? 10.0).toDouble();
        } else {
          _repairCommissionPercent = 10.0;
        }
      });
      return;
    }
    
    // Fallback to local payroll settings
    final localSettings = await db.getPayrollSettings();
    setState(() {
      _saleCommissionPercent = (localSettings['saleCommPercent'] ?? 1.0).toDouble();
      _repairCommissionPercent = (localSettings['repairProfitPercent'] ?? 10.0).toDouble();
    });
  }

  Future<void> _saveCommissionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('saleCommissionPercent', _saleCommissionPercent);
    await prefs.setDouble('repairCommissionPercent', _repairCommissionPercent);
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();

    // Lấy danh sách tên nhân viên duy nhất từ các đơn hàng
    Set<String> staffNames = {};
    for (var r in repairs) {
      if (r.createdBy != null) staffNames.add(r.createdBy!.toUpperCase());
    }
    for (var s in sales) {
      staffNames.add(s.sellerName.toUpperCase());
    }
    
    // Cập nhật danh sách tên nhân viên cho filter
    _allStaffNames = staffNames.where((n) => n.isNotEmpty && n != "SYSTEM").toList()..sort();

    List<Map<String, dynamic>> results = [];
    
    // Xác định khoảng thời gian dựa trên filter
    DateTime firstDay;
    DateTime lastDay;
    if (_useCustomDateRange && _customStartDate != null && _customEndDate != null) {
      firstDay = _customStartDate!;
      lastDay = DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59);
    } else {
      firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
    }

    for (var name in staffNames) {
      if (name.isEmpty || name == "SYSTEM") continue;

      // Doanh số sửa chữa - chỉ tính đơn đã giao (status == 4)
      final staffRepairs = repairs
          .where(
            (r) =>
                r.createdBy?.toUpperCase() == name &&
                r.status == 4 &&
                r.deliveredAt != null &&
                r.deliveredAt! >= firstDay.millisecondsSinceEpoch &&
                r.deliveredAt! <= lastDay.millisecondsSinceEpoch,
          )
          .toList();

      int repairRevenue = staffRepairs.fold(0, (sum, r) => sum + r.price);
      int repairProfit = staffRepairs.fold(
        0,
        (sum, r) => sum + (r.price - r.totalCost),
      );

      // Doanh số bán hàng
      final staffSales = sales
          .where(
            (s) =>
                s.sellerName.toUpperCase() == name &&
                s.soldAt >= firstDay.millisecondsSinceEpoch &&
                s.soldAt <= lastDay.millisecondsSinceEpoch,
          )
          .toList();

      int saleRevenue = staffSales.fold(0, (sum, s) => sum + s.totalPrice);
      int saleProfit = staffSales.fold(
        0,
        (sum, s) => sum + (s.totalPrice - s.totalCost),
      );

      // Tính lương dự kiến theo % cấu hình
      double estimatedSalary = (saleRevenue * _saleCommissionPercent / 100) + 
                               (repairProfit * _repairCommissionPercent / 100);

      results.add({
        'name': name,
        'repairCount': staffRepairs.length,
        'repairRev': repairRevenue,
        'repairProfit': repairProfit,
        'saleCount': staffSales.length,
        'saleRev': saleRevenue,
        'saleProfit': saleProfit,
        'totalProfit': repairProfit + saleProfit,
        'salary': estimatedSalary,
      });
    }

    setState(() {
      _reports = results;
      _applyStaffFilter();
      _loading = false;
    });
  }
  
  void _applyStaffFilter() {
    if (_selectedStaffName == null || _selectedStaffName!.isEmpty) {
      _filteredReports = List.from(_reports);
    } else {
      _filteredReports = _reports.where((r) => r['name'] == _selectedStaffName).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "DOANH SỐ & LƯƠNG NHÂN VIÊN",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        actions: [
          IconButton(
            onPressed: () => _showCommissionSettingsDialog(),
            icon: const Icon(Icons.settings, color: Colors.orange),
            tooltip: 'Cài đặt % hoa hồng',
          ),
          IconButton(
            onPressed: () => _selectMonth(context),
            icon: const Icon(Icons.calendar_month, color: Colors.blue),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFiltersSection(),
                _buildSummaryHeader(),
                Expanded(
                  child: _filteredReports.isEmpty
                      ? const Center(
                          child: Text(
                            'Không có dữ liệu trong khoảng thời gian này',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredReports.length,
                          itemBuilder: (ctx, i) => _buildStaffCard(_filteredReports[i]),
                        ),
                ),
              ],
            ),
    );
  }
  
  // === BỘ LỌC SECTION ===
  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Dropdown chọn nhân viên
          Row(
            children: [
              const Icon(Icons.person_search, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStaffName,
                  decoration: InputDecoration(
                    labelText: 'Lọc theo nhân viên',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('👥 Tất cả nhân viên'),
                    ),
                    ..._allStaffNames.map((name) => DropdownMenuItem(
                      value: name,
                      child: Text(name),
                    )),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedStaffName = val;
                      _applyStaffFilter();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Toggle custom date range
          Row(
            children: [
              const Icon(Icons.date_range, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 10),
              const Text('Lọc theo khoảng thời gian:', style: TextStyle(fontSize: 13)),
              const Spacer(),
              Switch(
                value: _useCustomDateRange,
                onChanged: (val) {
                  setState(() {
                    _useCustomDateRange = val;
                    if (!val) {
                      _customStartDate = null;
                      _customEndDate = null;
                    }
                  });
                  _loadReport();
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
          // Row 3: Date pickers (chỉ hiện khi bật custom)
          if (_useCustomDateRange) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectStartDate(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            _customStartDate != null 
                                ? DateFormat('dd/MM/yyyy').format(_customStartDate!)
                                : 'Từ ngày',
                            style: TextStyle(
                              fontSize: 13,
                              color: _customStartDate != null ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectEndDate(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            _customEndDate != null 
                                ? DateFormat('dd/MM/yyyy').format(_customEndDate!)
                                : 'Đến ngày',
                            style: TextStyle(
                              fontSize: 13,
                              color: _customEndDate != null ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final fmt = NumberFormat('#,###');
    final totalSalary = _filteredReports.fold(0.0, (sum, r) => sum + (r['salary'] as double));
    final totalRevenue = _filteredReports.fold(0, (sum, r) => sum + (r['saleRev'] as int) + (r['repairRev'] as int));
    
    String dateRangeText;
    if (_useCustomDateRange && _customStartDate != null && _customEndDate != null) {
      dateRangeText = "${DateFormat('dd/MM').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}";
    } else {
      dateRangeText = "THÁNG ${DateFormat('MM / yyyy').format(_selectedMonth)}";
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Text(
            dateRangeText,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF2962FF),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _summaryChip(
                '👥 ${_filteredReports.length} NV',
                Colors.blue.shade50,
              ),
              _summaryChip(
                '💰 ${fmt.format(totalRevenue)} đ',
                Colors.green.shade50,
              ),
              _summaryChip(
                '💵 ${fmt.format(totalSalary)} đ',
                Colors.orange.shade50,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "📊 Hoa hồng: ${_saleCommissionPercent.toStringAsFixed(1)}% doanh số + ${_repairCommissionPercent.toStringAsFixed(1)}% lợi nhuận sửa",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }
  
  Widget _summaryChip(String text, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> data) {
    final fmt = NumberFormat('#,###');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: Text(
                data['name'][0],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              data['name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  "THU NHẬP",
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${fmt.format(data['salary'])} đ",
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat(
                  "SỬA MÁY",
                  "${data['repairCount']} đơn",
                  fmt.format(data['repairRev']),
                ),
                _miniStat(
                  "BÁN HÀNG",
                  "${data['saleCount']} đơn",
                  fmt.format(data['saleRev']),
                ),
                _miniStat(
                  "LỢI NHUẬN",
                  "Mang về",
                  fmt.format(data['totalProfit']),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String sub, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.blueGrey,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          val,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedMonth) {
      setState(() {
        _selectedMonth = picked;
        _useCustomDateRange = false;
        _customStartDate = null;
        _customEndDate = null;
      });
      _loadReport();
    }
  }
  
  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _customStartDate = picked);
      if (_customEndDate != null) _loadReport();
    }
  }
  
  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? DateTime.now(),
      firstDate: _customStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _customEndDate = picked);
      if (_customStartDate != null) _loadReport();
    }
  }
  
  // === ĐIỀU HƯỚNG ĐẾN TRANG CÀI ĐẶT LƯƠNG & HOA HỒNG ===
  void _showCommissionSettingsDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HRSalarySettingsView()),
    ).then((_) {
      // Reload commission settings after returning
      _loadCommissionSettings();
      _loadReport();
    });
  }
}
