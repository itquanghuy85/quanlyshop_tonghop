// PaymentIntentService - Central service for managing payment intents
//
// PURPOSE:
// - Manage PaymentIntent lifecycle (create, execute, cancel)
// - ONLY service allowed to execute payments
// - Integrates with MoneyValidationService and MoneyTransactionService
//
// RULES:
// - PaymentIntent can only be executed ONCE
// - Validation MUST pass before execution
// - All payments MUST go through this service
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 6 - Unified Payment)

import 'package:flutter/foundation.dart';
import '../models/payment_intent_model.dart';
import '../data/db_helper.dart';
import 'money_validation_service.dart';
import 'money_transaction_service.dart';
import '../constants/financial_constants.dart';

/// Result of a payment execution
class PaymentExecutionResult {
  final bool success;
  final String? errorCode;
  final String? errorMessage;
  final String? ledgerEntryId;
  final PaymentIntent? updatedIntent;

  PaymentExecutionResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.ledgerEntryId,
    this.updatedIntent,
  });

  factory PaymentExecutionResult.success({
    required String ledgerEntryId,
    required PaymentIntent updatedIntent,
  }) {
    return PaymentExecutionResult(
      success: true,
      ledgerEntryId: ledgerEntryId,
      updatedIntent: updatedIntent,
    );
  }

  factory PaymentExecutionResult.failure({
    required String errorCode,
    required String errorMessage,
  }) {
    return PaymentExecutionResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
}

/// Central service for managing ALL payment intents
///
/// This is the ONLY service that can execute payments.
/// Business modules must create PaymentIntent objects and
/// redirect to the Unified Payment Page.
class PaymentIntentService {
  static final DBHelper _db = DBHelper();

  // In-memory cache of pending payment intents (for current session)
  static final Map<String, PaymentIntent> _pendingIntents = {};

  // ---------------------------------------------------------------------------
  // INTENT LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Create a new payment intent
  ///
  /// This does NOT execute the payment. It only creates a pending intent
  /// that must be executed through the Unified Payment Page.
  static PaymentIntent createIntent(PaymentIntent intent) {
    if (intent.status != PaymentIntentStatus.pending) {
      throw ArgumentError('New payment intent must have PENDING status');
    }

    // Store in cache
    _pendingIntents[intent.id] = intent;

    debugPrint('💳 PaymentIntent created: ${intent.id} - ${intent.type.code}');
    return intent;
  }

  /// Get a pending payment intent by ID
  static PaymentIntent? getIntent(String intentId) {
    return _pendingIntents[intentId];
  }

  /// Get all pending payment intents
  static List<PaymentIntent> getPendingIntents() {
    return _pendingIntents.values
        .where((i) => i.status == PaymentIntentStatus.pending)
        .toList();
  }

  /// Cancel a payment intent
  static bool cancelIntent(String intentId, {String? reason}) {
    final intent = _pendingIntents[intentId];
    if (intent == null) {
      debugPrint('❌ PaymentIntent not found: $intentId');
      return false;
    }

    if (!intent.canExecute) {
      debugPrint('❌ PaymentIntent cannot be cancelled: ${intent.status.code}');
      return false;
    }

    intent.status = PaymentIntentStatus.cancelled;
    intent.notes = reason != null
        ? '${intent.notes ?? ''}\nHủy: $reason'.trim()
        : intent.notes;

    debugPrint('🚫 PaymentIntent cancelled: $intentId');
    return true;
  }

  // ---------------------------------------------------------------------------
  // PAYMENT EXECUTION (ONLY ALLOWED FROM UNIFIED PAYMENT PAGE)
  // ---------------------------------------------------------------------------

  /// Execute a payment intent
  ///
  /// This is the ONLY method that can execute a payment.
  /// It MUST be called from the Unified Payment Page ONLY.
  ///
  /// Steps:
  /// 1. Validate the intent exists and is pending
  /// 2. Validate the payment amount via MoneyValidationService
  /// 3. Record the payment to the ledger via MoneyTransactionService
  /// 4. Update the intent status to COMPLETED
  /// 5. Update related entities (debt, sale, etc.) if needed
  static Future<PaymentExecutionResult> executePayment({
    required String intentId,
    required PaymentMethod paymentMethod,
    required String executedBy,
  }) async {
    // 1. Get the intent
    final intent = _pendingIntents[intentId];
    if (intent == null) {
      return PaymentExecutionResult.failure(
        errorCode: 'INTENT_NOT_FOUND',
        errorMessage: 'Payment intent not found: $intentId',
      );
    }

    // 2. Check if intent can be executed
    if (!intent.canExecute) {
      return PaymentExecutionResult.failure(
        errorCode: 'INTENT_ALREADY_PROCESSED',
        errorMessage: 'Payment intent already processed: ${intent.status.code}',
      );
    }

    // 3. Validate the payment amount
    try {
      MoneyValidationService.validateAmount(intent.amount);
    } catch (e) {
      return PaymentExecutionResult.failure(
        errorCode: 'VALIDATION_FAILED',
        errorMessage: 'Payment validation failed: $e',
      );
    }

    // 4. Record to ledger
    final now = DateTime.now().millisecondsSinceEpoch;
    final ledgerEntryId = 'ledger_${intent.id}_$now';

    try {
      // Determine direction based on payment type
      final direction = intent.isIncome ? 'IN' : 'OUT';

      // Record to ledger via MoneyTransactionService
      await MoneyTransactionService.appendLedger(
        activityType: intent.type.code,
        direction: direction,
        amount: intent.amount,
        paymentMethod: paymentMethod.code,
        referenceType: intent.referenceType ?? 'payment_intent',
        referenceId: intent.referenceId ?? intent.id,
        notes: intent.description,
        createdBy: executedBy,
      );

      // 5. Update intent status
      intent.status = PaymentIntentStatus.completed;
      intent.paymentMethod = paymentMethod;
      intent.paidBy = executedBy;
      intent.paidAt = now;
      intent.ledgerEntryId = ledgerEntryId;

      // 6. Update related entities based on payment type
      await _updateRelatedEntities(intent, paymentMethod);

      debugPrint('✅ Payment executed: ${intent.id} - ${intent.amount}đ');

      return PaymentExecutionResult.success(
        ledgerEntryId: ledgerEntryId,
        updatedIntent: intent,
      );
    } catch (e) {
      // Mark as failed
      intent.status = PaymentIntentStatus.failed;
      intent.notes = '${intent.notes ?? ''}\nLỗi: $e'.trim();

      debugPrint('❌ Payment execution failed: $e');
      return PaymentExecutionResult.failure(
        errorCode: 'EXECUTION_FAILED',
        errorMessage: 'Payment execution failed: $e',
      );
    }
  }

  /// Update related entities after payment execution
  static Future<void> _updateRelatedEntities(
    PaymentIntent intent,
    PaymentMethod paymentMethod,
  ) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (intent.type) {
      case PaymentIntentType.supplierDebt:
      case PaymentIntentType.customerDebtCollection:
      case PaymentIntentType.otherDebt:
        // Update debt payment
        if (intent.referenceId != null) {
          await _db.insertDebtPayment({
            'firestoreId': 'dp_${intent.id}',
            'debtId': intent.referenceId,
            'amount': intent.amount,
            'paymentMethod': paymentMethod.code,
            'paidAt': now,
            'paidBy': intent.paidBy,
            'note': intent.notes,
            'isSynced': 0,
          });
        }
        break;

      case PaymentIntentType.operatingExpense:
      case PaymentIntentType.utilityExpense:
      case PaymentIntentType.otherExpense:
        // Insert expense record
        await _db.insertExpense({
          'firestoreId': 'exp_${intent.id}',
          'amount': intent.amount,
          'note': intent.description,
          'paymentMethod': paymentMethod.code,
          'createdAt': now,
          'createdBy': intent.paidBy,
          'category': intent.metadata?['category'] ?? 'OTHER',
          'isSynced': 0,
        });
        break;

      case PaymentIntentType.salaryPayment:
      case PaymentIntentType.bonusPayment:
        // Record salary payment
        await _db.insertExpense({
          'firestoreId': 'salary_${intent.id}',
          'amount': intent.amount,
          'note': intent.description,
          'paymentMethod': paymentMethod.code,
          'createdAt': now,
          'createdBy': intent.paidBy,
          'category': 'SALARY',
          'isSynced': 0,
        });
        break;

      default:
        // For other types, the ledger entry is sufficient
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITY METHODS
  // ---------------------------------------------------------------------------

  /// Clear all pending intents (use with caution)
  static void clearPendingIntents() {
    _pendingIntents.clear();
    debugPrint('🧹 All pending payment intents cleared');
  }

  /// Get statistics about payment intents
  static Map<String, int> getStatistics() {
    int pending = 0;
    int completed = 0;
    int cancelled = 0;
    int failed = 0;

    for (final intent in _pendingIntents.values) {
      switch (intent.status) {
        case PaymentIntentStatus.pending:
          pending++;
          break;
        case PaymentIntentStatus.completed:
          completed++;
          break;
        case PaymentIntentStatus.cancelled:
          cancelled++;
          break;
        case PaymentIntentStatus.failed:
          failed++;
          break;
      }
    }

    return {
      'pending': pending,
      'completed': completed,
      'cancelled': cancelled,
      'failed': failed,
      'total': _pendingIntents.length,
    };
  }
}
