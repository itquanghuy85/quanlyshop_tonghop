import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/db_helper.dart';
import '../../core/utils/money_utils.dart';
import '../../services/user_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// "Cần xử lý" card - shows actionable items with counts
class ActionRequiredCard extends StatefulWidget {
  final bool enableRepair;
  final bool enableWarranty;
  final bool enableExpiry;
  final VoidCallback? onPendingRepairsTap;
  final VoidCallback? onPendingStockTap;
  final VoidCallback? onWarrantyTap;
  final VoidCallback? onExpiryTap;

  const ActionRequiredCard({
    super.key,
    this.enableRepair = true,
    this.enableWarranty = true,
    this.enableExpiry = false,
    this.onPendingRepairsTap,
    this.onPendingStockTap,
    this.onWarrantyTap,
    this.onExpiryTap,
  });

  @override
  State<ActionRequiredCard> createState() => _ActionRequiredCardState();
}

class _ActionRequiredCardState extends State<ActionRequiredCard> {
  int _pendingRepairs = 0;
  int _pendingStock = 0;
  int _expiringWarranty = 0;
  int _expiringProducts = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final db = await DBHelper().database;
      final results = await Future.wait([
        db.rawQuery('SELECT COUNT(*) FROM repairs WHERE status IN (1, 2)'),
        db.rawQuery("SELECT COUNT(*) FROM products WHERE pendingConfirm = 1"),
        // Warranty expiring within 7 days
        db.query('repairs',
          columns: ['deliveredAt', 'warranty'],
          where: "deliveredAt IS NOT NULL AND warranty IS NOT NULL AND warranty != '' AND UPPER(warranty) != 'KO BH' AND status = 4"),
      ]);

      final pendingR = (results[0].first.values.first as num?)?.toInt() ?? 0;
      final pendingS = (results[1].first.values.first as num?)?.toInt() ?? 0;

      // Calculate expiring warranties
      int expW = 0;
      final now = DateTime.now();
      for (final r in results[2]) {
        final deliveredAt = (r['deliveredAt'] as num?)?.toInt();
        final warranty = (r['warranty'] ?? '').toString();
        if (deliveredAt == null) continue;
        int m = int.tryParse(warranty.split(' ').first) ?? 0;
        if (m > 0) {
          DateTime d = DateTime.fromMillisecondsSinceEpoch(deliveredAt);
          DateTime e = DateTime(d.year, d.month + m, d.day);
          if (e.isAfter(now) && e.difference(now).inDays <= 7) expW++;
        }
      }

      if (mounted) {
        setState(() {
          _pendingRepairs = pendingR;
          _pendingStock = pendingS;
          _expiringWarranty = expW;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('ActionRequiredCard: Error loading counts: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return _buildShimmer();
    }

    final items = <_ActionItem>[];
    if (widget.enableRepair && _pendingRepairs > 0) {
      items.add(_ActionItem(
        icon: Icons.build_circle,
        label: '$_pendingRepairs đơn sửa chờ xử lý',
        color: Colors.blue,
        onTap: widget.onPendingRepairsTap,
      ));
    }
    if (_pendingStock > 0) {
      items.add(_ActionItem(
        icon: Icons.pending_actions,
        label: '$_pendingStock hàng chờ xác nhận',
        color: Colors.orange,
        onTap: widget.onPendingStockTap,
      ));
    }
    if (widget.enableWarranty && _expiringWarranty > 0) {
      items.add(_ActionItem(
        icon: Icons.shield,
        label: '$_expiringWarranty thiết bị sắp hết bảo hành',
        color: Colors.amber.shade800,
        onTap: widget.onWarrantyTap,
      ));
    }
    if (widget.enableExpiry && _expiringProducts > 0) {
      items.add(_ActionItem(
        icon: Icons.timer,
        label: '$_expiringProducts sản phẩm sắp hết HSD',
        color: Colors.red,
        onTap: widget.onExpiryTap,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notification_important, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 6),
              Text(
                'CẦN XỬ LÝ (${items.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) => InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, color: item.color, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionItem({required this.icon, required this.label, required this.color, this.onTap});
}

/// Compact finance summary - shows Thu/Chi with expandable detail
class FinanceSummaryCard extends StatelessWidget {
  final int totalIn;
  final int totalOut;
  final int netProfit;
  final VoidCallback? onTap;

  const FinanceSummaryCard({
    super.key,
    required this.totalIn,
    required this.totalOut,
    required this.netProfit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.account_balance_wallet, color: Colors.blue.shade600, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  'TÓM TẮT HÔM NAY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd/MM').format(DateTime.now()),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 12),
            // Thu - Chi - Profit row
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    '📥 Thu',
                    '+${MoneyUtils.formatVND(totalIn)}',
                    Colors.green,
                  ),
                ),
                Container(width: 1, height: 36, color: Colors.grey.shade200),
                Expanded(
                  child: _metricTile(
                    '📤 Chi',
                    '-${MoneyUtils.formatVND(totalOut)}',
                    Colors.red,
                  ),
                ),
                Container(width: 1, height: 36, color: Colors.grey.shade200),
                Expanded(
                  child: _metricTile(
                    '💰 Lãi',
                    '${netProfit >= 0 ? '+' : ''}${MoneyUtils.formatVND(netProfit)}',
                    netProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Activity Feed card showing recent transactions
class ActivityFeedCard extends StatefulWidget {
  final bool enableRepair;

  const ActivityFeedCard({
    super.key,
    this.enableRepair = true,
  });

  @override
  State<ActivityFeedCard> createState() => _ActivityFeedCardState();
}

class _ActivityFeedCardState extends State<ActivityFeedCard> {
  List<_ActivityItem> _activities = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final db = await DBHelper().database;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final startMs = todayStart.millisecondsSinceEpoch;

      // Load recent sales, repairs, expenses from today
      final results = await Future.wait([
        // Recent sales (last 5)
        db.query('sales',
          columns: ['customerName', 'totalPrice', 'soldAt', 'paymentMethod'],
          where: 'soldAt >= ?', whereArgs: [startMs],
          orderBy: 'soldAt DESC', limit: 5),
        // Recent repairs (last 5)
        if (widget.enableRepair)
          db.query('repairs',
            columns: ['customerName', 'deviceName', 'price', 'createdAt', 'status', 'deliveredAt'],
            where: 'createdAt >= ? OR (deliveredAt IS NOT NULL AND deliveredAt >= ?)',
            whereArgs: [startMs, startMs],
            orderBy: 'createdAt DESC', limit: 5)
        else
          Future.value(<Map<String, dynamic>>[]),
        // Recent expenses (last 5)
        db.query('expenses',
          columns: ['title', 'amount', 'date', 'type', 'category'],
          where: 'date >= ?', whereArgs: [startMs],
          orderBy: 'date DESC', limit: 5),
      ]);

      final activities = <_ActivityItem>[];

      // Sales
      for (final s in results[0]) {
        final name = s['customerName'] ?? 'Khách lẻ';
        final price = (s['totalPrice'] as num?)?.toInt() ?? 0;
        final at = (s['soldAt'] as num?)?.toInt() ?? 0;
        activities.add(_ActivityItem(
          icon: Icons.shopping_cart,
          color: Colors.green,
          title: 'Bán hàng - $name',
          amount: '+${MoneyUtils.formatVND(price)}',
          amountColor: Colors.green,
          timestamp: at,
        ));
      }

      // Repairs
      for (final r in results[1]) {
        final name = (r['customerName'] ?? '').toString();
        final device = (r['deviceName'] ?? '').toString();
        final status = (r['status'] as num?)?.toInt() ?? 1;
        final at = (r['deliveredAt'] as num?)?.toInt() ?? (r['createdAt'] as num?)?.toInt() ?? 0;
        final price = (r['price'] as num?)?.toInt() ?? 0;
        final isDelivered = status == 4;
        activities.add(_ActivityItem(
          icon: isDelivered ? Icons.check_circle : Icons.build_circle,
          color: isDelivered ? Colors.blue : Colors.orange,
          title: isDelivered ? 'Giao máy - $name' : 'Nhận sửa - ${device.isNotEmpty ? device : name}',
          amount: isDelivered ? '+${MoneyUtils.formatVND(price)}' : '',
          amountColor: Colors.blue,
          timestamp: at,
        ));
      }

      // Expenses
      for (final e in results[2]) {
        final title = e['title'] ?? e['category'] ?? 'Chi phí';
        final amount = (e['amount'] as num?)?.toInt() ?? 0;
        final at = (e['date'] as num?)?.toInt() ?? 0;
        final eType = (e['type'] as String? ?? '').toUpperCase();
        final isIncome = eType == 'THU';
        activities.add(_ActivityItem(
          icon: isIncome ? Icons.add_circle : Icons.remove_circle,
          color: isIncome ? Colors.teal : Colors.red,
          title: isIncome ? 'Thu: $title' : 'Chi: $title',
          amount: isIncome ? '+${MoneyUtils.formatVND(amount)}' : '-${MoneyUtils.formatVND(amount)}',
          amountColor: isIncome ? Colors.teal : Colors.red,
          timestamp: at,
        ));
      }

      // Sort by timestamp desc, take top 8
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final top = activities.take(8).toList();

      if (mounted) {
        setState(() {
          _activities = top;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('ActivityFeedCard: Error: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_activities.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.history, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Text(
              'Chưa có hoạt động hôm nay',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.purple.shade400, size: 16),
                const SizedBox(width: 6),
                Text(
                  'HOẠT ĐỘNG HÔM NAY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade600,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_activities.length} mục',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._activities.map((a) => _buildActivityRow(a)),
        ],
      ),
    );
  }

  Widget _buildActivityRow(_ActivityItem item) {
    final time = item.timestamp > 0
        ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.timestamp))
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Time column
          SizedBox(
            width: 40,
            child: Text(
              time,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
          ),
          // Icon
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(item.icon, color: item.color, size: 14),
          ),
          const SizedBox(width: 8),
          // Title
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Amount
          if (item.amount.isNotEmpty)
            Text(
              item.amount,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: item.amountColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final Color color;
  final String title;
  final String amount;
  final Color amountColor;
  final int timestamp;

  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.amount,
    required this.amountColor,
    required this.timestamp,
  });
}
