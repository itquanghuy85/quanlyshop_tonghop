import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../models/repair_model.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/money_utils.dart';

/// Trang chốt quỹ độc lập - truy cập nhanh từ tab Tài chính
class CashClosingView extends StatefulWidget {
  const CashClosingView({super.key});

  @override
  State<CashClosingView> createState() => _CashClosingViewState();
}

class _CashClosingViewState extends State<CashClosingView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;
  bool _isLoading = true;

  // Data
  List<SaleOrder> _sales = [];
  List<Repair> _repairs = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _debtPayments = [];
  List<Map<String, dynamic>> _supplierImports = [];
  List<Map<String, dynamic>> _supplierPayments = [];
  Map<String, dynamic>? _previousDayClosing;

  // Controllers
  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();

  StreamSubscription? _closingSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
    _initClosingRealTimeSync();
  }

  @override
  void dispose() {
    _closingSubscription?.cancel();
    _tabController.dispose();
    cashEndCtrl.dispose();
    bankEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _initClosingRealTimeSync() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return;

    _closingSubscription = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('cash_closings')
        .snapshots()
        .listen((snapshot) {
      if (mounted) _loadAllData();
    });
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    final sales = await db.getAllSales();
    final repairs = await db.getAllRepairs();
    final expenses = await db.getAllExpenses();
    final debtPayments = await db.getAllDebtPaymentsWithDetails();
    final supplierImports = await db.getAllSupplierImportHistory();
    final supplierPayments = await db.getAllSupplierPayments();

    // Load previous day closing
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);
    final previousClosing = await db.getClosingByDateKey(yesterdayKey);

    if (mounted) {
      setState(() {
        _sales = sales;
        _repairs = repairs;
        _expenses = expenses;
        _debtPayments = debtPayments;
        _supplierImports = supplierImports;
        _supplierPayments = supplierPayments;
        _previousDayClosing = previousClosing;
        _isLoading = false;
      });
    }
  }

  bool _isSameDay(int timestamp, DateTime target) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return d.year == target.year &&
        d.month == target.month &&
        d.day == target.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CHỐT QUỸ"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: "HÔM NAY"),
            Tab(text: "LỊCH SỬ"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTodayClosing(),
                _buildClosingHistory(),
              ],
            ),
    );
  }

  Widget _buildTodayClosing() {
    final now = DateTime.now();
    final analysis = _analyzeTransactions(now);

    final openingCash = _previousDayClosing?['cashEnd'] as int? ?? 0;
    final openingBank = _previousDayClosing?['bankEnd'] as int? ?? 0;

    final expectedCash = openingCash + analysis.cashIn - analysis.cashOut;
    final expectedBank = openingBank + analysis.bankIn - analysis.bankOut;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ngày
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('EEEE, dd/MM/yyyy', 'vi').format(now),
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Số dư đầu kỳ
            _buildCard("SỐ DƯ ĐẦU KỲ", Colors.blue, [
              _row("Tiền mặt", MoneyUtils.formatVND(openingCash)),
              _row("Ngân hàng", MoneyUtils.formatVND(openingBank)),
              const Divider(),
              _row("Tổng",
                  MoneyUtils.formatVND(openingCash + openingBank),
                  bold: true),
            ]),
            const SizedBox(height: 12),

            // Biến động trong ngày
            _buildCard("BIẾN ĐỘNG TRONG NGÀY", Colors.orange, [
              _row("Thu tiền mặt", "+${MoneyUtils.formatVND(analysis.cashIn)}",
                  color: Colors.green),
              _row("Chi tiền mặt", "-${MoneyUtils.formatVND(analysis.cashOut)}",
                  color: Colors.red),
              const Divider(),
              _row("Thu chuyển khoản",
                  "+${MoneyUtils.formatVND(analysis.bankIn)}",
                  color: Colors.green),
              _row("Chi chuyển khoản",
                  "-${MoneyUtils.formatVND(analysis.bankOut)}",
                  color: Colors.red),
            ]),
            const SizedBox(height: 12),

            // Số dư dự kiến
            _buildCard("SỐ DƯ DỰ KIẾN CUỐI NGÀY", Colors.green, [
              _row("Tiền mặt", MoneyUtils.formatVND(expectedCash)),
              _row("Ngân hàng", MoneyUtils.formatVND(expectedBank)),
              const Divider(),
              _row("Tổng dự kiến",
                  MoneyUtils.formatVND(expectedCash + expectedBank),
                  bold: true),
            ]),
            const SizedBox(height: 24),

            // Nút chốt quỹ
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showClosingDialog(expectedCash, expectedBank),
                icon: const Icon(Icons.check_circle),
                label: const Text("CHỐT QUỸ HÔM NAY"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
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
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingHistory() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.getAllCashClosings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final closings = snapshot.data!;
        if (closings.isEmpty) {
          return const Center(
            child: Text("Chưa có lịch sử chốt quỹ"),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: closings.length,
          itemBuilder: (context, index) {
            final c = closings[index];
            final dateKey = c['dateKey'] as String? ?? '';
            final cashEnd = c['cashEnd'] as int? ?? 0;
            final bankEnd = c['bankEnd'] as int? ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green),
                ),
                title: Text(dateKey, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  "TM: ${MoneyUtils.formatVND(cashEnd)} • CK: ${MoneyUtils.formatVND(bankEnd)}",
                ),
                trailing: Text(
                  MoneyUtils.formatVND(cashEnd + bankEnd),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showClosingDialog(int expectedCash, int expectedBank) {
    cashEndCtrl.text = expectedCash.toString();
    bankEndCtrl.text = expectedBank.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÁC NHẬN CHỐT QUỸ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cashEndCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Tiền mặt thực tế",
                prefixIcon: Icon(Icons.money),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bankEndCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Số dư ngân hàng",
                prefixIcon: Icon(Icons.account_balance),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveClosing();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("LƯU"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveClosing() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final cashEnd = int.tryParse(cashEndCtrl.text) ?? 0;
    final bankEnd = int.tryParse(bankEndCtrl.text) ?? 0;

    final data = {
      'dateKey': dateKey,
      'cashEnd': cashEnd,
      'bankEnd': bankEnd,
      'closedAt': DateTime.now().millisecondsSinceEpoch,
      'closedBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
    };

    await db.upsertCashClosing(data);

    // Sync to cloud
    final shopId = await UserService.getCurrentShopId();
    if (shopId != null) {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('cash_closings')
          .doc(dateKey)
          .set(data, SetOptions(merge: true));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ĐÃ CHỐT QUỸ THÀNH CÔNG")),
      );
      _loadAllData();
    }
  }

  _TransactionAnalysis _analyzeTransactions(DateTime now) {
    int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0;

    // Sales
    for (var s in _sales.where((s) => _isSameDay(s.soldAt, now))) {
      if (s.paymentMethod == 'CÔNG NỢ') continue;
      final amount = s.isInstallment ? s.downPayment : s.totalPrice;
      if (s.paymentMethod == 'TIỀN MẶT') {
        cashIn += amount;
      } else {
        bankIn += amount;
      }
    }

    // Repairs
    for (var r in _repairs.where((r) =>
        r.status == 4 &&
        r.deliveredAt != null &&
        _isSameDay(r.deliveredAt!, now))) {
      if (r.paymentMethod == 'CÔNG NỢ') continue;
      if (r.paymentMethod == 'TIỀN MẶT') {
        cashIn += r.price;
      } else {
        bankIn += r.price;
      }
    }

    // Expenses
    for (var e in _expenses.where((e) => _isSameDay(e['date'] as int, now))) {
      final method = e['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final amount = e['amount'] as int? ?? 0;
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }

    // Supplier imports
    for (var imp in _supplierImports.where((i) =>
        _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, now))) {
      final method = imp['paymentMethod'] as String? ?? 'TIỀN MẶT';
      if (method == 'CÔNG NỢ') continue;
      final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }

    // Supplier payments
    for (var pay in _supplierPayments
        .where((p) => _isSameDay((p['paidAt'] ?? 0) as int, now))) {
      final method = pay['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final amount = (pay['amount'] ?? 0) as int;
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }

    // Debt payments
    for (var p in _debtPayments
        .where((p) => _isSameDay(p['paidAt'] as int, now))) {
      final isShopPay = p['debtType'] == 'SHOP_OWES';
      final method = p['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final amount = p['amount'] as int? ?? 0;
      if (isShopPay) {
        if (method == 'TIỀN MẶT') {
          cashOut += amount;
        } else {
          bankOut += amount;
        }
      } else {
        if (method == 'TIỀN MẶT') {
          cashIn += amount;
        } else {
          bankIn += amount;
        }
      }
    }

    return _TransactionAnalysis(
      cashIn: cashIn,
      cashOut: cashOut,
      bankIn: bankIn,
      bankOut: bankOut,
    );
  }
}

class _TransactionAnalysis {
  final int cashIn;
  final int cashOut;
  final int bankIn;
  final int bankOut;

  _TransactionAnalysis({
    required this.cashIn,
    required this.cashOut,
    required this.bankIn,
    required this.bankOut,
  });
}
