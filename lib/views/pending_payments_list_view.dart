// Pending Payments List View - Compact & Professional Design
//
// PURPOSE:
// - Display all pending payment intents (THU / CHI / LỊCH SỬ)
// - Inline payment execution via bottom sheet (no separate page)
// - Swipe to cancel, tap to pay
//
// Created: 2026-01-22 | Redesigned: 2026-02-25

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payment_intent_model.dart';
import '../services/payment_intent_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../constants/financial_constants.dart';
import '../services/event_bus.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/responsive_wrapper.dart';

class PendingPaymentsListView extends StatefulWidget {
  const PendingPaymentsListView({super.key});

  @override
  State<PendingPaymentsListView> createState() =>
      _PendingPaymentsListViewState();
}

class _PendingPaymentsListViewState extends State<PendingPaymentsListView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PaymentIntent> _incomeIntents = [];
  List<PaymentIntent> _expenseIntents = [];
  List<PaymentIntent> _historyIntents = [];
  bool _isLoading = true;
  StreamSubscription<String>? _eventSub;

  final _currencyFmt = NumberFormat('#,###', 'vi');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _eventSub = EventBus().on('payment_intents_changed', (_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        PaymentIntentService.getPendingIncomeIntents(),
        PaymentIntentService.getPendingExpenseIntents(),
        PaymentIntentService.getHistoryIntents(),
      ]);
      if (!mounted) return;
      setState(() {
        _incomeIntents = results[0]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _expenseIntents = results[1]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _historyIntents = results[2];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Load payment intents error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ──────────────────────────────────────────────────
  // PAYMENT EXECUTION - Inline bottom sheet
  // ──────────────────────────────────────────────────

  Future<void> _executePayment(PaymentIntent intent) async {
    // If method is preset, execute directly
    if (intent.paymentMethod != null) {
      await _doExecute(intent, intent.paymentMethod!);
      return;
    }
    // Show method selection bottom sheet
    if (!mounted) return;
    final method = await showAppBottomSheet<PaymentMethod>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentMethodSheet(intent: intent),
    );
    if (method != null) {
      await _doExecute(intent, method);
    }
  }

  Future<void> _doExecute(PaymentIntent intent, PaymentMethod method) async {
    // Show loading overlay
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final userName = await UserService.getCurrentUserName();
      final result = await PaymentIntentService.executePayment(
        intentId: intent.id,
        paymentMethod: method,
        executedBy: userName ?? 'Unknown',
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      if (result.success) {
        NotificationService.showSnackBar(
          intent.isIncome ? '✅ Thu tiền thành công!' : '✅ Thanh toán thành công!',
          color: Colors.green,
        );
        _loadData();
      } else {
        NotificationService.showSnackBar(
          '❌ ${result.errorMessage ?? "Có lỗi xảy ra"}',
          color: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
    }
  }

  /// Quick pay with cash - one tap
  Future<void> _quickPay(PaymentIntent intent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(intent.isIncome ? 'Thu tiền mặt?' : 'Chi tiền mặt?'),
        content: Text(
          '${intent.description}\n${_currencyFmt.format(intent.amount)}đ',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _doExecute(intent, PaymentMethod.cash);
    }
  }

  Future<void> _cancelPayment(PaymentIntent intent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy thanh toán?'),
        content: Text(intent.description),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Không')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hủy thanh toán'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final ok = await PaymentIntentService.cancelIntent(intent.id, reason: 'Hủy thủ công');
      if (ok) {
        NotificationService.showSnackBar('Đã hủy thanh toán', color: Colors.orange);
        _loadData();
      }
    }
  }

  // ──────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: ResponsiveCenter(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_incomeIntents, isIncome: true),
                _buildList(_expenseIntents, isIncome: false),
                _buildHistoryList(),
              ],
            ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [CustomAppBar.kGradientStart, CustomAppBar.kGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        'Thanh Toán',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded, size: 22),
          tooltip: 'Thống kê',
          onPressed: _showStats,
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 22),
          tooltip: 'Tải lại',
          onPressed: _loadData,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(36),
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 2.5,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: [
              Tab(text: 'THU (${_incomeIntents.length})'),
              Tab(text: 'CHI (${_expenseIntents.length})'),
              Tab(text: 'LỊCH SỬ (${_historyIntents.length})'),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // PENDING LIST (THU / CHI)
  // ──────────────────────────────────────────────────

  Widget _buildList(List<PaymentIntent> items, {required bool isIncome}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              isIncome ? 'Không có khoản thu chờ xử lý' : 'Không có khoản chi chờ xử lý',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final totalAmount = items.fold<int>(0, (sum, i) => sum + i.amount);

    return Column(
      children: [
        // ── Compact summary bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isIncome ? Colors.green.shade50 : Colors.red.shade50,
          child: Row(
            children: [
              Icon(
                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16,
                color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '${items.length} khoản',
                style: TextStyle(
                  fontSize: 12,
                  color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              const Spacer(),
              Text(
                '${_currencyFmt.format(totalAmount)}đ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
        // ── Items ──
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
              itemBuilder: (ctx, i) => _buildCompactCard(items[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(PaymentIntent intent) {
    final isIncome = intent.isIncome;
    final color = isIncome ? Colors.green : Colors.red;
    final date = DateTime.fromMillisecondsSinceEpoch(intent.createdAt);
    final dateStr = DateFormat('dd/MM HH:mm').format(date);

    return Dismissible(
      key: Key(intent.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.cancel, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _cancelPayment(intent);
        return false; // We handle removal ourselves via _loadData
      },
      child: InkWell(
        onTap: () => _executePayment(intent),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // ── Icon ──
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _typeIcon(intent.type),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              // ── Info ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intent.description,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (intent.personName != null) ...[
                          Icon(Icons.person_outline, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              intent.personName!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ── Amount + Quick pay ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? "+" : "-"}${_currencyFmt.format(intent.amount)}đ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => _quickPay(intent),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Tiền mặt',
                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // HISTORY LIST
  // ──────────────────────────────────────────────────

  Widget _buildHistoryList() {
    if (_historyIntents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              'Chưa có lịch sử thanh toán',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _historyIntents.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
        itemBuilder: (ctx, i) => _buildHistoryTile(_historyIntents[i]),
      ),
    );
  }

  Widget _buildHistoryTile(PaymentIntent intent) {
    final isCompleted = intent.status == PaymentIntentStatus.completed;
    final isIncome = intent.isIncome;
    final color = isCompleted
        ? (isIncome ? Colors.green : Colors.blue)
        : Colors.grey;
    final statusIcon = isCompleted ? Icons.check_circle : Icons.cancel;
    final paidAt = intent.paidAt != null
        ? DateFormat('dd/MM HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(intent.paidAt!))
        : DateFormat('dd/MM HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(intent.createdAt));
    final methodText = intent.paymentMethod?.displayName ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // ── Status icon ──
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          // ── Info ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  intent.description,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: isCompleted ? null : TextDecoration.lineThrough,
                    color: isCompleted ? null : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    intent.type.displayName,
                    if (methodText.isNotEmpty) methodText,
                    paidAt,
                  ].join(' · '),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Amount ──
          Flexible(
            flex: 0,
            child: Text(
              '${isIncome ? "+" : "-"}${_currencyFmt.format(intent.amount)}đ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isCompleted ? color : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // STATS
  // ──────────────────────────────────────────────────

  void _showStats() {
    final totalIncome = _incomeIntents.fold<int>(0, (s, i) => s + i.amount);
    final totalExpense = _expenseIntents.fold<int>(0, (s, i) => s + i.amount);
    final net = totalIncome - totalExpense;
    final completedCount = _historyIntents
        .where((i) => i.status == PaymentIntentStatus.completed)
        .length;

    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Thống Kê Thanh Toán',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Stats grid
            Row(
              children: [
                _statChip('Chờ thu', _incomeIntents.length, Colors.green),
                const SizedBox(width: 8),
                _statChip('Chờ chi', _expenseIntents.length, Colors.red),
                const SizedBox(width: 8),
                _statChip('Đã xử lý', completedCount, Colors.blue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _amountChip('Tổng thu', totalIncome, Colors.green),
                const SizedBox(width: 8),
                _amountChip('Tổng chi', totalExpense, Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: net >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    'Chênh lệch chờ',
                    style: TextStyle(
                      fontSize: 11,
                      color: net >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  Text(
                    '${net >= 0 ? "+" : ""}${_currencyFmt.format(net)}đ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: net >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _amountChip(String label, int amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '${_currencyFmt.format(amount)}đ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────

  IconData _typeIcon(PaymentIntentType type) {
    switch (type) {
      case PaymentIntentType.supplierDebt:
      case PaymentIntentType.supplierPurchase:
        return Icons.local_shipping_outlined;
      case PaymentIntentType.customerDebtCollection:
        return Icons.person_outline;
      case PaymentIntentType.customerRefund:
        return Icons.replay;
      case PaymentIntentType.repairService:
        return Icons.build_outlined;
      case PaymentIntentType.repairPartnerDebt:
        return Icons.handyman_outlined;
      case PaymentIntentType.salePayment:
      case PaymentIntentType.saleInstallment:
        return Icons.shopping_bag_outlined;
      case PaymentIntentType.inventoryPurchase:
      case PaymentIntentType.partsStockIn:
        return Icons.inventory_2_outlined;
      case PaymentIntentType.operatingExpense:
      case PaymentIntentType.utilityExpense:
        return Icons.receipt_long_outlined;
      case PaymentIntentType.salaryPayment:
      case PaymentIntentType.bonusPayment:
        return Icons.payments_outlined;
      default:
        return Icons.payment;
    }
  }
}

// ════════════════════════════════════════════════════
// PAYMENT METHOD BOTTOM SHEET
// ════════════════════════════════════════════════════

class _PaymentMethodSheet extends StatefulWidget {
  final PaymentIntent intent;
  const _PaymentMethodSheet({required this.intent});

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  PaymentMethod _selected = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    if (widget.intent.paymentMethod != null) {
      _selected = widget.intent.paymentMethod!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final isIncome = intent.isIncome;
    final color = isIncome ? Colors.green : const Color(0xFF0068FF);
    final fmt = NumberFormat('#,###', 'vi');

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // ── Amount ──
          Text(
            '${fmt.format(intent.amount)}đ',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            intent.description,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          // ── Method buttons ──
          Row(
            children: [
              _methodBtn(PaymentMethod.cash, Icons.money, 'Tiền mặt', color),
              const SizedBox(width: 8),
              _methodBtn(PaymentMethod.transfer, Icons.account_balance, 'Chuyển khoản', color),
              const SizedBox(width: 8),
              _methodBtn(PaymentMethod.debt, Icons.receipt_long, 'Công nợ', color),
            ],
          ),
          const SizedBox(height: 16),
          // ── Confirm ──
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                isIncome ? 'XÁC NHẬN THU' : 'XÁC NHẬN CHI',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodBtn(PaymentMethod method, IconData icon, String label, Color activeColor) {
    final isActive = _selected == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selected = method),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? activeColor : Colors.grey.shade200,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? activeColor : Colors.grey, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? activeColor : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


