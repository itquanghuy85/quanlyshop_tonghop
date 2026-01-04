import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/sync_service.dart';
import '../widgets/currency_text_field.dart';
import 'debt_view.dart';
import 'warranty_view.dart';

class RevenueView extends StatefulWidget {
  const RevenueView({super.key});
  @override
  State<RevenueView> createState() => _RevenueViewState();
}

class _RevenueViewState extends State<RevenueView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;

  List<Repair> _repairs = [];
  List<SaleOrder> _sales = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _closings = [];
  List<Map<String, dynamic>> _debtPayments = [];
  bool _hasRevenueAccess = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatus = 'Đã đồng bộ';
  final String _selectedPeriod = 'Tháng này';

  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _loadPermissions();
    _loadAllData();
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _hasRevenueAccess = perms['allowViewRevenue'] ?? false;
    });
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();
    final expenses = await db.getAllExpenses();
    final debtPayments = await db.getAllDebtPaymentsWithDetails();

    final dbRaw = await db.database;
    final closings = await dbRaw.query(
      'cash_closings',
      orderBy: 'createdAt DESC',
      limit: 10,
    );

    if (!mounted) return;
    setState(() {
      _repairs = repairs;
      _sales = sales;
      _expenses = expenses;
      _debtPayments = debtPayments;
      _closings = closings;
      _isLoading = false;
    });
  }

  Future<void> _syncWithFirebase() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Đang đồng bộ...';
    });

    try {
      await SyncService.syncAllToCloud();
      await SyncService.downloadAllFromCloud();

      // Reload data after sync
      await _loadAllData();

      if (mounted) {
        setState(() {
          _syncStatus = 'Đã đồng bộ';
        });
      }
    } catch (e) {
      print('DEBUG: Sync error: $e');
      if (mounted) {
        setState(() {
          _syncStatus = 'Lỗi đồng bộ';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  bool _isSameDay(int ms, DateTime day) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return dt.day == day.day && dt.month == day.month && dt.year == day.year;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasRevenueAccess)
      return const Scaffold(
        body: Center(child: Text("Bạn không có quyền truy cập")),
      );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text(
          "QUẢN LÝ TÀI CHÍNH",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        automaticallyImplyLeading: true,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _syncStatus,
                style: TextStyle(
                  fontSize: 12,
                  color: _syncStatus == 'Lỗi đồng bộ'
                      ? Colors.red
                      : Colors.grey[600],
                  fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? Colors.orange : Colors.blue,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "TỔNG QUAN"),
            Tab(text: "CHỐT QUỸ"),
            Tab(text: "BÁN HÀNG"),
            Tab(text: "SỬA CHỮA"),
            Tab(text: "BẢO HÀNH"),
            Tab(text: "CHI TIÊU"),
            Tab(text: "CÔNG NỢ"),
            Tab(text: "DÒNG TIỀN"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildCashClosingTab(),
                _buildSaleDetail(),
                _buildRepairDetail(),
                const WarrantyView(),
                _buildExpenseDetail(),
                const DebtView(),
                _buildCashFlowHistory(),
              ],
            ),
    );
  }

  Widget _buildCashClosingTab() {
    final now = DateTime.now();
    List<_TransactionItem> todayTrans = [];

    for (var s in _sales.where((s) => _isSameDay(s.soldAt, now))) {
      todayTrans.add(
        _TransactionItem(
          title: "Bán: ${s.productNames}",
          amount: s.totalPrice,
          method: s.paymentMethod,
          time: s.soldAt,
          type: "IN",
          isDebt: s.paymentMethod == "CÔNG NỢ",
        ),
      );
    }
    // Chỉ tính repair khi status == 4 (Đã giao) và có deliveredAt
    for (var r in _repairs.where(
      (r) =>
          r.status == 4 &&
          r.deliveredAt != null &&
          _isSameDay(r.deliveredAt!, now),
    )) {
      todayTrans.add(
        _TransactionItem(
          title: "Sửa: ${r.model}",
          amount: r.price,
          method: r.paymentMethod,
          time: r.deliveredAt!,
          type: "IN",
          isDebt: r.paymentMethod == "CÔNG NỢ",
        ),
      );
    }
    for (var e in _expenses.where((e) => _isSameDay(e['date'] as int, now))) {
      todayTrans.add(
        _TransactionItem(
          title: "Chi: ${e['title']}",
          amount: e['amount'],
          method: e['paymentMethod'] ?? 'TIỀN MẶT',
          time: e['date'],
          type: "OUT",
          isDebt: false,
        ),
      );
    }
    for (var p in _debtPayments.where(
      (p) => _isSameDay(p['paidAt'] as int, now),
    )) {
      bool isShopPay = p['debtType'] == 'SHOP_OWES';
      todayTrans.add(
        _TransactionItem(
          title: isShopPay
              ? "Trả nợ NCC: ${p['personName']}"
              : "Thu nợ: ${p['personName']}",
          amount: p['amount'],
          method: p['paymentMethod'] ?? 'TIỀN MẶT',
          time: p['paidAt'],
          type: isShopPay ? "OUT" : "IN",
          isDebt: false,
        ),
      );
    }

    todayTrans.sort((a, b) => b.time.compareTo(a.time));

    int cashExp =
        todayTrans
            .where((t) => t.type == "IN" && !t.isDebt && t.method == "TIỀN MẶT")
            .fold<int>(0, (sum, t) => sum + t.amount) -
        todayTrans
            .where((t) => t.type == "OUT" && t.method == "TIỀN MẶT")
            .fold<int>(0, (sum, t) => sum + t.amount);
    int bankExp =
        todayTrans
            .where(
              (t) => t.type == "IN" && !t.isDebt && t.method == "CHUYỂN KHOẢN",
            )
            .fold<int>(0, (sum, t) => sum + t.amount) -
        todayTrans
            .where((t) => t.type == "OUT" && t.method == "CHUYỂN KHOẢN")
            .fold<int>(0, (sum, t) => sum + t.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _balanceCard("TIỀN MẶT DỰ TÍNH", cashExp, Colors.orange),
            const SizedBox(width: 12),
            _balanceCard("NGÂN HÀNG DỰ TÍNH", bankExp, Colors.blue),
          ],
        ),
        const SizedBox(height: 24),
        _inputClosingSection(),
        const SizedBox(height: 30),
        const Text(
          "GIAO DỊCH TRONG NGÀY",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 12),
        if (todayTrans.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text("Chưa có giao dịch"),
            ),
          )
        else
          ...todayTrans.map((t) => _buildTransactionRow(t)),
      ],
    );
  }

  Widget _buildTransactionRow(_TransactionItem t) {
    Color methodColor = t.method == "CHUYỂN KHOẢN"
        ? Colors.blue
        : (t.isDebt ? Colors.purple : Colors.orange);
    IconData icon = t.isDebt
        ? Icons.book_rounded
        : (t.type == "IN"
              ? Icons.add_circle_outline
              : Icons.remove_circle_outline);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: methodColor),
        title: Text(
          t.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          "${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.time))} | ${t.method}",
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          "${t.type == "IN" ? "+" : "-"}${NumberFormat('#,###').format(t.amount)}",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: t.type == "IN" ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }

  Widget _inputClosingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "ĐỐI SOÁT THỰC TẾ CUỐI NGÀY",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          CurrencyTextField(
            controller: cashEndCtrl,
            label: "TIỀN MẶT ĐẾM ĐƯỢC",
            icon: Icons.payments,
          ),
          const SizedBox(height: 12),
          CurrencyTextField(
            controller: bankEndCtrl,
            label: "SỐ DƯ NGÂN HÀNG THỰC TẾ",
            icon: Icons.account_balance,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saveClosing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
              ),
              child: const Text(
                "XÁC NHẬN CHỐT QUỸ",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveClosing() async {
    final cash = int.tryParse(cashEndCtrl.text.replaceAll('.', '')) ?? 0;
    final bank = int.tryParse(bankEndCtrl.text.replaceAll('.', '')) ?? 0;
    if (cash == 0 && bank == 0) return;
    await db.upsertClosing({
      'dateKey': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'cashEnd': cash,
      'bankEnd': bank,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final user = FirebaseAuth.instance.currentUser;
    await db.logAction(
      userId: user?.uid ?? "0",
      userName: user?.email?.split('@').first.toUpperCase() ?? "ADMIN",
      action: "CHỐT QUỸ",
      type: "FINANCE",
      desc:
          "Tiền mặt: ${NumberFormat('#,###').format(cash)}đ, Ngân hàng: ${NumberFormat('#,###').format(bank)}đ",
    );
    NotificationService.showSnackBar(
      "Đã chốt quỹ thành công!",
      color: Colors.green,
    );
    HapticFeedback.mediumImpact();
    _loadAllData();
    cashEndCtrl.clear();
    bankEndCtrl.clear();
  }

  Widget _balanceCard(String l, int v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l,
            style: TextStyle(
              fontSize: 9,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            NumberFormat('#,###').format(v),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildOverview() {
    final now = DateTime.now();
    final fSales = _sales.where((s) => _isSameDay(s.soldAt, now)).toList();
    // Chỉ tính repair khi status == 4 (Đã giao) và có deliveredAt
    final fRepairs = _repairs
        .where(
          (r) =>
              r.status == 4 &&
              r.deliveredAt != null &&
              _isSameDay(r.deliveredAt!, now),
        )
        .toList();
    final fExpenses = _expenses
        .where((e) => _isSameDay(e['date'] as int, now))
        .toList();
    int totalIn =
        fSales.fold<int>(0, (sum, s) => sum + s.totalPrice) +
        fRepairs.fold<int>(0, (sum, r) => sum + r.price);
    int totalOut = fExpenses.fold<int>(
      0,
      (sum, e) => sum + (e['amount'] as int),
    );
    int profit =
        totalIn -
        totalOut -
        fSales.fold<int>(0, (sum, s) => sum + s.totalCost) -
        fRepairs.fold<int>(0, (sum, r) => sum + r.totalCost);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            "TỔNG QUAN HÔM NAY",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2962FF),
            ),
          ),
          const SizedBox(height: 16),

          // Revenue Cards Row
          Row(
            children: [
              Expanded(
                child: _miniCard("THU HÔM NAY", totalIn, Colors.green.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _miniCard("CHI HÔM NAY", totalOut, Colors.red.shade700),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Profit Card
          _mainProfitCard(profit),

          const SizedBox(height: 24),

          // Quick Stats
          const Text(
            "THỐNG KÊ NHANH",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _statCard(
                  "Đơn bán hàng",
                  fSales.length.toString(),
                  Icons.shopping_cart,
                  Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  "Đơn sửa chữa",
                  fRepairs.length.toString(),
                  Icons.build,
                  Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  "Chi phí",
                  fExpenses.length.toString(),
                  Icons.receipt,
                  Colors.purple.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String l, int v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l,
            style: TextStyle(
              fontSize: 10,
              color: c.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            NumberFormat('#,###').format(v),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _mainProfitCard(int p) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: p >= 0
            ? [Colors.green.shade600, Colors.green.shade400]
            : [Colors.red.shade600, Colors.red.shade400],
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: (p >= 0 ? Colors.green : Colors.red).withOpacity(0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        Text(
          "LỢI NHUẬN RÒNG HÔM NAY",
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "${NumberFormat('#,###').format(p)} đ",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
  Widget _buildSaleDetail() {
    final list = _sales
        .where((s) => _isSameDay(s.soldAt, DateTime.now()))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) => Card(
        child: ListTile(
          title: Text(list[i].productNames),
          subtitle: Text("Khách: ${list[i].customerName}"),
          trailing: Text(
            "+${NumberFormat('#,###').format(list[i].totalPrice)}",
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // Chỉ hiển thị repair đã giao (status == 4) và có deliveredAt hôm nay
  Widget _buildRepairDetail() {
    final list = _repairs
        .where(
          (r) =>
              r.status == 4 &&
              r.deliveredAt != null &&
              _isSameDay(r.deliveredAt!, DateTime.now()),
        )
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) => Card(
        child: ListTile(
          title: Text(list[i].model),
          subtitle: Text("Khách: ${list[i].customerName}"),
          trailing: Text(
            "+${NumberFormat('#,###').format(list[i].price)}",
            style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseDetail() {
    final list = _expenses
        .where((e) => _isSameDay(e['date'] as int, DateTime.now()))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) => Card(
        child: ListTile(
          title: Text(list[i]['title'] ?? 'Chi phí'),
          subtitle: Text(list[i]['category'] ?? 'Khác'),
          trailing: Text(
            "-${NumberFormat('#,###').format(list[i]['amount'])}",
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCashFlowHistory() {
    // Collect all transactions with dates
    List<_TransactionItem> allTransactions = [];

    // Sales
    for (var s in _sales) {
      allTransactions.add(
        _TransactionItem(
          title: "Bán: ${s.productNames}",
          amount: s.totalPrice,
          method: s.paymentMethod,
          time: s.soldAt,
          type: "IN",
          isDebt: s.paymentMethod == "CÔNG NỢ",
        ),
      );
    }

    // Repairs
    for (var r in _repairs.where((r) => r.status == 4 && r.deliveredAt != null)) {
      allTransactions.add(
        _TransactionItem(
          title: "Sửa: ${r.model}",
          amount: r.price,
          method: r.paymentMethod,
          time: r.deliveredAt!,
          type: "IN",
          isDebt: r.paymentMethod == "CÔNG NỢ",
        ),
      );
    }

    // Expenses
    for (var e in _expenses) {
      allTransactions.add(
        _TransactionItem(
          title: "Chi: ${e['title']}",
          amount: e['amount'],
          method: e['paymentMethod'] ?? 'TIỀN MẶT',
          time: e['date'],
          type: "OUT",
          isDebt: false,
        ),
      );
    }

    // Debt payments
    for (var p in _debtPayments) {
      bool isShopPay = p['debtType'] == 'SHOP_OWES';
      allTransactions.add(
        _TransactionItem(
          title: isShopPay
              ? "Trả nợ NCC: ${p['personName']}"
              : "Thu nợ: ${p['personName']}",
          amount: p['amount'],
          method: p['paymentMethod'] ?? 'TIỀN MẶT',
          time: p['paidAt'],
          type: isShopPay ? "OUT" : "IN",
          isDebt: false,
        ),
      );
    }

    // Sort by time descending
    allTransactions.sort((a, b) => b.time.compareTo(a.time));

    if (allTransactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text("Chưa có giao dịch nào", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allTransactions.length,
      itemBuilder: (ctx, i) {
        final item = allTransactions[i];
        final date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.time));
        final isIncome = item.type == "IN";

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                color: isIncome ? Colors.green : Colors.red,
                size: 20,
              ),
            ),
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${item.method} • $date"),
                if (item.isDebt) const Text("Công nợ", style: TextStyle(color: Colors.orange, fontSize: 12)),
              ],
            ),
            trailing: Text(
              "${isIncome ? '+' : '-'}${NumberFormat('#,###').format(item.amount)}đ",
              style: TextStyle(
                color: isIncome ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 9, color: color.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _TransactionItem {
  final String title;
  final int amount;
  final String method;
  final int time;
  final String type;
  final bool isDebt;
  _TransactionItem({
    required this.title,
    required this.amount,
    required this.method,
    required this.time,
    required this.type,
    required this.isDebt,
  });
}
