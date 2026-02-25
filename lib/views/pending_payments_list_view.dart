// Pending Payments List View - Central hub for ALL payment operations
//
// PURPOSE:
// - Display ALL pending payment intents in one place
// - Allow users to select and execute payments
// - Filter by payment type (income/expense/debt)
// - Track payment history
//
// RULES:
// - This is the ONLY entry point for viewing pending payments
// - All business modules redirect here instead of handling payments directly
// - Payments are executed through UnifiedPaymentPage
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 7 - Centralized Payment Hub)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import '../theme/app_text_styles.dart';
import '../services/payment_intent_service.dart';
import '../services/first_time_guide_service.dart';
import '../services/event_bus.dart';
import 'unified_payment_page.dart';

/// Central payment hub - displays ALL pending payments
class PendingPaymentsListView extends StatefulWidget {
  /// Optional filter to show only specific payment types
  final PaymentIntentType? filterType;

  const PendingPaymentsListView({super.key, this.filterType});

  @override
  State<PendingPaymentsListView> createState() => _PendingPaymentsListViewState();
}

class _PendingPaymentsListViewState extends State<PendingPaymentsListView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PaymentIntent> _allIntents = [];
  bool _isLoading = true;

  // Filter - reserved for future filtering feature
  // ignore: unused_field
  String? _filterCategory; // 'income', 'expense', 'debt', null = all

  // FIX: EventBus subscription để lắng nghe khi data từ cloud sync thay đổi
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
    
    // FIX: Lắng nghe event khi payment_intents thay đổi từ sync
    _eventSubscription = EventBus().stream.listen((event) {
      if (event == 'payment_intents_changed') {
        debugPrint('📡 PendingPaymentsListView: Received payment_intents_changed event, reloading...');
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  /// Show first time guide
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: 'pending_payments',
      title: 'Quản Lý Thanh Toán',
      icon: Icons.account_balance_wallet,
      color: Colors.green,
      steps: const [
        GuideStep(
          title: '💰 Trung tâm thanh toán',
          description:
              'Đây là nơi tập trung TẤT CẢ các khoản thanh toán của shop. '
              'Mọi giao dịch tiền đều phải qua đây.',
          icon: Icons.hub,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '📊 Ba loại giao dịch',
          description:
              '• CHỜ THU: Tiền khách cần trả\n'
              '• CHỜ CHI: Tiền shop cần trả\n'
              '• LỊCH SỬ: Các giao dịch đã hoàn thành',
          icon: Icons.category,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '✅ Xác nhận thanh toán',
          description:
              'Nhấn vào giao dịch để xem chi tiết và xác nhận thanh toán. '
              'Chọn phương thức: Tiền mặt, Chuyển khoản, hoặc Quẹt thẻ.',
          icon: Icons.check_circle,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '🔒 An toàn tài chính',
          description:
              'Mỗi giao dịch chỉ được thực hiện MỘT LẦN. '
              'Hệ thống tự động ghi sổ và không thể sửa đổi.',
          icon: Icons.security,
          iconColor: Colors.orange,
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Ensure PaymentIntentService is initialized (loads from DB)
      await PaymentIntentService.initialize();
      // Reload from DB to pick up any sync changes
      await PaymentIntentService.reloadFromDb();
      
      // Get ALL intents from service (pending + history)
      final intents = await PaymentIntentService.getAllIntents();
      setState(() {
        _allIntents = intents;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading payment intents: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Get pending income payments (money coming in)
  List<PaymentIntent> get _pendingIncome {
    return _allIntents
        .where((i) => i.status == PaymentIntentStatus.pending && i.isIncome)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get pending expense payments (money going out)
  List<PaymentIntent> get _pendingExpense {
    return _allIntents
        .where((i) => i.status == PaymentIntentStatus.pending && i.isExpense)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get completed/cancelled payments (history)
  List<PaymentIntent> get _history {
    return _allIntents
        .where((i) => i.status != PaymentIntentStatus.pending)
        .toList()
      ..sort((a, b) => (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt));
  }

  /// Execute payment via UnifiedPaymentPage
  Future<void> _executePayment(PaymentIntent intent) async {
    final result = await Navigator.push<PaymentExecutionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => UnifiedPaymentPage(intent: intent),
      ),
    );

    // Luôn reload sau khi thoát trang thanh toán để đồng bộ UI với trạng thái intent
    await _loadData();

    if (!mounted) return;

    if (result != null && result.success) {
      _showSuccessDialog(intent);
    }
  }

  /// Quick execute payment with default/suggested method (TIỀN MẶT)
  Future<void> _quickExecutePayment(PaymentIntent intent) async {
    // Use suggested method from metadata or default to cash
    final suggestedStr = intent.metadata?['suggestedMethod'] as String? ?? 'TIỀN MẶT';
    final method = suggestedStr == 'CHUYỂN KHOẢN' 
        ? PaymentMethod.transfer 
        : PaymentMethod.cash;
    
    final user = FirebaseAuth.instance.currentUser;
    final result = await PaymentIntentService.executePayment(
      intentId: intent.id,
      paymentMethod: method,
      executedBy: user?.displayName ?? user?.email ?? 'unknown',
    );
    
    await _loadData();
    
    if (!mounted) return;
    
    if (result.success) {
      _showSuccessDialog(intent);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Có lỗi xảy ra'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show success dialog after payment
  void _showSuccessDialog(PaymentIntent intent) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Thanh toán thành công!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              intent.description,
              style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                  .format(intent.amount),
              style: TextStyle(
                fontSize: AppTextStyles.headline1.fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// Cancel a payment intent
  /// 
  /// NOTE: Hủy payment intent chỉ xóa khỏi hàng đợi thanh toán.
  /// KHÔNG tự động hoàn trả tiền hay thay đổi trạng thái liên quan (đơn sửa, công nợ, etc.)
  /// Nếu cần hoàn tiền, người dùng phải làm thủ công thông qua các chức năng khác.
  Future<void> _cancelIntent(PaymentIntent intent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hủy thanh toán?', style: TextStyle(fontSize: AppTextStyles.headline3.fontSize)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intent.description, style: TextStyle(fontSize: AppTextStyles.headline4.fontSize)),
            const SizedBox(height: 8),
            Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                  .format(intent.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lưu ý: Hủy chỉ xóa yêu cầu thanh toán này khỏi danh sách. '
                      'Tiền và trạng thái giao dịch liên quan (công nợ, đơn sửa) KHÔNG bị ảnh hưởng.',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy giao dịch', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      PaymentIntentService.cancelIntent(intent.id, reason: 'Người dùng hủy');
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = PaymentIntentService.getStatistics();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'THANH TOÁN',
              style: TextStyle(
                fontSize: AppTextStyles.headline3.fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            if (stats['pending']! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${stats['pending']}',
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
          IconButton(
            onPressed: _showStatistics,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Thống kê',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_downward, size: 16),
                  const SizedBox(width: 4),
                  const Text('THU', style: TextStyle(fontSize: 13)),
                  if (_pendingIncome.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildBadge(_pendingIncome.length, Colors.blue),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_upward, size: 16),
                  const SizedBox(width: 4),
                  const Text('CHI', style: TextStyle(fontSize: 13)),
                  if (_pendingExpense.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildBadge(_pendingExpense.length, Colors.orange),
                  ],
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 16),
                  SizedBox(width: 4),
                  Text('SỬ', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Pending Income
                _buildPaymentList(_pendingIncome, isIncome: true),
                // Tab 2: Pending Expense
                _buildPaymentList(_pendingExpense, isIncome: false),
                // Tab 3: History
                _buildHistoryList(),
              ],
            ),
    );
  }

  Widget _buildBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: AppTextStyles.caption.fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPaymentList(List<PaymentIntent> intents, {required bool isIncome}) {
    if (intents.isEmpty) {
      return _buildEmptyState(isIncome);
    }

    // Group by type
    final grouped = <PaymentIntentType, List<PaymentIntent>>{};
    for (final intent in intents) {
      grouped.putIfAbsent(intent.type, () => []).add(intent);
    }

    // Calculate totals
    final totalAmount = intents.fold<int>(0, (sum, i) => sum + i.amount);

    return Column(
      children: [
        // Summary header
        _buildSummaryHeader(
          count: intents.length,
          total: totalAmount,
          isIncome: isIncome,
        ),
        const Divider(height: 1),
        // List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: intents.length,
              itemBuilder: (ctx, index) {
                return _buildPaymentCard(intents[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Chưa có lịch sử thanh toán',
              style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _history.length,
        itemBuilder: (ctx, index) {
          return _buildHistoryCard(_history[index]);
        },
      ),
    );
  }

  Widget _buildSummaryHeader({
    required int count,
    required int total,
    required bool isIncome,
  }) {
    final color = isIncome ? Colors.blue : Colors.orange;
    final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
    final label = isIncome ? 'Cần thu' : 'Cần chi';

    return Container(
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.1),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                      .format(total),
                  style: TextStyle(
                    fontSize: AppTextStyles.headline1.fontSize,
                    fontWeight: FontWeight.bold,
                    color: isIncome ? Colors.blue.shade700 : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count giao dịch',
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                fontWeight: FontWeight.bold,
                color: isIncome ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isIncome) {
    final color = isIncome ? Colors.blue : Colors.orange;
    final icon = isIncome ? Icons.payments_outlined : Icons.money_off_outlined;
    final text = isIncome
        ? 'Không có khoản thu nào chờ xử lý'
        : 'Không có khoản chi nào chờ xử lý';
    final subtext = isIncome
        ? 'Các khoản thu từ bán hàng, sửa chữa sẽ hiển thị ở đây'
        : 'Các khoản chi cho NCC, chi phí sẽ hiển thị ở đây';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: color.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            subtext,
            style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(PaymentIntent intent) {
    final dateStr = DateFormat('dd/MM HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(intent.createdAt));

    // Determine card styling based on type
    final isIncome = intent.isIncome;
    final bgColor = isIncome ? Colors.blue.shade50 : Colors.orange.shade50;
    final borderColor = isIncome ? Colors.blue.shade200 : Colors.orange.shade200;
    final accentColor = isIncome ? Colors.blue : Colors.orange;

    // Type icon
    final typeIcon = _getTypeIcon(intent.type);

    // Age warning
    final age = DateTime.now().millisecondsSinceEpoch - intent.createdAt;
    final daysSinceCreated = age ~/ (1000 * 60 * 60 * 24);
    final hasWarning = daysSinceCreated > 3;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _executePayment(intent),
        borderRadius: BorderRadius.circular(12),
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
                      color: accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(typeIcon, style: TextStyle(fontSize: AppTextStyles.headline1.fontSize)),
                  ),
                  const SizedBox(width: 12),
                  // Description and person
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          intent.description,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline4.fontSize,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (intent.personName != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 12,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  intent.personName!,
                                  style: TextStyle(
                                    fontSize: AppTextStyles.subtitle1.fontSize,
                                    color: Colors.grey.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (intent.personPhone != null) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.phone_outlined,
                                  size: 12,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  intent.personPhone!,
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                            .format(intent.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline3.fontSize,
                          color: isIncome ? Colors.blue.shade700 : Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
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

              // Info chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _infoChip(
                    intent.type.displayName,
                    accentColor.withOpacity(0.2),
                  ),
                  if (intent.referenceId != null)
                    _infoChip(
                      '🔗 ${intent.referenceType ?? "ref"}',
                      Colors.grey.shade200,
                    ),
                  if (hasWarning)
                    _infoChip(
                      '⚠️ $daysSinceCreated ngày',
                      daysSinceCreated > 7
                          ? Colors.red.shade100
                          : Colors.yellow.shade100,
                    ),
                ],
              ),

              const Divider(height: 12),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel button
                  TextButton(
                    onPressed: () => _cancelIntent(intent),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close, size: 14),
                        const SizedBox(width: 4),
                        Text('Hủy', style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quick pay button (tiền mặt by default)
                  OutlinedButton(
                    onPressed: () => _quickExecutePayment(intent),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on, size: 14),
                        const SizedBox(width: 4),
                        Text('Nhanh', style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Pay button (with options)
                  ElevatedButton(
                    onPressed: () => _executePayment(intent),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isIncome ? Icons.download : Icons.upload,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isIncome ? 'Thu tiền' : 'Thanh toán',
                          style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                        ),
                      ],
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

  Widget _buildHistoryCard(PaymentIntent intent) {
    final isCompleted = intent.isCompleted;
    final dateStr = intent.paidAt != null
        ? DateFormat('dd/MM/yyyy HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(intent.paidAt!))
        : DateFormat('dd/MM/yyyy HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(intent.createdAt));

    final bgColor = isCompleted ? Colors.green.shade50 : Colors.grey.shade100;
    final borderColor =
        isCompleted ? Colors.green.shade200 : Colors.grey.shade300;
    final statusColor = isCompleted ? Colors.green : Colors.grey;
    final statusIcon = isCompleted ? Icons.check_circle : Icons.cancel;
    final statusText = intent.status.displayName;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Status icon
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    intent.description,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.headline5.fontSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          intent.type.displayName,
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (intent.paymentMethod != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${intent.paymentMethod!.displayName}',
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // Amount and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                      .format(intent.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline4.fontSize,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: AppTextStyles.body1.fontSize)),
    );
  }

  String _getTypeIcon(PaymentIntentType type) {
    switch (type) {
      case PaymentIntentType.supplierDebt:
      case PaymentIntentType.supplierPurchase:
        return '🏭';
      case PaymentIntentType.customerDebtCollection:
        return '👤';
      case PaymentIntentType.customerRefund:
        return '↩️';
      case PaymentIntentType.repairService:
        return '🔧';
      case PaymentIntentType.repairPartnerDebt:
        return '🤝';
      case PaymentIntentType.salePayment:
      case PaymentIntentType.saleInstallment:
        return '🛒';
      case PaymentIntentType.inventoryPurchase:
      case PaymentIntentType.partsStockIn:
        return '📦';
      case PaymentIntentType.operatingExpense:
      case PaymentIntentType.utilityExpense:
        return '💡';
      case PaymentIntentType.salaryPayment:
      case PaymentIntentType.bonusPayment:
        return '💰';
      case PaymentIntentType.otherDebt:
        return '📝';
      case PaymentIntentType.otherExpense:
        return '💸';
      case PaymentIntentType.otherIncome:
        return '💵';
    }
  }

  void _showStatistics() {
    final stats = PaymentIntentService.getStatistics();
    final totalPendingIncome =
        _pendingIncome.fold<int>(0, (sum, i) => sum + i.amount);
    final totalPendingExpense =
        _pendingExpense.fold<int>(0, (sum, i) => sum + i.amount);
    final netPending = totalPendingIncome - totalPendingExpense;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Thống kê thanh toán',
              style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // Stats grid
            Row(
              children: [
                _buildStatCard(
                  'Chờ thu',
                  stats['pending']! > 0
                      ? _pendingIncome.length.toString()
                      : '0',
                  NumberFormat.compact(locale: 'vi').format(totalPendingIncome),
                  Colors.blue,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Chờ chi',
                  stats['pending']! > 0
                      ? _pendingExpense.length.toString()
                      : '0',
                  NumberFormat.compact(locale: 'vi').format(totalPendingExpense),
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard(
                  'Hoàn thành',
                  '${stats['completed']}',
                  null,
                  Colors.green,
                ),
                const SizedBox(width: 12),
                _buildStatCard(
                  'Đã hủy',
                  '${stats['cancelled']}',
                  null,
                  Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Net pending
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: netPending >= 0
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: netPending >= 0
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    netPending >= 0 ? 'Sẽ thu thêm:' : 'Sẽ chi thêm:',
                    style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                  ),
                  Text(
                    NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                        .format(netPending.abs()),
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                      color: netPending >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String count,
    String? amount,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              count,
              style: TextStyle(
                fontSize: AppTextStyles.headline1.fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (amount != null) ...[
              const SizedBox(height: 2),
              Text(
                '$amountđ',
                style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
