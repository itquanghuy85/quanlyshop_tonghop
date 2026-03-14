import 'dart:async';
import 'package:flutter/material.dart';
import '../core/utils/money_utils.dart';
import '../services/reminder_service.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import 'order_list_view.dart';
import 'debt_view.dart';
import 'sales_return_list_view.dart';
import 'pending_stock_list_view.dart';
import 'purchase_order_list_view.dart';
import 'payment_request_chat_view.dart';
import '../widgets/permission_gate.dart';

/// Trang Nhắc nhở — hiển thị tất cả task cần xử lý theo role & quyền
class RemindersView extends StatefulWidget {
  final String role;
  final Map<String, bool> permissions;

  const RemindersView({
    super.key,
    required this.role,
    required this.permissions,
  });

  @override
  State<RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<RemindersView> {
  List<TaskReminder> _reminders = [];
  bool _isLoading = true;
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadReminders();
    // Listen for data changes
    _eventSub = EventBus().stream.listen((event) {
      if (event.contains('changed') ||
          event.contains('REFRESH') ||
          event.contains('SYNC')) {
        _loadReminders();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    try {
      final reminders = await ReminderService.loadReminders(
        role: widget.role,
        permissions: widget.permissions,
      );
      if (mounted) {
        setState(() {
          _reminders = reminders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('RemindersView._loadReminders error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar.build(
        title: 'Nhắc nhở',
        accentColor: AppBarAccents.repairs,
      ),
      body: RefreshIndicator(
        onRefresh: _loadReminders,
        child: _isLoading ? _buildLoading() : _buildBody(),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildBody() {
    if (_reminders.isEmpty) {
      return _buildEmpty();
    }

    // Group by priority
    final urgent = _reminders.where((r) => r.priority == ReminderPriority.urgent).toList();
    final high = _reminders.where((r) => r.priority == ReminderPriority.high).toList();
    final normal = _reminders.where((r) => r.priority == ReminderPriority.normal).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Summary header
        _buildSummaryHeader(),
        const SizedBox(height: 16),

        // Urgent section
        if (urgent.isNotEmpty) ...[
          _buildSectionHeader(
            'Cần xử lý ngay',
            Icons.priority_high_rounded,
            const Color(0xFFD32F2F),
          ),
          const SizedBox(height: 8),
          ...urgent.map(_buildReminderCard),
          const SizedBox(height: 16),
        ],

        // High priority section
        if (high.isNotEmpty) ...[
          _buildSectionHeader(
            'Quan trọng',
            Icons.flag_rounded,
            const Color(0xFFF57C00),
          ),
          const SizedBox(height: 8),
          ...high.map(_buildReminderCard),
          const SizedBox(height: 16),
        ],

        // Normal section
        if (normal.isNotEmpty) ...[
          _buildSectionHeader(
            'Công việc chờ',
            Icons.check_circle_outline_rounded,
            const Color(0xFF1976D2),
          ),
          const SizedBox(height: 8),
          ...normal.map(_buildReminderCard),
        ],
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 56,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Không có việc cần xử lý',
                style: AppTextStyles.headline4.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tất cả đã được xử lý xong!',
                style: AppTextStyles.body2.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Summary card ở đầu trang
  Widget _buildSummaryHeader() {
    final totalCount = _reminders.fold<int>(0, (s, r) => s + r.count);
    final urgentCount = _reminders
        .where((r) => r.priority == ReminderPriority.urgent)
        .fold<int>(0, (s, r) => s + r.count);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: urgentCount > 0
              ? [const Color(0xFFFF6F00), const Color(0xFFE65100)]
              : [const Color(0xFF1565C0), const Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (urgentCount > 0 ? const Color(0xFFE65100) : const Color(0xFF0D47A1))
                .withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalCount việc cần xử lý',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  urgentCount > 0
                      ? '$urgentCount việc cần xử lý ngay'
                      : 'Không có việc khẩn cấp',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _reminders.length.toString(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  /// Section header
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(color: color.withOpacity(0.2), thickness: 1),
        ),
      ],
    );
  }

  /// Card cho mỗi TaskReminder
  Widget _buildReminderCard(TaskReminder reminder) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTapReminder(reminder),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: reminder.color.withOpacity(0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon circle with badge
                _buildIconWithBadge(reminder),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reminder.subtitle,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onSurface.withOpacity(0.55),
                        ),
                      ),
                      // Money amount if available
                      if (reminder.totalAmount != null && reminder.totalAmount! > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          MoneyUtils.formatVND(reminder.totalAmount!),
                          style: AppTextStyles.body2.copyWith(
                            fontWeight: FontWeight.w700,
                            color: reminder.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Arrow + count
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: reminder.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${reminder.count}',
                        style: TextStyle(
                          color: reminder.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: AppColors.onSurface.withOpacity(0.3),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconWithBadge(TaskReminder reminder) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: reminder.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            reminder.icon,
            color: reminder.color,
            size: 22,
          ),
        ),
        // Priority indicator
        if (reminder.priority == ReminderPriority.urgent)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// Navigate to relevant view based on reminder category
  void _onTapReminder(TaskReminder reminder) {
    Widget? targetView;
    String? requiredPermission;

    switch (reminder.category) {
      case ReminderCategory.repairApproval:
        requiredPermission = 'allowViewRepairs';
        targetView = OrderListView(
          role: widget.role,
          statusFilter: const [3],
        );
        break;
      case ReminderCategory.repairAssignment:
        requiredPermission = 'allowViewRepairs';
        targetView = OrderListView(
          role: widget.role,
          statusFilter: const [1, 2],
        );
        break;
      case ReminderCategory.deliveryTask:
        requiredPermission = 'allowViewRepairs';
        targetView = OrderListView(
          role: widget.role,
          statusFilter: const [3],
        );
        break;
      case ReminderCategory.activeDebt:
        requiredPermission = 'allowViewDebts';
        targetView = const DebtView();
        break;
      case ReminderCategory.pendingStock:
        requiredPermission = 'allowViewInventory';
        targetView = const PendingStockListView();
        break;
      case ReminderCategory.pendingPurchase:
        requiredPermission = 'allowViewInventory';
        targetView = const PurchaseOrderListView();
        break;
      case ReminderCategory.salesReturn:
        requiredPermission = 'allowViewSales';
        targetView = const SalesReturnListView();
        break;
      case ReminderCategory.paymentRequest:
        requiredPermission = 'allowViewDebts';
        targetView = const PaymentRequestChatView();
        break;
      case ReminderCategory.paymentIntent:
        requiredPermission = 'allowViewDebts';
        // No dedicated view — navigate to debt view which shows payment intents
        targetView = const DebtView();
        break;
    }

    if (!PermissionGateCheck.check(context, requiredPermission)) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => targetView!),
    ).then((_) => _loadReminders());
  }
}
