import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
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
  bool _canViewCostPrice = false;
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
    _tabController = TabController(length: 2, vsync: this);
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
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
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
      // Real-time listeners handle downloads — chỉ push local changes

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

  bool _isPersonalExpenseScope(Map<String, dynamic> expense) {
    final scope = (expense['scope'] ?? 'SHOP').toString().toUpperCase();
    return scope == 'CA_NHAN' || scope == 'CÁ NHÂN' || scope == 'PERSONAL';
  }

  bool _isBusinessOperatingExpense(Map<String, dynamic> expense) {
    final eType = (expense['type'] ?? 'CHI').toString().toUpperCase();
    if (eType == 'THU') return false;
    if (_isPersonalExpenseScope(expense)) return false;
    final category = (expense['category'] as String? ?? '').toUpperCase();
    return !category.contains('NHẬP HÀNG') &&
        !category.contains('PURCHASE') &&
        !category.contains('STOCK') &&
        !category.contains('ĐƠN NHẬP');
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
        title: 'BÁO CÁO DOANH THU',
        subtitle: 'Doanh thu · Chi phí · Lợi nhuận',
        accentColor: AppBarAccents.finance,
        actions: [
          IconButton(
            onPressed: _showFilterSheet,
            icon: Badge(
              label: Text(
                _getFilterLabel(),
                style: const TextStyle(
                  fontSize: 11,
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
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'TỔNG QUAN'),
                    Tab(text: 'SO SÁNH'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverview(),
                      _buildComparisonTab(),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  /// Calculate stats for a given date range filter function
  _PeriodStats _calculatePeriodStats(String label, bool Function(int ms) filter) {
    final fSales = _sales.where((s) => filter(s.soldAt)).toList();
    final fRepairs = _repairs
        .where((r) => r.status == 4 && r.deliveredAt != null && filter(r.deliveredAt!))
        .toList();
    final fExpenses = _expenses
        .where((e) => filter((e['date'] ?? e['createdAt']) as int))
        .toList();

    int salesIncome = 0, salesCost = 0;
    for (var s in fSales) {
      final saleRevenue = s.finalPrice;
      if (s.paymentMethod == 'CÔNG NỢ') {
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
        continue;
      }
      if (s.isInstallment) {
        final downPaid = s.downPayment;
        final settlementPaid =
            (s.settlementReceivedAt != null && filter(s.settlementReceivedAt!))
            ? s.settlementAmount.clamp(0, s.loanAmount + s.loanAmount2)
            : 0;
        final totalPaid = downPaid + settlementPaid;
        salesIncome += totalPaid;
        final ratio = saleRevenue > 0 ? totalPaid / saleRevenue : 0.0;
        salesCost += (s.totalCost * ratio).round();
      } else {
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
      }
    }

    int repairsIncome = 0, repairsCost = 0;
    for (var r in fRepairs) {
      repairsIncome += r.price;
      repairsCost += r.totalCost;
    }

    int miscIncome = fExpenses
        .where((e) => (e['type'] ?? 'CHI').toString().toUpperCase() == 'THU')
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int? ?? 0));

    int expenseOut = fExpenses
      .where(_isBusinessOperatingExpense)
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int));

    return _PeriodStats(
      label: label,
      salesIncome: salesIncome,
      salesCost: salesCost,
      repairsIncome: repairsIncome,
      repairsCost: repairsCost,
      miscIncome: miscIncome,
      expenseOut: expenseOut,
      salesCount: fSales.length,
      repairsCount: fRepairs.length,
    );
  }

  /// Get date ranges for current period and previous period based on _timeFilter
  List<_PeriodStats> _getComparisonPeriods() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_timeFilter) {
      case 'today':
        final yesterday = today.subtract(const Duration(days: 1));
        return [
          _calculatePeriodStats('Hôm nay', (ms) => _isSameDay(ms, now)),
          _calculatePeriodStats('Hôm qua', (ms) => _isSameDay(ms, yesterday)),
        ];
      case 'week':
        final weekAgo = today.subtract(const Duration(days: 7));
        final twoWeeksAgo = today.subtract(const Duration(days: 14));
        return [
          _calculatePeriodStats('7 ngày gần đây', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(weekAgo);
          }),
          _calculatePeriodStats('7 ngày trước đó', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(twoWeeksAgo) && dt.isBefore(weekAgo);
          }),
        ];
      case 'month':
        final monthStart = DateTime(now.year, now.month, 1);
        final prevMonthStart = DateTime(now.year, now.month - 1, 1);
        return [
          _calculatePeriodStats('Tháng ${now.month}', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(monthStart);
          }),
          _calculatePeriodStats('Tháng ${now.month - 1 == 0 ? 12 : now.month - 1}', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(prevMonthStart) && dt.isBefore(monthStart);
          }),
        ];
      case 'quarter':
        final currentQ = ((now.month - 1) ~/ 3) + 1;
        final qStartMonth = (currentQ - 1) * 3 + 1;
        final qStart = DateTime(now.year, qStartMonth, 1);
        final prevQ = currentQ == 1 ? 4 : currentQ - 1;
        final prevYear = currentQ == 1 ? now.year - 1 : now.year;
        final prevQStartMonth = (prevQ - 1) * 3 + 1;
        final prevQStart = DateTime(prevYear, prevQStartMonth, 1);
        return [
          _calculatePeriodStats('Quý $currentQ/${now.year}', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(qStart);
          }),
          _calculatePeriodStats('Quý $prevQ/$prevYear', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(prevQStart) && dt.isBefore(qStart);
          }),
        ];
      case 'year':
        final yearStart = DateTime(now.year, 1, 1);
        final prevYearStart = DateTime(now.year - 1, 1, 1);
        return [
          _calculatePeriodStats('Năm ${now.year}', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(yearStart);
          }),
          _calculatePeriodStats('Năm ${now.year - 1}', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(prevYearStart) && dt.isBefore(yearStart);
          }),
        ];
      default: // custom or fallback — compare this month vs last month
        final monthStart = DateTime(now.year, now.month, 1);
        final prevMonthStart = DateTime(now.year, now.month - 1, 1);
        return [
          _calculatePeriodStats('Tháng này', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(monthStart);
          }),
          _calculatePeriodStats('Tháng trước', (ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return !dt.isBefore(prevMonthStart) && dt.isBefore(monthStart);
          }),
        ];
    }
  }

  Widget _buildComparisonTab() {
    final periods = _getComparisonPeriods();
    if (periods.length < 2) return const SizedBox();
    final cur = periods[0];
    final prev = periods[1];

    String fmt(int v) => '${NumberFormat('#,###').format(v)}đ';
    String pct(int a, int b) {
      if (b == 0) return a > 0 ? '+∞' : '0%';
      final p = ((a - b) / b.abs() * 100).round();
      return '${p >= 0 ? '+' : ''}$p%';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Period comparison header (compact) ──
          Row(
            children: [
              _periodBadge(cur.label, cur.totalRevenue, fmt, AppColors.primary, true),
              const SizedBox(width: 8),
              _periodBadge(prev.label, prev.totalRevenue, fmt, Colors.grey.shade600, false),
            ],
          ),

          const SizedBox(height: 14),

          // ── Grouped bar chart: current vs previous ──
          _comparisonBarChart(cur, prev),

          const SizedBox(height: 14),

          // ── Delta cards (compact) ──
          _deltaRow('Doanh thu', cur.totalRevenue, prev.totalRevenue, fmt, pct, const Color(0xFF1E88E5), Icons.trending_up),
          _deltaRow('Lợi nhuận', cur.profit, prev.profit, fmt, pct, const Color(0xFF43A047), Icons.account_balance_wallet),
          if (_canViewCostPrice)
          _deltaRow('Giá vốn', cur.totalCost, prev.totalCost, fmt, pct, const Color(0xFFFB8C00), Icons.inventory_2_outlined),
          _deltaRow('Chi phí', cur.expenseOut, prev.expenseOut, fmt, pct, const Color(0xFFE53935), Icons.money_off),
          if (_enableRepair)
            _deltaRow('Sửa chữa', cur.repairsIncome, prev.repairsIncome, fmt, pct, const Color(0xFF7E57C2), Icons.build),

          const SizedBox(height: 14),

          // ── Detail breakdown table ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHI TIẾT', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                // Column headers
                Row(
                  children: [
                    const SizedBox(width: 90),
                    Expanded(child: Text(cur.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary), textAlign: TextAlign.right)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(prev.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500), textAlign: TextAlign.right)),
                    const SizedBox(width: 6),
                    SizedBox(width: 48, child: Text('%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500), textAlign: TextAlign.right)),
                  ],
                ),
                Divider(height: 12, color: Colors.grey.shade200),
                _compRow('Bán hàng', cur.salesIncome, prev.salesIncome, fmt, pct),
                if (_canViewCostPrice) _compRow('Giá vốn BH', cur.salesCost, prev.salesCost, fmt, pct),
                if (_enableRepair) _compRow('Sửa chữa', cur.repairsIncome, prev.repairsIncome, fmt, pct),
                if (_enableRepair && _canViewCostPrice) _compRow('Vốn SC', cur.repairsCost, prev.repairsCost, fmt, pct),
                _compRow('Thu khác', cur.miscIncome, prev.miscIncome, fmt, pct),
                _compRow('Chi phí HĐ', cur.expenseOut, prev.expenseOut, fmt, pct),
                Divider(height: 12, color: Colors.grey.shade200),
                _compRow('Đơn bán', cur.salesCount, prev.salesCount, (v) => '$v', pct),
                if (_enableRepair) _compRow('Đơn SC', cur.repairsCount, prev.repairsCount, (v) => '$v', pct),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodBadge(String label, int revenue, String Function(int) fmt, Color color, bool active) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color.withOpacity(0.2) : Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? color : Colors.grey.shade600)),
            const SizedBox(height: 2),
            Text(fmt(revenue), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: active ? color : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _comparisonBarChart(_PeriodStats cur, _PeriodStats prev) {
    final metrics = <_CompMetric>[
      _CompMetric('DT', cur.totalRevenue, prev.totalRevenue, const Color(0xFF1E88E5)),
      _CompMetric('LN', cur.profit, prev.profit, const Color(0xFF43A047)),
      _CompMetric('Vốn', cur.totalCost, prev.totalCost, const Color(0xFFFB8C00)),
      _CompMetric('Chi', cur.expenseOut, prev.expenseOut, const Color(0xFFE53935)),
    ];
    final maxVal = metrics.fold<double>(0, (m, e) => math.max(m, math.max(e.cur.toDouble(), e.prev.toDouble())));
    if (maxVal == 0) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SO SÁNH', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
              const Spacer(),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text('Hiện tại', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 10),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text('Trước', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= metrics.length) return const SizedBox();
                        return Text(metrics[idx].label, style: TextStyle(fontSize: 12, color: metrics[idx].color, fontWeight: FontWeight.w600));
                      },
                    ),
                  ),
                ),
                barGroups: metrics.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 3,
                    barRods: [
                      BarChartRodData(
                        toY: m.cur.toDouble().clamp(0, double.infinity),
                        color: m.color,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: m.prev.toDouble().clamp(0, double.infinity),
                        color: m.color.withOpacity(0.3),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaRow(String title, int current, int previous,
      String Function(int) fmt, String Function(int, int) pct,
      Color color, IconData icon) {
    final d = current - previous;
    final isUp = d >= 0;
    final isPositiveMetric = title == 'Doanh thu' || title == 'Lợi nhuận' || title == 'Sửa chữa';
    final changeColor = isUp
        ? (isPositiveMetric ? const Color(0xFF2E7D32) : const Color(0xFFC62828))
        : (isPositiveMetric ? const Color(0xFFC62828) : const Color(0xFF2E7D32));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(fmt(current), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: changeColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: changeColor),
                const SizedBox(width: 2),
                Text(pct(current, previous), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: changeColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compRow(String label, int current, int previous,
      String Function(int) fmt, String Function(int, int) pct) {
    final d = current - previous;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
          Expanded(child: Text(fmt(current), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          Expanded(child: Text(fmt(previous), style: TextStyle(fontSize: 13, color: Colors.grey.shade500), textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          SizedBox(
            width: 48,
            child: Text(
              pct(current, previous),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: d >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
              textAlign: TextAlign.right,
            ),
          ),
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

    // ACCRUAL BASIS calculations
    int salesIncome = 0, salesCost = 0;
    for (var s in fSales) {
      final saleRevenue = s.finalPrice;
      if (s.paymentMethod == 'CÔNG NỢ') {
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
        continue;
      }
      if (s.isInstallment) {
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
        salesIncome += saleRevenue;
        salesCost += s.totalCost;
      }
    }

    int repairsIncome = 0, repairsCost = 0;
    for (var r in fRepairs) {
      repairsIncome += r.price;
      repairsCost += r.totalCost;
    }

    int totalIn = salesIncome + repairsIncome;
    int miscIncome = fExpenses
        .where((e) => (e['type'] ?? 'CHI').toString().toUpperCase() == 'THU')
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int? ?? 0));
    totalIn += miscIncome;

    int totalOut = fExpenses
      .where(_isBusinessOperatingExpense)
        .fold<int>(0, (sum, e) => sum + (e['amount'] as int));

    int totalCost = salesCost + repairsCost;
    int profit = totalIn - totalOut - totalCost;

    String fmt(int v) => NumberFormat('#,###').format(v);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ COMPACT PROFIT HEADER ═══
          _compactProfitHeader(profit, totalIn, totalOut + totalCost),

          const SizedBox(height: 12),

          // ═══ 4 METRIC TILES ═══
          Row(
            children: [
              _metricTile('Doanh thu', totalIn, const Color(0xFF2E7D32), Icons.trending_up),
              const SizedBox(width: 8),
              _metricTile('Chi phí', totalOut, const Color(0xFFC62828), Icons.trending_down),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricTile('Giá vốn', totalCost, const Color(0xFFE65100), Icons.inventory_2_outlined),
              const SizedBox(width: 8),
              _metricTile('Biên LN', totalIn > 0 ? (profit * 100 ~/ totalIn) : 0,
                profit >= 0 ? const Color(0xFF00695C) : const Color(0xFFC62828),
                Icons.percent, suffix: '%', raw: true),
            ],
          ),

          const SizedBox(height: 16),

          // ═══ DONUT CHART + BREAKDOWN ═══
          _donutBreakdownCard(salesIncome, repairsIncome, miscIncome, totalOut, totalCost),

          const SizedBox(height: 16),

          // ═══ BAR CHART: THU vs CHI ═══
          _barChartCard(salesIncome, repairsIncome, miscIncome, totalOut, totalCost),

          const SizedBox(height: 16),

          // ═══ QUICK STATS ═══
          _quickStatsRow(fSales.length, fRepairs.length, fExpenses.length),

          const SizedBox(height: 16),

          // Top sản phẩm bán chạy
          _buildTopProductsSection(fSales),

          // Top khách hàng mua nhiều
          _buildTopCustomersSection(fSales),

          // Receivables Section
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

  /// Top sản phẩm bán chạy (parsed from comma-separated productNames)
  Widget _buildTopProductsSection(List<SaleOrder> fSales) {
    final productStats = <String, _ProductStat>{};
    for (var s in fSales) {
      final names = s.productNames.split(RegExp(r'[,\n]')).map((n) => n.trim()).where((n) => n.isNotEmpty);
      final count = names.length;
      if (count == 0) continue;
      final revenuePerItem = s.finalPrice ~/ count;
      for (var name in names) {
        final key = name.toUpperCase();
        productStats.putIfAbsent(key, () => _ProductStat(name: name));
        productStats[key]!.qty += 1;
        productStats[key]!.revenue += revenuePerItem;
      }
    }
    if (productStats.isEmpty) return const SizedBox();

    final sorted = productStats.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
    final top = sorted.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.deepPurple, size: 16),
              const SizedBox(width: 6),
              Text('TOP SẢN PHẨM', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.deepPurple, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          ...top.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final p = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('$idx', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: idx <= 3 ? Colors.deepPurple : Colors.grey.shade500)),
                  ),
                  Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text('${p.qty}sp', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple)),
                  ),
                  const SizedBox(width: 6),
                  Text('${NumberFormat('#,###').format(p.revenue)}đ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopCustomersSection(List<SaleOrder> fSales) {
    final customerStats = <String, _CustomerStat>{};
    for (var s in fSales) {
      final name = s.customerName.trim();
      if (name.isEmpty) continue;
      final key = name.toUpperCase();
      customerStats.putIfAbsent(key, () => _CustomerStat(name: name));
      customerStats[key]!.orders += 1;
      customerStats[key]!.totalSpent += s.finalPrice;
    }
    if (customerStats.isEmpty) return const SizedBox();

    final sorted = customerStats.values.toList()..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    final top = sorted.take(5).toList();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, color: Colors.teal, size: 16),
              const SizedBox(width: 6),
              Text('TOP KHÁCH HÀNG', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.teal, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          ...top.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final c = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('$idx', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: idx <= 3 ? Colors.teal : Colors.grey.shade500)),
                  ),
                  Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text('${c.orders}đơn', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal)),
                  ),
                  const SizedBox(width: 6),
                  Text('${NumberFormat('#,###').format(c.totalSpent)}đ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // NEW COMPACT PROFESSIONAL WIDGETS
  // ═══════════════════════════════════════════════════════════════

  /// Compact profit header — period label + profit in one row
  Widget _compactProfitHeader(int profit, int totalIn, int totalOutCost) {
    final isPositive = profit >= 0;
    final profitColor = isPositive ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    final bgGradient = isPositive
        ? const [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]
        : const [Color(0xFFFFEBEE), Color(0xFFFFCDD2)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: bgGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: profitColor.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          // Period badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: profitColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _getFilterLabel(),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: profitColor, letterSpacing: 0.3),
            ),
          ),
          const Spacer(),
          // Profit amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Lợi nhuận ròng', style: TextStyle(fontSize: 12, color: profitColor.withOpacity(0.7))),
              Text(
                '${profit >= 0 ? '+' : ''}${NumberFormat('#,###').format(profit)}đ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: profitColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Single metric tile — used in 2x2 grid
  Widget _metricTile(String label, int value, Color color, IconData icon,
      {String suffix = 'đ', bool raw = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text(
                    raw ? '$value$suffix' : '${NumberFormat('#,###').format(value)}$suffix',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Donut chart with breakdown legend
  Widget _donutBreakdownCard(int salesIncome, int repairsIncome, int misc, int expenses, int cost) {
    final total = salesIncome + repairsIncome + misc + expenses + cost;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: Text('Chưa có dữ liệu', style: TextStyle(color: Colors.grey))),
      );
    }

    final sections = <_ChartItem>[
      _ChartItem('Bán hàng', salesIncome, const Color(0xFF43A047)),
      if (_enableRepair && repairsIncome > 0)
        _ChartItem('Sửa chữa', repairsIncome, const Color(0xFF1E88E5)),
      if (misc > 0) _ChartItem('Thu khác', misc, const Color(0xFF7E57C2)),
      _ChartItem('Chi phí', expenses, const Color(0xFFE53935)),
      _ChartItem('Giá vốn', cost, const Color(0xFFFB8C00)),
    ].where((s) => s.value > 0).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          // Donut
          SizedBox(
            width: 110, height: 110,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: sections.map((s) {
                  final pct = s.value / total * 100;
                  return PieChartSectionData(
                    color: s.color,
                    value: s.value.toDouble(),
                    radius: 22,
                    title: '${pct.round()}%',
                    titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    titlePositionPercentageOffset: 0.55,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections.map((s) {
                final pct = (s.value / total * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 6),
                      Expanded(child: Text(s.label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                      Text('$pct%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: s.color)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal bar chart: THU vs CHI comparison
  Widget _barChartCard(int salesIncome, int repairsIncome, int misc, int expenses, int cost) {
    final totalIn = salesIncome + repairsIncome + misc;
    final totalOut = expenses + cost;
    final maxVal = math.max(totalIn, totalOut).toDouble();
    if (maxVal == 0) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THU vs CHI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: Colors.grey.shade700, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.15,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        switch (v.toInt()) {
                          case 0: return Text('Bán hàng', style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
                          case 1: return Text(_enableRepair ? 'Sửa chữa' : 'Thu khác',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
                          case 2: return Text('Chi phí', style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
                          case 3: return Text('Giá vốn', style: TextStyle(fontSize: 11, color: Colors.grey.shade600));
                          default: return const SizedBox();
                        }
                      },
                    ),
                  ),
                ),
                barGroups: [
                  _barGroup(0, salesIncome.toDouble(), const Color(0xFF43A047)),
                  _barGroup(1, (_enableRepair ? repairsIncome : misc).toDouble(),
                    _enableRepair ? const Color(0xFF1E88E5) : const Color(0xFF7E57C2)),
                  _barGroup(2, expenses.toDouble(), const Color(0xFFE53935)),
                  _barGroup(3, cost.toDouble(), const Color(0xFFFB8C00)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 22,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true, toY: 0, color: color.withOpacity(0.06),
          ),
        ),
      ],
    );
  }

  /// Compact quick stats row
  Widget _quickStatsRow(int salesCount, int repairsCount, int expensesCount) {
    return Row(
      children: [
        _statChip('$salesCount đơn bán', const Color(0xFF1E88E5), Icons.shopping_cart_outlined),
        const SizedBox(width: 6),
        if (_enableRepair) ...[
          _statChip('$repairsCount sửa', const Color(0xFFFB8C00), Icons.build_outlined),
          const SizedBox(width: 6),
        ],
        _statChip('$expensesCount chi', const Color(0xFFE53935), Icons.receipt_outlined),
      ],
    );
  }

  Widget _statChip(String text, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

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

/// Stats for a time period, used in comparison tab
class _PeriodStats {
  final String label;
  final int salesIncome;
  final int salesCost;
  final int repairsIncome;
  final int repairsCost;
  final int miscIncome;
  final int expenseOut;  // Chi phí hoạt động (không gồm nhập hàng)
  final int salesCount;
  final int repairsCount;

  _PeriodStats({
    required this.label,
    required this.salesIncome,
    required this.salesCost,
    required this.repairsIncome,
    required this.repairsCost,
    required this.miscIncome,
    required this.expenseOut,
    required this.salesCount,
    required this.repairsCount,
  });

  int get totalRevenue => salesIncome + repairsIncome + miscIncome;
  int get totalCost => salesCost + repairsCost;
  int get profit => totalRevenue - expenseOut - totalCost;
}

class _ChartItem {
  final String label;
  final int value;
  final Color color;
  _ChartItem(this.label, this.value, this.color);
}

class _CompMetric {
  final String label;
  final int cur;
  final int prev;
  final Color color;
  _CompMetric(this.label, this.cur, this.prev, this.color);
}

class _ProductStat {
  final String name;
  int qty = 0;
  int revenue = 0;
  _ProductStat({required this.name});
}

class _CustomerStat {
  final String name;
  int orders = 0;
  int totalSpent = 0;
  _CustomerStat({required this.name});
}
