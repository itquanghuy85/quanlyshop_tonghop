// ignore_for_file: unused_element
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/sale_model.dart';
import '../models/repair_model.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/responsive_wrapper.dart';
import 'sale_detail_view.dart';
import 'repair_detail_view.dart';

const _kPageSize = 30;

/// Màn hình xem toàn bộ hoạt động gần đây
/// Lọc theo ngày, phân trang, phân quyền chính xác
class RecentActivityView extends StatefulWidget {
  final Map<String, dynamic> permissions;
  final bool hasFullAccess;
  final bool enableRepair;

  const RecentActivityView({
    super.key,
    required this.permissions,
    this.hasFullAccess = false,
    this.enableRepair = true,
  });

  @override
  State<RecentActivityView> createState() => _RecentActivityViewState();
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE RANGE ENUM
// ─────────────────────────────────────────────────────────────────────────────
enum _DateRange { today, week, month, custom }

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────
class _RecentActivityViewState extends State<RecentActivityView> {
  final _db = DBHelper();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;

  _DateRange _range = _DateRange.week;
  DateTime? _customStart;
  DateTime? _customEnd;
  String _searchQuery = '';
  String? _activityTypeFilter; // null = tất cả

  Timer? _searchDebounce;

  // Summary aggregates for header
  int _totalIn = 0;
  int _totalOut = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Date helpers ─────────────────────────────────────────────────────────

  (int, int) get _dateWindow {
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_range) {
      case _DateRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch);
      case _DateRange.week:
        final start = now.subtract(const Duration(days: 6));
        final startOfDay = DateTime(start.year, start.month, start.day);
        return (startOfDay.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch);
      case _DateRange.month:
        final start = now.subtract(const Duration(days: 29));
        final startOfDay = DateTime(start.year, start.month, start.day);
        return (startOfDay.millisecondsSinceEpoch, endOfDay.millisecondsSinceEpoch);
      case _DateRange.custom:
        final s = _customStart ?? now.subtract(const Duration(days: 6));
        final e = _customEnd ?? now;
        final startMs = DateTime(s.year, s.month, s.day).millisecondsSinceEpoch;
        final endMs = DateTime(e.year, e.month, e.day, 23, 59, 59).millisecondsSinceEpoch;
        return (startMs, endMs);
    }
  }

  // ─── Permission filter ────────────────────────────────────────────────────

  bool _canView(Map<String, dynamic> log) {
    if (widget.hasFullAccess) return true;
    final perms = widget.permissions;
    bool has(String key) => perms[key] == true;
    final type = (log['activityType'] as String? ?? '').toUpperCase();
    switch (type) {
      case 'SALE':
      case 'REFUND':
        return has('allowViewSales') || has('allowViewRevenue');
      case 'REPAIR':
        return widget.enableRepair && has('allowViewRepairs');
      case 'PURCHASE':
        return has('allowViewPurchaseOrders') ||
            has('allowCreatePurchaseOrders') ||
            has('allowViewExpenses');
      case 'EXPENSE':
        return has('allowViewExpenses');
      case 'DEBT_COLLECT':
      case 'DEBT_PAY':
        return has('allowViewDebts');
      case 'SETTLEMENT':
        return has('allowViewRevenue');
      default:
        return false;
    }
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _reload() async {
    setState(() {
      _items = [];
      _offset = 0;
      _hasMore = true;
      _totalIn = 0;
      _totalOut = 0;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final shopId = UserService.getShopIdSync() ?? await UserService.getCurrentShopId();
      final (startMs, endMs) = _dateWindow;

      final batch = await _db.getFinancialActivities(
        startDate: startMs,
        endDate: endMs,
        activityType: _activityTypeFilter,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        limit: _kPageSize + 50, // fetch extra for permission filtering
        offset: _offset,
        shopId: shopId,
      );

      // apply permission filter
      final allowed = batch.where(_canView).toList();

      // Update running totals only on first page (for header summary)
      if (_offset == 0) {
        // Fetch all for summary (lightweight: only amount + direction)
        final allForSummary = await _db.getFinancialActivities(
          startDate: startMs,
          endDate: endMs,
          activityType: _activityTypeFilter,
          searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
          limit: 10000,
          offset: 0,
          shopId: shopId,
        );
        int tin = 0, tout = 0;
        for (final r in allForSummary.where(_canView)) {
          final dir = (r['direction'] as String? ?? '').toUpperCase();
          final amt = (r['amount'] as num?)?.toInt() ?? 0;
          if (dir == 'IN') tin += amt; else tout += amt;
        }
        if (mounted) setState(() { _totalIn = tin; _totalOut = tout; });
      }

      if (mounted) {
        setState(() {
          _items.addAll(allowed);
          _offset += batch.length; // advance by raw batch size (next page)
          _hasMore = batch.length == _kPageSize + 50;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('RecentActivityView: load error $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = q.trim());
      _reload();
    });
  }

  // ─── Custom date picker ───────────────────────────────────────────────────

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customStart ?? now.subtract(const Duration(days: 6)),
        end: _customEnd ?? now,
      ),
      locale: const Locale('vi'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppBarAccents.finance,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _range = _DateRange.custom;
      });
      _reload();
    }
  }

  // ─── Navigation to detail ─────────────────────────────────────────────────

  Future<void> _openDetail(Map<String, dynamic> log) async {
    final refType = (log['referenceType'] as String? ?? '').toLowerCase();
    final refId = log['referenceId'] as String?;
    if (refId == null || refId.isEmpty) return;

    try {
      if (refType == 'sale') {
        final SaleOrder? sale = await _db.getSaleByFirestoreId(refId);
        if (sale != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
          );
        }
      } else if (refType == 'repair' && widget.enableRepair) {
        final Repair? repair = await _db.getRepairByFirestoreId(refId);
        if (repair != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RepairDetailView(repair: repair),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('RecentActivityView: navigation error $e');
    }
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────

  static IconData _iconFor(String type) {
    switch (type.toUpperCase()) {
      case 'SALE': return Icons.shopping_cart;
      case 'REPAIR': return Icons.build_circle;
      case 'EXPENSE': return Icons.remove_circle;
      case 'PURCHASE': return Icons.inventory_2;
      case 'DEBT_COLLECT': return Icons.account_balance_wallet;
      case 'DEBT_PAY': return Icons.payment;
      case 'SETTLEMENT': return Icons.account_balance;
      case 'REFUND': return Icons.assignment_return;
      default: return Icons.history;
    }
  }

  static Color _colorFor(String type, String direction) {
    switch (type.toUpperCase()) {
      case 'SALE': return Colors.green;
      case 'REPAIR': return Colors.blue;
      case 'EXPENSE': return Colors.red;
      case 'PURCHASE': return Colors.orange;
      case 'DEBT_COLLECT': return Colors.cyan.shade700;
      case 'DEBT_PAY': return Colors.deepOrange;
      case 'SETTLEMENT': return Colors.indigo;
      case 'REFUND': return Colors.redAccent;
      default: return direction.toUpperCase() == 'OUT' ? Colors.red : Colors.grey;
    }
  }

  static String _labelFor(String type) {
    switch (type.toUpperCase()) {
      case 'SALE': return 'Bán hàng';
      case 'REPAIR': return 'Sửa chữa';
      case 'EXPENSE': return 'Chi phí';
      case 'PURCHASE': return 'Nhập hàng';
      case 'DEBT_COLLECT': return 'Thu nợ';
      case 'DEBT_PAY': return 'Trả nợ';
      case 'SETTLEMENT': return 'Tất toán';
      case 'REFUND': return 'Hoàn hàng';
      default: return type;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.build(
        title: 'HOẠT ĐỘNG GẦN ĐÂY',
        subtitle: '${_items.length} mục${_hasMore ? '+' : ''}',
        accentColor: AppBarAccents.finance,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
            tooltip: 'Làm mới',
            splashRadius: 18,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            height: 44,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _buildSearchField(),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            _buildDateRangeBar(),
            _buildTypeFilterBar(),
            _buildSummaryBar(),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(17),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(
          color: AppColors.onSurface,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        cursorColor: AppBarAccents.finance,
        decoration: InputDecoration(
          hintText: 'Tìm theo tiêu đề, khách hàng...',
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: AppTextStyles.subtitle1.fontSize,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppBarAccents.finance,
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _reload();
                  },
                  splashRadius: 14,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildDateRangeBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _dateChip('Hôm nay', _DateRange.today),
            const SizedBox(width: 8),
            _dateChip('7 ngày', _DateRange.week),
            const SizedBox(width: 8),
            _dateChip('30 ngày', _DateRange.month),
            const SizedBox(width: 8),
            _customDateChip(),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, _DateRange value) {
    final selected = _range == value;
    return GestureDetector(
      onTap: () {
        if (_range != value) {
          setState(() => _range = value);
          _reload();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppBarAccents.finance : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppBarAccents.finance : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _customDateChip() {
    final selected = _range == _DateRange.custom;
    String label = 'Tùy chọn';
    if (selected && _customStart != null && _customEnd != null) {
      final fmt = DateFormat('dd/MM');
      label = '${fmt.format(_customStart!)} – ${fmt.format(_customEnd!)}';
    }
    return GestureDetector(
      onTap: _pickCustomRange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppBarAccents.finance : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppBarAccents.finance : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range,
              size: 14,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilterBar() {
    const types = [
      (null, 'Tất cả', Icons.all_inclusive),
      ('SALE', 'Bán hàng', Icons.shopping_cart),
      ('REPAIR', 'Sửa chữa', Icons.build_circle),
      ('EXPENSE', 'Chi phí', Icons.remove_circle),
      ('PURCHASE', 'Nhập hàng', Icons.inventory_2),
      ('DEBT_COLLECT', 'Thu nợ', Icons.account_balance_wallet),
      ('DEBT_PAY', 'Trả nợ', Icons.payment),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types
              .where((e) => e.$1 != 'REPAIR' || widget.enableRepair)
              .map((e) {
            final isSelected = _activityTypeFilter == e.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  if (_activityTypeFilter != e.$1) {
                    setState(() => _activityTypeFilter = e.$1);
                    _reload();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppBarAccents.finance.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppBarAccents.finance
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        e.$3,
                        size: 12,
                        color: isSelected
                            ? AppBarAccents.finance
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        e.$2,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppBarAccents.finance
                              : Colors.grey.shade700,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    if (_items.isEmpty && !_loading) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryItem('THU', _totalIn, Colors.green),
          const SizedBox(
            width: 1,
            height: 30,
            child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE0E0E0))),
          ),
          _summaryItem('CHI', _totalOut, Colors.red),
          const SizedBox(
            width: 1,
            height: 30,
            child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE0E0E0))),
          ),
          _summaryItem(
            'CHÊNH LỆCH',
            _totalIn - _totalOut,
            _totalIn >= _totalOut ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int amount, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            MoneyUtils.formatVND(amount.abs()),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Không có hoạt động nào',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Thử đổi khoảng thời gian hoặc bộ lọc',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _items.length + (_loading ? 1 : (_hasMore ? 1 : 0)),
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          return _loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: TextButton(
                      onPressed: _loadMore,
                      child: const Text('Tải thêm'),
                    ),
                  ),
                );
        }
        return _buildItemCard(_items[i], i);
      },
    );
  }

  Widget _buildItemCard(Map<String, dynamic> log, int index) {
    final type = (log['activityType'] as String? ?? '').toUpperCase();
    final direction = (log['direction'] as String? ?? '').toUpperCase();
    final title = (log['title'] as String?)?.trim() ?? 'Hoạt động';
    final description = (log['description'] as String?)?.trim() ?? '';
    final customerName = (log['customerName'] as String?)?.trim() ?? '';
    final amount = (log['amount'] as num?)?.toInt() ?? 0;
    final createdAt = (log['createdAt'] as num?)?.toInt() ?? 0;
    final createdBy = (log['createdBy'] as String?)?.trim() ?? '';
    final referenceType = (log['referenceType'] as String? ?? '').toLowerCase();
    final referenceId = log['referenceId'] as String?;

    final color = _colorFor(type, direction);
    final icon = _iconFor(type);
    final label = _labelFor(type);

    final date = createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(createdAt)
        : null;
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final dateStr = date != null ? DateFormat('dd/MM').format(date) : '';

    final amountStr = amount > 0
        ? '${direction == 'OUT' ? '-' : '+'}${MoneyUtils.formatVND(amount)}'
        : '';
    final amountColor = direction == 'OUT' ? Colors.red : Colors.green;

    final canNavigate = referenceId != null &&
        referenceId.isNotEmpty &&
        (referenceType == 'sale' ||
            (referenceType == 'repair' && widget.enableRepair));

    return GestureDetector(
      onTap: canNavigate ? () => _openDetail(log) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date/time column
            SizedBox(
              width: 38,
              child: Column(
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty || customerName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [if (customerName.isNotEmpty) customerName,
                       if (description.isNotEmpty) description]
                          .join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (createdBy.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 11, color: Colors.blue.shade400),
                        const SizedBox(width: 3),
                        Text(
                          createdBy,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amountStr.isNotEmpty)
                  Text(
                    amountStr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                if (canNavigate)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
