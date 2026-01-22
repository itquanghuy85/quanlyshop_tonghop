// Unified Payment Page - The ONLY place where payments can be executed
//
// PURPOSE:
// - Single entry point for ALL payment executions
// - Display payment info and confirm action
// - Trigger validation via MoneyValidationService
// - Record money to ledger via PaymentIntentService
//
// RULES:
// - This is the ONLY UI allowed to write money data
// - All payments MUST go through this page
// - No direct money transaction outside this page
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 6 - Unified Payment)

import 'package:flutter/material.dart';
import '../models/payment_intent_model.dart';
import '../services/payment_intent_service.dart';
import '../services/user_service.dart';
import '../constants/financial_constants.dart';

/// Unified Payment Page - The ONLY place where payments are executed
///
/// Business modules create PaymentIntent objects and navigate here.
/// This page is responsible for:
/// 1. Displaying payment information
/// 2. Confirming payment action
/// 3. Validating payment
/// 4. Recording to ledger
class UnifiedPaymentPage extends StatefulWidget {
  /// The payment intent to process
  final PaymentIntent intent;

  const UnifiedPaymentPage({Key? key, required this.intent}) : super(key: key);

  /// Navigate to this page with a payment intent
  static Future<PaymentExecutionResult?> navigateWithIntent(
    BuildContext context,
    PaymentIntent intent,
  ) async {
    // Register the intent
    PaymentIntentService.createIntent(intent);

    // Navigate to payment page
    final result = await Navigator.of(context).push<PaymentExecutionResult>(
      MaterialPageRoute(
        builder: (context) => UnifiedPaymentPage(intent: intent),
      ),
    );

    return result;
  }

  @override
  State<UnifiedPaymentPage> createState() => _UnifiedPaymentPageState();
}

class _UnifiedPaymentPageState extends State<UnifiedPaymentPage> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh Toán'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _handleCancel(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Payment Info Card
            _buildPaymentInfoCard(intent, theme),

            const SizedBox(height: 24),

            // Payment Method Selection
            _buildPaymentMethodSection(theme),

            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Confirm Button
            _buildConfirmButton(intent, theme),

            const SizedBox(height: 16),

            // Cancel Button
            OutlinedButton(
              onPressed: _isProcessing ? null : () => _handleCancel(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfoCard(PaymentIntent intent, ThemeData theme) {
    final isIncome = intent.isIncome;
    final directionColor = isIncome ? Colors.green : Colors.red;
    final directionIcon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
    final directionText = isIncome ? 'THU' : 'CHI';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with direction
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: directionColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(directionIcon, color: directionColor, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      directionText,
                      style: TextStyle(
                        color: directionColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      intent.type.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(height: 24),

            // Amount (Large)
            Center(
              child: Text(
                '${_formatCurrency(intent.amount)} đ',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: directionColor,
                ),
              ),
            ),

            const Divider(height: 24),

            // Details
            _buildInfoRow('Mô tả', intent.description),
            if (intent.personName != null)
              _buildInfoRow(isIncome ? 'Từ' : 'Đến', intent.personName!),
            if (intent.personPhone != null)
              _buildInfoRow('SĐT', intent.personPhone!),
            if (intent.referenceId != null)
              _buildInfoRow('Mã tham chiếu', intent.referenceId!),
            if (intent.notes != null && intent.notes!.isNotEmpty)
              _buildInfoRow('Ghi chú', intent.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection(ThemeData theme) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phương thức thanh toán',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._buildPaymentMethodOptions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPaymentMethodOptions() {
    final methods = [PaymentMethod.cash, PaymentMethod.transfer];

    return methods.map((method) {
      final isSelected = _selectedMethod == method;
      return RadioListTile<PaymentMethod>(
        value: method,
        groupValue: _selectedMethod,
        onChanged: _isProcessing
            ? null
            : (value) {
                if (value != null) {
                  setState(() => _selectedMethod = value);
                }
              },
        title: Text(method.displayName),
        subtitle: Text(_getMethodDescription(method)),
        secondary: Icon(
          _getMethodIcon(method),
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      );
    }).toList();
  }

  String _getMethodDescription(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Thanh toán bằng tiền mặt';
      case PaymentMethod.transfer:
        return 'Chuyển khoản ngân hàng';
      case PaymentMethod.debt:
        return 'Ghi nợ';
      case PaymentMethod.installment:
        return 'Thanh toán trả góp';
      default:
        return '';
    }
  }

  IconData _getMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.money;
      case PaymentMethod.transfer:
        return Icons.account_balance;
      case PaymentMethod.debt:
        return Icons.receipt_long;
      case PaymentMethod.installment:
        return Icons.calendar_month;
      default:
        return Icons.payment;
    }
  }

  Widget _buildConfirmButton(PaymentIntent intent, ThemeData theme) {
    final isIncome = intent.isIncome;
    final buttonColor = isIncome ? Colors.green : theme.primaryColor;

    return ElevatedButton(
      onPressed: _isProcessing ? null : () => _handleConfirm(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _isProcessing
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(
              isIncome ? 'XÁC NHẬN THU TIỀN' : 'XÁC NHẬN THANH TOÁN',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  Future<void> _handleConfirm(BuildContext context) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Get current user
      final currentUser = await UserService.getCurrentUserName();

      // Execute payment via PaymentIntentService
      final result = await PaymentIntentService.executePayment(
        intentId: widget.intent.id,
        paymentMethod: _selectedMethod,
        executedBy: currentUser ?? 'Unknown',
      );

      if (!mounted) return;

      if (result.success) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  widget.intent.isIncome
                      ? 'Thu tiền thành công!'
                      : 'Thanh toán thành công!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Return result to caller
        Navigator.of(context).pop(result);
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Có lỗi xảy ra';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handleCancel(BuildContext context) {
    // Cancel the intent
    PaymentIntentService.cancelIntent(
      widget.intent.id,
      reason: 'User cancelled',
    );

    // Return null to indicate cancellation
    Navigator.of(context).pop(null);
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
