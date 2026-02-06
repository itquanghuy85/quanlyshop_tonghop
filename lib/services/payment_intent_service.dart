// PaymentIntentService - Central service for managing payment intents
//
// PURPOSE:
// - Manage PaymentIntent lifecycle (create, execute, cancel)
// - ONLY service allowed to execute payments
// - Integrates with MoneyValidationService and MoneyTransactionService
// - PERSISTS payment intents to database
//
// RULES:
// - PaymentIntent can only be executed ONCE
// - Validation MUST pass before execution
// - All payments MUST go through this service
//
// Created: 2026-01-22
// Updated: 2026-01-22 (Added database persistence)
// Author: AI Assistant (Phase 6 - Unified Payment)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/payment_intent_model.dart';
import '../data/db_helper.dart';
import 'money_validation_service.dart';
import 'money_transaction_service.dart';
import '../constants/financial_constants.dart';
import 'user_service.dart';

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

  // In-memory cache of ALL payment intents (for current session)
  // Key: intent.id, Value: PaymentIntent
  static final Map<String, PaymentIntent> _pendingIntents = {};

  // History of completed/cancelled intents (limited to last 100)
  static final List<PaymentIntent> _historyIntents = [];
  
  // Flag to track if data has been loaded from database
  static bool _isInitialized = false;
  
  // Track current shopId to detect shop changes
  static String? _currentShopId;

  // ---------------------------------------------------------------------------
  // INITIALIZATION (Load from database)
  // ---------------------------------------------------------------------------

  /// Initialize service by loading pending intents from database
  static Future<void> initialize() async {
    // Check if shop has changed - if so, need to reinitialize
    final currentShopId = UserService.getShopIdSync();
    if (_isInitialized && _currentShopId != currentShopId) {
      debugPrint('💳 Shop changed from $_currentShopId to $currentShopId, reinitializing...');
      await reinitialize();
      return;
    }
    
    if (_isInitialized) return;
    
    _currentShopId = currentShopId;
    
    try {
      // Load pending intents from database
      final pendingRows = await _db.getPendingPaymentIntents();
      debugPrint('💳 DB returned ${pendingRows.length} pending rows');
      for (final row in pendingRows) {
        final intent = _intentFromDbRow(row);
        _pendingIntents[intent.id] = intent;
        debugPrint('💳 Loaded from DB: ${intent.id} - ${intent.type.code} - ${intent.status.code}');
      }
      
      // Load history (completed/cancelled/failed)
      final historyRows = await _db.getPaymentIntentsHistory(limit: 100);
      for (final row in historyRows) {
        final intent = _intentFromDbRow(row);
        _historyIntents.add(intent);
      }
      
      _isInitialized = true;
      debugPrint('💳 PaymentIntentService initialized: ${_pendingIntents.length} pending, ${_historyIntents.length} history');
    } catch (e) {
      debugPrint('❌ PaymentIntentService initialization error: $e');
      _isInitialized = true; // Mark as initialized to prevent repeated failures
    }
  }

  /// Reinitialize service - call when shop changes or user logs out
  /// This clears all cached data and reloads from database
  static Future<void> reinitialize() async {
    debugPrint('💳 Reinitializing PaymentIntentService...');
    _pendingIntents.clear();
    _historyIntents.clear();
    _isInitialized = false;
    _currentShopId = null;
    await initialize();
  }
  
  /// Clear all cached data (call on logout)
  static void clearCache() {
    debugPrint('💳 Clearing PaymentIntentService cache...');
    _pendingIntents.clear();
    _historyIntents.clear();
    _isInitialized = false;
    _currentShopId = null;
  }

  /// Convert database row to PaymentIntent
  static PaymentIntent _intentFromDbRow(Map<String, dynamic> row) {
    // Parse metadata from JSON string
    Map<String, dynamic>? metadata;
    if (row['metadata'] != null && row['metadata'].toString().isNotEmpty) {
      try {
        metadata = jsonDecode(row['metadata']);
      } catch (e) {
        debugPrint('Error parsing metadata: $e');
      }
    }
    
    return PaymentIntent(
      id: row['intentId'] ?? '',
      type: PaymentIntentType.fromCode(row['type']),
      amount: row['amount'] ?? 0,
      status: PaymentIntentStatus.fromCode(row['status']),
      paymentMethod: row['paymentMethod'] != null
          ? PaymentMethod.fromCode(row['paymentMethod'])
          : null,
      description: row['description'] ?? '',
      referenceId: row['referenceId'],
      referenceType: row['referenceType'],
      personName: row['personName'],
      personPhone: row['personPhone'],
      notes: row['notes'],
      createdBy: row['createdBy'] ?? '',
      createdAt: row['createdAt'] ?? 0,
      paidBy: row['paidBy'],
      paidAt: row['paidAt'],
      metadata: metadata,
    );
  }

  /// Convert PaymentIntent to database row
  static Map<String, dynamic> _intentToDbRow(PaymentIntent intent) {
    return {
      'intentId': intent.id,
      'type': intent.type.code,
      'amount': intent.amount,
      'status': intent.status.code,
      'description': intent.description,
      'personName': intent.personName,
      'personPhone': intent.personPhone,
      'referenceId': intent.referenceId,
      'referenceType': intent.referenceType,
      'paymentMethod': intent.paymentMethod?.code,
      'createdBy': intent.createdBy,
      'createdAt': intent.createdAt,
      'paidBy': intent.paidBy,
      'paidAt': intent.paidAt,
      'notes': intent.notes,
      'metadata': intent.metadata != null ? jsonEncode(intent.metadata) : null,
      'shopId': UserService.getShopIdSync(),
      'isSynced': 0,
    };
  }

  // ---------------------------------------------------------------------------
  // INTENT LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Create a new payment intent
  ///
  /// If status is PENDING: stores in pending cache for later execution.
  /// If status is COMPLETED: stores directly in history (for instant cash payments).
  static Future<PaymentIntent> createIntent(PaymentIntent intent) async {
    // Ensure service is initialized
    if (!_isInitialized) {
      await initialize();
    }

    // Persist to database first
    try {
      await _db.insertPaymentIntent(_intentToDbRow(intent));
      debugPrint('💳 PaymentIntent created and persisted: ${intent.id} - ${intent.type.code} - ${intent.status.code}');
    } catch (e) {
      debugPrint('⚠️ PaymentIntent DB insert error: $e');
      // Still continue to store in memory
    }

    // Store in appropriate cache based on status
    if (intent.status == PaymentIntentStatus.pending) {
      _pendingIntents[intent.id] = intent;
    } else {
      // Already completed/cancelled/failed - add to history
      _historyIntents.insert(0, intent);
      if (_historyIntents.length > 100) {
        _historyIntents.removeLast();
      }
    }

    return intent;
  }

  /// Get a pending payment intent by ID
  static PaymentIntent? getIntent(String intentId) {
    // Check pending intents first
    if (_pendingIntents.containsKey(intentId)) {
      return _pendingIntents[intentId];
    }
    // Check history
    return _historyIntents.cast<PaymentIntent?>().firstWhere(
      (i) => i?.id == intentId,
      orElse: () => null,
    );
  }

  /// Get all pending payment intents
  /// Note: This is async to ensure data is loaded from DB first
  static Future<List<PaymentIntent>> getPendingIntents() async {
    // Ensure data is loaded from database
    if (!_isInitialized) {
      await initialize();
    }
    return _pendingIntents.values
        .where((i) => i.status == PaymentIntentStatus.pending)
        .toList();
  }
  
  /// Get pending income intents (CHỜ THU)
  static Future<List<PaymentIntent>> getPendingIncomeIntents() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _pendingIntents.values
        .where((i) => i.status == PaymentIntentStatus.pending && i.isIncome)
        .toList();
  }
  
  /// Get pending expense intents (CHỜ CHI)
  static Future<List<PaymentIntent>> getPendingExpenseIntents() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _pendingIntents.values
        .where((i) => i.status == PaymentIntentStatus.pending && i.isExpense)
        .toList();
  }

  /// Get all payment intents (pending + history)
  static Future<List<PaymentIntent>> getAllIntents() async {
    if (!_isInitialized) {
      await initialize();
    }
    final all = <PaymentIntent>[];
    all.addAll(_pendingIntents.values);
    all.addAll(_historyIntents);
    return all;
  }

  /// Get history of completed/cancelled intents
  static Future<List<PaymentIntent>> getHistoryIntents() async {
    if (!_isInitialized) {
      await initialize();
    }
    return List.unmodifiable(_historyIntents);
  }

  /// Move intent to history after completion/cancellation
  static Future<void> _moveToHistory(PaymentIntent intent) async {
    // Remove from pending
    _pendingIntents.remove(intent.id);
    
    // Add to history (limit to 100)
    _historyIntents.insert(0, intent);
    if (_historyIntents.length > 100) {
      _historyIntents.removeLast();
    }
    
    // Update in database
    try {
      await _db.updatePaymentIntent(intent.id, _intentToDbRow(intent));
    } catch (e) {
      debugPrint('⚠️ PaymentIntent DB update error: $e');
    }
  }

  /// Cancel a payment intent
  static Future<bool> cancelIntent(String intentId, {String? reason}) async {
    // Ensure service is initialized
    if (!_isInitialized) {
      debugPrint('⚠️ PaymentIntentService not initialized for cancel, initializing...');
      await initialize();
    }
    
    final intent = _pendingIntents[intentId];
    if (intent == null) {
      debugPrint('❌ PaymentIntent not found for cancel: $intentId');
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

    // Move to history
    await _moveToHistory(intent);

    debugPrint('🚫 PaymentIntent cancelled: $intentId');
    return true;
  }

  // ---------------------------------------------------------------------------
  // DIRECT PAYMENT EXECUTION (Không cần navigate qua UnifiedPaymentPage)
  // ---------------------------------------------------------------------------

  /// Execute payment directly without going through UI
  ///
  /// This is a convenience method for business modules that want to
  /// execute payments inline without navigating to UnifiedPaymentPage.
  ///
  /// Parameters:
  /// - type: Loại thanh toán (PaymentIntentType)
  /// - amount: Số tiền
  /// - paymentMethod: Phương thức thanh toán
  /// - description: Mô tả giao dịch
  /// - executedBy: Người thực hiện
  /// - referenceId: ID tham chiếu (debt ID, sale ID, etc.)
  /// - referenceType: Loại tham chiếu
  /// - personName: Tên người liên quan
  /// - personPhone: SĐT
  /// - notes: Ghi chú
  /// - metadata: Thông tin bổ sung
  ///
  /// Returns: PaymentExecutionResult
  static Future<PaymentExecutionResult> executePaymentDirect({
    required PaymentIntentType type,
    required int amount,
    required PaymentMethod paymentMethod,
    required String description,
    required String executedBy,
    String? referenceId,
    String? referenceType,
    String? personName,
    String? personPhone,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Validate amount
      if (amount <= 0) {
        return PaymentExecutionResult.failure(
          errorCode: 'INVALID_AMOUNT',
          errorMessage: 'Số tiền phải > 0',
        );
      }

      // Create intent with timestamp-based ID
      final now = DateTime.now().millisecondsSinceEpoch;
      final intentId = 'pi_direct_${type.code.toLowerCase()}_$now';
      
      final intent = PaymentIntent(
        id: intentId,
        type: type,
        amount: amount,
        status: PaymentIntentStatus.pending,
        paymentMethod: paymentMethod,
        description: description,
        referenceId: referenceId,
        referenceType: referenceType,
        personName: personName,
        personPhone: personPhone,
        notes: notes,
        createdBy: executedBy,
        createdAt: now,
        metadata: metadata,
      );

      // Store in memory temporarily (for tracking)
      _pendingIntents[intentId] = intent;

      // Persist to database (for audit trail)
      try {
        await _db.insertPaymentIntent(_intentToDbRow(intent));
      } catch (e) {
        debugPrint('⚠️ Direct payment DB insert warning: $e');
      }

      // Execute immediately
      final result = await executePayment(
        intentId: intentId,
        paymentMethod: paymentMethod,
        executedBy: executedBy,
      );

      debugPrint('💳 Direct payment ${result.success ? "SUCCESS" : "FAILED"}: ${intent.type.code} - ${intent.amount}đ');
      
      return result;
    } catch (e) {
      debugPrint('❌ executePaymentDirect error: $e');
      return PaymentExecutionResult.failure(
        errorCode: 'EXECUTION_ERROR',
        errorMessage: 'Lỗi thực thi thanh toán: $e',
      );
    }
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
    // Ensure service is initialized (loads from DB if needed)
    if (!_isInitialized) {
      debugPrint('⚠️ PaymentIntentService not initialized, initializing now...');
      await initialize();
    }
    
    // 1. Get the intent
    final intent = _pendingIntents[intentId];
    if (intent == null) {
      debugPrint('❌ Intent not found in _pendingIntents: $intentId');
      debugPrint('   Current pending IDs: ${_pendingIntents.keys.toList()}');
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

      // 7. Move to history
      await _moveToHistory(intent);

      debugPrint('✅ Payment executed: ${intent.id} - ${intent.amount}đ');

      return PaymentExecutionResult.success(
        ledgerEntryId: ledgerEntryId,
        updatedIntent: intent,
      );
    } catch (e) {
      // Mark as failed
      intent.status = PaymentIntentStatus.failed;
      intent.notes = '${intent.notes ?? ''}\nLỗi: $e'.trim();
      
      // Move failed to history too
      await _moveToHistory(intent);

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
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (intent.type) {
      case PaymentIntentType.supplierDebt:
      case PaymentIntentType.customerDebtCollection:
      case PaymentIntentType.otherDebt:
      case PaymentIntentType.inventoryPurchase: // Thêm: nhập kho có công nợ
      case PaymentIntentType.partsStockIn: // Thêm: nhập linh kiện có công nợ
        // Update debt payment
        if (intent.metadata != null && intent.metadata!['debtId'] != null) {
          final debtId = intent.metadata!['debtId'];
          final debtFirestoreId = intent.metadata!['debtFirestoreId'];
          final debtType = intent.metadata!['debtType'] as String? ?? 'SHOP_OWES';
          
          await _db.insertDebtPayment({
            'firestoreId': 'dp_${intent.id}',
            'debtId': debtId,
            'debtFirestoreId': debtFirestoreId,
            'debtType': debtType, // FIX: Add debtType for proper filtering
            'amount': intent.amount,
            'paymentMethod': paymentMethod.code,
            'paidAt': now,
            'createdBy': intent.paidBy,
            'note': intent.notes,
            'isSynced': 0,
          });
          
          // Update debt paidAmount
          if (debtId is int) {
            await _db.updateDebtPaid(debtId, intent.amount);
          }
        }
        break;

      case PaymentIntentType.operatingExpense:
      case PaymentIntentType.utilityExpense:
      case PaymentIntentType.otherExpense:
        // Insert expense record - FIX: use correct field names
        final shopId = UserService.getShopIdSync();
        await _db.insertExpense({
          'firestoreId': 'exp_${intent.id}',
          'amount': intent.amount,
          'title': intent.description,
          'description': intent.description,
          'note': intent.notes,
          'paymentMethod': paymentMethod.code,
          'date': now,
          'createdAt': now,
          'category': intent.metadata?['category'] ?? 'KHÁC',
          'shopId': shopId,
          'isSynced': 0,
        });
        break;

      case PaymentIntentType.salaryPayment:
      case PaymentIntentType.bonusPayment:
        // Record salary payment - FIX: use correct field names
        final shopIdSalary = UserService.getShopIdSync();
        await _db.insertExpense({
          'firestoreId': 'salary_${intent.id}',
          'amount': intent.amount,
          'title': intent.description,
          'description': intent.description,
          'note': intent.notes,
          'paymentMethod': paymentMethod.code,
          'date': now,
          'createdAt': now,
          'category': 'LƯƠNG',
          'shopId': shopIdSalary,
          'isSynced': 0,
        });
        break;
        
      case PaymentIntentType.repairService:
        // Repair payment - cũng cần update debt nếu có
        if (intent.metadata != null && intent.metadata!['debtId'] != null) {
          final debtId = intent.metadata!['debtId'];
          final debtFirestoreId = intent.metadata!['debtFirestoreId'];
          final debtType = intent.metadata!['debtType'] as String? ?? 'CUSTOMER_OWES';
          
          await _db.insertDebtPayment({
            'firestoreId': 'dp_${intent.id}',
            'debtId': debtId,
            'debtFirestoreId': debtFirestoreId,
            'debtType': debtType, // FIX: Add debtType for proper filtering
            'amount': intent.amount,
            'paymentMethod': paymentMethod.code,
            'paidAt': now,
            'createdBy': intent.paidBy,
            'note': intent.notes,
            'isSynced': 0,
          });
          
          // Update debt paidAmount
          if (debtId is int) {
            await _db.updateDebtPaid(debtId, intent.amount);
          }
        }
        break;
        
      case PaymentIntentType.repairPartnerDebt:
        // Partner debt payment
        if (intent.metadata != null && intent.metadata!['partnerId'] != null) {
          final partnerId = intent.metadata!['partnerId'];
          await _db.insertRepairPartnerPayment({
            'firestoreId': 'rpp_${intent.id}',
            'partnerId': partnerId,
            'partnerName': intent.personName,
            'amount': intent.amount,
            'paymentMethod': paymentMethod.code,
            'paidAt': now,
            'note': intent.notes,
            'isSynced': 0,
          });
        }
        break;

      default:
        // For other types, the ledger entry is sufficient
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITY METHODS
  // ---------------------------------------------------------------------------

  /// Reload intents from database
  static Future<void> reload() async {
    _pendingIntents.clear();
    _historyIntents.clear();
    _isInitialized = false;
    await initialize();
  }

  /// Clear all pending intents (use with caution)
  static void clearPendingIntents() {
    _pendingIntents.clear();
    debugPrint('🧹 All pending payment intents cleared');
  }

  /// Get statistics about payment intents
  static Map<String, dynamic> getStatistics() {
    int pending = 0;
    int completed = 0;
    int cancelled = 0;
    int failed = 0;
    int totalPendingIncome = 0;
    int totalPendingExpense = 0;

    for (final intent in _pendingIntents.values) {
      if (intent.status == PaymentIntentStatus.pending) {
        pending++;
        if (intent.isIncome) {
          totalPendingIncome += intent.amount;
        } else {
          totalPendingExpense += intent.amount;
        }
      }
    }
    
    for (final intent in _historyIntents) {
      switch (intent.status) {
        case PaymentIntentStatus.completed:
          completed++;
          break;
        case PaymentIntentStatus.cancelled:
          cancelled++;
          break;
        case PaymentIntentStatus.failed:
          failed++;
          break;
        default:
          break;
      }
    }

    return {
      'pending': pending,
      'completed': completed,
      'cancelled': cancelled,
      'failed': failed,
      'total': _pendingIntents.length + _historyIntents.length,
      'totalPendingIncome': totalPendingIncome,
      'totalPendingExpense': totalPendingExpense,
    };
  }

  // ---------------------------------------------------------------------------
  // TESTING & DEBUG UTILITIES
  // ---------------------------------------------------------------------------

  /// Delete a payment intent by ID (for testing/cleanup)
  static Future<bool> deleteIntent(String intentId) async {
    try {
      // Remove from memory
      _pendingIntents.remove(intentId);
      _historyIntents.removeWhere((i) => i.id == intentId);
      
      // Remove from database
      await _db.deletePaymentIntent(intentId);
      
      debugPrint('🗑️ PaymentIntent deleted: $intentId');
      return true;
    } catch (e) {
      debugPrint('❌ PaymentIntent delete error: $e');
      return false;
    }
  }
}
