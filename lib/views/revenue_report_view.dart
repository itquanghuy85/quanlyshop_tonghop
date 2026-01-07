import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/sync_service.dart';
import '../services/event_bus.dart';

class RevenueReportView extends StatefulWidget {
  const RevenueReportView({super.key});
  @override
  State<RevenueReportView> createState() => _RevenueReportViewState();
}

class _RevenueReportViewState extends State<RevenueReportView> {
  final db = DBHelper();
  String _filter = 'month';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();

  List<Repair> _repairs = [];
  List<SaleOrder> _sales = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _setRange();
    _loadData();

    // Listen for real-time sync updates
    SyncService.initRealTimeSync(() {
      if (mounted) _loadData();
    });

    // Listen for sales changes
    EventBus().stream.listen((event) {
      if ((event == 'sales_changed' || event == 'repairs_changed') && mounted) {
        _loadData();
      }
    });
  }

  void _setRange() {
    final now = DateTime.now();
    if (_filter == 'today') {
      _start = DateTime(now.year, now.month, now.day);
      _end = DateTime(now.year, now.month, now.day, 23, 59);
    } else if (_filter == 'week') {
      _start = now.subtract(Duration(days: now.weekday - 1));
      _end = now;
    } else {
      _start = DateTime(now.year, now.month, 1);
      _end = now;
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Sync data from cloud first
    try {
      await SyncService.downloadAllFromCloud();
    } catch (e) {
      debugPrint('Error syncing data: $e');
      // Continue with local data if sync fails
    }

    final rs = await db.getAllRepairs();
    final ss = await db.getAllSales();
    final es = await db.getAllExpenses();

    debugPrint(
      'Revenue Report - Loaded ${rs.length} repairs, ${ss.length} sales, ${es.length} expenses',
    );
    debugPrint(
      'Revenue Report - Date range: ${_start.toString()} to ${_end.toString()}',
    );

    bool inR(DateTime d) =>
        d.isAfter(_start.subtract(const Duration(seconds: 1))) &&
        d.isBefore(_end.add(const Duration(seconds: 1)));

    final filteredRepairs = rs
        .where((r) => inR(DateTime.fromMillisecondsSinceEpoch(r.createdAt)))
        .toList();
    final filteredSales = ss
        .where((s) => inR(DateTime.fromMillisecondsSinceEpoch(s.soldAt)))
        .toList();
    final filteredExpenses = es
        .where(
          (e) => inR(DateTime.fromMillisecondsSinceEpoch(e['date'] as int)),
        )
        .toList();

    debugPrint(
      'Revenue Report - Filtered: ${filteredRepairs.length} repairs, ${filteredSales.length} sales, ${filteredExpenses.length} expenses',
    );

    setState(() {
      _repairs = filteredRepairs;
      _sales = filteredSales;
      _expenses = filteredExpenses;
      _loading = false;
    });
  }

  // Chỉ tính repair đã giao (status == 4) vào doanh thu
  double get totalRev =>
      _sales.fold(0.0, (a, b) => a + b.totalPrice) +
      _repairs.where((r) => r.status == 4).fold(0.0, (a, b) => a + b.price);
  double get totalCost =>
      _sales.fold(0.0, (a, b) => a + b.totalCost) +
      _repairs.where((r) => r.status == 4).fold(0.0, (a, b) => a + b.cost) +
      _expenses.fold(0.0, (a, b) => a + (b['amount'] as num).toDouble());
  double get profit => totalRev - totalCost;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "BÁO CÁO TÀI CHÍNH",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildTimeFilter(),
                  const SizedBox(height: 20),
                  _buildSummaryCard("TỔNG DOANH THU", totalRev, Colors.blue),
                  const SizedBox(height: 12),
                  _buildSummaryCard("TỔNG CHI PHÍ", totalCost, Colors.orange),
                  const SizedBox(height: 12),
                  _buildSummaryCard(
                    "LỢI NHUẬN THUẦN",
                    profit,
                    Colors.green,
                    isMain: true,
                  ),
                  const SizedBox(height: 25),
                  _buildDetailSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildTimeFilter() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          _filterBtn("Hôm nay", "today"),
          _filterBtn("Tuần này", "week"),
          _filterBtn("Tháng này", "month"),
        ],
      ),
    );
  }

  Widget _filterBtn(String l, String v) {
    bool active = _filter == v;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _filter = v;
            _setRange();
          });
          _loadData();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2962FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            l,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double val,
    Color color, {
    bool isMain = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isMain ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isMain ? Colors.white70 : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          Text(
            "${NumberFormat('#,###').format(val)} đ",
            style: TextStyle(
              color: isMain ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection() {
    // Chỉ hiển thị repair đã giao (status == 4)
    final deliveredRepairs = _repairs.where((r) => r.status == 4).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "CHI TIẾT NGUỒN THU",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 20),
          _row(
            "Bán hàng (${_sales.length})",
            _sales.fold(0.0, (a, b) => a + b.totalPrice),
            Colors.blue,
          ),
          _row(
            "Sửa chữa (${deliveredRepairs.length})",
            deliveredRepairs.fold(0.0, (a, b) => a + b.price),
            Colors.orange,
          ),
          const Divider(height: 30),
          const Text(
            "CHI TIẾT CHI PHÍ",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 20),
          _row(
            "Giá vốn máy bán",
            _sales.fold(0.0, (a, b) => a + b.totalCost),
            Colors.redAccent,
          ),
          _row(
            "Giá vốn linh kiện",
            deliveredRepairs.fold(0.0, (a, b) => a + b.cost),
            Colors.redAccent,
          ),
          _row(
            "Chi phí vận hành",
            _expenses.fold(0.0, (a, b) => a + (b['amount'] as num).toDouble()),
            Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _row(String l, double v, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            "${NumberFormat('#,###').format(v)} đ",
            style: TextStyle(fontWeight: FontWeight.bold, color: c),
          ),
        ],
      ),
    );
  }
}
