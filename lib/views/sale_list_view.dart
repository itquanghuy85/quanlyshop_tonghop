import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../services/event_bus.dart';
import 'sale_detail_view.dart';
import 'create_sale_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SaleListView extends StatefulWidget {
  final bool todayOnly;
  const SaleListView({super.key, this.todayOnly = false});

  @override
  State<SaleListView> createState() => _SaleListViewState();
}

class _SaleListViewState extends State<SaleListView> {
  final db = DBHelper();
  List<SaleOrder> _sales = [];
  bool _loading = true;
  String _search = "";

  // Filter states
  String _timeFilter = 'all'; // all, today, week, month, custom
  String _paymentStatusFilter = 'all'; // all, paid, debt
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    if (widget.todayOnly) {
      _timeFilter = 'today';
    }
    _refresh();
    // Listen to sales changes (e.g., when settlement is received)
    EventBus().on('sales_changed', (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    // EventBus auto-manages listeners via weak references
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = await db.getAllSales();
    if (!mounted) return;
    setState(() {
      _sales = data;
      _loading = false;
    });
  }

  List<SaleOrder> _applyFilters() {
    var list = _sales.where((s) {
      // Search filter
      if (_search.isNotEmpty) {
        final searchLower = _search.toUpperCase();
        if (!s.customerName.toUpperCase().contains(searchLower) &&
            !s.productNames.toUpperCase().contains(searchLower) &&
            !s.productImeis.toUpperCase().contains(searchLower)) {
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
          if (_customStartDate != null && saleDate.isBefore(_customStartDate!))
            return false;
          if (_customEndDate != null &&
              saleDate.isAfter(_customEndDate!.add(const Duration(days: 1))))
            return false;
          break;
      }

      // Payment status filter
      final remain = s.totalPrice - s.downPayment;
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
          borderRadius: BorderRadius.circular(20),
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
      (sum, s) =>
          sum +
          (s.totalPrice - s.downPayment > 0 ? s.totalPrice - s.downPayment : 0),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.success, AppColors.success.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Tooltip(
          message: "Xem, tìm kiếm và theo dõi tất cả đơn bán hàng.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.todayOnly ? "DOANH SỐ HÔM NAY" : "QUẢN LÝ ĐƠN BÁN",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                '$totalSales đơn • ${fmt.format(totalRevenue)}đ',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ).then((_) => _refresh()),
            icon: const Icon(
              Icons.add_shopping_cart_rounded,
              color: Colors.white,
            ),
            tooltip: "Tạo đơn bán hàng mới",
          ),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: "Tìm theo tên khách, máy hoặc IMEI...",
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                          padding: const EdgeInsets.all(15),
                          itemCount: list.length,
                          itemBuilder: (ctx, i) {
                            final s = list[i];
                            final date = DateFormat('HH:mm - dd/MM/yy').format(
                              DateTime.fromMillisecondsSinceEpoch(s.soldAt),
                            );
                            final remain = s.finalPrice - s.downPayment;
                            final index = i + 1;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.shadow,
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: ListTile(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SaleDetailView(sale: s),
                                    ),
                                  ).then((_) => _refresh());
                                },
                                contentPadding: const EdgeInsets.all(15),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$index',
                                      style: AppTextStyles.body2.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.customerName.toUpperCase(),
                                        style: AppTextStyles.body2.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      date,
                                      style: AppTextStyles.overline.copyWith(
                                        color: AppColors.onSurface.withOpacity(
                                          0.6,
                                        ),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text(
                                      s.productNames,
                                      style: AppTextStyles.body2.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      "IMEI: ${s.productImeis}",
                                      style: AppTextStyles.caption.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Divider(height: 1),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: _statItem(
                                            "TỔNG TIỀN",
                                            fmt.format(s.finalPrice),
                                            AppColors.onSurface,
                                          ),
                                        ),
                                        Flexible(
                                          child: _statItem(
                                            "ĐÃ THU",
                                            fmt.format(s.downPayment),
                                            AppColors.success,
                                          ),
                                        ),
                                        if (remain > 0)
                                          Flexible(
                                            child: _statItem(
                                              "CÒN NỢ",
                                              fmt.format(remain),
                                              AppColors.error,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getPayColor(
                                              s.paymentMethod,
                                            ).withAlpha(25),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            s.paymentMethod,
                                            style: AppTextStyles.overline
                                                .copyWith(
                                                  color: _getPayColor(
                                                    s.paymentMethod,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          "NV: ${s.sellerName}",
                                          style: AppTextStyles.caption.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: AppColors.onSurface
                                                .withOpacity(0.6),
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
                ),
              ],
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
          style: AppTextStyles.overline.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "$value đ",
          style: AppTextStyles.caption.copyWith(
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
}
