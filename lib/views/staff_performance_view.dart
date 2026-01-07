import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';

class StaffPerformanceView extends StatefulWidget {
  const StaffPerformanceView({super.key});
  @override
  State<StaffPerformanceView> createState() => _StaffPerformanceViewState();
}

class _StaffPerformanceViewState extends State<StaffPerformanceView> {
  final db = DBHelper();
  bool _loading = true;
  List<Map<String, dynamic>> _reports = [];
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();
    final users = await db
        .getCustomerSuggestions(); // Tạm dùng để lấy danh sách tên người dùng từ lịch sử

    // Lấy danh sách tên nhân viên duy nhất từ các đơn hàng
    Set<String> staffNames = {};
    for (var r in repairs) {
      if (r.createdBy != null) staffNames.add(r.createdBy!.toUpperCase());
    }
    for (var s in sales) {
      staffNames.add(s.sellerName.toUpperCase());
    }

    List<Map<String, dynamic>> results = [];
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

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

      // Tính lương dự kiến (Ví dụ: 5% doanh số bán + 10% lợi nhuận sửa)
      double estimatedSalary = (saleRevenue * 0.01) + (repairProfit * 0.1);

      results.add({
        'name': name,
        'repairCount': staffRepairs.length,
        'repairRev': repairRevenue,
        'saleCount': staffSales.length,
        'saleRev': saleRevenue,
        'totalProfit': repairProfit + saleProfit,
        'salary': estimatedSalary,
      });
    }

    setState(() {
      _reports = results;
      _loading = false;
    });
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
            onPressed: () => _selectMonth(context),
            icon: const Icon(Icons.calendar_month, color: Colors.blue),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryHeader(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reports.length,
                    itemBuilder: (ctx, i) => _buildStaffCard(_reports[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        children: [
          Text(
            "THÁNG ${DateFormat('MM / yyyy').format(_selectedMonth)}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF2962FF),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "Tổng nhân viên hoạt động: ${_reports.length}",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
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
        _loadReport();
      });
    }
  }
}
