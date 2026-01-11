import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../models/repair_model.dart';
import '../models/expense_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../utils/money_utils.dart';

/// Trang chốt quỹ chuyên nghiệp - Thiết kế lại hoàn toàn
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
  DateTime _selectedDate = DateTime.now();

  // Data
  List<SaleOrder> _sales = [];
  List<Repair> _repairs = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _debtPayments = [];
  List<Map<String, dynamic>> _supplierImports = [];
  List<Map<String, dynamic>> _supplierPayments = [];
  Map<String, dynamic>? _previousDayClosing;
  Map<String, dynamic>? _todayClosing;

  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  StreamSubscription? _closingSubscription;
  StreamSubscription? _debtPaymentsSubscription;
  StreamSubscription? _supplierPaymentsSubscription;
  StreamSubscription? _salesSubscription;
  StreamSubscription? _repairsSubscription;
  StreamSubscription? _expensesSubscription;
  
  // Debounce để tránh load quá nhiều lần
  Timer? _debounceTimer;
  bool _isLoadingFromFirestore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
    _initRealTimeSync();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _closingSubscription?.cancel();
    _debtPaymentsSubscription?.cancel();
    _supplierPaymentsSubscription?.cancel();
    _salesSubscription?.cancel();
    _repairsSubscription?.cancel();
    _expensesSubscription?.cancel();
    _tabController.dispose();
    cashEndCtrl.dispose();
    bankEndCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }
  
  /// Debounced reload - tránh load quá nhiều lần
  void _scheduleReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_isLoadingFromFirestore) {
        _loadAllDataFromFirestore();
      }
    });
  }

  Future<void> _initRealTimeSync() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return;
    
    final shopRef = FirebaseFirestore.instance.collection('shops').doc(shopId);
    
    // Listen to all relevant collections - khi có thay đổi thì schedule reload
    _closingSubscription = shopRef.collection('cash_closings').snapshots().listen((_) {
      _scheduleReload();
    });
    
    _debtPaymentsSubscription = shopRef.collection('debt_payments').snapshots().listen((_) {
      _scheduleReload();
    });
    
    _supplierPaymentsSubscription = shopRef.collection('supplier_payments').snapshots().listen((_) {
      _scheduleReload();
    });
    
    _salesSubscription = shopRef.collection('sales').snapshots().listen((_) {
      _scheduleReload();
    });
    
    _repairsSubscription = shopRef.collection('repairs').snapshots().listen((_) {
      _scheduleReload();
    });
    
    _expensesSubscription = shopRef.collection('expenses').snapshots().listen((_) {
      _scheduleReload();
    });
  }
  
  /// Load dữ liệu trực tiếp từ Firestore để đảm bảo đồng bộ giữa các thiết bị
  Future<void> _loadAllDataFromFirestore() async {
    if (!mounted || _isLoadingFromFirestore) return;
    _isLoadingFromFirestore = true;
    setState(() => _isLoading = true);
    
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        setState(() => _isLoading = false);
        _isLoadingFromFirestore = false;
        return;
      }
      
      final shopRef = FirebaseFirestore.instance.collection('shops').doc(shopId);
      
      // Load từ Firestore song song - lấy tất cả và filter locally
      final results = await Future.wait([
        shopRef.collection('sales').get(),
        shopRef.collection('repairs').get(),
        shopRef.collection('expenses').get(),
        shopRef.collection('debt_payments').get(),
        shopRef.collection('supplier_payments').get(),
      ]);
      
      // Parse sales - filter deleted
      final sales = results[0].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return SaleOrder.fromMap(data);
          }).toList();
      
      // Parse repairs - filter deleted
      final repairs = results[1].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return Repair.fromMap(data);
          }).toList();
      
      // Parse expenses - filter deleted
      final expenses = results[2].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          }).toList();
      
      // Parse debt_payments - filter deleted
      final debtPayments = results[3].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          }).toList();
      
      // Parse supplier_payments - filter deleted
      final supplierPayments = results[4].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          }).toList();
      
      // Load supplier imports từ local (không cần sync realtime)
      final supplierImports = await db.getAllSupplierImportHistory();
      
      // Load closings
      final yesterday = _selectedDate.subtract(const Duration(days: 1));
      final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);
      final todayKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      
      final closingResults = await Future.wait([
        shopRef.collection('cash_closings').doc(yesterdayKey).get(),
        shopRef.collection('cash_closings').doc(todayKey).get(),
      ]);
      
      final previousClosing = closingResults[0].exists ? closingResults[0].data() : null;
      final todayClosing = closingResults[1].exists ? closingResults[1].data() : null;

      if (mounted) {
        setState(() {
          _sales = sales;
          _repairs = repairs;
          _expenses = expenses.cast<Map<String, dynamic>>();
          _debtPayments = debtPayments.cast<Map<String, dynamic>>();
          _supplierImports = supplierImports;
          _supplierPayments = supplierPayments.cast<Map<String, dynamic>>();
          _previousDayClosing = previousClosing;
          _todayClosing = todayClosing;
          _isLoading = false;
        });
      }
      _isLoadingFromFirestore = false;
    } catch (e) {
      debugPrint('Error loading from Firestore: $e');
      _isLoadingFromFirestore = false;
      // Fallback to local DB if Firestore fails
      if (mounted) await _loadAllDataFromLocalDB();
    }
  }
  
  /// Fallback: Load từ local DB khi offline
  Future<void> _loadAllDataFromLocalDB() async {
    final sales = await db.getAllSales();
    final repairs = await db.getAllRepairs();
    final expenses = await db.getAllExpenses();
    final debtPayments = await db.getAllDebtPaymentsWithDetails();
    final supplierImports = await db.getAllSupplierImportHistory();
    final supplierPayments = await db.getAllSupplierPayments();
    final yesterday = _selectedDate.subtract(const Duration(days: 1));
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);
    final previousClosing = await db.getClosingByDateKey(yesterdayKey);
    final todayKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final todayClosing = await db.getClosingByDateKey(todayKey);

    if (mounted) {
      setState(() {
        _sales = sales;
        _repairs = repairs;
        _expenses = expenses;
        _debtPayments = debtPayments;
        _supplierImports = supplierImports;
        _supplierPayments = supplierPayments;
        _previousDayClosing = previousClosing;
        _todayClosing = todayClosing;
        _isLoading = false;
      });
    }
  }
  
  /// Chuyển đổi Timestamp fields sang milliseconds
  void _convertTimestampFields(Map<String, dynamic> data) {
    for (var key in data.keys.toList()) {
      if (data[key] is Timestamp) {
        data[key] = (data[key] as Timestamp).millisecondsSinceEpoch;
      }
    }
  }

  /// Load tất cả dữ liệu - ưu tiên từ Firestore
  Future<void> _loadAllData() async {
    await _loadAllDataFromFirestore();
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
      backgroundColor: const Color(0xFFF5F7FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, _) => [_buildSliverAppBar()],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildIncomeTab(),
                  _buildExpenseTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: false,
      pinned: true,
      backgroundColor: Colors.indigo.shade700,
      foregroundColor: Colors.white,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("CHỐT QUỸ", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM/yyyy', 'vi').format(_selectedDate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_month),
          onPressed: _pickDate,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        tabs: const [
          Tab(icon: Icon(Icons.dashboard, size: 20), text: "Tổng quan"),
          Tab(icon: Icon(Icons.arrow_downward, size: 20), text: "Thu"),
          Tab(icon: Icon(Icons.arrow_upward, size: 20), text: "Chi"),
          Tab(icon: Icon(Icons.history, size: 20), text: "Lịch sử"),
        ],
      ),
    );
  }

  Widget _fundCard(String emoji, String label, int amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 9,
                  ),
                ),
                Text(
                  MoneyUtils.formatVND(amount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('vi'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadAllData();
    }
  }

  Widget _buildOverviewTab() {
    final analysis = _analyzeTransactions(_selectedDate);
    final openingCash = _previousDayClosing?['cashEnd'] as int? ?? 0;
    final openingBank = _previousDayClosing?['bankEnd'] as int? ?? 0;
    final expectedCash = openingCash + analysis.cashIn - analysis.cashOut;
    final expectedBank = openingBank + analysis.bankIn - analysis.bankOut;
    final totalIncome = analysis.cashIn + analysis.bankIn;
    final totalExpense = analysis.cashOut + analysis.bankOut;
    final totalFund = expectedCash + expectedBank;
    final previousTotal = openingCash + openingBank;
    final diff = totalFund - previousTotal;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Card tổng quỹ hiện tại
          _buildCurrentFundCard(expectedCash, expectedBank, totalFund, diff),
          const SizedBox(height: 16),
          _buildOpeningBalanceCard(openingCash, openingBank),
          const SizedBox(height: 16),
          _buildIncomeExpenseChart(totalIncome, totalExpense, analysis),
          const SizedBox(height: 16),
          _buildSectionCard(
            "SỐ DƯ DỰ KIẾN CUỐI NGÀY",
            Icons.savings,
            Colors.green,
            [
              _infoRow("Tiền mặt", MoneyUtils.formatVND(expectedCash)),
              _infoRow("Ngân hàng", MoneyUtils.formatVND(expectedBank)),
              const Divider(height: 16),
              _infoRow(
                "Tổng dự kiến",
                MoneyUtils.formatVND(expectedCash + expectedBank),
                bold: true,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildClosingStatusCard(expectedCash, expectedBank),
        ],
      ),
    );
  }

  Widget _buildCurrentFundCard(int cash, int bank, int total, int diff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                "TỔNG QUỸ HIỆN TẠI",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: diff >= 0 ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${diff >= 0 ? '↑' : '↓'} ${MoneyUtils.formatVND(diff.abs())}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            MoneyUtils.formatVND(total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "💵 Tiền mặt",
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyUtils.formatVND(cash),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "🏦 Ngân hàng",
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyUtils.formatVND(bank),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
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
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningBalanceCard(int openingCash, int openingBank) {
    final hasOpening = _previousDayClosing != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "SỐ DƯ ĐẦU NGÀY",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ),
              if (!hasOpening)
                TextButton.icon(
                  onPressed: _showSetOpeningBalanceDialog,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text("Nhập", style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Tiền mặt", MoneyUtils.formatVND(openingCash)),
          _infoRow("Ngân hàng", MoneyUtils.formatVND(openingBank)),
          const Divider(height: 16),
          _infoRow(
            "Tổng đầu ngày",
            MoneyUtils.formatVND(openingCash + openingBank),
            bold: true,
          ),
          if (!hasOpening)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Chưa có số dư đầu kỳ. Bấm \"Nhập\" để thiết lập.",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSetOpeningBalanceDialog() {
    final openingCashCtrl = TextEditingController();
    final openingBankCtrl = TextEditingController();
    final formatter = NumberFormat('#,###', 'vi');

    String formatCurrency(String value) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return '';
      return formatter.format(int.parse(digits));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "NHẬP SỐ DƯ ĐẦU KỲ",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Số dư này sẽ được dùng làm điểm bắt đầu cho ${DateFormat('dd/MM/yyyy').format(_selectedDate)}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: openingCashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final formatted = formatCurrency(v);
                  if (formatted != v) {
                    openingCashCtrl.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: "💵 Tiền mặt đầu kỳ",
                  hintText: "VD: 10,000,000",
                  suffixText: "đ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.money, color: Colors.amber),
                  filled: true,
                  fillColor: Colors.amber.shade50,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: openingBankCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final formatted = formatCurrency(v);
                  if (formatted != v) {
                    openingBankCtrl.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: "🏦 Số dư ngân hàng đầu kỳ",
                  hintText: "VD: 50,000,000",
                  suffixText: "đ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(
                    Icons.account_balance,
                    color: Colors.blue,
                  ),
                  filled: true,
                  fillColor: Colors.blue.shade50,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("HỦY"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final cashText = openingCashCtrl.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final bankText = openingBankCtrl.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final cashEnd = int.tryParse(cashText) ?? 0;
                        final bankEnd = int.tryParse(bankText) ?? 0;

                        debugPrint(
                          'Saving opening balance: cash=$cashEnd, bank=$bankEnd',
                        );

                        Navigator.pop(ctx);
                        await _saveOpeningBalance(cashEnd, bankEnd);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("LƯU SỐ DƯ ĐẦU KỲ"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
  }

  Future<void> _saveOpeningBalance(int cashEnd, int bankEnd) async {
    debugPrint('_saveOpeningBalance called with cash=$cashEnd, bank=$bankEnd');
    try {
      // Lưu như là chốt quỹ ngày hôm trước
      final yesterday = _selectedDate.subtract(const Duration(days: 1));
      final dateKey = DateFormat('yyyy-MM-dd').format(yesterday);

      // Data cho local DB - chỉ dùng fields có trong schema
      final localData = {
        'dateKey': dateKey,
        'cashStart': 0,
        'bankStart': 0,
        'cashEnd': cashEnd,
        'bankEnd': bankEnd,
        'expectedCashDelta': 0,
        'expectedBankDelta': 0,
        'note': 'Số dư đầu kỳ được nhập thủ công',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      debugPrint('Saving to local DB: $localData');
      await db.upsertCashClosing(localData);
      debugPrint('Local DB saved successfully');

      // Data cho Firestore - có thể chứa thêm metadata
      final firestoreData = {
        ...localData,
        'closedBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        'isManualOpening': true,
      };

      // Sync to Firestore (best effort - local already saved)
      final shopId = await UserService.getCurrentShopId();
      debugPrint('Shop ID: $shopId');
      if (shopId != null) {
        try {
          debugPrint('Saving to Firestore...');
          // Use root collection with shopId field instead of subcollection
          final firestoreDoc = {
            ...firestoreData,
            'shopId': shopId,
            'firestoreId': 'closing_${shopId}_$dateKey',
          };
          await FirebaseFirestore.instance
              .collection('cash_closings')
              .doc('closing_${shopId}_$dateKey')
              .set(firestoreDoc, SetOptions(merge: true));
          debugPrint('Saved to Firestore successfully');
        } catch (e) {
          // Firestore sync failed but local is saved - don't show error
          debugPrint('Firestore sync failed (local saved): $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Đã lưu số dư đầu kỳ"),
            backgroundColor: Colors.indigo,
          ),
        );
        await _loadAllData();
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving opening balance: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildIncomeExpenseChart(
    int totalIncome,
    int totalExpense,
    _TransactionAnalysis analysis,
  ) {
    final maxVal = totalIncome > totalExpense ? totalIncome : totalExpense;
    final incomeRatio = maxVal > 0 ? totalIncome / maxVal : 0.0;
    final expenseRatio = maxVal > 0 ? totalExpense / maxVal : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "BIẾN ĐỘNG TRONG NGÀY",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 50,
                        height: 100 * incomeRatio,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.green.shade300,
                              Colors.green.shade600,
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "📥 THU",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      "+${MoneyUtils.formatVND(totalIncome)}",
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 50,
                        height: 100 * expenseRatio,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.red.shade300, Colors.red.shade600],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "📤 CHI",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      "-${MoneyUtils.formatVND(totalExpense)}",
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          // Phần thu
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "📥 CHI TIẾT THU",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _breakdownItem(
                      "Bán hàng",
                      analysis.saleIncome,
                      Colors.green,
                    ),
                    _breakdownItem(
                      "Sửa chữa",
                      analysis.repairIncome,
                      Colors.green,
                    ),
                    _breakdownItem(
                      "Thu nợ KH",
                      analysis.debtCollected,
                      Colors.green,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "📤 CHI TIẾT CHI",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _breakdownItem("Chi phí", analysis.expenseOut, Colors.red),
                    _breakdownItem("Nhập hàng", analysis.importOut, Colors.red),
                    _breakdownItem(
                      "Trả nợ NCC",
                      analysis.supplierPaid,
                      Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          // Lợi nhuận ròng
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: analysis.netProfit >= 0
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: analysis.netProfit >= 0
                    ? Colors.green.shade200
                    : Colors.red.shade200,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "💰 LỢI NHUẬN RÒNG",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      "${analysis.netProfit >= 0 ? '+' : ''}${MoneyUtils.formatVND(analysis.netProfit)}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: analysis.netProfit >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _breakdownItem(
                        "Giá vốn bán",
                        analysis.saleCost,
                        Colors.orange,
                      ),
                    ),
                    Expanded(
                      child: _breakdownItem(
                        "Giá vốn SC",
                        analysis.repairCost,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "= Doanh thu - Chi phí - Giá vốn",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownItem(String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Text(
            MoneyUtils.formatVND(amount),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingStatusCard(int expectedCash, int expectedBank) {
    final isToday = _isSameDay(
      DateTime.now().millisecondsSinceEpoch,
      _selectedDate,
    );
    final isClosed = _todayClosing != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isClosed ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClosed ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isClosed ? Icons.check_circle : Icons.pending_actions,
            size: 48,
            color: isClosed ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 12),
          Text(
            isClosed ? "✅ ĐÃ CHỐT QUỸ" : "⏳ CHƯA CHỐT QUỸ",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isClosed ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ),
          if (isClosed) ...[
            const SizedBox(height: 8),
            Text(
              "Chốt lúc ${_formatTime(_todayClosing!['closedAt'])} bởi ${_todayClosing!['closedBy'] ?? 'N/A'}",
              style: TextStyle(fontSize: 12, color: Colors.green.shade600),
              textAlign: TextAlign.center,
            ),
            Text(
              "TM: ${MoneyUtils.formatVND(_todayClosing!['cashEnd'] ?? 0)} • CK: ${MoneyUtils.formatVND(_todayClosing!['bankEnd'] ?? 0)}",
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
          if (!isClosed && isToday) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showClosingDialog(expectedCash, expectedBank),
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  "CHỐT QUỸ NGAY",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    return DateFormat(
      'HH:mm dd/MM',
    ).format(DateTime.fromMillisecondsSinceEpoch(timestamp as int));
  }

  Widget _buildIncomeTab() {
    final incomeList = _getIncomeTransactions(_selectedDate);
    final totalIncome = incomeList.fold<int>(
      0,
      (sum, t) => sum + (t['amount'] as int),
    );
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TỔNG THU HÔM NAY",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              Text(
                "+${MoneyUtils.formatVND(totalIncome)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: incomeList.isEmpty
              ? const Center(
                  child: Text(
                    "Không có giao dịch thu",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: incomeList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _transactionCard(incomeList[i], true),
                ),
        ),
      ],
    );
  }

  Widget _buildExpenseTab() {
    final expenseList = _getExpenseTransactions(_selectedDate);
    final totalExpense = expenseList.fold<int>(
      0,
      (sum, t) => sum + (t['amount'] as int),
    );
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.red.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TỔNG CHI HÔM NAY",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              Text(
                "-${MoneyUtils.formatVND(totalExpense)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: expenseList.isEmpty
              ? const Center(
                  child: Text(
                    "Không có giao dịch chi",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: expenseList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _transactionCard(expenseList[i], false),
                ),
        ),
      ],
    );
  }

  Widget _transactionCard(Map<String, dynamic> t, bool isIncome) {
    final color = isIncome ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              t['icon'] as String? ?? '💰',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['title'] as String? ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t['subtitle'] as String? ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  t['time'] as String? ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            "${isIncome ? '+' : '-'}${MoneyUtils.formatVND(t['amount'] as int)}",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: db.getAllCashClosings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final closings = snapshot.data!;
        if (closings.isEmpty) {
          return const Center(child: Text("Chưa có lịch sử chốt quỹ"));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHistoryChart(closings.take(7).toList()),
            const SizedBox(height: 16),
            const Text(
              "LỊCH SỬ CHỐT QUỸ",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...closings.map((c) => _historyCard(c)),
          ],
        );
      },
    );
  }

  Widget _buildHistoryChart(List<Map<String, dynamic>> closings) {
    if (closings.isEmpty) return const SizedBox.shrink();
    final maxTotal = closings
        .map((c) => (c['cashEnd'] as int? ?? 0) + (c['bankEnd'] as int? ?? 0))
        .reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "📊 XU HƯỚNG QUỸ 7 NGÀY",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: closings.reversed.map((c) {
                final total =
                    (c['cashEnd'] as int? ?? 0) + (c['bankEnd'] as int? ?? 0);
                final ratio = maxTotal > 0 ? total / maxTotal : 0.0;
                final dateKey = c['dateKey'] as String? ?? '';
                final day = dateKey.length >= 10
                    ? dateKey.substring(8, 10)
                    : '';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: 70 * ratio,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.indigo.shade300,
                                Colors.indigo.shade600,
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> c) {
    final dateKey = c['dateKey'] as String? ?? '';
    final cashEnd = c['cashEnd'] as int? ?? 0;
    final bankEnd = c['bankEnd'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateKey,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "TM: ${MoneyUtils.formatVND(cashEnd)} • CK: ${MoneyUtils.formatVND(bankEnd)}",
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          Text(
            MoneyUtils.formatVND(cashEnd + bankEnd),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  void _showClosingDialog(int expectedCash, int expectedBank) {
    cashEndCtrl.text = expectedCash.toString();
    bankEndCtrl.text = expectedBank.toString();
    noteCtrl.clear();
    bool isSavingClosing = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final actualCash = int.tryParse(cashEndCtrl.text) ?? 0;
          final actualBank = int.tryParse(bankEndCtrl.text) ?? 0;
          final cashDiff = actualCash - expectedCash;
          final bankDiff = actualBank - expectedBank;
          final hasDiff = cashDiff != 0 || bankDiff != 0;
          final canSubmit = !hasDiff || noteCtrl.text.trim().isNotEmpty;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "XÁC NHẬN CHỐT QUỸ",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy').format(_selectedDate),
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  _closingInputCard(
                    "💵 TIỀN MẶT",
                    expectedCash,
                    cashEndCtrl,
                    cashDiff,
                    () => setModalState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _closingInputCard(
                    "🏦 NGÂN HÀNG",
                    expectedBank,
                    bankEndCtrl,
                    bankDiff,
                    () => setModalState(() {}),
                  ),
                  if (hasDiff) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: "Ghi chú chênh lệch (bắt buộc)",
                        hintText: "Giải thích lý do chênh lệch...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.orange.shade50,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSavingClosing
                              ? null
                              : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text("HỦY"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (!canSubmit || isSavingClosing)
                              ? null
                              : () async {
                                  setModalState(() => isSavingClosing = true);
                                  try {
                                    await _saveClosing();
                                    if (mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    setModalState(
                                      () => isSavingClosing = false,
                                    );
                                    NotificationService.showSnackBar(
                                      "Lỗi: $e",
                                      color: Colors.red,
                                    );
                                  }
                                },
                          icon: isSavingClosing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            isSavingClosing ? "ĐANG LƯU..." : "XÁC NHẬN CHỐT",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _closingInputCard(
    String label,
    int expected,
    TextEditingController ctrl,
    int diff,
    VoidCallback onChanged,
  ) {
    final isOk = diff == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOk ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                "Dự kiến: ",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                MoneyUtils.formatVND(expected),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: "Thực tế",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("Chênh lệch: ", style: TextStyle(fontSize: 12)),
              Text(
                "${diff >= 0 ? '+' : ''}${MoneyUtils.formatVND(diff)}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOk ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isOk ? Icons.check_circle : Icons.warning,
                size: 16,
                color: isOk ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveClosing() async {
    try {
      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      
      // Data cho local DB - chỉ dùng fields có trong schema
      final localData = {
        'dateKey': dateKey,
        'cashEnd': int.tryParse(cashEndCtrl.text) ?? 0,
        'bankEnd': int.tryParse(bankEndCtrl.text) ?? 0,
        'note': noteCtrl.text.trim(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Lưu local trước
      await db.upsertCashClosing(localData);
      
      // Sync to Firestore (best effort)
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null) {
        try {
          final firestoreData = {
            ...localData,
            'shopId': shopId,
            'firestoreId': 'closing_${shopId}_$dateKey',
            'closedAt': DateTime.now().millisecondsSinceEpoch,
            'closedBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
          };
          await FirebaseFirestore.instance
              .collection('cash_closings')
              .doc('closing_${shopId}_$dateKey')
              .set(firestoreData, SetOptions(merge: true));
        } catch (e) {
          // Firestore sync failed but local is saved - log but don't show error
          debugPrint('Firestore sync failed for cash closing (local saved): $e');
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ ĐÃ CHỐT QUỸ THÀNH CÔNG"),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      debugPrint('Error saving closing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getIncomeTransactions(DateTime date) {
    final list = <Map<String, dynamic>>[];
    for (var s in _sales.where(
      (s) => _isSameDay(s.soldAt, date) && s.paymentMethod != 'CÔNG NỢ',
    )) {
      list.add({
        'icon': '🛒',
        'title': 'Bán hàng #${s.firestoreId?.substring(0, 8) ?? s.id}',
        'subtitle':
            '${s.customerName ?? 'KH lẻ'} • ${s.paymentMethod == 'TIỀN MẶT' ? '💵' : '🏦'} ${s.paymentMethod}',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(s.soldAt)),
        'amount': s.isInstallment ? s.downPayment : s.totalPrice,
      });
    }
    
    // Thêm tiền tất toán từ ngân hàng (trả góp đã nhận tiền trong ngày)
    for (var s in _sales.where(
      (s) => s.isInstallment && 
             s.settlementReceivedAt != null && 
             _isSameDay(s.settlementReceivedAt!, date) &&
             s.settlementAmount > 0,
    )) {
      // Tính số tiền thực nhận từ settlement (clamp để tránh đúp khi set sai)
      final isSameDayAsSale = _isSameDay(s.soldAt, date);
      final actualAmount = isSameDayAsSale 
          ? s.settlementAmount.clamp(0, s.loanAmount) 
          : s.settlementAmount;
      
      if (actualAmount > 0) {
        list.add({
          'icon': '🏦',
          'title': 'Tất toán NH: ${s.bankName ?? "Ngân hàng"}',
          'subtitle':
              '${s.customerName ?? 'KH'} • Đơn #${s.firestoreId?.substring(0, 8) ?? s.id}',
          'time': DateFormat(
            'HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(s.settlementReceivedAt!)),
          'amount': actualAmount,
        });
      }
    }
    
    for (var r in _repairs.where(
      (r) =>
          r.status == 4 &&
          r.deliveredAt != null &&
          _isSameDay(r.deliveredAt!, date) &&
          r.paymentMethod != 'CÔNG NỢ',
    )) {
      list.add({
        'icon': '🔧',
        'title': 'Sửa chữa #${r.firestoreId?.substring(0, 8) ?? r.id}',
        'subtitle':
            '${r.customerName ?? 'KH'} • ${r.paymentMethod == 'TIỀN MẶT' ? '💵' : '🏦'} ${r.paymentMethod}',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!)),
        'amount': r.price,
      });
    }
    for (var p in _debtPayments.where(
      (p) =>
          _isSameDay(p['paidAt'] as int, date) && p['debtType'] != 'SHOP_OWES',
    )) {
      list.add({
        'icon': '💳',
        'title': 'Thu nợ khách hàng',
        'subtitle':
            '${p['customerName'] ?? 'KH'} • ${(p['paymentMethod'] ?? 'TIỀN MẶT') == 'TIỀN MẶT' ? '💵' : '🏦'}',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int)),
        'amount': p['amount'] as int? ?? 0,
      });
    }
    // Tiền tất toán từ ngân hàng (trả góp đã nhận tiền trong ngày)
    for (var s in _sales.where(
      (s) => s.isInstallment && 
             s.settlementReceivedAt != null && 
             _isSameDay(s.settlementReceivedAt!, date) &&
             s.settlementAmount > 0,
    )) {
      list.add({
        'icon': '🏦',
        'title': 'Tất toán NH: ${s.bankName ?? "Ngân hàng"}',
        'subtitle': '${s.customerName ?? 'KH'} • 🏦 CHUYỂN KHOẢN',
        'time': DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(s.settlementReceivedAt!),
        ),
        'amount': s.settlementAmount,
      });
    }
    list.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
    return list;
  }

  List<Map<String, dynamic>> _getExpenseTransactions(DateTime date) {
    final list = <Map<String, dynamic>>[];
    
    // Debug log
    debugPrint('=== _getExpenseTransactions for ${DateFormat('dd/MM/yyyy').format(date)} ===');
    debugPrint('Total expenses: ${_expenses.length}');
    debugPrint('Total supplierImports: ${_supplierImports.length}');
    debugPrint('Total supplierPayments: ${_supplierPayments.length}');
    debugPrint('Total debtPayments: ${_debtPayments.length}');
    
    // Chi phí thường - HIỂN THỊ TẤT CẢ (bao gồm nhập hàng, trả nợ...)
    // Lưu ý: Logic loại trừ chỉ áp dụng trong _analyzeTransactions để tránh double-counting cashFlow
    for (var e in _expenses) {
      final expenseDate = e['date'] as int?;
      if (expenseDate == null) {
        debugPrint('Skipping expense with null date: ${e['category']}');
        continue;
      }
      if (!_isSameDay(expenseDate, date)) continue;
      
      final category = e['category'] as String? ?? 'Chi phí';
      debugPrint('Adding expense to list: $category, amount=${e['amount']}');
      
      list.add({
        'icon': '💸',
        'title': category,
        'subtitle':
            '${e['note'] ?? ''} • ${(e['paymentMethod'] ?? 'TIỀN MẶT') == 'TIỀN MẶT' ? '💵' : '🏦'}',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(expenseDate)),
        'amount': e['amount'] as int? ?? 0,
      });
    }
    for (var imp in _supplierImports.where(
      (i) =>
          _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, date) &&
          (i['paymentMethod'] ?? '') != 'CÔNG NỢ',
    )) {
      list.add({
        'icon': '📦',
        'title': 'Nhập hàng',
        'subtitle':
            '${imp['supplierName'] ?? 'NCC'} • ${(imp['paymentMethod'] ?? 'TIỀN MẶT') == 'TIỀN MẶT' ? '💵' : '🏦'}',
        'time': DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(
            (imp['importDate'] ?? imp['createdAt'] ?? 0) as int,
          ),
        ),
        'amount': (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int,
      });
    }
    for (var pay in _supplierPayments.where(
      (p) => _isSameDay((p['paidAt'] ?? 0) as int, date),
    )) {
      list.add({
        'icon': '🏭',
        'title': 'Trả nợ NCC',
        'subtitle':
            '${pay['supplierName'] ?? 'NCC'} • ${(pay['paymentMethod'] ?? 'TIỀN MẶT') == 'TIỀN MẶT' ? '💵' : '🏦'}',
        'time': DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch((pay['paidAt'] ?? 0) as int),
        ),
        'amount': (pay['amount'] ?? 0) as int,
      });
    }
    for (var p in _debtPayments.where(
      (p) {
        final paidAt = p['paidAt'];
        if (paidAt == null) return false;
        return _isSameDay(paidAt as int, date) && p['debtType'] == 'SHOP_OWES';
      },
    )) {
      list.add({
        'icon': '💳',
        'title': 'Trả nợ khách',
        'subtitle':
            '${p['customerName'] ?? 'KH'} • ${(p['paymentMethod'] ?? 'TIỀN MẶT') == 'TIỀN MẶT' ? '💵' : '🏦'}',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int)),
        'amount': p['amount'] as int? ?? 0,
      });
    }
    list.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
    return list;
  }

  _TransactionAnalysis _analyzeTransactions(DateTime now) {
    int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0;
    int saleIncome = 0, repairIncome = 0, debtCollected = 0;
    int expenseOut = 0, importOut = 0, supplierPaid = 0;
    int saleCost = 0, repairCost = 0; // Giá vốn
    int settlementIncome = 0; // Tiền tất toán từ ngân hàng

    for (var s in _sales.where((s) => _isSameDay(s.soldAt, now))) {
      if (s.paymentMethod == 'CÔNG NỢ') continue;
      final amount = s.isInstallment ? s.downPayment : s.totalPrice;
      saleIncome += amount;
      if (s.paymentMethod == 'TIỀN MẶT') {
        cashIn += amount;
      } else {
        bankIn += amount;
      }

      // Tính giá vốn (cho đơn đã thu tiền)
      if (s.isInstallment) {
        // Trả góp: tính giá vốn theo tỷ lệ đã thu
        final ratio = s.totalPrice > 0 ? amount / s.totalPrice : 0.0;
        saleCost += (s.totalCost * ratio).round();
      } else {
        saleCost += s.totalCost;
      }
    }
    
    // Tính tiền tất toán từ ngân hàng nhận trong ngày
    for (var s in _sales.where(
      (s) => s.isInstallment && 
             s.settlementReceivedAt != null && 
             _isSameDay(s.settlementReceivedAt!, now) &&
             s.settlementAmount > 0,
    )) {
      // CHỈ tính settlement nếu KHÁC ngày bán (để tránh đúp)
      // Nếu cùng ngày bán, đã tính downPayment ở trên rồi
      final isSameDayAsSale = _isSameDay(s.soldAt, now);
      if (isSameDayAsSale) {
        // Cùng ngày: chỉ cộng thêm phần chênh lệch (settlement - downPayment đã tính)
        // settlement thực tế = loanAmount = totalPrice - downPayment
        // Nên chỉ cần cộng (settlementAmount) nếu settlementAmount <= loanAmount
        final actualSettlement = s.settlementAmount.clamp(0, s.loanAmount);
        if (actualSettlement > 0) {
          settlementIncome += actualSettlement;
          bankIn += actualSettlement;
          // Tính giá vốn phần còn lại
          final downPaymentRatio = s.totalPrice > 0 ? s.downPayment / s.totalPrice : 0.0;
          final remainingCostRatio = 1.0 - downPaymentRatio;
          saleCost += (s.totalCost * remainingCostRatio).round();
        }
      } else {
        // Khác ngày: tính toàn bộ settlementAmount
        settlementIncome += s.settlementAmount;
        bankIn += s.settlementAmount;
        // Tính giá vốn còn lại
        final downPaymentRatio = s.totalPrice > 0 ? s.downPayment / s.totalPrice : 0.0;
        final remainingCostRatio = 1.0 - downPaymentRatio;
        saleCost += (s.totalCost * remainingCostRatio).round();
      }
    }
    
    for (var r in _repairs.where(
      (r) =>
          r.status == 4 &&
          r.deliveredAt != null &&
          _isSameDay(r.deliveredAt!, now),
    )) {
      if (r.paymentMethod == 'CÔNG NỢ') continue;
      repairIncome += r.price;
      if (r.paymentMethod == 'TIỀN MẶT') {
        cashIn += r.price;
      } else {
        bankIn += r.price;
      }
      repairCost += r.totalCost; // Giá vốn linh kiện sửa chữa
    }
    for (var e in _expenses.where((e) {
      final dateVal = e['date'];
      if (dateVal == null) return false;
      return _isSameDay(dateVal as int, now);
    })) {
      final method = e['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final amount = e['amount'] as int? ?? 0;
      final category = (e['category'] as String? ?? '').toUpperCase();
      final description = (e['description'] as String? ?? '').toUpperCase();
      final title = (e['title'] as String? ?? '').toUpperCase();
      
      // LUÔN tính vào dòng tiền (cashOut/bankOut) - đây là tiền thực chi ra
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
      
      // Chỉ loại trừ nhập hàng/purchase khỏi expenseOut (dùng cho tính profit)
      // vì chi phí nhập hàng sẽ được tính qua giá vốn khi bán/sửa
      final isImportExpense =
          category.contains('NHẬP HÀNG') ||
          category.contains('NHẬP LINH KIỆN') ||
          category.contains('PURCHASE') ||
          category.contains('STOCK') ||
          category.contains('ĐƠN NHẬP') ||
          category.contains('LINH KIỆN') ||
          category.contains('REPAIR_PARTS') ||
          description.contains('NHẬP LINH KIỆN') ||
          description.contains('NHẬP HÀNG') ||
          title.contains('NHẬP LINH KIỆN') ||
          title.contains('NHẬP HÀNG');
      if (!isImportExpense) {
        expenseOut += amount;
      }
    }
    for (var imp in _supplierImports.where(
      (i) => _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, now),
    )) {
      final method = imp['paymentMethod'] as String? ?? 'TIỀN MẶT';
      if (method == 'CÔNG NỢ') continue;
      final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
      importOut += amount;
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }
    for (var pay in _supplierPayments.where(
      (p) => _isSameDay((p['paidAt'] ?? 0) as int, now),
    )) {
      final method = pay['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final amount = (pay['amount'] ?? 0) as int;
      supplierPaid += amount;
      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }
    for (var p in _debtPayments.where((p) {
      final paidAt = p['paidAt'];
      if (paidAt == null) return false;
      return _isSameDay(paidAt as int, now);
    })) {
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
        debtCollected += amount;
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
      saleIncome: saleIncome,
      settlementIncome: settlementIncome,
      repairIncome: repairIncome,
      debtCollected: debtCollected,
      expenseOut: expenseOut,
      importOut: importOut,
      supplierPaid: supplierPaid,
      saleCost: saleCost,
      repairCost: repairCost,
    );
  }
}

class _TransactionAnalysis {
  final int cashIn, cashOut, bankIn, bankOut;
  final int saleIncome, settlementIncome, repairIncome, debtCollected;
  final int expenseOut, importOut, supplierPaid;
  final int saleCost, repairCost; // Giá vốn hàng đã bán và sửa chữa
  _TransactionAnalysis({
    required this.cashIn,
    required this.cashOut,
    required this.bankIn,
    required this.bankOut,
    required this.saleIncome,
    required this.settlementIncome,
    required this.repairIncome,
    required this.debtCollected,
    required this.expenseOut,
    required this.importOut,
    required this.supplierPaid,
    required this.saleCost,
    required this.repairCost,
  });

  /// Lợi nhuận ròng = (Doanh thu bán + tất toán + sửa chữa + thu nợ) - (Chi phí + giá vốn)
  /// Không tính nhập hàng vào vì đó là dòng tiền, không phải chi phí
  int get netProfit =>
      saleIncome +
      settlementIncome +
      repairIncome +
      debtCollected -
      expenseOut -
      saleCost -
      repairCost;
}
