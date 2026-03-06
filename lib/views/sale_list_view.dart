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
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';
import '../widgets/responsive_wrapper.dart';

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
  String _timeFilter = 'all'; // all, today, week, month, custom
  String _paymentStatusFilter = 'all'; // all, paid, debt
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  
  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);
  
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
    
    // Setup scroll listener for lazy loading
    _scrollController.addListener(_onScroll);
    
    // Listen to sales changes (e.g., when settlement is received)
    EventBus().on('sales_changed', (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // EventBus auto-manages listeners via weak references
    super.dispose();
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
    
    if (_needsFullData || widget.todayOnly) {
      // Load all data for filtering
      final data = await db.getAllSales();
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
          if (_customStartDate != null && saleDate.isBefore(_customStartDate!)) {
            return false;
          }
          if (_customEndDate != null &&
              saleDate.isAfter(_customEndDate!.add(const Duration(days: 1)))) {
            return false;
          }
          break;
      }

      // Payment status filter - dùng remainingDebt tính đúng nợ thực tế
      final remain = s.remainingDebt;
      switch (_paymentStatusFilter) {
        case 'paid':
          if (remain > 0) return false;
          break;
        case 'debt':
          if (remain <= 0) return false;
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
                ],
              ),
              const SizedBox(height: 24),

              // Apply button
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
    final fmt = NumberFormat('#,###');
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
        subtitle: '$totalSales đơn • ${fmt.format(totalRevenue)}đ',
        accentColor: AppBarAccents.sales,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ).then((_) => _refresh()),
            icon: const Icon(
              Icons.add_shopping_cart_rounded,
              color: AppBarAccents.sales,
            ),
            tooltip: "Tạo đơn bán hàng mới",
          ),
          Stack(
            children: [
              IconButton(
                onPressed: _showFilterSheet,
                icon: const Icon(
                  Icons.filter_list_rounded,
                  color: AppBarAccents.sales,
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
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: AppBarAccents.sales),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: AppBarAccents.sales),
            tooltip: 'Xuất Excel đơn bán',
            onPressed: () async {
              final result = await ExportDateFilterDialog.show(context, title: 'Xuất đơn bán');
              if (result == null) return;
              if (!mounted) return;
              await ExcelExportHelper.exportSales(
                context,
                startMs: result['startMs'],
                endMs: result['endMs'],
              );
            },
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
                hintText: "Tìm theo tên khách, ${_terms.productLabel.toLowerCase()} hoặc ${_terms.specialField1Label}...",
                hintStyle: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey.shade500),
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
                // Summary stats bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [
                      BoxShadow(color: AppColors.shadow, blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _summaryItem(
                        'Đơn hàng',
                        '$totalSales',
                        AppColors.primary,
                      ),
                      _summaryItem(
                        'Doanh thu',
                        '${fmt.format(totalRevenue)}đ',
                        AppColors.success,
                      ),
                      _summaryItem(
                        'Còn nợ',
                        '${fmt.format(totalDebt)}đ',
                        totalDebt > 0 ? AppColors.error : AppColors.success,
                      ),
                    ],
                  ),
                ),

                // Active filters chips
                if (_activeFilterCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_timeFilter != 'all' && !widget.todayOnly)
                            _activeFilterChip(
                              _getTimeFilterLabel(),
                              () => setState(() => _timeFilter = 'all'),
                            ),
                          if (_paymentStatusFilter != 'all')
                            _activeFilterChip(
                              _getPaymentStatusLabel(),
                              () =>
                                  setState(() => _paymentStatusFilter = 'all'),
                            ),
                        ],
                      ),
                    ),
                  ),

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
                                  onPressed: () => setState(() {
                                    _timeFilter = widget.todayOnly
                                        ? 'today'
                                        : 'all';
                                    _paymentStatusFilter = 'all';
                                  }),
                                  child: const Text('Xóa bộ lọc'),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: list.length + (_isLoadingMore ? 1 : 0) + (!_hasMore && list.isNotEmpty ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i >= list.length) {
                              if (_isLoadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              // End of list indicator
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    'Đã hiển thị ${list.length} đơn bán',
                                    style: TextStyle(color: Colors.grey[600], fontSize: AppTextStyles.subtitle1.fontSize),
                                  ),
                                ),
                              );
                            }
                            
                            final s = list[i];
                            final date = DateFormat('dd/MM HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(s.soldAt),
                            );
                            final remain = s.remainingDebt; // Dùng getter mới
                            final index = i + 1;
                            
                            // Determine card color based on payment status
                            final isPaid = s.isPaid; // Dùng getter mới
                            final bgColor = isPaid 
                                ? Colors.green.shade50 
                                : Colors.orange.shade50;
                            final borderColor = isPaid 
                                ? Colors.green.shade300 
                                : Colors.orange.shade300;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: bgColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: borderColor),
                              ),
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
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header row
                                      Row(
                                        children: [
                                          // STT
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: borderColor.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$index',
                                                style: TextStyle(
                                                  fontSize: AppTextStyles.body1.fontSize,
                                                  fontWeight: FontWeight.bold,
                                                  color: borderColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // Thông tin chính
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s.productNames,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: AppTextStyles.headline5.fontSize,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${s.customerName} • ${s.phone}',
                                                  style: TextStyle(
                                                    fontSize: AppTextStyles.body1.fontSize,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Status + Date
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isPaid ? Colors.green : Colors.orange,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  isPaid ? 'ĐÃ THU' : 'CÒN NỢ',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: AppTextStyles.overlineSize,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                date,
                                                style: TextStyle(
                                                  fontSize: AppTextStyles.caption.fontSize,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 8),
                                      
                                      // Info chips row
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          // Tổng tiền
                                          _saleInfoChip(
                                            '💰 ${fmt.format(s.finalPrice)}đ',
                                            Colors.blue.shade100,
                                          ),
                                          // Đã thu
                                          if (s.downPayment > 0)
                                            _saleInfoChip(
                                              '✅ ${fmt.format(s.downPayment)}đ',
                                              Colors.green.shade100,
                                            ),
                                          // Còn nợ
                                          if (remain > 0)
                                            _saleInfoChip(
                                              '⚠️ Nợ ${fmt.format(remain)}đ',
                                              Colors.red.shade100,
                                            ),
                                          // Phương thức
                                          _saleInfoChip(
                                            '💳 ${s.paymentMethod}',
                                            _getPayColor(s.paymentMethod).withAlpha(40),
                                          ),
                                          // NV
                                          _saleInfoChip(
                                            '👤 ${s.sellerName}',
                                            Colors.blue.shade100,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
}
