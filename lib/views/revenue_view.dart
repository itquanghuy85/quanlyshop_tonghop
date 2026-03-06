import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/shop_settings_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../utils/perf_monitor.dart';
import '../services/category_service.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/custom_app_bar.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/responsive_wrapper.dart';

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
  List<Map<String, dynamic>> _repairPartnerPayments = []; // Thanh toán đối tác sửa chữa
  Map<String, dynamic>? _todayClosing; // Thông tin chốt quỹ hôm nay
  bool _hasRevenueAccess = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatus = 'Đã đồng bộ';

  // Real-time listener cho cash_closings
  StreamSubscription<DocumentSnapshot>? _closingSubscription;
  
  // EventBus subscription để nghe thay đổi data
  StreamSubscription? _eventBusSubscription;
  
  // Debounce timer để tránh reload quá nhiều
  Timer? _reloadDebounceTimer;
  bool _dataLoaded = false; // Flag để tránh reload khi mới vào trang

  // Filter states
  String _timeFilter = 'today'; // today, week, month, quarter, year, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();

  // State for detail tab sub-navigation
  int _detailSubTab = 0; // 0: Bán hàng, 1: Sửa chữa, 2: Chi tiêu

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;
  bool get _isFashion => _shopSettings?.businessType == 'fashion';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadPermissions();
    _loadShopSettings();
    _loadAllData();
    _initClosingRealTimeSync();
    // Lắng nghe event bus thay vì gọi initRealTimeSync trực tiếp
    // Sử dụng debounce để tránh reload quá nhiều
    _eventBusSubscription = EventBus().stream.listen((event) {
      if (!mounted || !_dataLoaded) return;
      // Chỉ reload khi có events liên quan đến finance
      if (event == 'sales_changed' || 
          event == 'repairs_changed' || 
          event == 'expenses_changed' ||
          event == 'debts_changed' ||
          event == 'cash_closings_changed') {
        _debouncedReload();
      }
    });
  }
  
  /// Reload data với debounce để tránh gọi quá nhiều lần
  void _debouncedReload() {
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _dataLoaded) {
        _loadAllData();
      }
    });
  }

  @override
  void dispose() {
    _closingSubscription?.cancel();
    _eventBusSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
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

  Future<void> _loadShopSettings() async {
    final settings = await CategoryService().getShopSettings();
    if (!mounted) return;
    setState(() {
      _shopSettings = settings;
    });
  }

  Future<void> _loadAllData() async {
    PerfMonitor.start('revenue_loadAllData');
    setState(() => _isLoading = true);

    // ===== PERFORMANCE: Load only data within relevant date range =====
    // Max filter is "year" (Jan 1 of current year). Load from Jan 1 of
    // PREVIOUS year to support year-over-year comparisons & custom ranges.
    final now = DateTime.now();
    final rangeStart = DateTime(now.year - 1, 1, 1);
    final startMs = rangeStart.millisecondsSinceEpoch;
    final endMs = now.add(const Duration(days: 1)).millisecondsSinceEpoch;

    final repairs = await db.getRepairsByCreatedAtRange(startMs, endMs);
    final sales = await db.getSalesByDateRange(startMs, endMs);
    final expenses = await db.getExpensesByDateRange(startMs, endMs);
    final debtPayments = await db.getDebtPaymentsWithDebtInfoByDateRange(startMs, endMs);
    // FIX BUG-007: Load supplier imports từ Firestore để sync giữa các thiết bị
    final shopId = await UserService.getCurrentShopId();
    List<Map<String, dynamic>> supplierImports = [];
    if (shopId != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('supplier_import_history')
            .where('shopId', isEqualTo: shopId)
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(startMs))
            .get();
        supplierImports = snapshot.docs
            .where((doc) => doc.data()['deleted'] != true)
            .map((doc) {
              final data = doc.data();
              data['firestoreId'] = doc.id;
              return data;
            })
            .toList();
      } catch (e) {
        debugPrint('Error loading supplier imports from Firestore: $e');
        supplierImports = await db.getAllSupplierImportHistoryByDateRange(startMs, endMs);
      }
    }
    final supplierPayments = await db.getSupplierPaymentsByDateRange(startMs, endMs);
    final repairPartnerPayments = await db.getRepairPartnerPaymentsByDateRange(startMs, endMs);

    final dbRaw = await db.database;
    final effectiveShopId = shopId ?? UserService.getShopIdSync();
    List<Map<String, dynamic>> closings;
    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      closings = await dbRaw.query(
        'cash_closings',
        where: 'shopId = ? OR shopId IS NULL',
        whereArgs: [effectiveShopId],
        orderBy: 'createdAt DESC',
        limit: 10,
      );
    } else {
      closings = await dbRaw.query(
        'cash_closings',
        orderBy: 'createdAt DESC',
        limit: 10,
      );
    }

    // Lấy thông tin chốt quỹ của ngày hôm nay
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    List<Map<String, dynamic>> todayClosingResult;
    if (effectiveShopId != null && effectiveShopId.isNotEmpty) {
      todayClosingResult = await dbRaw.query(
        'cash_closings',
        where: 'dateKey = ? AND (shopId = ? OR shopId IS NULL)',
        whereArgs: [todayKey, effectiveShopId],
        limit: 1,
      );
    } else {
      todayClosingResult = await dbRaw.query(
        'cash_closings',
        where: 'dateKey = ?',
        whereArgs: [todayKey],
        limit: 1,
      );
    }

    // Lấy chốt quỹ của ngày trước làm số dư đầu kỳ
    final prevClosing = await db.getPreviousDayClosing(todayKey);

    if (!mounted) return;
    PerfMonitor.stop('revenue_loadAllData');
    setState(() {
      _repairs = repairs;
      _sales = sales;
      _expenses = expenses;
      _debtPayments = debtPayments;
      _supplierImports = supplierImports;
      _supplierPayments = supplierPayments;
      _repairPartnerPayments = repairPartnerPayments;
      _closings = closings;
      _todayClosing = todayClosingResult.isNotEmpty
          ? todayClosingResult.first
          : null;
      _previousDayClosing = prevClosing;
      _loadingPreviousClosing = false;
      _isLoading = false;
      _dataLoaded = true; // Đánh dấu đã load xong lần đầu
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
      case 'quarter':
        final currentQuarter = ((now.month - 1) ~/ 3) + 1;
        final quarterStartMonth = (currentQuarter - 1) * 3 + 1;
        final quarterStart = DateTime(now.year, quarterStartMonth, 1);
        return !dt.isBefore(quarterStart);
      case 'year':
        final yearStart = DateTime(now.year, 1, 1);
        return !dt.isBefore(yearStart);
      case 'custom':
        if (_customStartDate != null && dt.isBefore(_customStartDate!)) {
          return false;
        }
        if (_customEndDate != null &&
            dt.isAfter(_customEndDate!.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  String _getFilterLabel() {
    final now = DateTime.now();
    switch (_timeFilter) {
      case 'today':
        return 'HÔM NAY';
      case 'week':
        return '7 NGÀY QUA';
      case 'month':
        return 'THÁNG ${now.month}';
      case 'quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        return 'QUÝ $q/${now.year}';
      case 'year':
        return 'NĂM ${now.year}';
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
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(12),
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
                  _filterChip('Quý này', 'quarter', setSheetState),
                  _filterChip('Năm nay', 'year', setSheetState),
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
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
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
    if (!_hasRevenueAccess) {
      return const Scaffold(
        body: Center(child: Text("Bạn không có quyền truy cập")),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: 'TÀI CHÍNH',
        subtitle: 'Doanh thu · Chi phí',
        accentColor: AppBarAccents.finance,
        actions: [
          IconButton(
            onPressed: _showFilterSheet,
            icon: Badge(
              label: Text(
                _getFilterLabel(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.orange,
              child: const Icon(
                Icons.filter_list_rounded,
                size: 20,
                color: AppBarAccents.finance,
              ),
            ),
            tooltip: 'Lọc theo thời gian',
            splashRadius: 18,
          ),
          IconButton(
            onPressed: _isSyncing ? null : _syncWithFirebase,
            icon: Icon(
              _isSyncing ? Icons.sync : Icons.sync_outlined,
              size: 20,
              color: _isSyncing ? Colors.orange : AppBarAccents.finance,
            ),
            tooltip: 'Đồng bộ với Firebase',
            splashRadius: 18,
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _buildOverview(),
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
    // Xây dựng danh sách segments động dựa trên enableRepair
    final segments = <ButtonSegment<int>>[
      const ButtonSegment(
        value: 0,
        label: Text("BÁN HÀNG"),
        icon: Icon(Icons.shopping_cart, size: 16),
      ),
      if (_enableRepair)
        const ButtonSegment(
          value: 1,
          label: Text("SỬA CHỮA"),
          icon: Icon(Icons.build, size: 16),
        ),
      ButtonSegment(
        value: _enableRepair ? 2 : 1,
        label: const Text("CHI TIÊU"),
        icon: const Icon(Icons.money_off, size: 16),
      ),
    ];

    // Map selectedIndex dựa trên enableRepair
    int displayIndex = _detailSubTab;
    if (!_enableRepair && _detailSubTab > 0) {
      displayIndex = _detailSubTab; // Chi tiêu = 1 khi không có repair
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: segments,
              selected: {displayIndex},
              onSelectionChanged: (Set<int> selected) {
                setState(() => _detailSubTab = selected.first);
              },
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _detailSubTab,
            children: [
              _buildSaleDetail(),
              if (_enableRepair) _buildRepairDetail(),
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
              borderRadius: BorderRadius.circular(12),
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
                    fontSize: AppTextStyles.body1.fontSize,
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
                    style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.grey.shade600),
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
                style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey.shade600),
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
                child: const Icon(
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
                style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
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
              color: Colors.blue,
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
            style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey.shade700),
          ),
        ),
        Text(
          '${isIncome && !isDebt ? '+' : (isDebt ? '' : '-')}${NumberFormat('#,###').format(amount)} đ',
          style: TextStyle(
            fontSize: AppTextStyles.headline5.fontSize,
            fontWeight: FontWeight.bold,
            color: isDebt
                ? Colors.blue
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
              Text(label, style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${delta >= 0 ? '+' : ''}${NumberFormat('#,###').format(delta)} đ',
            style: TextStyle(
              fontSize: AppTextStyles.headline4.fontSize,
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
          colors: [Colors.indigo.shade50, Colors.blue.shade50],
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
                style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.indigo.shade600),
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
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${showPrefix && amount >= 0 ? '+' : ''}${NumberFormat('#,###').format(amount)} đ',
          style: TextStyle(
            fontSize: AppTextStyles.headline3.fontSize,
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
                            fontSize: AppTextStyles.caption.fontSize,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Thực tế',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextStyles.caption.fontSize,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Lệch',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextStyles.caption.fontSize,
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
                    color: Colors.blue,
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
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
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
            style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade600),
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
              label: Text(
                'XÁC NHẬN CHỐT QUỸ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline3.fontSize,
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
            style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            NumberFormat('#,###').format(actual),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isBold ? AppTextStyles.body1.fontSize : AppTextStyles.caption.fontSize,
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
                fontSize: AppTextStyles.overlineSize,
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
                  fontSize: AppTextStyles.subtitle1.fontSize,
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
        : (t.isDebt ? Colors.blue : Colors.orange);
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
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTextStyles.headline5.fontSize),
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
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
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
                  fontSize: AppTextStyles.overlineSize,
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
            fontSize: AppTextStyles.headline4.fontSize,
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
          // Dùng downPaymentMethod (TIỀN MẶT/CHUYỂN KHOẢN) thay vì paymentMethod (TRẢ GÓP NH)
          final downMethod = s.downPaymentMethod ?? 'TIỀN MẶT';
          final item = _TransactionItem(
            title: "Bán TG cọc: ${s.productNames}",
            amount: s.downPayment,
            method: downMethod,
            time: s.soldAt,
            type: "IN",
            isDebt:
                false, // Tiền trả trước luôn là tiền thật, không phải công nợ
          );
          todayTrans.add(item);
          if (downMethod == "TIỀN MẶT") {
            cashIn += item.amount;
          } else {
            bankIn += item.amount;
          }
        }
      } else {
        // Handle KẾT HỢP (combined cash+transfer) separately
        if (s.paymentMethod == "KẾT HỢP") {
          // Split into cash and transfer portions
          if (s.cashAmount > 0) {
            final cashItem = _TransactionItem(
              title: "Bán (TM): ${s.productNames}",
              amount: s.cashAmount,
              method: "TIỀN MẶT",
              time: s.soldAt,
              type: "IN",
              isDebt: false,
            );
            todayTrans.add(cashItem);
            cashIn += cashItem.amount;
          }
          if (s.transferAmount > 0) {
            final transferItem = _TransactionItem(
              title: "Bán (CK): ${s.productNames}",
              amount: s.transferAmount,
              method: "CHUYỂN KHOẢN",
              time: s.soldAt,
              type: "IN",
              isDebt: false,
            );
            todayTrans.add(transferItem);
            bankIn += transferItem.amount;
          }
        } else {
          final item = _TransactionItem(
            title: "Bán: ${s.productNames}",
            amount: s.finalPrice,
            method: s.paymentMethod,
            time: s.soldAt,
            type: "IN",
            isDebt: s.paymentMethod == "CÔNG NỢ",
          );
          todayTrans.add(item);
          if (!item.isDebt) {
            if (item.method == "TIỀN MẶT") {
              cashIn += item.amount;
            } else {
              bankIn += item.amount;
            }
          } else {
            debtAmount += item.amount;
          }
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
        if (item.method == "TIỀN MẶT") {
          cashIn += item.amount;
        } else {
          bankIn += item.amount;
        }
      } else {
        debtAmount += item.amount;
      }
    }

    // Expenses - Lưu lại amount nhập hàng để tránh double-count
    final importExpenseAmounts = <int>{};
    for (var e in _expenses.where(
      (e) => _isSameDay((e['date'] ?? e['createdAt']) as int, now),
    )) {
      final category = (e['category'] ?? e['title'] ?? '')
          .toString()
          .toUpperCase();
      final amount = e['amount'] as int? ?? 0;
      final eType = (e['type'] ?? 'CHI').toString().toUpperCase();

      // Thu phát sinh (type=THU) → tính vào income
      if (eType == 'THU') {
        final item = _TransactionItem(
          title: "Thu: ${e['title'] ?? e['description'] ?? 'Thu phát sinh'}",
          amount: amount,
          method: e['paymentMethod'] ?? 'TIỀN MẶT',
          time: (e['date'] ?? e['createdAt']) as int,
          type: "IN",
          isDebt: false,
        );
        todayTrans.add(item);
        if (item.method == "TIỀN MẶT") {
          cashIn += item.amount;
        } else {
          bankIn += item.amount;
        }
        continue;
      }

      // Lưu lại amount nếu là expense NHẬP HÀNG
      if (category.contains('NHẬP') || category.contains('LINH KIỆN')) {
        importExpenseAmounts.add(amount);
      }

      final item = _TransactionItem(
        title: "Chi: ${e['title'] ?? e['description'] ?? 'Chi phí'}",
        amount: amount,
        method: e['paymentMethod'] ?? 'TIỀN MẶT',
        time: (e['date'] ?? e['createdAt']) as int,
        type: "OUT",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.method == "TIỀN MẶT") {
        cashOut += item.amount;
      } else {
        bankOut += item.amount;
      }
    }

    // Supplier imports (Nhập hàng từ NCC) - CHỈ tính khi KHÔNG có expense tương ứng (tránh double-count)
    for (var imp in _supplierImports.where(
      (i) => _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, now),
    )) {
      final paymentMethod = imp['paymentMethod'] as String? ?? 'TIỀN MẶT';
      // Bỏ qua nếu là công nợ (sẽ tính khi thanh toán)
      if (paymentMethod == 'CÔNG NỢ') continue;

      final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
      if (amount <= 0) continue;

      // Kiểm tra đã có expense tương ứng chưa (tránh double-count)
      final hasMatchingExpense = importExpenseAmounts.any(
        (expAmount) => (expAmount - amount).abs() < 1000,
      );
      if (hasMatchingExpense) continue;

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
      if (item.method == "TIỀN MẶT") {
        cashOut += item.amount;
      } else {
        bankOut += item.amount;
      }
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
      if (item.method == "TIỀN MẶT") {
        cashOut += item.amount;
      } else {
        bankOut += item.amount;
      }
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
        if (item.method == "TIỀN MẶT") {
          cashIn += item.amount;
        } else {
          bankIn += item.amount;
        }
      } else {
        if (item.method == "TIỀN MẶT") {
          cashOut += item.amount;
        } else {
          bankOut += item.amount;
        }
      }
    }

    // Repair partner payments (Thanh toán đối tác sửa chữa)
    for (var pay in _repairPartnerPayments.where(
      (p) => _isSameDay((p['paidAt'] ?? 0) as int, now),
    )) {
      final amount = (pay['amount'] ?? 0) as int;
      if (amount <= 0) continue;

      final paymentMethod = pay['paymentMethod'] as String? ?? 'TIỀN MẶT';
      final item = _TransactionItem(
        title: "Trả đối tác SC: ${pay['partnerName'] ?? 'Đối tác'}",
        amount: amount,
        method: paymentMethod,
        time: (pay['paidAt'] ?? 0) as int,
        type: "OUT",
        isDebt: false,
      );
      todayTrans.add(item);
      if (item.method == "TIỀN MẶT") {
        cashOut += item.amount;
      } else {
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Bạn có chắc muốn mở khóa ngày hôm nay?",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "• Các giao dịch sẽ được phép thêm/sửa/xóa\n"
              "• Bạn cần chốt quỹ lại sau khi hoàn tất\n"
              "• Hành động này sẽ được ghi nhật ký",
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey),
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
    // Finalize currency fields trước khi xử lý
    CurrencyTextField.finalizeAll();

    final cash = CurrencyTextField.parseValue(cashEndCtrl.text);
    final bank = CurrencyTextField.parseValue(bankEndCtrl.text);

    // Xác nhận trước khi chốt
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
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
            const SizedBox(height: 4),
            Text('Ngân hàng: ${NumberFormat('#,###').format(bank)} đ'),
            const SizedBox(height: 12),
            Text(
              'Sau khi chốt, bạn sẽ không thể sửa/xóa các phiếu trong ngày.',
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text(
              'CHỐT QUỸ',
              style: TextStyle(color: Colors.white),
            ),
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
              fontSize: AppTextStyles.overlineSize,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            NumberFormat('#,###').format(v),
            style: TextStyle(
              fontSize: AppTextStyles.headline3.fontSize,
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

    // ACCRUAL BASIS: Tính tổng doanh thu và giá vốn từ sales (bao gồm cả công nợ)
    int salesIncome = 0;
    int salesCost = 0;
    int salesDebt = 0; // Track công nợ riêng
    for (var s in fSales) {
      final saleRevenue = s.finalPrice; // Giá sau giảm giá

      if (s.paymentMethod == 'CÔNG NỢ') {
        // K3: Công nợ - VẪN TÍNH vào doanh thu và giá vốn (accrual basis)
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
        salesDebt += saleRevenue;
        continue;
      }
      if (s.isInstallment) {
        // Trả góp: tính theo số tiền đã thu
        final downPaid = s.downPayment;
        final settlementPaid =
            (s.settlementReceivedAt != null &&
                _isInFilterPeriod(s.settlementReceivedAt!))
            ? s.settlementAmount.clamp(0, s.loanAmount + s.loanAmount2)
            : 0;
        final totalPaid = downPaid + settlementPaid;
        
        salesIncome += totalPaid;
        final ratio = saleRevenue > 0 ? totalPaid / saleRevenue : 0.0;
        salesCost += (s.totalCost * ratio).round();
      } else {
        // Bán thường
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
      }
    }

    // ACCRUAL BASIS: Tính tổng doanh thu và giá vốn từ repairs (bao gồm cả công nợ)
    int repairsIncome = 0;
    int repairsCost = 0;
    for (var r in fRepairs) {
      // Tính cả công nợ vào doanh thu và giá vốn
      repairsIncome += r.price;
      repairsCost += r.totalCost;
    }

    int totalIn = salesIncome + repairsIncome;

    // Thu phát sinh (type=THU) → cộng vào tổng thu
    int miscIncome = fExpenses
        .where((e) => (e['type'] ?? 'CHI').toString().toUpperCase() == 'THU')
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int? ?? 0));
    totalIn += miscIncome;

    // CHI PHÍ = tổng expenses (LOẠI TRỪ nhập hàng/purchase và thu phát sinh)
    int totalOut = fExpenses
        .where((e) {
          // Loại trừ thu phát sinh (type=THU)
          final eType = (e['type'] ?? 'CHI').toString().toUpperCase();
          if (eType == 'THU') return false;
          final category = (e['category'] as String? ?? '').toUpperCase();
          // Loại trừ các chi phí nhập hàng/purchase vì sẽ được tính qua giá vốn khi bán
          return !category.contains('NHẬP HÀNG') &&
              !category.contains('PURCHASE') &&
              !category.contains('STOCK') &&
              !category.contains('ĐƠN NHẬP');
        })
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int));
    // ACCRUAL BASIS: LỢI NHUẬN RÒNG = DOANH THU - CHI PHÍ - GIÁ VỐN
    int profit = totalIn - totalOut - salesCost - repairsCost;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter indicator với gradient
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primary.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getFilterLabel(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.headline3.fontSize,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Báo cáo tổng quan tài chính',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Main Profit Card - nổi bật
          _mainProfitCard(profit, _getFilterLabel()),
          const SizedBox(height: 20),

          // Revenue Cards Row
          Row(
            children: [
              _modernIncomeCard(
                "DOANH THU",
                totalIn,
                Colors.green,
                Icons.arrow_downward_rounded,
              ),
              const SizedBox(width: 12),
              _modernIncomeCard(
                "CHI PHÍ",
                totalOut,
                Colors.red,
                Icons.arrow_upward_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _modernIncomeCard(
                "GIÁ VỐN",
                salesCost + repairsCost,
                Colors.orange,
                Icons.inventory_2,
              ),
              const SizedBox(width: 12),
              _modernIncomeCard(
                "LỢI NHUẬN",
                profit,
                profit >= 0 ? Colors.teal : Colors.red,
                Icons.trending_up,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Mini Revenue Chart
          _buildMiniRevenueChart(
            salesIncome,
            repairsIncome,
            totalOut,
            salesCost + repairsCost,
          ),
          const SizedBox(height: 24),

          // Quick Stats Section
          Container(
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
                        color: Colors.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.analytics,
                        color: Colors.indigo,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "THỐNG KÊ CHI TIẾT",
                      style: TextStyle(
                        fontSize: AppTextStyles.headline5.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _modernStatCard(
                        "Đơn bán",
                        fSales.length.toString(),
                        Icons.shopping_cart,
                        Colors.blue,
                      ),
                    ),
                    if (_enableRepair) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _modernStatCard(
                          "Sửa chữa",
                          fRepairs.length.toString(),
                          Icons.build,
                          Colors.orange,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: _modernStatCard(
                        "Chi phí",
                        fExpenses.length.toString(),
                        Icons.receipt,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Chi tiết nguồn thu
                _buildRevenueBreakdown(
                  salesIncome,
                  _enableRepair ? repairsIncome : 0,
                  fSales.length,
                  _enableRepair ? fRepairs.length : 0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Receivables Section - Công nợ phải thu
          _buildReceivablesSection(),
        ],
      ),
    );
  }

  /// Widget hiển thị công nợ phải thu
  Widget _buildReceivablesSection() {
    // Tính công nợ từ bán hàng (CÔNG NỢ payment method)
    final debtSales = _sales
        .where((s) => s.paymentMethod == 'CÔNG NỢ')
        .toList();
    int saleDebt = debtSales.fold(0, (sum, s) => sum + s.finalPrice);

    // Tính công nợ từ sửa chữa (status == 4 + paymentMethod CÔNG NỢ)
    final debtRepairs = _repairs
        .where((r) => r.status == 4 && r.paymentMethod == 'CÔNG NỢ')
        .toList();
    int repairDebt = debtRepairs.fold(0, (sum, r) => sum + r.price);

    // Tính tiền trả góp chưa nhận từ NH
    final pendingInstallments = _sales
        .where(
          (s) =>
              s.isInstallment &&
              s.settlementReceivedAt == null &&
              (s.loanAmount > 0 || s.loanAmount2 > 0),
        )
        .toList();
    int pendingFromBank = pendingInstallments.fold(
      0,
      (sum, s) => sum + s.loanAmount + s.loanAmount2, // Include both loans
    );

    // Tổng phải thu
    int totalReceivables = saleDebt + repairDebt + pendingFromBank;

    if (totalReceivables == 0) return const SizedBox();

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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.blue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "CÔNG NỢ PHẢI THU",
                  style: TextStyle(
                    fontSize: AppTextStyles.headline5.fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${NumberFormat('#,###').format(totalReceivables)} đ",
                  style: TextStyle(
                    fontSize: AppTextStyles.headline4.fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          if (saleDebt > 0 || (_enableRepair && repairDebt > 0) || pendingFromBank > 0) ...[
            const Divider(height: 20),
            if (saleDebt > 0)
              _receivableItem(
                "Công nợ bán hàng",
                saleDebt,
                debtSales.length,
                Icons.shopping_bag,
                Colors.blue,
              ),
            if (_enableRepair && repairDebt > 0)
              _receivableItem(
                "Công nợ sửa chữa",
                repairDebt,
                debtRepairs.length,
                Icons.build,
                Colors.orange,
              ),
            if (pendingFromBank > 0)
              _receivableItem(
                "Chờ NH tất toán",
                pendingFromBank,
                pendingInstallments.length,
                Icons.account_balance,
                Colors.teal,
              ),
          ],
        ],
      ),
    );
  }

  Widget _receivableItem(
    String label,
    int amount,
    int count,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$label ($count đơn)",
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey.shade700),
            ),
          ),
          Text(
            "${NumberFormat('#,###').format(amount)} đ",
            style: TextStyle(
              fontSize: AppTextStyles.headline5.fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị biểu đồ mini doanh thu
  Widget _buildMiniRevenueChart(
    int salesIncome,
    int repairsIncome,
    int expenses,
    int cost,
  ) {
    final total = salesIncome + repairsIncome + expenses + cost;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text("Chưa có dữ liệu", style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final salesPct = (salesIncome / total * 100).clamp(0, 100);
    final repairsPct = (repairsIncome / total * 100).clamp(0, 100);
    final expensesPct = (expenses / total * 100).clamp(0, 100);
    final costPct = (cost / total * 100).clamp(0, 100);

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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.pie_chart,
                  color: Colors.blue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "PHÂN BỔ TÀI CHÍNH",
                style: TextStyle(
                  fontSize: AppTextStyles.headline5.fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stacked Bar Chart
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(
                children: [
                  if (salesPct > 0)
                    Flexible(
                      flex: salesPct.round().clamp(1, 100),
                      child: Container(color: Colors.green.shade400),
                    ),
                  if (_enableRepair && repairsPct > 0)
                    Flexible(
                      flex: repairsPct.round().clamp(1, 100),
                      child: Container(color: Colors.blue.shade400),
                    ),
                  if (expensesPct > 0)
                    Flexible(
                      flex: expensesPct.round().clamp(1, 100),
                      child: Container(color: Colors.red.shade400),
                    ),
                  if (costPct > 0)
                    Flexible(
                      flex: costPct.round().clamp(1, 100),
                      child: Container(color: Colors.orange.shade400),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _chartLegend(
                "Bán hàng",
                Colors.green.shade400,
                "${salesPct.toStringAsFixed(0)}%",
              ),
              if (_enableRepair)
                _chartLegend(
                  "Sửa chữa",
                  Colors.blue.shade400,
                  "${repairsPct.toStringAsFixed(0)}%",
                ),
              _chartLegend(
                "Chi phí",
                Colors.red.shade400,
                "${expensesPct.toStringAsFixed(0)}%",
              ),
              _chartLegend(
                "Giá vốn",
                Colors.orange.shade400,
                "${costPct.toStringAsFixed(0)}%",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(String label, Color color, String pct) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          "$label: $pct",
          style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildRevenueBreakdown(
    int salesIncome,
    int repairsIncome,
    int salesCount,
    int repairsCount,
  ) {
    return Column(
      children: [
        _revenueBreakdownRow(
          "Bán hàng ($salesCount đơn)",
          salesIncome,
          Colors.green,
        ),
        if (_enableRepair && repairsCount > 0) ...[
          const SizedBox(height: 8),
          _revenueBreakdownRow(
            "Sửa chữa ($repairsCount đơn)",
            repairsIncome,
            Colors.blue,
          ),
        ],
      ],
    );
  }

  Widget _revenueBreakdownRow(String label, int amount, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade700),
          ),
        ),
        Text(
          "+${NumberFormat('#,###').format(amount)} đ",
          style: TextStyle(
            fontSize: AppTextStyles.headline5.fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _modernIncomeCard(
    String label,
    int amount,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextStyles.caption.fontSize,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${NumberFormat('#,###').format(amount)}đ',
              style: TextStyle(
                fontSize: AppTextStyles.headline4.fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTextStyles.headline2.fontSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: color.withOpacity(0.8)),
            textAlign: TextAlign.center,
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
              fontSize: AppTextStyles.caption.fontSize,
              color: c.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${NumberFormat('#,###').format(v)}đ',
            style: TextStyle(
              fontSize: AppTextStyles.headline4.fontSize,
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
    padding: const EdgeInsets.all(12),
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
            fontSize: AppTextStyles.body1.fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "${NumberFormat('#,###').format(p)} đ",
          style: TextStyle(
            color: Colors.white,
            fontSize: AppTextStyles.headline1.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
  Widget _buildSaleDetail() {
    final list = _sales.where((s) => _isInFilterPeriod(s.soldAt)).toList();
    list.sort((a, b) => b.soldAt.compareTo(a.soldAt));

    // Tính doanh thu đã thu thực tế (cash basis for installment)
    final totalRevenue = list.fold<int>(0, (sum, s) {
      if (s.isInstallment) {
        // Trả góp: chỉ tính tiền đã thu (downPayment + settlement nếu có)
        final settlementPaid = s.settlementReceivedAt != null ? s.settlementAmount : 0;
        return sum + s.downPayment + settlementPaid;
      }
      return sum + s.totalPrice;
    });

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
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: AppTextStyles.subtitle1.fontSize,
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
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                                fontSize: AppTextStyles.subtitle1.fontSize,
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
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                                fontSize: AppTextStyles.subtitle1.fontSize,
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
          // Dùng downPaymentMethod để phân biệt tiền mặt/chuyển khoản
          final downMethod = s.downPaymentMethod ?? 'TIỀN MẶT';
          allTransactions.add(
            _TransactionItem(
              title: "Bán TG cọc: ${s.productNames}",
              amount: s.downPayment,
              method: downMethod,
              time: s.soldAt,
              type: "IN",
              isDebt: false, // Tiền trả trước không phải công nợ
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
                        fontSize: AppTextStyles.caption.fontSize,
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
                  Text(
                    "Công nợ",
                    style: TextStyle(color: Colors.orange, fontSize: AppTextStyles.subtitle1.fontSize),
                  ),
              ],
            ),
            trailing: Text(
              "${isIncome ? '+' : '-'}${NumberFormat('#,###').format(item.amount)}đ",
              style: TextStyle(
                color: isIncome ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.headline4.fontSize,
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
                fontSize: AppTextStyles.subtitle1.fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: AppTextStyles.overlineSize, color: color.withOpacity(0.7)),
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
