import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/sync_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'debt_view.dart';
import 'warranty_view.dart';
import 'customer_receivables_view.dart';

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
  Map<String, dynamic>? _todayClosing; // Thông tin chốt quỹ hôm nay
  bool _hasRevenueAccess = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatus = 'Đã đồng bộ';
  
  // Real-time listener cho cash_closings
  StreamSubscription<DocumentSnapshot>? _closingSubscription;
  
  // Filter states
  String _timeFilter = 'today'; // today, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _loadPermissions();
    _loadAllData();
    _initClosingRealTimeSync();
    // Lắng nghe real-time sync từ cloud
    SyncService.initRealTimeSync(() {
      if (mounted) _loadAllData();
    });
  }
  
  @override
  void dispose() {
    _closingSubscription?.cancel();
    _tabController.dispose();
    cashEndCtrl.dispose();
    bankEndCtrl.dispose();
    super.dispose();
  }
  
  /// Khởi tạo real-time sync cho cash_closings để các máy khác nhận được update
  Future<void> _initClosingRealTimeSync() async {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return;
    
    final docId = "closing_${shopId}_$todayKey";
    
    _closingSubscription = FirebaseFirestore.instance
        .collection('cash_closings')
        .doc(docId)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && mounted) {
        final cloudData = snapshot.data()!;
        final cloudIsLocked = cloudData['isLocked'];
        final localIsLocked = _todayClosing?['isLocked'];
        
        // Nếu trạng thái khóa khác nhau, cập nhật local DB và UI
        if (cloudIsLocked != localIsLocked) {
          debugPrint('Cash closing sync: Cloud isLocked=$cloudIsLocked, Local isLocked=$localIsLocked');
          
          // Cập nhật local DB
          final dbRaw = await db.database;
          await dbRaw.update(
            'cash_closings',
            {
              'isLocked': cloudIsLocked == true || cloudIsLocked == 1 ? 1 : 0,
              'lockedBy': cloudData['lockedBy'],
              'lockedAt': cloudData['lockedAt'],
              'unlockedBy': cloudData['unlockedBy'],
              'unlockedAt': cloudData['unlockedAt'],
              'cashEnd': cloudData['cashEnd'],
              'bankEnd': cloudData['bankEnd'],
            },
            where: 'dateKey = ?',
            whereArgs: [todayKey],
          );
          
          // Reload UI
          await _loadAllData();
          
          // Hiển thị thông báo
          final isNowLocked = cloudIsLocked == true || cloudIsLocked == 1;
          NotificationService.showSnackBar(
            isNowLocked 
                ? "🔒 Quỹ hôm nay đã được ${cloudData['lockedBy']} chốt!" 
                : "🔓 Quỹ hôm nay đã được ${cloudData['unlockedBy']} mở khóa!",
            color: isNowLocked ? Colors.green : Colors.orange,
          );
        }
      }
    });
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
    
    // Lấy thông tin chốt quỹ của ngày hôm nay
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayClosingResult = await dbRaw.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [todayKey],
      limit: 1,
    );

    if (!mounted) return;
    setState(() {
      _repairs = repairs;
      _sales = sales;
      _expenses = expenses;
      _debtPayments = debtPayments;
      _closings = closings;
      _todayClosing = todayClosingResult.isNotEmpty ? todayClosingResult.first : null;
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

  bool _isInFilterPeriod(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (_timeFilter) {
      case 'today':
        return _isSameDay(ms, now);
      case 'week':
        final weekAgo = today.subtract(const Duration(days: 7));
        return !dt.isBefore(weekAgo);
      case 'month':
        final monthStart = DateTime(now.year, now.month, 1);
        return !dt.isBefore(monthStart);
      case 'custom':
        if (_customStartDate != null && dt.isBefore(_customStartDate!)) return false;
        if (_customEndDate != null && dt.isAfter(_customEndDate!.add(const Duration(days: 1)))) return false;
        return true;
      default:
        return true;
    }
  }

  String _getFilterLabel() {
    switch (_timeFilter) {
      case 'today': return 'HÔM NAY';
      case 'week': return '7 NGÀY QUA';
      case 'month': return 'THÁNG NÀY';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('dd/MM').format(_customStartDate!)} - ${DateFormat('dd/MM').format(_customEndDate!)}';
        }
        return 'TÙY CHỌN';
      default: return '';
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('LỌC THEO THỜI GIAN', style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('Hôm nay', 'today', setSheetState),
                  _filterChip('7 ngày', 'week', setSheetState),
                  _filterChip('Tháng này', 'month', setSheetState),
                  _customDateChip(ctx, setSheetState),
                ],
              ),
              if (_timeFilter == 'custom' && _customStartDate != null && _customEndDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.date_range, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}',
                          style: AppTextStyles.body2.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {}); // Refresh main view
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('ÁP DỤNG', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value, StateSetter setSheetState) {
    final isSelected = _timeFilter == value;
    return GestureDetector(
      onTap: () => setSheetState(() => _timeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.onSurface.withOpacity(0.2)),
        ),
        child: Text(
          label,
          style: AppTextStyles.body2.copyWith(
            color: isSelected ? Colors.white : AppColors.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _customDateChip(BuildContext ctx, StateSetter setSheetState) {
    final isSelected = _timeFilter == 'custom';
    return GestureDetector(
      onTap: () async {
        final range = await showDateRangePicker(
          context: ctx,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
            : null,
          locale: const Locale('vi', 'VN'),
        );
        if (range != null) {
          setSheetState(() {
            _timeFilter = 'custom';
            _customStartDate = range.start;
            _customEndDate = range.end;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.onSurface.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, size: 16, color: isSelected ? Colors.white : AppColors.onSurface),
            const SizedBox(width: 6),
            Text(
              'Tùy chọn',
              style: AppTextStyles.body2.copyWith(
                color: isSelected ? Colors.white : AppColors.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasRevenueAccess)
      return const Scaffold(
        body: Center(child: Text("Bạn không có quyền truy cập")),
      );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "QUẢN LÝ TÀI CHÍNH",
              style: AppTextStyles.headline5.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text("Tổng quan doanh thu, chi phí", style: AppTextStyles.caption.copyWith(color: Colors.white70)),
          ],
        ),
        automaticallyImplyLeading: true,
        actions: [
          // Filter button with badge
          Stack(
            children: [
              IconButton(
                onPressed: _showFilterSheet,
                icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
                tooltip: 'Lọc theo thời gian',
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getFilterLabel(),
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? Colors.orange : Colors.white,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
        ],
        bottom: TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: AppTextStyles.button.copyWith(fontWeight: FontWeight.bold),
          unselectedLabelStyle: AppTextStyles.button,
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "TỔNG QUAN"),
            Tab(text: "CHỐT QUỸ"),
            Tab(text: "BÁN HÀNG"),
            Tab(text: "SỬA CHỮA"),
            Tab(text: "BẢO HÀNH"),
            Tab(text: "CHI TIÊU"),
            Tab(text: "PHẢI THU"),
            Tab(text: "DÒNG TIỀN"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildCashClosingTab(),
                _buildSaleDetail(),
                _buildRepairDetail(),
                const WarrantyView(),
                _buildExpenseDetail(),
                const CustomerReceivablesView(),
                _buildCashFlowHistory(),
              ],
            ),
    );
  }

  Widget _buildCashClosingTab() {
    final now = DateTime.now();
    List<_TransactionItem> todayTrans = [];

    for (var s in _sales.where((s) => _isSameDay(s.soldAt, now))) {
      // Xử lý trả góp: chỉ tính tiền trả trước (downPayment), không tính phần vay NH
      if (s.isInstallment) {
        // Tiền trả trước từ khách (nếu có)
        if (s.downPayment > 0) {
          todayTrans.add(
            _TransactionItem(
              title: "Bán TG cọc: ${s.productNames}",
              amount: s.downPayment,
              method: s.paymentMethod,
              time: s.soldAt,
              type: "IN",
              isDebt: s.paymentMethod == "CÔNG NỢ",
            ),
          );
        }
      } else {
        // Bán thường: tính toàn bộ totalPrice
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
    }
    
    // Thêm tiền tất toán từ NH nhận hôm nay (trả góp đã tất toán)
    for (var s in _sales.where((s) => 
        s.isInstallment && 
        s.settlementReceivedAt != null && 
        _isSameDay(s.settlementReceivedAt!, now))) {
      todayTrans.add(
        _TransactionItem(
          title: "Tất toán NH: ${s.productNames}",
          amount: s.settlementAmount,
          method: "CHUYỂN KHOẢN", // NH luôn chuyển khoản
          time: s.settlementReceivedAt!,
          type: "IN",
          isDebt: false,
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
    final isLocked = _todayClosing != null && (_todayClosing!['isLocked'] == 1 || _todayClosing!['isLocked'] == true);
    final cashEnd = _todayClosing?['cashEnd'] as int? ?? 0;
    final bankEnd = _todayClosing?['bankEnd'] as int? ?? 0;
    final lockedBy = _todayClosing?['lockedBy'] as String? ?? '';
    final lockedAt = _todayClosing?['lockedAt'] as int?;
    
    // Nếu đã chốt quỹ - hiển thị thông tin và nút mở khóa
    if (isLocked) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade300, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10),
          ],
        ),
        child: Column(
          children: [
            // Header đã chốt
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, color: Colors.green.shade700, size: 24),
                const SizedBox(width: 8),
                Text(
                  "ĐÃ CHỐT QUỸ HÔM NAY",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Thông tin chốt
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _closingInfoRow(
                    Icons.payments,
                    "Tiền mặt đếm được",
                    NumberFormat('#,###').format(cashEnd),
                    Colors.orange,
                  ),
                  const Divider(height: 20),
                  _closingInfoRow(
                    Icons.account_balance,
                    "Số dư ngân hàng",
                    NumberFormat('#,###').format(bankEnd),
                    Colors.blue,
                  ),
                  const Divider(height: 20),
                  _closingInfoRow(
                    Icons.calculate,
                    "TỔNG CỘNG",
                    NumberFormat('#,###').format(cashEnd + bankEnd),
                    Colors.purple,
                    isBold: true,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Thông tin người chốt
            Text(
              "Chốt bởi: $lockedBy ${lockedAt != null ? '- ${DateFormat('HH:mm dd/MM').format(DateTime.fromMillisecondsSinceEpoch(lockedAt))}' : ''}",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            
            const SizedBox(height: 20),
            
            // Nút mở khóa
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _confirmUnlockClosing,
                icon: const Icon(Icons.lock_open, color: Colors.red),
                label: const Text(
                  "MỞ KHÓA ĐỂ SỬA ĐỔI",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // Nếu chưa chốt - hiển thị form nhập
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                "CHƯA CHỐT QUỸ",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
            child: ElevatedButton.icon(
              onPressed: _saveClosing,
              icon: const Icon(Icons.lock, color: Colors.white),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
              ),
              label: const Text(
                "XÁC NHẬN CHỐT QUỸ & KHÓA",
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
  
  Widget _closingInfoRow(IconData icon, String label, String value, Color color, {bool isBold = false}) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          "$value đ",
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  Future<void> _confirmUnlockClosing() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text("XÁC NHẬN MỞ KHÓA"),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Bạn có chắc muốn mở khóa ngày hôm nay?",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              "• Các giao dịch sẽ được phép thêm/sửa/xóa\n"
              "• Bạn cần chốt quỹ lại sau khi hoàn tất\n"
              "• Hành động này sẽ được ghi nhật ký",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("MỞ KHÓA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (result == true) {
      await _unlockClosing();
    }
  }
  
  Future<void> _unlockClosing() async {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first.toUpperCase() ?? "ADMIN";
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final shopId = await UserService.getCurrentShopId();
    final firestoreId = "closing_${shopId}_$dateKey";
    
    final closingData = {
      'dateKey': dateKey,
      'isLocked': 0,
      'unlockedBy': userName,
      'unlockedAt': now,
      'firestoreId': firestoreId,
      'shopId': shopId,
    };
    
    // Cập nhật local DB
    final dbRaw = await db.database;
    await dbRaw.update(
      'cash_closings',
      closingData,
      where: 'dateKey = ?',
      whereArgs: [dateKey],
    );
    
    // Queue sync via SyncOrchestrator
    final closingId = await db.getCashClosingIdByFirestoreId(firestoreId);
    await SyncOrchestrator().enqueue(
      entityType: SyncEntityType.cashClosing,
      entityId: closingId ?? 0,
      firestoreId: firestoreId,
      operation: SyncOperation.update,
      data: closingData,
    );
    
    await db.logAction(
      userId: user?.uid ?? "0",
      userName: userName,
      action: "MỞ KHÓA QUỸ",
      type: "FINANCE",
      desc: "Đã mở khóa ngày $dateKey để sửa đổi",
    );
    
    NotificationService.showSnackBar(
      "Đã mở khóa ngày $dateKey!",
      color: Colors.orange,
    );
    HapticFeedback.mediumImpact();
    _loadAllData();
  }

  Future<void> _saveClosing() async {
    final cash = int.tryParse(cashEndCtrl.text.replaceAll('.', '')) ?? 0;
    final bank = int.tryParse(bankEndCtrl.text.replaceAll('.', '')) ?? 0;
    
    // Xác nhận trước khi chốt
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('XÁC NHẬN CHỐT QUỸ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tiền mặt: ${NumberFormat('#,###').format(cash)} đ'),
            SizedBox(height: 4),
            Text('Ngân hàng: ${NumberFormat('#,###').format(bank)} đ'),
            SizedBox(height: 12),
            Text(
              'Sau khi chốt, bạn sẽ không thể sửa/xóa các phiếu trong ngày.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text('CHỐT QUỸ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first.toUpperCase() ?? "ADMIN";
    final now = DateTime.now().millisecondsSinceEpoch;
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    final shopId = await UserService.getCurrentShopId();
    final firestoreId = "closing_${shopId}_$dateKey";
    
    final closingData = {
      'dateKey': dateKey,
      'cashEnd': cash,
      'bankEnd': bank,
      'createdAt': now,
      'isLocked': 1, // Tự động khóa khi chốt
      'lockedBy': userName,
      'lockedAt': now,
      'firestoreId': firestoreId,
      'shopId': shopId,
    };
    
    // Lưu local
    await db.upsertClosing(closingData);
    
    // Queue sync via SyncOrchestrator
    final closingId = await db.getCashClosingIdByFirestoreId(firestoreId);
    await SyncOrchestrator().enqueue(
      entityType: SyncEntityType.cashClosing,
      entityId: closingId ?? 0,
      firestoreId: firestoreId,
      operation: SyncOperation.create,
      data: closingData,
    );
    
    await db.logAction(
      userId: user?.uid ?? "0",
      userName: userName,
      action: "CHỐT QUỸ",
      type: "FINANCE",
      desc:
          "Tiền mặt: ${NumberFormat('#,###').format(cash)}đ, Ngân hàng: ${NumberFormat('#,###').format(bank)}đ - Ngày $dateKey đã bị khóa",
    );
    NotificationService.showSnackBar(
      "Đã chốt quỹ thành công! Ngày $dateKey đã bị khóa.",
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
    final fSales = _sales.where((s) => _isInFilterPeriod(s.soldAt)).toList();
    // Chỉ tính repair khi status == 4 (Đã giao) và có deliveredAt
    final fRepairs = _repairs
        .where(
          (r) =>
              r.status == 4 &&
              r.deliveredAt != null &&
              _isInFilterPeriod(r.deliveredAt!),
        )
        .toList();
    final fExpenses = _expenses
        .where((e) => _isInFilterPeriod(e['date'] as int))
        .toList();
    
    // Tính tổng thu từ sales (xử lý trả góp đúng cách)
    int salesIncome = 0;
    for (var s in fSales) {
      if (s.paymentMethod == 'CÔNG NỢ') {
        // Công nợ: không tính vào dòng tiền thực tế
        continue;
      }
      if (s.isInstallment) {
        // Trả góp: chỉ tính downPayment + settlementAmount (nếu đã nhận)
        salesIncome += s.downPayment;
        if (s.settlementReceivedAt != null && _isInFilterPeriod(s.settlementReceivedAt!)) {
          salesIncome += s.settlementAmount;
        }
      } else {
        // Bán thường
        salesIncome += s.totalPrice;
      }
    }
    
    // Tính tổng thu từ repairs (loại trừ công nợ)
    int repairsIncome = 0;
    for (var r in fRepairs) {
      if (r.paymentMethod != 'CÔNG NỢ') {
        repairsIncome += r.price;
      }
    }
    
    int totalIn = salesIncome + repairsIncome;
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
          // Filter indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'TỔNG QUAN: ${_getFilterLabel()}',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Revenue Cards Row
          Row(
            children: [
              _miniCard("TỔNG THU", totalIn, Colors.green.shade700),
              const SizedBox(width: 12),
              _miniCard("TỔNG CHI", totalOut, Colors.red.shade700),
            ],
          ),
          const SizedBox(height: 16),

          // Profit Card
          _mainProfitCard(profit, _getFilterLabel()),

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
            '${NumberFormat('#,###').format(v)}đ',
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
  Widget _mainProfitCard(int p, String periodLabel) => Container(
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
          "LỢI NHUẬN RÒNG ($periodLabel)",
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
        .where((s) => _isInFilterPeriod(s.soldAt))
        .toList();
    list.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    
    final totalRevenue = list.fold<int>(0, (sum, s) => sum + s.totalPrice);
    
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${list.length} đơn bán', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold)),
              Text('${NumberFormat('#,###').format(totalRevenue)}đ', style: AppTextStyles.body2.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
            ? Center(child: Text('Không có đơn bán trong ${_getFilterLabel().toLowerCase()}', style: AppTextStyles.body2.copyWith(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final sale = list[i];
                  final date = DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt));
                  final index = i + 1;
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(sale.productNames, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Khách: ${sale.customerName} • $date"),
                      trailing: Text(
                        "+${NumberFormat('#,###').format(sale.totalPrice)}đ",
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  // Chỉ hiển thị repair đã giao (status == 4) và có deliveredAt trong filter period
  Widget _buildRepairDetail() {
    final list = _repairs
        .where(
          (r) =>
              r.status == 4 &&
              r.deliveredAt != null &&
              _isInFilterPeriod(r.deliveredAt!),
        )
        .toList();
    list.sort((a, b) => (b.deliveredAt ?? 0).compareTo(a.deliveredAt ?? 0));
    
    final totalRevenue = list.fold<int>(0, (sum, r) => sum + r.price);
    
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${list.length} đơn sửa chữa', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold)),
              Text('${NumberFormat('#,###').format(totalRevenue)}đ', style: AppTextStyles.body2.copyWith(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
            ? Center(child: Text('Không có đơn sửa chữa trong ${_getFilterLabel().toLowerCase()}', style: AppTextStyles.body2.copyWith(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final repair = list[i];
                  final date = DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(repair.deliveredAt!));
                  final index = i + 1;
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(repair.model, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Khách: ${repair.customerName} • $date"),
                      trailing: Text(
                        "+${NumberFormat('#,###').format(repair.price)}đ",
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildExpenseDetail() {
    final list = _expenses
        .where((e) => _isInFilterPeriod(e['date'] as int))
        .toList();
    list.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    
    final totalExpense = list.fold<int>(0, (sum, e) => sum + (e['amount'] as int));
    
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${list.length} khoản chi', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold)),
              Text('-${NumberFormat('#,###').format(totalExpense)}đ', style: AppTextStyles.body2.copyWith(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
            ? Center(child: Text('Không có chi phí trong ${_getFilterLabel().toLowerCase()}', style: AppTextStyles.body2.copyWith(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final expense = list[i];
                  final date = DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(expense['date'] as int));
                  final index = i + 1;
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$index',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(expense['title'] ?? 'Chi phí', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${expense['category'] ?? 'Khác'} • $date"),
                      trailing: Text(
                        "-${NumberFormat('#,###').format(expense['amount'])}đ",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildCashFlowHistory() {
    // Collect all transactions with dates
    List<_TransactionItem> allTransactions = [];

    // Sales - xử lý trả góp đúng cách
    for (var s in _sales) {
      if (s.isInstallment) {
        // Bán trả góp: chỉ tính tiền trả trước (downPayment)
        if (s.downPayment > 0) {
          allTransactions.add(
            _TransactionItem(
              title: "Bán TG cọc: ${s.productNames}",
              amount: s.downPayment,
              method: s.paymentMethod,
              time: s.soldAt,
              type: "IN",
              isDebt: s.paymentMethod == "CÔNG NỢ",
            ),
          );
        }
        // Thêm giao dịch tất toán nếu đã nhận tiền từ NH
        if (s.settlementReceivedAt != null && s.settlementAmount > 0) {
          allTransactions.add(
            _TransactionItem(
              title: "Tất toán NH: ${s.productNames}",
              amount: s.settlementAmount,
              method: "CHUYỂN KHOẢN",
              time: s.settlementReceivedAt!,
              type: "IN",
              isDebt: false,
            ),
          );
        }
      } else {
        // Bán thường
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
        final index = i + 1;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                Container(
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
              ],
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
