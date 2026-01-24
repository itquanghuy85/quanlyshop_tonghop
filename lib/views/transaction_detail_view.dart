import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../models/repair_model.dart';
import '../services/sync_service.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/money_utils.dart';
import 'sale_detail_view.dart';
import 'repair_detail_view.dart';

/// Trang chi tiết giao dịch - gộp Bán hàng, Sửa chữa, Chi tiêu
class TransactionDetailView extends StatefulWidget {
  final int initialTab;
  const TransactionDetailView({super.key, this.initialTab = 0});

  @override
  State<TransactionDetailView> createState() => _TransactionDetailViewState();
}

class _TransactionDetailViewState extends State<TransactionDetailView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;
  bool _isLoading = true;

  // Filter
  String _filterPeriod = 'today'; // today, week, month, all
  DateTime? _customStart;
  DateTime? _customEnd;

  // Data
  List<SaleOrder> _sales = [];
  List<Repair> _repairs = [];
  List<Map<String, dynamic>> _expenses = [];
  bool _dataLoaded = false; // Prevent unnecessary reloads
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadAllData();
    // Only init real-time sync once
    if (!_dataLoaded) {
      SyncService.initRealTimeSync(() {
        if (mounted && !_isLoading) _loadAllData();
      });
    }
    
    // Listen to global events for data changes
    _eventSub = EventBus().stream.where((e) => 
      e == 'repairs_changed' || e == 'sales_changed' || e == 'expenses_changed'
    ).listen((_) {
      if (mounted && !_isLoading) _loadAllData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (_isLoading && _dataLoaded) return; // Prevent duplicate loads
    setState(() => _isLoading = true);
    final sales = await db.getAllSales();
    final repairs = await db.getAllRepairs();
    final expenses = await db.getAllExpenses();

    if (mounted) {
      setState(() {
        _sales = sales;
        _repairs = repairs;
        _expenses = expenses;
        _isLoading = false;
        _dataLoaded = true;
      });
    }
  }

  bool _isInFilterPeriod(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_filterPeriod) {
      case 'today':
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      case 'week':
        final weekAgo = today.subtract(const Duration(days: 7));
        return date.isAfter(weekAgo);
      case 'month':
        final monthStart = DateTime(now.year, now.month, 1);
        return date.isAfter(monthStart.subtract(const Duration(days: 1)));
      case 'custom':
        if (_customStart != null && date.isBefore(_customStart!)) return false;
        if (_customEnd != null &&
            date.isAfter(_customEnd!.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text("CHI TIẾT GIAO DỊCH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Lọc theo thời gian',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_cart, size: 18), text: "BÁN HÀNG"),
            Tab(icon: Icon(Icons.build, size: 18), text: "SỬA CHỮA"),
            Tab(icon: Icon(Icons.money_off, size: 18), text: "CHI TIÊU"),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Icon(Icons.date_range, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  _getFilterLabel(),
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_filterPeriod != 'all')
                  TextButton(
                    onPressed: () => setState(() => _filterPeriod = 'all'),
                    child: Text("Xem tất cả", style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSalesTab(),
                      _buildRepairsTab(),
                      _buildExpensesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _getFilterLabel() {
    switch (_filterPeriod) {
      case 'today':
        return 'Hôm nay - ${DateFormat('dd/MM/yyyy').format(DateTime.now())}';
      case 'week':
        return '7 ngày qua';
      case 'month':
        return 'Tháng ${DateTime.now().month}/${DateTime.now().year}';
      case 'custom':
        if (_customStart != null && _customEnd != null) {
          return '${DateFormat('dd/MM').format(_customStart!)} - ${DateFormat('dd/MM').format(_customEnd!)}';
        }
        return 'Tùy chọn';
      default:
        return 'Tất cả thời gian';
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "LỌC THEO THỜI GIAN",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('Hôm nay', 'today'),
                _filterChip('7 ngày', 'week'),
                _filterChip('Tháng này', 'month'),
                _filterChip('Tất cả', 'all'),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 16),
                  label: const Text('Tùy chọn'),
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      locale: const Locale('vi', 'VN'),
                    );
                    if (range != null) {
                      setState(() {
                        _filterPeriod = 'custom';
                        _customStart = range.start;
                        _customEnd = range.end;
                      });
                      if (mounted) Navigator.pop(ctx);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterPeriod == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterPeriod = value);
        Navigator.pop(context);
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
    );
  }

  Widget _buildSalesTab() {
    final filtered = _sales.where((s) => _isInFilterPeriod(s.soldAt)).toList();
    filtered.sort((a, b) => b.soldAt.compareTo(a.soldAt));

    if (filtered.isEmpty) {
      return _emptyState("Không có đơn bán hàng", Icons.shopping_cart_outlined);
    }

    final totalRevenue = filtered.fold<int>(0, (sum, s) => sum + s.totalPrice);
    final totalProfit = filtered.fold<int>(
        0, (sum, s) => sum + (s.totalPrice - s.totalCost));

    return Column(
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: Row(
            children: [
              Expanded(
                child: _summaryItem(
                  "${filtered.length}",
                  "Đơn hàng",
                  Icons.receipt,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  MoneyUtils.formatVND(totalRevenue),
                  "Doanh thu",
                  Icons.attach_money,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  MoneyUtils.formatVND(totalProfit),
                  "Lợi nhuận",
                  Icons.trending_up,
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final s = filtered[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.shopping_cart, color: Colors.green),
                ),
                title: Text(
                  s.productNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${s.customerName} • ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(s.soldAt))}",
                ),
                trailing: Text(
                  "+${MoneyUtils.formatVND(s.totalPrice)}",
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SaleDetailView(sale: s)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRepairsTab() {
    // Filter: Hiển thị đơn sửa chữa đã giao (status == 4)
    // Ưu tiên dùng deliveredAt, nếu không có thì dùng finishedAt hoặc createdAt
    final filtered = _repairs.where((r) {
      if (r.status != 4) return false;
      
      // Lấy timestamp để filter
      final timestamp = r.deliveredAt ?? r.finishedAt ?? r.createdAt;
      return _isInFilterPeriod(timestamp);
    }).toList();
    
    // Sort theo thời gian giao (ưu tiên deliveredAt)
    filtered.sort((a, b) {
      final timeA = a.deliveredAt ?? a.finishedAt ?? a.createdAt;
      final timeB = b.deliveredAt ?? b.finishedAt ?? b.createdAt;
      return timeB.compareTo(timeA);
    });

    if (filtered.isEmpty) {
      return _emptyState("Không có đơn sửa chữa đã giao", Icons.build_outlined);
    }

    final totalRevenue = filtered.fold<int>(0, (sum, r) => sum + r.price);
    final totalProfit =
        filtered.fold<int>(0, (sum, r) => sum + (r.price - r.totalCost));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Expanded(
                child: _summaryItem(
                  "${filtered.length}",
                  "Đơn giao",
                  Icons.check_circle,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  MoneyUtils.formatVND(totalRevenue),
                  "Doanh thu",
                  Icons.attach_money,
                ),
              ),
              Expanded(
                child: _summaryItem(
                  MoneyUtils.formatVND(totalProfit),
                  "Lợi nhuận",
                  Icons.trending_up,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final r = filtered[i];
              // Lấy timestamp hiển thị (ưu tiên deliveredAt)
              final displayTime = r.deliveredAt ?? r.finishedAt ?? r.createdAt;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.build, color: Colors.blue),
                ),
                title: Text(
                  r.model,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${r.customerName} • ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(displayTime))}",
                ),
                trailing: Text(
                  "+${MoneyUtils.formatVND(r.price)}",
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesTab() {
    final filtered = _expenses
        .where((e) => _isInFilterPeriod((e['date'] ?? e['createdAt']) as int))
        .toList();
    filtered.sort((a, b) =>
        ((b['date'] ?? b['createdAt']) as int)
            .compareTo((a['date'] ?? a['createdAt']) as int));

    if (filtered.isEmpty) {
      return _emptyState("Không có chi tiêu", Icons.money_off_outlined);
    }

    final totalExpense =
        filtered.fold<int>(0, (sum, e) => sum + (e['amount'] as int? ?? 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.red.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _summaryItem(
                "${filtered.length}",
                "Khoản chi",
                Icons.receipt_long,
              ),
              const SizedBox(width: 40),
              _summaryItem(
                "-${MoneyUtils.formatVND(totalExpense)}",
                "Tổng chi",
                Icons.money_off,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final e = filtered[i];
              final date = DateTime.fromMillisecondsSinceEpoch(
                  (e['date'] ?? e['createdAt']) as int);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  child: const Icon(Icons.money_off, color: Colors.red),
                ),
                title: Text(
                  e['title'] ?? e['description'] ?? 'Chi phí',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${e['category'] ?? 'Khác'} • ${DateFormat('dd/MM HH:mm').format(date)}",
                ),
                trailing: Text(
                  "-${MoneyUtils.formatVND(e['amount'] as int? ?? 0)}",
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline4.fontSize),
        ),
        Text(
          label,
          style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
