import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/payment_intent_service.dart';
import '../views/pending_payments_list_view.dart';
import '../theme/app_text_styles.dart';

/// Widget hiển thị số lượng thanh toán chờ xử lý trên Dashboard
class PendingPaymentsWidget extends StatefulWidget {
  const PendingPaymentsWidget({super.key});

  @override
  State<PendingPaymentsWidget> createState() => _PendingPaymentsWidgetState();
}

class _PendingPaymentsWidgetState extends State<PendingPaymentsWidget> {
  Map<String, dynamic> _stats = {};
  int _totalPendingIncome = 0;
  int _totalPendingExpense = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = PaymentIntentService.getStatistics();
      final pendingIntents = await PaymentIntentService.getPendingIntents();

      int income = 0;
      int expense = 0;
      for (final intent in pendingIntents) {
        if (intent.isIncome) {
          income += intent.amount;
        } else {
          expense += intent.amount;
        }
      }

      if (mounted) {
        setState(() {
          _stats = stats;
          _totalPendingIncome = income;
          _totalPendingExpense = expense;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending payment stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openPaymentsList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PendingPaymentsListView()),
    ).then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _stats['pending'] ?? 0;

    // Không hiển thị nếu không có giao dịch chờ
    if (!_isLoading && pendingCount == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade300),
      ),
      child: InkWell(
        onTap: _openPaymentsList,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isLoading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  children: [
                    // Icon with badge
                    Stack(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet,
                            size: 28,
                            color: Colors.green.shade700,
                          ),
                        ),
                        if (pendingCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                '$pendingCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTextStyles.caption.fontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thanh toán chờ xử lý',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: AppTextStyles.headline4.fontSize,
                              color: Colors.green.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (_totalPendingIncome > 0)
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.arrow_downward,
                                        size: 12,
                                        color: Colors.blue.shade600,
                                      ),
                                      const SizedBox(width: 2),
                                      Flexible(
                                        child: Text(
                                          'Thu: ${NumberFormat.compact(locale: 'vi').format(_totalPendingIncome)}đ',
                                          style: TextStyle(
                                            fontSize: AppTextStyles.body1.fontSize,
                                            color: Colors.blue.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                ),
                              if (_totalPendingExpense > 0)
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.arrow_upward,
                                        size: 12,
                                        color: Colors.orange.shade600,
                                      ),
                                      const SizedBox(width: 2),
                                      Flexible(
                                        child: Text(
                                          'Chi: ${NumberFormat.compact(locale: 'vi').format(_totalPendingExpense)}đ',
                                          style: TextStyle(
                                            fontSize: AppTextStyles.body1.fontSize,
                                            color: Colors.orange.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Arrow
                    Icon(Icons.chevron_right, color: Colors.green.shade400),
                  ],
                ),
        ),
      ),
    );
  }
}
