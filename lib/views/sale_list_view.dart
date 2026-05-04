import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../services/event_bus.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/shop_settings_model.dart';
import 'sale_detail_view.dart';
import 'create_sale_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../utils/vietnamese_utils.dart';
import '../utils/money_utils.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';
import '../widgets/responsive_wrapper.dart';
import '../services/sales_return_service.dart';
import '../services/user_service.dart';
import 'create_sales_return_view.dart';
import 'debt_view.dart';
import 'monthly_profit_report_view.dart';
import 'customer_management_view.dart';

class SaleListView extends StatefulWidget {
  final bool todayOnly;
  const SaleListView({super.key, this.todayOnly = false});

  @override
  State<SaleListView> createState() => _SaleListViewState();
}

class _SaleListViewState extends State<SaleListView> {
  final db = DBHelper();
  final ScrollController _scrollController = ScrollController();
  List<SaleOrder> _sales = [];
  List<SaleOrder> _allLoadedSales = []; // Cache for filtering
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 30;
  String _search = "";

  // Filter states
  String _timeFilter = 'today'; // all, today, week, month, custom
  String _paymentStatusFilter =
      'all'; // all, paid, debt, bank_pending, bank_received
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Return tracking: saleId -> return summary
  Map<int, _SaleReturnInfo> _returnInfoMap = {};

  // Permission
  bool _canViewCostPrice = false;

  // EventBus subscriptions & debounce
  StreamSubscription<String>? _saleChangedSub;
  StreamSubscription<String>? _saleReturnSub;
  Timer? _saleRefreshDebounce;

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  /// Check if we need full data (for filtering)
  bool get _needsFullData =>
      _search.isNotEmpty ||
      _timeFilter != 'all' ||
      _paymentStatusFilter != 'all';

  @override
  void initState() {
    super.initState();
    if (widget.todayOnly) {
      _timeFilter = 'today';
    }
    _refresh();
    _loadPermissions();

    // Setup scroll listener for lazy loading
    _scrollController.addListener(_onScroll);

    // Listen to sales changes (e.g., when settlement is received)
    _saleChangedSub = EventBus().on('sales_changed', (event) {
      debugPrint('🛒 [SaleListView] Nhận event "$event" → refresh local DB');
      _debouncedRefresh();
    });
    _saleReturnSub = EventBus().on('sales_returns_changed', (event) {
      debugPrint('🛒 [SaleListView] Nhận event "$event" → refresh local DB');
      _debouncedRefresh();
    });
  }

  @override
  void dispose() {
    _saleChangedSub?.cancel();
    _saleReturnSub?.cancel();
    _saleRefreshDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await UserService.getCurrentUserPermissions();
      if (!mounted) return;
      setState(() {
        _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
      });
    } catch (_) {}
  }

  void _debouncedRefresh() {
    _saleRefreshDebounce?.cancel();
    _saleRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refresh();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreIfNeeded();
    }
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_isLoadingMore || !_hasMore || _needsFullData) return;

    setState(() => _isLoadingMore = true);

    try {
      final newData = await db.getSalesPaged(_pageSize, _currentOffset);
      if (mounted) {
        setState(() {
          _allLoadedSales.addAll(newData);
          _sales = _allLoadedSales;
          _currentOffset += _pageSize;
          _isLoadingMore = false;
          _hasMore = newData.length >= _pageSize;
        });
      }
    } catch (e) {
      debugPrint('SaleListView: Error loading more: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _currentOffset = 0;
      _allLoadedSales = [];
      _hasMore = true;
    });

    // Load shop settings for terminology
    final settings = await CategoryService().getShopSettings();
    if (mounted) _shopSettings = settings;

    // Load return info per sale
    try {
      final returns = await SalesReturnService.getReturns();
      final map = <int, _SaleReturnInfo>{};
      for (final r in returns) {
        if (r.salesOrderId == null) continue;
        final sid = r.salesOrderId!;
        final info = map.putIfAbsent(sid, () => _SaleReturnInfo());
        info.totalReturnedAmount += r.totalReturnAmount;
        info.returnCount += 1;
      }
      _returnInfoMap = map;
    } catch (_) {}

    if (_needsFullData || widget.todayOnly) {
      // Optimize: use date-range query when time filter is set
      final List<SaleOrder> data;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      switch (_timeFilter) {
        case 'today':
          data = await db.getSalesByDateRange(
            today.millisecondsSinceEpoch,
            today.add(const Duration(days: 1)).millisecondsSinceEpoch - 1,
          );
          break;
        case 'week':
          data = await db.getSalesByDateRange(
            today.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          );
          break;
        case 'month':
          data = await db.getSalesByDateRange(
            DateTime(now.year, now.month, 1).millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          );
          break;
        case 'custom':
          if (_customStartDate != null && _customEndDate != null) {
            data = await db.getSalesByDateRange(
              _customStartDate!.millisecondsSinceEpoch,
              _customEndDate!
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch -
                  1,
            );
          } else {
            data = await db.getAllSales();
          }
          break;
        default:
          data = await db.getAllSales();
      }
      if (!mounted) return;
      setState(() {
        _allLoadedSales = data;
        _sales = data;
        _loading = false;
        _hasMore = false;
      });
    } else {
      // Lazy load first page
      final firstPage = await db.getSalesPaged(_pageSize, 0);
      if (!mounted) return;
      setState(() {
        _allLoadedSales = firstPage;
        _sales = firstPage;
        _currentOffset = _pageSize;
        _loading = false;
        _hasMore = firstPage.length >= _pageSize;
      });
    }

    // Check fully-returned status (after sales loaded)
    _checkReturnStatus();
  }

  Future<void> _checkReturnStatus() async {
    if (_returnInfoMap.isEmpty) return;
    bool changed = false;
    for (final entry in _returnInfoMap.entries) {
      try {
        final sale = _allLoadedSales
            .where((s) => s.id == entry.key)
            .firstOrNull;
        if (sale != null && sale.id != null && sale.id! > 0) {
          final was = entry.value.allReturned;
          entry.value.allReturned = await _checkAllReturned(sale);
          if (was != entry.value.allReturned) changed = true;
        }
      } catch (_) {}
    }
    if (changed && mounted) setState(() {});
  }

  List<SaleOrder> _applyFilters() {
    var list = _sales.where((s) {
      // Search filter
      if (_search.isNotEmpty) {
        if (!VietnameseUtils.containsVietnamese(s.customerName, _search) &&
            !VietnameseUtils.containsVietnamese(s.productNames, _search) &&
            !s.productImeis.toUpperCase().contains(_search.toUpperCase())) {
          return false;
        }
      }

      // Time filter
      final saleDate = DateTime.fromMillisecondsSinceEpoch(s.soldAt);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      switch (_timeFilter) {
        case 'today':
          final saleDay = DateTime(saleDate.year, saleDate.month, saleDate.day);
          if (saleDay != today) return false;
          break;
        case 'week':
          final weekAgo = today.subtract(const Duration(days: 7));
          if (saleDate.isBefore(weekAgo)) return false;
          break;
        case 'month':
          final monthStart = DateTime(now.year, now.month, 1);
          if (saleDate.isBefore(monthStart)) return false;
          break;
        case 'custom':
          if (_customStartDate != null &&
              saleDate.isBefore(_customStartDate!)) {
            return false;
          }
          if (_customEndDate != null &&
              saleDate.isAfter(_customEndDate!.add(const Duration(days: 1)))) {
            return false;
          }
          break;
      }

      // Payment status filter - tách rõ trạng thái trả góp nhận tiền NH
      final remain = s.remainingDebt;
      final isInstallment =
          s.isInstallment || s.paymentMethod.toUpperCase().contains('TRẢ GÓP');
      final hasBankSettlement =
          (s.settlementReceivedAt ?? 0) > 0 || s.settlementAmount > 0;
      switch (_paymentStatusFilter) {
        case 'paid':
          if (isInstallment) {
            if (remain > 0 || !hasBankSettlement) return false;
          } else {
            if (remain > 0) return false;
          }
          break;
        case 'debt':
          if (remain <= 0) return false;
          break;
        case 'bank_pending':
          if (!isInstallment || hasBankSettlement) return false;
          break;
        case 'bank_received':
          if (!isInstallment || !hasBankSettlement) return false;
          break;
      }

      return true;
    }).toList();

    // Sort by date descending (newest first)
    list.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    return list;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_timeFilter != 'all' && !widget.todayOnly) count++;
    if (_paymentStatusFilter != 'all') count++;
    return count;
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
                    'BỘ LỌC',
                    style: AppTextStyles.headline6.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _timeFilter = widget.todayOnly ? 'today' : 'all';
                        _paymentStatusFilter = 'all';
                        _customStartDate = null;
                        _customEndDate = null;
                      });
                    },
                    child: const Text('Đặt lại'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Time filter
              if (!widget.todayOnly) ...[
                Text(
                  'THỜI GIAN',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(
                      'Tất cả',
                      'all',
                      _timeFilter,
                      (v) => setSheetState(() => _timeFilter = v),
                    ),
                    _filterChip(
                      'Hôm nay',
                      'today',
                      _timeFilter,
                      (v) => setSheetState(() => _timeFilter = v),
                    ),
                    _filterChip(
                      '7 ngày',
                      'week',
                      _timeFilter,
                      (v) => setSheetState(() => _timeFilter = v),
                    ),
                    _filterChip(
                      'Tháng này',
                      'month',
                      _timeFilter,
                      (v) => setSheetState(() => _timeFilter = v),
                    ),
                    _filterChip('Tùy chọn', 'custom', _timeFilter, (v) async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange:
                            _customStartDate != null && _customEndDate != null
                            ? DateTimeRange(
                                start: _customStartDate!,
                                end: _customEndDate!,
                              )
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
                    }),
                  ],
                ),
                if (_timeFilter == 'custom' &&
                    _customStartDate != null &&
                    _customEndDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              // Payment status filter
              Text(
                'TRẠNG THÁI THANH TOÁN',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip(
                    'Tất cả',
                    'all',
                    _paymentStatusFilter,
                    (v) => setSheetState(() => _paymentStatusFilter = v),
                  ),
                  _filterChip(
                    'Đã thanh toán',
                    'paid',
                    _paymentStatusFilter,
                    (v) => setSheetState(() => _paymentStatusFilter = v),
                  ),
                  _filterChip(
                    'Còn nợ',
                    'debt',
                    _paymentStatusFilter,
                    (v) => setSheetState(() => _paymentStatusFilter = v),
                  ),
                  _filterChip(
                    'TG chờ NH',
                    'bank_pending',
                    _paymentStatusFilter,
                    (v) => setSheetState(() => _paymentStatusFilter = v),
                  ),
                  _filterChip(
                    'TG đã nhận NH',
                    'bank_received',
                    _paymentStatusFilter,
                    (v) => setSheetState(() => _paymentStatusFilter = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _refresh(); // Reload data for new filter range
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

  Widget _filterChip(
    String label,
    String value,
    String currentValue,
    Function(String) onSelect,
  ) {
    final isSelected = currentValue == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          style: AppTextStyles.caption.copyWith(
            color: isSelected ? Colors.white : AppColors.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _applyFilters();

    // Calculate summary stats
    int totalSales = list.length;
    int totalRevenue = list.fold(0, (sum, s) => sum + s.totalPrice);
    int totalDebt = list.fold(
      0,
      (sum, s) => sum + s.remainingDebt, // Dùng getter mới tính đúng nợ thực tế
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: widget.todayOnly ? 'DOANH SỐ HÔM NAY' : 'QUẢN LÝ ĐƠN BÁN',
        subtitle:
            '$totalSales đơn • ${MoneyUtils.formatCompactCurrency(totalRevenue)}',
        accentColor: AppBarAccents.sales,
        centerTitle: false,
        actions: [
          // Tạo đơn bán
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ).then((_) => _refresh()),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: Colors.white,
            ),
            tooltip: 'Tạo đơn bán',
          ),
          // Xuất Excel
          IconButton(
            onPressed: () async {
              final result = await ExportDateFilterDialog.show(
                context,
                title: 'Xuất đơn bán',
              );
              if (result == null) return;
              if (!mounted) return;
              await ExcelExportHelper.exportSales(
                context,
                startMs: result['startMs'],
                endMs: result['endMs'],
              );
            },
            icon: const Icon(Icons.file_download_outlined, color: Colors.white),
            tooltip: 'Xuất Excel',
          ),
          // Bộ lọc
          Stack(
            children: [
              IconButton(
                onPressed: _showFilterSheet,
                icon: const Icon(
                  Icons.filter_list_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Bộ lọc',
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_activeFilterCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTextStyles.caption.fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
              decoration: InputDecoration(
                hintText:
                    "Tìm theo tên khách, ${_terms.productLabel.toLowerCase()} hoặc ${_terms.specialField1Label}...",
                hintStyle: TextStyle(
                  fontSize: AppTextStyles.headline5.fontSize,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppBarAccents.sales,
                  size: 20,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: Column(
                children: [
                  // Summary stats bar – compact 1 row
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Text(
                          '$totalSales đơn',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          ' • ',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'DT: ${MoneyUtils.formatCompactCurrency(totalRevenue)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                        if (totalDebt > 0) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Nợ: ${MoneyUtils.formatCompactCurrency(totalDebt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_activeFilterCount > 0)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _timeFilter =
                                    widget.todayOnly ? 'today' : 'all';
                                _paymentStatusFilter = 'all';
                              });
                              _refresh();
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Lọc ($_activeFilterCount)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.close,
                                    size: 10,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          _needsFullData
                              ? '${list.length} kết quả'
                              : '${list.length} đơn',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _buildSalesLoadInsight(list.length),

                  // List
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 80,
                                  color: AppColors.onSurface.withOpacity(0.3),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Không có đơn hàng nào",
                                  style: AppTextStyles.body1.copyWith(
                                    color: AppColors.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                if (_activeFilterCount > 0)
                                  TextButton(
                                    onPressed: () {
                                      _timeFilter = widget.todayOnly
                                          ? 'today'
                                          : 'all';
                                      _paymentStatusFilter = 'all';
                                      _refresh();
                                    },
                                    child: const Text('Xóa bộ lọc'),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            itemCount:
                                list.length +
                                (_isLoadingMore ? 1 : 0) +
                                (!_needsFullData && _hasMore && !_isLoadingMore
                                    ? 1
                                    : 0) +
                                (!_hasMore && list.isNotEmpty ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i >= list.length) {
                                if (_isLoadingMore) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                if (!_needsFullData && _hasMore) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      6,
                                      12,
                                      12,
                                    ),
                                    child: OutlinedButton.icon(
                                      onPressed: _loadMoreIfNeeded,
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('Tải thêm đơn bán'),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: Text(
                                      'Đã hiển thị ${list.length} đơn bán',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize:
                                            AppTextStyles.subtitle1.fontSize,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final s = list[i];
                              final date = DateFormat('dd/MM HH:mm').format(
                                DateTime.fromMillisecondsSinceEpoch(s.soldAt),
                              );
                              final remain = s.remainingDebt;
                              final index = i + 1;
                              final isPaid = s.isPaid;
                              final isInstallment =
                                  s.isInstallment ||
                                  s.paymentMethod
                                      .toUpperCase()
                                      .contains('TRẢ GÓP');
                              final hasBankSettlement =
                                  (s.settlementReceivedAt ?? 0) > 0 ||
                                  s.settlementAmount > 0;
                              final returnInfo = s.id != null
                                  ? _returnInfoMap[s.id]
                                  : null;
                              final isFullyReturned =
                                  returnInfo?.allReturned == true;
                                final accentColor = isFullyReturned
                                  ? Colors.grey.shade500
                                  : (isInstallment && !hasBankSettlement)
                                  ? Colors.orange.shade600
                                  : (isPaid
                                    ? Colors.green.shade600
                                    : Colors.orange.shade600);
                                final borderColor = accentColor.withValues(
                                alpha: 0.22,
                                );

                              final paidAmount = (s.finalPrice - remain).clamp(0, s.finalPrice);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: borderColor,
                                    width: 1,
                                  ),
                                ),
                                elevation: 0.5,
                                shadowColor: accentColor.withValues(alpha: 0.15),
                                color: Colors.white,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SaleDetailView(sale: s),
                                      ),
                                    ).then((_) => _refresh());
                                  },
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    _openReturn(s);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Left accent bar
                                      Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: accentColor,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(10),
                                            bottomLeft: Radius.circular(10),
                                          ),
                                        ),
                                      ),
                                      // Content
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // ROW 1: Index + Product name + Status badge
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    width: 18,
                                                    height: 16,
                                                    margin: const EdgeInsets.only(right: 5),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '$index',
                                                        style: const TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppColors.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      s.productNamesDisplay,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  // Status badge
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: accentColor,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      isFullyReturned
                                                          ? 'TRẢ'
                                                          : (isInstallment && !hasBankSettlement)
                                                          ? 'CHỜ NH'
                                                          : (isPaid ? 'ĐÃ THU' : 'CÒN NỢ'),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // ROW 2: Customer + Date
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Row(
                                                  children: [
                                                    if (s.customerName.isNotEmpty) ...[
                                                      const Icon(Icons.person_outline, size: 10, color: Color(0xFF64748B)),
                                                      const SizedBox(width: 2),
                                                      Expanded(
                                                        child: Text(
                                                          s.customerName,
                                                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ] else
                                                      const Spacer(),
                                                    Text(
                                                      date,
                                                      style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              // ROW 3: Cash – Đã thu / Còn nợ
                                              if (s.finalPrice > 0)
                                                _saleInfoRow(
                                                  left: _saleChip(
                                                    '💰 Đã thu',
                                                    MoneyUtils.formatCompactCurrency(paidAmount),
                                                    const Color(0xFF0369A1),
                                                    const Color(0xFFE0F2FE),
                                                  ),
                                                  right: remain > 0
                                                      ? _saleChip(
                                                          '⚠️ Còn nợ',
                                                          MoneyUtils.formatCompactCurrency(remain),
                                                          const Color(0xFFB45309),
                                                          const Color(0xFFFEF3C7),
                                                        )
                                                      : null,
                                                ),
                                              const SizedBox(height: 3),
                                              // ROW 4: Value – Bán / Vốn
                                              _saleInfoRow(
                                                left: s.finalPrice > 0
                                                    ? _saleChip(
                                                        '🏷 Bán',
                                                        MoneyUtils.formatCompactCurrency(s.finalPrice),
                                                        const Color(0xFF374151),
                                                        const Color(0xFFF3F4F6),
                                                      )
                                                    : null,
                                                right: (_canViewCostPrice && s.totalCost > 0)
                                                    ? _saleChip(
                                                        '📦 Vốn',
                                                        MoneyUtils.formatCompactCurrency(s.totalCost),
                                                        const Color(0xFF6B7280),
                                                        const Color(0xFFF9FAFB),
                                                      )
                                                    : null,
                                              ),
                                              // ROW 5: Lãi / Lỗ
                                              if (_canViewCostPrice && s.totalCost > 0 && s.finalPrice > 0)
                                                Builder(builder: (ctx) {
                                                  final profit = s.finalPrice - s.totalCost;
                                                  final isGain = profit >= 0;
                                                  return Padding(
                                                    padding: const EdgeInsets.only(top: 3),
                                                    child: _saleChip(
                                                      isGain ? '📈 Lãi' : '📉 Lỗ',
                                                      (isGain ? '+' : '-') + MoneyUtils.formatCompactCurrency(profit.abs()),
                                                      isGain ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                                                      isGain ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                                    ),
                                                  );
                                                }),
                                              // ROW 6: Return info
                                              if (returnInfo != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 3),
                                                  child: _saleChip(
                                                    isFullyReturned ? '↩ Trả hết' : '↩ Trả 1 phần',
                                                    isFullyReturned
                                                        ? MoneyUtils.formatCompactCurrency(returnInfo.totalReturnedAmount)
                                                        : '${MoneyUtils.formatCompactCurrency(returnInfo.totalReturnedAmount)} (${returnInfo.returnCount} lần)',
                                                    Colors.grey.shade700,
                                                    Colors.grey.shade100,
                                                  ),
                                                ),
                                              // ROW 7: Installment note
                                              if (isInstallment)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 3),
                                                  child: _saleChip(
                                                    '🏦 Trả góp',
                                                    hasBankSettlement
                                                        ? 'Đã nhận NH ${MoneyUtils.formatCompactCurrency(s.settlementAmount)}'
                                                        : 'Chưa nhận tiền NH',
                                                    hasBankSettlement ? const Color(0xFF0369A1) : const Color(0xFF92400E),
                                                    hasBankSettlement ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7),
                                                  ),
                                                ),
                                              // Seller name (small)
                                              if (s.sellerName.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    s.sellerName,
                                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Chip màu thể hiện 1 chỉ số tài chính trong card đơn bán
  Widget _saleChip(String label, String value, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 10,
                color: textColor.withOpacity(0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 10,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hàng 2 chip cạnh nhau với Spacer cuối
  Widget _saleInfoRow({Widget? left, Widget? right}) {
    if (left == null && right == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (left != null) left,
        if (left != null && right != null) const SizedBox(width: 6),
        if (right != null) right,
      ],
    );
  }

  Widget _buildSalesLoadInsight(int shownCount) {
    final modeLabel = _needsFullData
        ? 'Đang lọc: tải toàn bộ dữ liệu'
        : 'Tải cuộn $_pageSize đơn/lần';
    final statusLabel = (!_needsFullData && _hasMore)
        ? 'Còn dữ liệu để tải thêm'
        : 'Đã tải hết dữ liệu hiện có';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, size: 14, color: Color(0xFF2962FF)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$modeLabel • Đang hiển thị $shownCount đơn',
              style: AppTextStyles.caption.copyWith(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: AppTextStyles.overline.copyWith(
              color: (!_needsFullData && _hasMore)
                  ? Colors.orange.shade700
                  : Colors.green.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeFilterChip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  String _getTimeFilterLabel() {
    switch (_timeFilter) {
      case 'today':
        return 'Hôm nay';
      case 'week':
        return '7 ngày';
      case 'month':
        return 'Tháng này';
      case 'custom':
        return 'Tùy chọn';
      default:
        return '';
    }
  }

  String _getPaymentStatusLabel() {
    switch (_paymentStatusFilter) {
      case 'paid':
        return 'Đã thanh toán';
      case 'debt':
        return 'Còn nợ';
      case 'bank_pending':
        return 'Trả góp chờ NH';
      case 'bank_received':
        return 'Trả góp đã nhận NH';
      default:
        return '';
    }
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyles.overlineSize,
            color: AppColors.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "$value đ",
          style: TextStyle(
            fontSize: AppTextStyles.caption.fontSize,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getPayColor(String m) {
    if (m.contains("TIỀN MẶT")) return AppColors.success;
    if (m.contains("CHUYỂN KHOẢN")) return AppColors.primary;
    if (m.contains("TRẢ GÓP")) return AppColors.warning;
    return AppColors.error;
  }

  Widget _saleInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppTextStyles.caption.fontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ── Return helpers ──

  Future<bool> _checkAllReturned(SaleOrder sale) async {
    if (sale.id == null || sale.id! <= 0) return false;
    final returnedMap = await db.getReturnedQuantitiesForSale(sale.id!);
    if (returnedMap.isEmpty) return false;
    final names = sale.productNames.split(RegExp(r',\s*'));
    final imeis = sale.productImeis.split(RegExp(r',\s*'));
    for (int i = 0; i < names.length; i++) {
      final name = names[i].trim();
      if (name.isEmpty) continue;
      final imei = i < imeis.length ? imeis[i].trim() : '';
      int origQty = 1;
      String cleanName = name;
      final qtyMatch = RegExp(r'^(.+?)\s+[xX](\d+)').firstMatch(name);
      if (qtyMatch != null) {
        cleanName = qtyMatch.group(1)!.trim();
        origQty = int.tryParse(qtyMatch.group(2)!) ?? 1;
      }
      if (imei.toUpperCase().startsWith('PKX')) {
        origQty = int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? 1;
      }
      final isPhone =
          imei.isNotEmpty &&
          !imei.toUpperCase().startsWith('PKX') &&
          imei != 'NO_IMEI';
      final key = isPhone ? imei.toUpperCase() : cleanName.toUpperCase();
      final returned = returnedMap[key] ?? 0;
      if (returned < origQty) return false;
    }
    return true;
  }

  List<Widget> _buildReturnChips(SaleOrder s) {
    final info = _returnInfoMap[s.id];
    if (info == null) return [];
    if (info.allReturned) {
      return [
        _saleInfoChip(
          '↩️ Trả hết ${MoneyUtils.formatCompactCurrency(info.totalReturnedAmount)}',
          Colors.grey.shade300,
        ),
      ];
    }
    return [
      GestureDetector(
        onTap: () => _openReturn(s),
        child: _saleInfoChip(
          '↩️ Trả ${MoneyUtils.formatCompactCurrency(info.totalReturnedAmount)} (${info.returnCount} lần)',
          Colors.purple.shade100,
        ),
      ),
    ];
  }

  void _openReturn(SaleOrder s) async {
    final info = _returnInfoMap[s.id];
    if (info != null && info.allReturned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đơn này đã trả hết hàng'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateSalesReturnView(sale: s)),
    );
    if (result == true && mounted) {
      _refresh();
    }
  }
}

class _SaleReturnInfo {
  int totalReturnedAmount = 0;
  int returnCount = 0;
  bool allReturned = false;
}
