import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../core/utils/money_utils.dart' as core_money;
import '../utils/money_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../services/event_bus.dart';
import '../l10n/app_localizations.dart';

/// Trang báo cáo tài chính tổng hợp
/// Hiển thị TẤT CẢ giao dịch liên quan đến tiền:
/// - Bán hàng, Sửa chữa
/// - Chi phí, Nhập hàng
/// - Công nợ (thu/chi)
/// - Thanh toán nợ
class FinancialReportView extends StatefulWidget {
  final bool embedded;
  const FinancialReportView({super.key, this.embedded = false});

  @override
  State<FinancialReportView> createState() => _FinancialReportViewState();
}

/// Model giao dịch tổng hợp
class TransactionItem {
  final String id;
  final int timestamp;
  final String
  type; // SALE, REPAIR, EXPENSE, DEBT_IN, DEBT_OUT, PAYMENT_IN, PAYMENT_OUT
  final String category; // Chi tiết loại
  final String description;
  final int amount;
  final bool isIncome; // true = thu vào, false = chi ra
  final String? personName; // Khách hàng/NCC/Đối tác
  final String? note;

  TransactionItem({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    required this.isIncome,
    this.personName,
    this.note,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}

class _FinancialReportViewState extends State<FinancialReportView>
    with SingleTickerProviderStateMixin {
  final _db = DBHelper();
  late TabController _tabController;

  List<TransactionItem> _transactions = [];
  bool _loading = true;

  // Filters
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final Set<String> _selectedTypes = {};
  bool _showIncomeOnly = false;
  bool _showExpenseOnly = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Summary
  int _totalIncome = 0;
  int _totalExpense = 0;

  // Filter types
  static const _typeFilters = [
    {
      'key': 'SALE',
      'label': 'Bán hàng',
      'icon': Icons.shopping_cart,
      'color': Colors.green,
    },
    {
      'key': 'REPAIR',
      'label': 'Sửa chữa',
      'icon': Icons.build,
      'color': Colors.blue,
    },
    {
      'key': 'EXPENSE',
      'label': 'Chi phí',
      'icon': Icons.money_off,
      'color': Colors.red,
    },
    {
      'key': 'PURCHASE',
      'label': 'Nhập hàng',
      'icon': Icons.inventory,
      'color': Colors.orange,
    },
    {
      'key': 'DEBT_COLLECT',
      'label': 'Thu nợ',
      'icon': Icons.call_received,
      'color': Colors.teal,
    },
    {
      'key': 'DEBT_PAY',
      'label': 'Trả nợ',
      'icon': Icons.call_made,
      'color': Colors.blue,
    },
  ];

  // EventBus subscriptions for real-time sync
  StreamSubscription<String>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    // Subscribe to data change events for real-time sync
    _eventSubscription = EventBus().stream.listen((event) {
      if (event == 'sales_changed' ||
          event == 'repairs_changed' ||
          event == 'expenses_changed' ||
          event == 'debts_changed' ||
          event == 'debt_payments_changed') {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final startMs = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      ).millisecondsSinceEpoch;
      final endMs = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;

      final List<TransactionItem> allTransactions = [];

      // 1. Bán hàng — chỉ lấy trong khoảng thời gian (thay vì getAllSales)
      final sales = await _db.getSalesByDateRange(startMs, endMs);
      for (final sale in sales) {
        final soldAt = sale.soldAt;
        final isCongNo = sale.paymentMethod.toUpperCase() == 'CÔNG NỢ';

        // Tính số tiền THỰC NHẬN (không tính công nợ)
        // - Nếu trả góp: downPayment + settlementAmount (tiền từ NH)
        // - Nếu CÔNG NỢ: 0đ (chưa nhận tiền)
        // - Nếu tiền mặt/CK: toàn bộ finalPrice (sau giảm giá)
        final int actualPaid;
        if (sale.isInstallment) {
          actualPaid = sale.downPayment + sale.settlementAmount;
        } else if (isCongNo) {
          actualPaid = 0; // Công nợ - chưa nhận tiền
        } else {
          actualPaid = sale.finalPrice;
        }

        // Chỉ ghi nhận THU khi thực sự nhận được tiền
        if (actualPaid > 0) {
          allTransactions.add(
            TransactionItem(
              id: 'sale_${sale.id}',
              timestamp: soldAt,
              type: 'SALE',
              category: sale.isInstallment ? 'Bán trả góp' : 'Bán hàng',
              description: sale.customerName.isNotEmpty
                  ? sale.customerName
                  : 'Khách lẻ',
              amount: actualPaid,
              isIncome: true,
              personName: sale.customerName,
              note: sale.notes,
            ),
          );
        }

        // NOTE: Không tính "giá vốn" ở đây để tránh double-counting với:
        // - Chi phí nhập hàng (nếu trả tiền mặt)
        // - Trả nợ NCC (nếu nhập công nợ)
        // Lợi nhuận thực = Doanh thu bán hàng - Chi phí nhập hàng/Trả nợ NCC
      }

      // 2. Sửa chữa — chỉ lấy đơn đã giao trong khoảng (thay vì getAllRepairs)
      final repairs = await _db.getDeliveredRepairsByDateRange(startMs, endMs);
      for (final repair in repairs) {
        final deliveredAt = repair.deliveredAt ?? repair.createdAt;
        allTransactions.add(
          TransactionItem(
            id: 'repair_${repair.id}',
            timestamp: deliveredAt,
            type: 'REPAIR',
            category: 'Sửa chữa',
            description: '${repair.model} - ${repair.customerName}',
            amount: repair.price,
            isIncome: true,
            personName: repair.customerName,
            note: repair.issue,
          ),
        );

        // NOTE: Không tính "chi phí linh kiện" ở đây để tránh double-counting
        // Chi phí linh kiện đã được ghi nhận khi:
        // - Nhập linh kiện với tiền mặt (tạo expense)
        // - Nhập linh kiện với công nợ rồi trả nợ (tạo debt_payment)
        // Lợi nhuận sửa chữa = Phí sửa - Chi phí nhập linh kiện/Trả nợ NCC
      }

      // 3. Chi phí & Thu phát sinh — chỉ lấy trong khoảng (thay vì getAllExpenses)
      final expenses = await _db.getExpensesByDateRange(startMs, endMs);
      for (final e in expenses) {
        if ((e['deleted'] ?? 0) != 1) {
          final expenseDate = (e['date'] as int?) ?? (e['createdAt'] as int?) ?? 0;
          final eType = (e['type'] ?? 'CHI').toString().toUpperCase();
          final isThu = eType == 'THU';
          allTransactions.add(
            TransactionItem(
              id: 'expense_${e['id']}',
              timestamp: expenseDate,
              type: isThu ? 'INCOME' : 'EXPENSE',
              category: isThu
                  ? 'Thu phát sinh'
                  : (e['category'] as String?) ?? 'Chi phí khác',
              description:
                  (e['description'] as String?) ??
                  (e['category'] as String?) ??
                  (isThu ? 'Thu phát sinh' : 'Chi phí'),
              amount: (e['amount'] as int?) ?? 0,
              isIncome: isThu,
              note: e['note'] as String?,
            ),
          );
        }
      }

      // 4. Thanh toán nợ — JOIN trực tiếp trong SQL (thay vì N+1: getAllDebts → getDebtPayments)
      // NOTE: Chỉ lấy các lần THANH TOÁN NỢ thực tế, không lấy debt records
      // DEBT_OUT/CUSTOMER_OWES bản thân không là giao dịch tiền thực
      final debtPayments = await _db.getDebtPaymentsWithDebtInfoByDateRange(startMs, endMs);
      for (final p in debtPayments) {
        final debtType = p['debtType'] as String? ?? '';
        final personName = p['debtPersonName'] as String?;
        final paidAt = (p['paidAt'] as int?) ?? 0;

        if (debtType == 'CUSTOMER_OWES' || debtType == 'OTHER_CUSTOMER_OWES') {
          // Thu nợ từ khách - ĐÂY LÀ THU TIỀN THỰC
          allTransactions.add(
            TransactionItem(
              id: 'payment_in_${p['id']}',
              timestamp: paidAt,
              type: 'DEBT_COLLECT',
              category: 'Thu nợ khách',
              description: 'Thu nợ: ${personName ?? "Khách"}',
              amount: (p['amount'] as int?) ?? 0,
              isIncome: true,
              personName: personName,
              note: p['note'] as String?,
            ),
          );
        } else if (debtType == 'SHOP_OWES' || debtType == 'OTHER_SHOP_OWES' || debtType == 'OWED') {
          // Trả nợ NCC/Đối tác - ĐÂY LÀ CHI TIỀN THỰC
          allTransactions.add(
            TransactionItem(
              id: 'payment_out_${p['id']}',
              timestamp: paidAt,
              type: 'DEBT_PAY',
              category: 'Trả nợ NCC',
              description: 'Trả nợ: ${personName ?? "NCC"}',
              amount: (p['amount'] as int?) ?? 0,
              isIncome: false,
              personName: personName,
              note: p['note'] as String?,
            ),
          );
        }
      }

      // Sắp xếp theo thời gian mới nhất
      allTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Tính summary từ TẤT CẢ giao dịch (không bị ảnh hưởng bởi filter)
      // để lợi nhuận luôn chính xác bất kể đang xem tab nào
      int totalIncome = 0, totalExpense = 0;
      for (final t in allTransactions) {
        if (t.isIncome) {
          totalIncome += t.amount;
        } else {
          totalExpense += t.amount;
        }
      }

      // Filter chỉ để hiển thị trong list, không ảnh hưởng summary
      final filtered = _filterTransactions(allTransactions);

      setState(() {
        _transactions = filtered;
        _totalIncome = totalIncome;
        _totalExpense = totalExpense;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading financial report: $e');
      setState(() => _loading = false);
    }
  }

  List<TransactionItem> _filterTransactions(List<TransactionItem> items) {
    return items.where((t) {
      // Filter by type
      if (_selectedTypes.isNotEmpty && !_selectedTypes.contains(t.type)) {
        return false;
      }
      // Filter income/expense
      if (_showIncomeOnly && !t.isIncome) return false;
      if (_showExpenseOnly && t.isIncome) return false;
      // Search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final match =
            t.description.toLowerCase().contains(q) ||
            t.category.toLowerCase().contains(q) ||
            (t.personName?.toLowerCase().contains(q) ?? false) ||
            (t.note?.toLowerCase().contains(q) ?? false);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  /// Compact filter chip for embedded mode
  Widget _directionChip(String label, int index) {
    final isSelected = (index == 0 && !_showIncomeOnly && !_showExpenseOnly) ||
        (index == 1 && _showIncomeOnly) ||
        (index == 2 && _showExpenseOnly);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: AppTextStyles.caption.fontSize)),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _showIncomeOnly = index == 1;
          _showExpenseOnly = index == 2;
        });
        _loadData();
      },
      selectedColor: const Color(0xFF0068FF),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = _loading
        ? const Expanded(child: Center(child: CircularProgressIndicator()))
        : Expanded(
            child: Column(
              children: [
                _buildSummaryCard(),
                _buildDateRangeBar(),
                _buildQuickFilters(),
                Expanded(child: _buildTransactionList()),
              ],
            ),
          );

    if (widget.embedded) {
      return Column(
        children: [
          // Compact filter row: chips + action buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.white,
            child: Row(
              children: [
                _directionChip(AppLocalizations.of(context)?.all ?? 'Tất cả', 0),
                const SizedBox(width: 4),
                _directionChip(AppLocalizations.of(context)?.income ?? 'Thu', 1),
                const SizedBox(width: 4),
                _directionChip(AppLocalizations.of(context)?.expense ?? 'Chi', 2),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _showFilterDialog,
                  tooltip: 'Bộ lọc',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadData,
                  tooltip: 'Làm mới',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          bodyContent,
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          AppLocalizations.of(context)?.financialReportLabel ?? 'Financial Report',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Bộ lọc',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Làm mới',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: AppLocalizations.of(context)?.all ?? 'ALL'),
            Tab(text: AppLocalizations.of(context)?.income ?? 'INCOME'),
            Tab(text: AppLocalizations.of(context)?.expense ?? 'EXPENSE'),
          ],
          onTap: (index) {
            setState(() {
              _showIncomeOnly = index == 1;
              _showExpenseOnly = index == 2;
            });
            _loadData();
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(),
                _buildDateRangeBar(),
                _buildQuickFilters(),
                Expanded(child: _buildTransactionList()),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    final net = _totalIncome - _totalExpense;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: net >= 0
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.red.shade400, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (net >= 0 ? Colors.green : Colors.red).withValues(
              alpha: 0.3,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _summaryItem('Thu', _totalIncome, Icons.arrow_downward)),
          Container(width: 1, height: 36, color: Colors.white30),
          Expanded(child: _summaryItem('Chi', _totalExpense, Icons.arrow_upward)),
          Container(width: 1, height: 36, color: Colors.white30),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      net >= 0 ? Icons.trending_up : Icons.trending_down,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Lãi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: AppTextStyles.subtitle1.fontSize,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  MoneyUtils.formatCurrency(net),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.body1.fontSize,
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

  Widget _summaryItem(String label, int amount, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white70,
                fontSize: AppTextStyles.subtitle1.fontSize,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          MoneyUtils.formatCurrency(amount),
          style: TextStyle(
            color: Colors.white,
            fontSize: AppTextStyles.body1.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangeBar() {
    final df = DateFormat('dd/MM/yyyy');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: _selectDateRange,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.date_range, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${df.format(_startDate)} - ${df.format(_endDate)}',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilters() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _filterChip('Tất cả', null, _selectedTypes.isEmpty),
          ..._typeFilters.map(
            (f) => _filterChip(
              f['label'] as String,
              f['key'] as String,
              _selectedTypes.contains(f['key']),
              icon: f['icon'] as IconData,
              color: f['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String? key,
    bool selected, {
    IconData? icon,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : (color ?? AppColors.onSurface),
              ),
              const SizedBox(width: 4),
            ],
            Text(label),
          ],
        ),
        selected: selected,
        onSelected: (v) {
          setState(() {
            if (key == null) {
              _selectedTypes.clear();
            } else {
              if (v) {
                _selectedTypes.add(key);
              } else {
                _selectedTypes.remove(key);
              }
            }
          });
          _loadData();
        },
        selectedColor: color ?? AppColors.primary,
        backgroundColor: AppColors.surface,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.onSurface,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: AppColors.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Không có giao dịch nào',
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped = <String, List<TransactionItem>>{};
    final df = DateFormat('dd/MM/yyyy');
    for (final t in _transactions) {
      final key = df.format(t.dateTime);
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: grouped.length,
      itemBuilder: (ctx, index) {
        final date = grouped.keys.elementAt(index);
        final items = grouped[date]!;

        // Tính tổng trong ngày
        int dayIncome = 0, dayExpense = 0;
        for (final t in items) {
          if (t.isIncome) {
            dayIncome += t.amount;
          } else {
            dayExpense += t.amount;
          }
        }
        final dayNet = dayIncome - dayExpense;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header with summary
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: dayNet >= 0
                      ? [Colors.green.shade50, Colors.green.shade100]
                      : [Colors.red.shade50, Colors.red.shade100],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: dayNet >= 0
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: dayNet >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline4.fontSize,
                          ),
                        ),
                        Text(
                          '${items.length} giao dịch',
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (dayIncome > 0) ...[
                            Icon(
                              Icons.arrow_downward,
                              size: 12,
                              color: Colors.green.shade700,
                            ),
                            Text(
                              '+${core_money.MoneyUtils.formatCompact(dayIncome)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.body1.fontSize,
                              ),
                            ),
                          ],
                          if (dayIncome > 0 && dayExpense > 0)
                            Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: AppTextStyles.caption.fontSize,
                              ),
                            ),
                          if (dayExpense > 0) ...[
                            Icon(
                              Icons.arrow_upward,
                              size: 12,
                              color: Colors.red.shade700,
                            ),
                            Text(
                              '-${core_money.MoneyUtils.formatCompact(dayExpense)}',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.body1.fontSize,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: dayNet >= 0 ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${dayNet >= 0 ? "+" : ""}${core_money.MoneyUtils.formatCompact(dayNet)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.caption.fontSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Transaction cards
            ...items.map((t) => _buildTransactionCard(t)),
          ],
        );
      },
    );
  }

  Widget _buildTransactionCard(TransactionItem t) {
    final time = DateFormat('HH:mm').format(t.dateTime);
    final icon = _getTypeIcon(t.type);
    final typeColor = _getTypeColor(t.type);
    final amountColor = t.isIncome ? Colors.green : Colors.red;

    // Background color based on type
    final bgColor = t.isIncome ? Colors.green.shade50 : Colors.red.shade50;
    final borderColor = t.isIncome
        ? Colors.green.shade200
        : Colors.red.shade200;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _showTransactionDetail(t),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: typeColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  // Description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.description,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline5.fontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (t.personName != null && t.personName!.isNotEmpty)
                          Text(
                            t.personName!,
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
                  // Amount and time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: amountColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${t.isIncome ? "+" : "-"}${MoneyUtils.formatCurrency(t.amount)}đ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.subtitle1.fontSize,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        time,
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
                  _infoChip(
                    t.category,
                    typeColor.withValues(alpha: 0.2),
                    typeColor,
                  ),
                  if (t.note != null && t.note!.isNotEmpty)
                    _infoChip(
                      '📝 ${t.note!.length > 20 ? "${t.note!.substring(0, 20)}..." : t.note}',
                      Colors.grey.shade200,
                      Colors.grey.shade700,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextStyles.caption.fontSize,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'SALE':
        return Icons.shopping_cart;
      case 'REPAIR':
        return Icons.build;
      case 'EXPENSE':
        return Icons.money_off;
      case 'PURCHASE':
        return Icons.inventory;
      case 'DEBT_IN':
      case 'DEBT_OUT':
        return Icons.account_balance_wallet;
      case 'DEBT_COLLECT':
        return Icons.call_received;
      case 'DEBT_PAY':
        return Icons.call_made;
      default:
        return Icons.receipt;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'SALE':
        return Colors.green;
      case 'REPAIR':
        return Colors.blue;
      case 'EXPENSE':
        return Colors.red;
      case 'PURCHASE':
        return Colors.orange;
      case 'DEBT_IN':
      case 'DEBT_OUT':
        return Colors.blue;
      case 'DEBT_COLLECT':
        return Colors.teal;
      case 'DEBT_PAY':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  void _showTransactionDetail(TransactionItem t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (t.isIncome ? Colors.green : Colors.red).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getTypeIcon(t.type),
                    color: t.isIncome ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.category, style: AppTextStyles.headline6),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(t.dateTime),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow('Mô tả', t.description),
            _detailRow(
              'Số tiền',
              '${t.isIncome ? "+" : "-"}${MoneyUtils.formatCurrency(t.amount)}',
              valueColor: t.isIncome ? Colors.green : Colors.red,
            ),
            if (t.personName != null && t.personName!.isNotEmpty)
              _detailRow('Đối tượng', t.personName!),
            if (t.note != null && t.note!.isNotEmpty)
              _detailRow('Ghi chú', t.note!),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.body2.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _showFilterDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bộ lọc nâng cao', style: AppTextStyles.headline6),
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        _selectedTypes.clear();
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    child: const Text('Xóa bộ lọc'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Tìm kiếm',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => setModalState(() => _searchQuery = v),
              ),
              const SizedBox(height: 16),
              Text(
                'Loại giao dịch',
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _typeFilters
                    .map(
                      (f) => FilterChip(
                        label: Text(f['label'] as String),
                        selected: _selectedTypes.contains(f['key']),
                        onSelected: (v) {
                          setModalState(() {
                            if (v) {
                              _selectedTypes.add(f['key'] as String);
                            } else {
                              _selectedTypes.remove(f['key']);
                            }
                          });
                        },
                        selectedColor: (f['color'] as Color).withValues(
                          alpha: 0.3,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  child: const Text('Áp dụng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
