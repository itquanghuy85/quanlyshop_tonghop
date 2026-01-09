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
  List<Map<String, dynamic>> _supplierImports = []; // Nhập hàng từ NCC
  List<Map<String, dynamic>> _supplierPayments = []; // Thanh toán NCC
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

  // State for detail tab sub-navigation
  int _detailSubTab = 0; // 0: Bán hàng, 1: Sửa chữa, 2: Chi tiêu

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
              debugPrint(
                'Cash closing sync: Cloud isLocked=$cloudIsLocked, Local isLocked=$localIsLocked',
              );

              // Cập nhật local DB
              final dbRaw = await db.database;
              await dbRaw.update(
                'cash_closings',
                {
                  'isLocked': cloudIsLocked == true || cloudIsLocked == 1
                      ? 1
                      : 0,
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
    final supplierImports = await db.getAllSupplierImportHistory();
    final supplierPayments = await db.getAllSupplierPayments();

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

    // Lấy chốt quỹ của ngày trước làm số dư đầu kỳ
    final prevClosing = await db.getPreviousDayClosing(todayKey);

    if (!mounted) return;
    setState(() {
      _repairs = repairs;
      _sales = sales;
      _expenses = expenses;
      _debtPayments = debtPayments;
      _supplierImports = supplierImports;
      _supplierPayments = supplierPayments;
      _closings = closings;
      _todayClosing = todayClosingResult.isNotEmpty
          ? todayClosingResult.first
          : null;
      _previousDayClosing = prevClosing;
      _loadingPreviousClosing = false;
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
        if (_customStartDate != null && dt.isBefore(_customStartDate!))
          return false;
        if (_customEndDate != null &&
            dt.isAfter(_customEndDate!.add(const Duration(days: 1))))
          return false;
        return true;
      default:
        return true;
    }
  }

  String _getFilterLabel() {
    switch (_timeFilter) {
      case 'today':
        return 'HÔM NAY';
      case 'week':
        return '7 NGÀY QUA';
      case 'month':
        return 'THÁNG NÀY';
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('dd/MM').format(_customStartDate!)} - ${DateFormat('dd/MM').format(_customEndDate!)}';
        }
        return 'TÙY CHỌN';
      default:
        return '';
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
                  Text(
                    'LỌC THEO THỜI GIAN',
                    style: AppTextStyles.headline6.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              if (_timeFilter == 'custom' &&
                  _customStartDate != null &&
                  _customEndDate != null)
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
                        const Icon(
                          Icons.date_range,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ÁP DỤNG',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.onSurface.withOpacity(0.2),
          ),
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
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.onSurface.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month,
              size: 16,
              color: isSelected ? Colors.white : AppColors.onSurface,
            ),
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
              style: AppTextStyles.headline5.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              "Tổng quan doanh thu, chi phí",
              style: AppTextStyles.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
        automaticallyImplyLeading: true,
        actions: [
          // Filter button with badge
          Stack(
            children: [
              IconButton(
                onPressed: _showFilterSheet,
                icon: const Icon(
                  Icons.filter_list_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Lọc theo thời gian',
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getFilterLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
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
          labelStyle: AppTextStyles.button.copyWith(
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: AppTextStyles.button,
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 18), text: "TỔNG QUAN"),
            Tab(
              icon: Icon(Icons.account_balance_wallet, size: 18),
              text: "CHỐT QUỸ",
            ),
            Tab(icon: Icon(Icons.receipt_long, size: 18), text: "CHI TIẾT"),
            Tab(icon: Icon(Icons.account_balance, size: 18), text: "CÔNG NỢ"),
            Tab(icon: Icon(Icons.verified_user, size: 18), text: "BẢO HÀNH"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(),
                _buildCashClosingWithHistory(), // Gộp CHỐT QUỸ + DÒNG TIỀN
                _buildDetailTab(), // Gộp BÁN HÀNG + SỬA CHỮA + CHI TIÊU
                const CustomerReceivablesView(), // CÔNG NỢ (PHẢI THU)
                const WarrantyView(), // BẢO HÀNH
              ],
            ),
    );
  }

  /// Widget gộp CHỐT QUỸ + DÒNG TIỀN trong 1 tab
  Widget _buildCashClosingWithHistory() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.grey.shade100,
            child: const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: "CHỐT QUỸ HÔM NAY"),
                Tab(text: "LỊCH SỬ DÒNG TIỀN"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [_buildCashClosingTab(), _buildCashFlowHistory()],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget gộp BÁN HÀNG + SỬA CHỮA + CHI TIÊU trong 1 tab với SegmentedButton
  Widget _buildDetailTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text("BÁN HÀNG"),
                  icon: Icon(Icons.shopping_cart, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text("SỬA CHỮA"),
                  icon: Icon(Icons.build, size: 16),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text("CHI TIÊU"),
                  icon: Icon(Icons.money_off, size: 16),
                ),
              ],
              selected: {_detailSubTab},
              onSelectionChanged: (Set<int> selected) {
                setState(() => _detailSubTab = selected.first);
              },
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _detailSubTab,
            children: [
              _buildSaleDetail(),
              _buildRepairDetail(),
              _buildExpenseDetail(),
            ],
          ),
        ),
      ],
    );
  }

  // State cho số dư đầu kỳ từ ngày trước
  Map<String, dynamic>? _previousDayClosing;
  bool _loadingPreviousClosing = true;

  Widget _buildCashClosingTab() {
    final now = DateTime.now();

    // Phân tích giao dịch chi tiết
    final analysis = _analyzeTransactions(now);

    // Số dư đầu kỳ từ chốt quỹ hôm qua
    final openingCash = _previousDayClosing?['cashEnd'] as int? ?? 0;
    final openingBank = _previousDayClosing?['bankEnd'] as int? ?? 0;
    final hasOpeningBalance = _previousDayClosing != null;

    // Tính số dư dự kiến cuối ngày
    final expectedCashEnd = openingCash + analysis.cashDelta;
    final expectedBankEnd = openingBank + analysis.bankDelta;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadAllData();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== HEADER - Ngày hôm nay =====
          _buildDateHeader(now),
          const SizedBox(height: 16),

          // ===== SỐ DƯ ĐẦU KỲ =====
          _buildOpeningBalanceSection(
            openingCash,
            openingBank,
            hasOpeningBalance,
          ),
          const SizedBox(height: 16),

          // ===== BIẾN ĐỘNG TRONG NGÀY =====
          _buildDailyChangesSection(analysis),
          const SizedBox(height: 16),

          // ===== SỐ DƯ DỰ KIẾN CUỐI NGÀY =====
          _buildExpectedEndBalanceSection(
            expectedCashEnd,
            expectedBankEnd,
            analysis,
          ),
          const SizedBox(height: 16),

          // ===== SECTION CHỐT QUỸ =====
          _buildClosingActionSection(expectedCashEnd, expectedBankEnd),
          const SizedBox(height: 24),

          // ===== DANH SÁCH GIAO DỊCH =====
          _buildTransactionListSection(analysis.transactions),
        ],
      ),
    );
  }

  /// Widget hiển thị ngày hôm nay
  Widget _buildDateHeader(DateTime now) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.primary.withOpacity(0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE', 'vi').format(now).toUpperCase(),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yyyy').format(now),
                  style: AppTextStyles.headline6.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Badge trạng thái
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  _todayClosing != null &&
                      (_todayClosing!['isLocked'] == 1 ||
                          _todayClosing!['isLocked'] == true)
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _todayClosing != null &&
                          (_todayClosing!['isLocked'] == 1 ||
                              _todayClosing!['isLocked'] == true)
                      ? Icons.lock
                      : Icons.lock_open,
                  size: 14,
                  color:
                      _todayClosing != null &&
                          (_todayClosing!['isLocked'] == 1 ||
                              _todayClosing!['isLocked'] == true)
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  _todayClosing != null &&
                          (_todayClosing!['isLocked'] == 1 ||
                              _todayClosing!['isLocked'] == true)
                      ? 'Đã chốt'
                      : 'Chưa chốt',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        _todayClosing != null &&
                            (_todayClosing!['isLocked'] == 1 ||
                                _todayClosing!['isLocked'] == true)
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị số dư đầu kỳ
  Widget _buildOpeningBalanceSection(
    int cashStart,
    int bankStart,
    bool hasData,
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
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: Colors.teal.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SỐ DƯ ĐẦU NGÀY',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
              const Spacer(),
              if (!hasData)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Ngày đầu tiên',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceItem(
                  icon: Icons.payments_rounded,
                  label: 'Tiền mặt',
                  amount: cashStart,
                  color: Colors.orange,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.grey.shade200),
              Expanded(
                child: _buildBalanceItem(
                  icon: Icons.account_balance_rounded,
                  label: 'Ngân hàng',
                  amount: bankStart,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.summarize, size: 16, color: Colors.teal.shade600),
              const SizedBox(width: 6),
              Text(
                'TỔNG: ',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              Text(
                '${NumberFormat('#,###').format(cashStart + bankStart)} đ',
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị biến động trong ngày
  Widget _buildDailyChangesSection(_TransactionAnalysis analysis) {
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
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.swap_vert_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'BIẾN ĐỘNG HÔM NAY',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${analysis.transactions.length} giao dịch',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // THU TIỀN MẶT
          _buildChangeRow(
            icon: Icons.arrow_downward_rounded,
            label: 'Thu tiền mặt',
            amount: analysis.cashIn,
            color: Colors.green,
            isIncome: true,
          ),
          const SizedBox(height: 8),

          // THU CHUYỂN KHOẢN
          _buildChangeRow(
            icon: Icons.arrow_downward_rounded,
            label: 'Thu chuyển khoản',
            amount: analysis.bankIn,
            color: Colors.green,
            isIncome: true,
          ),
          const SizedBox(height: 8),

          // CHI TIỀN MẶT
          _buildChangeRow(
            icon: Icons.arrow_upward_rounded,
            label: 'Chi tiền mặt',
            amount: analysis.cashOut,
            color: Colors.red,
            isIncome: false,
          ),
          const SizedBox(height: 8),

          // CHI CHUYỂN KHOẢN
          _buildChangeRow(
            icon: Icons.arrow_upward_rounded,
            label: 'Chi chuyển khoản',
            amount: analysis.bankOut,
            color: Colors.red,
            isIncome: false,
          ),

          // CÔNG NỢ (nếu có)
          if (analysis.debtAmount > 0) ...[
            const SizedBox(height: 8),
            _buildChangeRow(
              icon: Icons.schedule_rounded,
              label: 'Công nợ (chưa thu)',
              amount: analysis.debtAmount,
              color: Colors.purple,
              isIncome: false,
              isDebt: true,
            ),
          ],

          const Divider(height: 24),

          // TỔNG BIẾN ĐỘNG
          Row(
            children: [
              Expanded(
                child: _buildDeltaCard(
                  'Tiền mặt',
                  analysis.cashDelta,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDeltaCard(
                  'Ngân hàng',
                  analysis.bankDelta,
                  Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChangeRow({
    required IconData icon,
    required String label,
    required int amount,
    required Color color,
    required bool isIncome,
    bool isDebt = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
        Text(
          '${isIncome && !isDebt ? '+' : (isDebt ? '' : '-')}${NumberFormat('#,###').format(amount)} đ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDebt
                ? Colors.purple
                : (isIncome ? Colors.green : Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildDeltaCard(String label, int delta, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                delta >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: delta >= 0 ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${delta >= 0 ? '+' : ''}${NumberFormat('#,###').format(delta)} đ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: delta >= 0 ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị số dư dự kiến cuối ngày
  Widget _buildExpectedEndBalanceSection(
    int expectedCash,
    int expectedBank,
    _TransactionAnalysis analysis,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.purple.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calculate_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SỐ DƯ DỰ KIẾN CUỐI NGÀY',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceItem(
                  icon: Icons.payments_rounded,
                  label: 'Tiền mặt',
                  amount: expectedCash,
                  color: Colors.orange,
                  showPrefix: false,
                ),
              ),
              Container(width: 1, height: 50, color: Colors.indigo.shade100),
              Expanded(
                child: _buildBalanceItem(
                  icon: Icons.account_balance_rounded,
                  label: 'Ngân hàng',
                  amount: expectedBank,
                  color: Colors.blue,
                  showPrefix: false,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.indigo),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 20,
                color: Colors.indigo.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'TỔNG DỰ KIẾN: ',
                style: TextStyle(fontSize: 13, color: Colors.indigo.shade600),
              ),
              Text(
                '${NumberFormat('#,###').format(expectedCash + expectedBank)} đ',
                style: AppTextStyles.headline5.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceItem({
    required IconData icon,
    required String label,
    required int amount,
    required Color color,
    bool showPrefix = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${showPrefix && amount >= 0 ? '+' : ''}${NumberFormat('#,###').format(amount)} đ',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Section chốt quỹ hoặc hiển thị đã chốt
  Widget _buildClosingActionSection(int expectedCash, int expectedBank) {
    final isLocked =
        _todayClosing != null &&
        (_todayClosing!['isLocked'] == 1 || _todayClosing!['isLocked'] == true);
    final cashEnd = _todayClosing?['cashEnd'] as int? ?? 0;
    final bankEnd = _todayClosing?['bankEnd'] as int? ?? 0;
    final lockedBy = _todayClosing?['lockedBy'] as String? ?? '';
    final lockedAt = _todayClosing?['lockedAt'] as int?;

    if (isLocked) {
      // Tính chênh lệch
      final cashDiff = cashEnd - expectedCash;
      final bankDiff = bankEnd - expectedBank;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade300, width: 2),
        ),
        child: Column(
          children: [
            // Header đã chốt
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'ĐÃ CHỐT QUỸ',
                  style: AppTextStyles.headline6.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // So sánh Dự kiến vs Thực tế
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Header table
                  Row(
                    children: [
                      const Expanded(flex: 2, child: SizedBox()),
                      Expanded(
                        child: Text(
                          'Dự kiến',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Thực tế',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Lệch',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  // Tiền mặt
                  _buildComparisonRow(
                    label: 'Tiền mặt',
                    icon: Icons.payments,
                    color: Colors.orange,
                    expected: expectedCash,
                    actual: cashEnd,
                    diff: cashDiff,
                  ),
                  const SizedBox(height: 12),
                  // Ngân hàng
                  _buildComparisonRow(
                    label: 'Ngân hàng',
                    icon: Icons.account_balance,
                    color: Colors.blue,
                    expected: expectedBank,
                    actual: bankEnd,
                    diff: bankDiff,
                  ),
                  const Divider(height: 16),
                  // Tổng
                  _buildComparisonRow(
                    label: 'TỔNG',
                    icon: Icons.summarize,
                    color: Colors.purple,
                    expected: expectedCash + expectedBank,
                    actual: cashEnd + bankEnd,
                    diff: cashDiff + bankDiff,
                    isBold: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Thông tin người chốt
            Text(
              'Chốt bởi: $lockedBy ${lockedAt != null ? '• ${DateFormat('HH:mm dd/MM').format(DateTime.fromMillisecondsSinceEpoch(lockedAt))}' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 16),

            // Nút mở khóa
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _confirmUnlockClosing,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('MỞ KHÓA ĐỂ SỬA ĐỔI'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Chưa chốt - hiển thị form nhập
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_note,
                  color: Colors.orange.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'NHẬP SỐ THỰC TẾ',
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kiểm tra và nhập số tiền thực tế cuối ngày',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          CurrencyTextField(
            controller: cashEndCtrl,
            label: 'TIỀN MẶT ĐẾM ĐƯỢC',
            icon: Icons.payments,
          ),
          const SizedBox(height: 12),
          CurrencyTextField(
            controller: bankEndCtrl,
            label: 'SỐ DƯ NGÂN HÀNG',
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
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: const Text(
                'XÁC NHẬN CHỐT QUỸ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required String label,
    required IconData icon,
    required Color color,
    required int expected,
    required int actual,
    required int diff,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: isBold ? 12 : 11,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            NumberFormat('#,###').format(expected),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            NumberFormat('#,###').format(actual),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isBold ? 11 : 10,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: diff == 0
                  ? Colors.grey.shade100
                  : (diff > 0 ? Colors.green.shade50 : Colors.red.shade50),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              diff == 0
                  ? '0'
                  : '${diff > 0 ? '+' : ''}${NumberFormat('#,###').format(diff)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: diff == 0
                    ? Colors.grey
                    : (diff > 0 ? Colors.green.shade700 : Colors.red.shade700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Section danh sách giao dịch
  Widget _buildTransactionListSection(List<_TransactionItem> transactions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.receipt_long,
                color: Colors.grey.shade700,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'GIAO DỊCH TRONG NGÀY',
              style: AppTextStyles.subtitle2.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${transactions.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (transactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Chưa có giao dịch nào',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          ...transactions.map((t) => _buildTransactionRow(t)),
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
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (t.type == "IN" ? Colors.green : Colors.red).withOpacity(
              0.1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: t.type == "IN" ? Colors.green : Colors.red,
            size: 20,
          ),
        ),
        title: Text(
          t.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              DateFormat(
                'HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(t.time)),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: methodColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t.method == "CHUYỂN KHOẢN" ? "CK" : (t.isDebt ? "NỢ" : "TM"),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: methodColor,
                ),
              ),
            ),
          ],
        ),
        trailing: Text(
          "${t.type == "IN" ? "+" : "-"}${NumberFormat('#,###').format(t.amount)}",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: t.type == "IN" ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ),
    );
  }

  /// Phân tích giao dịch trong ngày
  _TransactionAnalysis _analyzeTransactions(DateTime now) {
    List<_TransactionItem> todayTrans = [];
    int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0, debtAmount = 0;

    for (var s in _sales.where((s) => _isSameDay(s.soldAt, now))) {
      if (s.isInstallment) {
        if (s.downPayment > 0) {
          final item = _TransactionItem(
            title: "Bán TG cọc: ${s.productNames}",
            amount: s.downPayment,
            method: s.paymentMethod,
            time: s.soldAt,
            type: "IN",
            isDebt: s.paymentMethod == "CÔNG NỢ",
          );
          todayTrans.add(item);
          if (!item.isDebt) {
            if (item.method == "TIỀN MẶT")
              cashIn += item.amount;
            else
              bankIn += item.amount;
          } else {
            debtAmount += item.amount;
          }
        }
      } else {
        final item = _TransactionItem(
          title: "Bán: ${s.productNames}",
          amount: s.totalPrice,
          method: s.paymentMethod,
          time: s.soldAt,
          type: "IN",
          isDebt: s.paymentMethod == "CÔNG NỢ",
        );
        todayTrans.add(item);
        if (!item.isDebt) {
          if (item.method == "TIỀN MẶT")
            cashIn += item.amount;
          else
            bankIn += item.amount;
        } else {
          debtAmount += item.amount;
        }
      }
    }

    // Tất toán NH
    for (var s in _sales.where(
      (s) =>
          s.isInstallment &&
          s.settlementReceivedAt != null &&
          _isSameDay(s.settlementReceivedAt!, now),
    )) {
      final item = _TransactionItem(
        title: "Tất toán NH: ${s.productNames}",
        amount: s.settlementAmount,
        method: "CHUYỂN KHOẢN",
        time: s.settlementReceivedAt!,
        type: "IN",
        isDebt: false,
      );
      todayTrans.add(item);
      bankIn += item.amount;
    }

    // Repairs
    for (var r in _repairs.where(
      (r) =>
          r.status == 4 &&
          r.deliveredAt != null &&
          _isSameDay(r.deliveredAt!, now),
    )) {
      final item = _TransactionItem(
        title: "Sửa: ${r.model}",
        amount: r.price,
        method: r.paymentMethod,
        time: r.deliveredAt!,
        type: "IN",
        isDebt: r.paymentMethod == "CÔNG NỢ",
      );
      todayTrans.add(item);
      if (!item.isDebt) {
        if (item.method == "TIỀN MẶT")
          cashIn += item.amount;
        else
          bankIn += item.amount;
      } else {
        debtAmount += item.amount;
      }
    }

    // Expenses
    for (var e in _expenses.where(
      (e) => _isSameDay((e['date'] ?? e['createdAt']) as int, now),
    )) {
      final item = _TransactionItem(
        title: "Chi: ${e['title'] ?? e['description'] ?? 'Chi phí'}",
        amount: e['amount'],
        method: e['paymentMethod'] ?? 'TIỀN MẶT',
        time: (e['date'] ?? e['createdAt']) as int,
        type: "OUT",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.method == "TIỀN MẶT")
        cashOut += item.amount;
      else
        bankOut += item.amount;
    }

    // Supplier imports (Nhập hàng từ NCC) - CHỈ tính khi thanh toán ngay (không nợ)
    for (var imp in _supplierImports.where(
      (i) => _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, now),
    )) {
      final paymentMethod = imp['paymentMethod'] as String? ?? 'TIỀN MẶT';
      // Bỏ qua nếu là công nợ (sẽ tính khi thanh toán)
      if (paymentMethod == 'CÔNG NỢ') continue;

      final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
      if (amount <= 0) continue;

      final item = _TransactionItem(
        title:
            "Nhập: ${imp['productName'] ?? imp['productBrand'] ?? 'Hàng hóa'}",
        amount: amount,
        method: paymentMethod,
        time: (imp['importDate'] ?? imp['createdAt'] ?? 0) as int,
        type: "OUT",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.method == "TIỀN MẶT")
        cashOut += item.amount;
      else
        bankOut += item.amount;
    }

    // Supplier payments (Thanh toán NCC - bao gồm trả nợ NCC)
    for (var pay in _supplierPayments.where(
      (p) => _isSameDay((p['paidAt'] ?? 0) as int, now),
    )) {
      final amount = (pay['amount'] ?? 0) as int;
      if (amount <= 0) continue;

      final paymentMethod = pay['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final item = _TransactionItem(
        title: "TT NCC: ${pay['note'] ?? 'Thanh toán'}",
        amount: amount,
        method: paymentMethod,
        time: (pay['paidAt'] ?? 0) as int,
        type: "OUT",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.method == "TIỀN MẶT")
        cashOut += item.amount;
      else
        bankOut += item.amount;
    }

    // Debt payments
    for (var p in _debtPayments.where(
      (p) => _isSameDay(p['paidAt'] as int, now),
    )) {
      bool isShopPay = p['debtType'] == 'SHOP_OWES';
      final item = _TransactionItem(
        title: isShopPay
            ? "Trả nợ NCC: ${p['personName']}"
            : "Thu nợ: ${p['personName']}",
        amount: p['amount'],
        method: p['paymentMethod'] ?? 'TIỀN MẶT',
        time: p['paidAt'],
        type: isShopPay ? "OUT" : "IN",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.type == "IN") {
        if (item.method == "TIỀN MẶT")
          cashIn += item.amount;
        else
          bankIn += item.amount;
      } else {
        if (item.method == "TIỀN MẶT")
          cashOut += item.amount;
        else
          bankOut += item.amount;
      }
    }

    todayTrans.sort((a, b) => b.time.compareTo(a.time));

    return _TransactionAnalysis(
      transactions: todayTrans,
      cashIn: cashIn,
      cashOut: cashOut,
      bankIn: bankIn,
      bankOut: bankOut,
      debtAmount: debtAmount,
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
        .where((e) => _isInFilterPeriod((e['date'] ?? e['createdAt']) as int))
        .toList();

    // Tính tổng thu từ sales (xử lý trả góp đúng cách)
    int salesIncome = 0;
    int salesCost = 0; // Chỉ tính giá vốn cho đơn đã thu tiền
    for (var s in fSales) {
      if (s.paymentMethod == 'CÔNG NỢ') {
        // Công nợ: không tính vào dòng tiền và lợi nhuận
        continue;
      }
      if (s.isInstallment) {
        // Trả góp: chỉ tính downPayment + settlementAmount (nếu đã nhận)
        salesIncome += s.downPayment;
        if (s.settlementReceivedAt != null &&
            _isInFilterPeriod(s.settlementReceivedAt!)) {
          salesIncome += s.settlementAmount;
        }
        // Giá vốn tính theo tỷ lệ đã thu
        final totalPaid =
            s.downPayment +
            (s.settlementReceivedAt != null &&
                    _isInFilterPeriod(s.settlementReceivedAt!)
                ? s.settlementAmount
                : 0);
        final ratio = s.totalPrice > 0 ? totalPaid / s.totalPrice : 0.0;
        salesCost += (s.totalCost * ratio).round();
      } else {
        // Bán thường
        salesIncome += s.totalPrice;
        salesCost += s.totalCost;
      }
    }

    // Tính tổng thu từ repairs (loại trừ công nợ)
    int repairsIncome = 0;
    int repairsCost = 0; // Chỉ tính giá vốn cho đơn đã thu tiền
    for (var r in fRepairs) {
      if (r.paymentMethod != 'CÔNG NỢ') {
        repairsIncome += r.price;
        repairsCost += r.totalCost;
      }
    }

    int totalIn = salesIncome + repairsIncome;
    int totalOut = fExpenses.fold<int>(
      0,
      (sum, e) => sum + (e['amount'] as int),
    );
    // LỢI NHUẬN RÒNG = THU - CHI - GIÁ VỐN (chỉ tính đơn đã thu tiền)
    int profit = totalIn - totalOut - salesCost - repairsCost;

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
                const Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: AppColors.primary,
                ),
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
    final list = _sales.where((s) => _isInFilterPeriod(s.soldAt)).toList();
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
              Text(
                '${list.length} đơn bán',
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${NumberFormat('#,###').format(totalRevenue)}đ',
                style: AppTextStyles.body2.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Không có đơn bán trong ${_getFilterLabel().toLowerCase()}',
                    style: AppTextStyles.body2.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final sale = list[i];
                    final date = DateFormat(
                      'dd/MM HH:mm',
                    ).format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt));
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
                        title: Text(
                          sale.productNames,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
              Text(
                '${list.length} đơn sửa chữa',
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${NumberFormat('#,###').format(totalRevenue)}đ',
                style: AppTextStyles.body2.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Không có đơn sửa chữa trong ${_getFilterLabel().toLowerCase()}',
                    style: AppTextStyles.body2.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final repair = list[i];
                    final date = DateFormat('dd/MM HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(repair.deliveredAt!),
                    );
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
                        title: Text(
                          repair.model,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
        .where((e) => _isInFilterPeriod((e['date'] ?? e['createdAt']) as int))
        .toList();
    list.sort(
      (a, b) => ((b['date'] ?? b['createdAt']) as int).compareTo(
        (a['date'] ?? a['createdAt']) as int,
      ),
    );

    final totalExpense = list.fold<int>(
      0,
      (sum, e) => sum + (e['amount'] as int? ?? 0),
    );

    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${list.length} khoản chi',
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '-${NumberFormat('#,###').format(totalExpense)}đ',
                style: AppTextStyles.body2.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Không có chi phí trong ${_getFilterLabel().toLowerCase()}',
                    style: AppTextStyles.body2.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final expense = list[i];
                    final expenseDate =
                        (expense['date'] ?? expense['createdAt']) as int? ?? 0;
                    final date = DateFormat(
                      'dd/MM HH:mm',
                    ).format(DateTime.fromMillisecondsSinceEpoch(expenseDate));
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
                        title: Text(
                          expense['title'] ??
                              expense['description'] ??
                              'Chi phí',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "${expense['category'] ?? 'Khác'} • $date",
                        ),
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
    for (var r in _repairs.where(
      (r) => r.status == 4 && r.deliveredAt != null,
    )) {
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
      final expenseTime = (e['date'] ?? e['createdAt']) as int? ?? 0;
      allTransactions.add(
        _TransactionItem(
          title: "Chi: ${e['title'] ?? e['description'] ?? 'Chi phí'}",
          amount: e['amount'] ?? 0,
          method: e['paymentMethod'] ?? 'TIỀN MẶT',
          time: expenseTime,
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
        final date = DateFormat(
          'dd/MM/yyyy HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(item.time));
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
                    color: isIncome
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
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
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${item.method} • $date"),
                if (item.isDebt)
                  const Text(
                    "Công nợ",
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
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

class _TransactionAnalysis {
  final List<_TransactionItem> transactions;
  final int cashIn;
  final int cashOut;
  final int bankIn;
  final int bankOut;
  final int debtAmount;

  _TransactionAnalysis({
    required this.transactions,
    required this.cashIn,
    required this.cashOut,
    required this.bankIn,
    required this.bankOut,
    required this.debtAmount,
  });

  int get cashDelta => cashIn - cashOut;
  int get bankDelta => bankIn - bankOut;
  int get totalIn => cashIn + bankIn;
  int get totalOut => cashOut + bankOut;
}
