import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/expansion_module_services.dart';
import '../../../expansion/safe_mode/crm_loyalty_models.dart';
import '../../../expansion/safe_mode/crm_loyalty_service.dart';

class LoyaltyHistoryView extends StatefulWidget {
  final String customerId;
  final List<String> customerIdAliases;
  final String customerName;
  final ExpansionFeatureFlags flags;

  const LoyaltyHistoryView({
    super.key,
    required this.customerId,
    this.customerIdAliases = const <String>[],
    required this.customerName,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<LoyaltyHistoryView> createState() => _LoyaltyHistoryViewState();
}

class _LoyaltyHistoryViewState extends State<LoyaltyHistoryView> {
  late final LoyaltyService _service;
  List<LoyaltyTransaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = LoyaltyService(flags: widget.flags);
    _load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final idsForLookup = <String>{
        widget.customerId,
        ...widget.customerIdAliases,
      }.toList(growable: false);
      debugPrint(
        '[CRM][LOYALTY_HISTORY] load customer=${widget.customerName} ids=$idsForLookup',
      );
      final list = await _service.getTransactionHistoryByAliases(
        primaryCustomerId: widget.customerId,
        aliases: widget.customerIdAliases,
      );
      debugPrint('[CRM][LOYALTY_HISTORY] loaded=${list.length}');
      if (!mounted) return;
      setState(() {
        _transactions = list;
        _loading = false;
      });
    } on ModuleDisabledException {
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lịch sử giao dịch', style: TextStyle(fontSize: 16)),
            Text(
              widget.customerName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_toggle_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Chưa có giao dịch nào', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            widget.customerName,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final int totalEarned = _transactions
        .where((t) => t.type == LoyaltyTransactionType.earn)
        .fold(0, (sum, t) => sum + t.points);
    final int totalRedeemed = _transactions
        .where((t) => t.type == LoyaltyTransactionType.redeem)
        .fold(0, (sum, t) => sum + t.points);

    return Column(
      children: [
        _buildSummaryRow(totalEarned, totalRedeemed),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _transactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildTile(_transactions[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(int earned, int redeemed) {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _buildStat(
              label: 'Đã tích',
              value: '+$earned điểm',
              color: Colors.green,
              icon: Icons.arrow_upward,
            ),
          ),
          Container(width: 1, height: 32, color: Colors.grey.shade300),
          Expanded(
            child: _buildStat(
              label: 'Đã đổi',
              value: '-$redeemed điểm',
              color: Colors.orange,
              icon: Icons.arrow_downward,
            ),
          ),
          Container(width: 1, height: 32, color: Colors.grey.shade300),
          Expanded(
            child: _buildStat(
              label: 'Giao dịch',
              value: '${_transactions.length} lần',
              color: Colors.blue,
              icon: Icons.receipt_long,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTile(LoyaltyTransaction tx) {
    final isEarn = tx.type == LoyaltyTransactionType.earn;
    final color = isEarn ? Colors.green : Colors.orange;
    final icon = isEarn ? Icons.add_circle : Icons.redeem;
    final sign = isEarn ? '+' : '-';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        isEarn ? 'Tích điểm' : 'Đổi điểm',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tx.note.isNotEmpty)
            Text(tx.note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            _formatDate(tx.createdAt),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign${tx.points} điểm',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          if (!isEarn && tx.discountAmount > 0)
            Text(
              _formatMoney(tx.discountAmount),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
      isThreeLine: tx.note.isNotEmpty,
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    }
    return '${amount ~/ 1000}k';
  }
}
