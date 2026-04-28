import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/crm_loyalty_models.dart';
import '../../../expansion/safe_mode/crm_loyalty_service.dart';
import 'redeem_points_view.dart';
import 'loyalty_history_view.dart';

class CustomerLoyaltyView extends StatefulWidget {
  final String customerId;
  final List<String> customerIdAliases;
  final String customerName;
  final int initialTotalSpent;
  final ExpansionFeatureFlags flags;

  const CustomerLoyaltyView({
    super.key,
    required this.customerId,
    this.customerIdAliases = const <String>[],
    required this.customerName,
    this.initialTotalSpent = 0,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<CustomerLoyaltyView> createState() => _CustomerLoyaltyViewState();
}

class _CustomerLoyaltyViewState extends State<CustomerLoyaltyView> {
  late final LoyaltyService _service;

  LoyaltyPoint? _loyaltyPoint;
  CustomerLevel? _customerLevel;
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
    if (!widget.flags.enableCRM) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final idsForLookup = <String>{
        widget.customerId,
        ...widget.customerIdAliases,
      }.toList(growable: false);
      debugPrint(
        '[CRM][LOYALTY] load customer=${widget.customerName} ids=$idsForLookup totalSpent=${widget.initialTotalSpent}',
      );

      final pointFromLoyalty = await _service.getCustomerPointsByAliases(
        primaryCustomerId: widget.customerId,
        aliases: widget.customerIdAliases,
        customerName: widget.customerName,
      );

      LoyaltyPoint? point = pointFromLoyalty;
      if (point == null && widget.initialTotalSpent > 0) {
        final estimated = _service.previewEarnPoints(
          widget.initialTotalSpent.toDouble(),
        );
        if (estimated > 0) {
          point = await _service.seedPointsIfMissing(
            customerId: widget.customerId,
            customerName: widget.customerName,
            initialPoints: estimated,
            note: 'Backfill từ tổng chi tiêu hiện có',
          );
        }
      }

      final level = await _service.getCustomerLevel(widget.customerId);
      debugPrint(
        '[CRM][LOYALTY] result points=${point?.totalPoints ?? 0} tier=${level?.tier.toString() ?? 'regular'}',
      );
      if (!mounted) return;
      setState(() {
        _loyaltyPoint = point;
        _customerLevel = level;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _currentPoints => _loyaltyPoint?.totalPoints ?? 0;

  CustomerLevelTier get _currentTier =>
      _customerLevel?.tier ?? CustomerLevelTier.regular;

  Color _tierColor(CustomerLevelTier tier) {
    switch (tier) {
      case CustomerLevelTier.platinum:
        return const Color(0xFF6A5ACD);
      case CustomerLevelTier.gold:
        return const Color(0xFFFFB300);
      case CustomerLevelTier.silver:
        return const Color(0xFF9E9E9E);
      case CustomerLevelTier.regular:
        return const Color(0xFF4CAF50);
    }
  }

  IconData _tierIcon(CustomerLevelTier tier) {
    switch (tier) {
      case CustomerLevelTier.platinum:
        return Icons.diamond;
      case CustomerLevelTier.gold:
        return Icons.emoji_events;
      case CustomerLevelTier.silver:
        return Icons.military_tech;
      case CustomerLevelTier.regular:
        return Icons.person;
    }
  }

  int _nextThreshold(CustomerLevelTier tier) {
    switch (tier) {
      case CustomerLevelTier.regular:
        return 800;
      case CustomerLevelTier.silver:
        return 2000;
      case CustomerLevelTier.gold:
        return 5000;
      case CustomerLevelTier.platinum:
        return 5000;
    }
  }

  Future<void> _openRedeem() async {
    final updatedPoints = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => RedeemPointsView(
          customerId: widget.customerId,
          customerName: widget.customerName,
          currentPoints: _currentPoints,
          flags: widget.flags,
        ),
      ),
    );
    if (!mounted || updatedPoints == null) return;

    setState(() {
      _loyaltyPoint = (_loyaltyPoint ??
              LoyaltyPoint(
                customerId: widget.customerId,
                customerName: widget.customerName,
                totalPoints: 0,
                updatedAt: DateTime.now(),
              ))
          .copyWith(
            totalPoints: updatedPoints,
            updatedAt: DateTime.now(),
          );
    });

    // Đồng bộ lại level/history ở nền để đảm bảo state đầy đủ.
    _load();
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoyaltyHistoryView(
          customerId: widget.customerId,
          customerIdAliases: widget.customerIdAliases,
          customerName: widget.customerName,
          flags: widget.flags,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Điểm thành viên')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !widget.flags.enableCRM
              ? _buildDisabledBanner()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildProfileCard(),
                      const SizedBox(height: 16),
                      _buildPointsCard(),
                      const SizedBox(height: 16),
                      _buildProgressCard(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDisabledBanner() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.orange),
            SizedBox(height: 12),
            Text(
              'Module CRM chưa được kích hoạt\n(enableCRM = false)',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: _tierColor(_currentTier).withValues(alpha: 0.15),
              child: Icon(
                _tierIcon(_currentTier),
                color: _tierColor(_currentTier),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customerName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: _tierColor(_currentTier).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Hạng: ${_currentTier.displayName}',
                    style: TextStyle(
                      color: _tierColor(_currentTier),
                      fontWeight: FontWeight.w600,
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

  Widget _buildPointsCard() {
    final preview = _currentPoints >= 500
        ? _service.previewRedeemDiscount(_currentPoints ~/ 500 * 500)
        : 0;

    return Card(
      color: _tierColor(_currentTier).withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '$_currentPoints',
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.bold,
                color: _tierColor(_currentTier),
              ),
            ),
            const Text('điểm tích lũy', style: TextStyle(fontSize: 14)),
            if (preview > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Có thể đổi: ${_formatMoney(preview)}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    if (_currentTier == CustomerLevelTier.platinum) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.diamond, color: _tierColor(CustomerLevelTier.platinum)),
              const SizedBox(width: 8),
              const Text('Đã đạt hạng cao nhất: Kim cương'),
            ],
          ),
        ),
      );
    }

    final next = _nextThreshold(_currentTier);
    final progress = (_currentPoints / next).clamp(0.0, 1.0);
    final remaining = next - _currentPoints;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cần thêm $remaining điểm để lên hạng tiếp',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: _tierColor(_currentTier),
              backgroundColor: _tierColor(_currentTier).withValues(alpha: 0.15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_currentPoints điểm'),
                Text('$next điểm'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.redeem),
            label: const Text('Đổi điểm'),
            onPressed: _currentPoints >= 500 ? _openRedeem : null,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('Lịch sử giao dịch'),
            onPressed: _openHistory,
          ),
        ),
        if (_currentPoints < 500) ...[
          const SizedBox(height: 8),
          Text(
            'Cần tối thiểu 500 điểm để đổi (hiện có $_currentPoints điểm)',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    }
    return '${amount ~/ 1000}k';
  }
}
