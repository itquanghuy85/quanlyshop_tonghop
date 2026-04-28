import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/expansion_module_services.dart';
import '../../../expansion/safe_mode/crm_loyalty_repository.dart';
import '../../../expansion/safe_mode/crm_loyalty_service.dart';

class RedeemPointsView extends StatefulWidget {
  final String customerId;
  final String customerName;
  final int currentPoints;
  final ExpansionFeatureFlags flags;

  const RedeemPointsView({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.currentPoints,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<RedeemPointsView> createState() => _RedeemPointsViewState();
}

class _RedeemPointsViewState extends State<RedeemPointsView> {
  late final LoyaltyService _service;

  // Bước 500 điểm / lần
  static const int _step = 500;
  static const int _discountPerStep = 50000;

  int _selectedPoints = 500;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _service = LoyaltyService(flags: widget.flags);
    _selectedPoints = _nearestStep(widget.currentPoints);
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  int _nearestStep(int points) {
    final maxSteps = points ~/ _step;
    if (maxSteps <= 0) return _step;
    return _step;
  }

  int get _maxRedeemablePoints {
    final steps = widget.currentPoints ~/ _step;
    return steps * _step;
  }

  int get _discountAmount => (_selectedPoints ~/ _step) * _discountPerStep;

  int get _stepsCount => _selectedPoints ~/ _step;

  bool get _canRedeem =>
      widget.currentPoints >= _step && _selectedPoints >= _step;

  void _adjustPoints(bool increase) {
    setState(() {
      if (increase) {
        final next = _selectedPoints + _step;
        if (next <= _maxRedeemablePoints) _selectedPoints = next;
      } else {
        final prev = _selectedPoints - _step;
        if (prev >= _step) _selectedPoints = prev;
      }
    });
  }

  Future<void> _confirm() async {
    if (!_canRedeem) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đổi điểm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách hàng: ${widget.customerName}'),
            const SizedBox(height: 4),
            Text('Điểm đổi: $_selectedPoints điểm'),
            Text('Chiết khấu nhận được: ${_formatMoney(_discountAmount)}'),
            const SizedBox(height: 8),
            Text(
              'Điểm còn lại: ${widget.currentPoints - _selectedPoints} điểm',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận đổi'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _redeeming = true);
    try {
      final result = await _service.redeemPoints(
        customerId: widget.customerId,
        customerName: widget.customerName,
        pointsToRedeem: _selectedPoints,
        note: 'Đổi $_selectedPoints điểm → ${_formatMoney(_discountAmount)}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đổi điểm thành công! Chiết khấu ${_formatMoney(_discountAmount)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      // Trả về điểm mới để màn cha cập nhật ngay, tránh cảm giác trễ reload.
      Navigator.pop(context, result.updatedPoint.totalPoints);
    } on InsufficientPointsException catch (e) {
      _showError('Không đủ điểm: có ${e.available}, cần ${e.requested}');
    } on ModuleDisabledException {
      _showError('Module CRM đang tắt.');
    } catch (_) {
      _showError('Có lỗi xảy ra. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}tr';
    }
    return '${amount ~/ 1000}k';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi điểm')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurrentPointsBanner(),
            const SizedBox(height: 20),
            _buildRateInfo(),
            const SizedBox(height: 20),
            _buildPointSelector(),
            const SizedBox(height: 20),
            _buildDiscountPreview(),
            const Spacer(),
            _buildConfirmButton(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPointsBanner() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.stars, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Điểm hiện có', style: TextStyle(color: Colors.grey)),
                Text(
                  '${widget.currentPoints} điểm',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Text('500 điểm → giảm 50.000₫'),
        ],
      ),
    );
  }

  Widget _buildPointSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Chọn số điểm muốn đổi', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _selectedPoints > _step ? () => _adjustPoints(false) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 32,
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '$_selectedPoints',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    const Text('điểm', style: TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: _selectedPoints < _maxRedeemablePoints
                      ? () => _adjustPoints(true)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 32,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tối đa có thể đổi: $_maxRedeemablePoints điểm',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountPreview() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Chiết khấu nhận được', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(
              _formatMoney(_discountAmount),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            Text(
              '$_stepsCount lần × 50.000₫',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        icon: _redeeming
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(_canRedeem ? 'Xác nhận đổi $_selectedPoints điểm' : 'Không đủ điểm'),
        onPressed: (_canRedeem && !_redeeming) ? _confirm : null,
      ),
    );
  }
}
