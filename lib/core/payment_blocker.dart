// PaymentBlocker - Guards against direct payment operations outside PaymentIntentService
//
// PURPOSE:
// - Block any direct payment operation that bypasses PaymentIntentService
// - Provide clear error messages to redirect to proper payment flow
//
// USAGE:
// - Call PaymentBlocker.block() to throw error with redirect message
// - Use in Views and Services that previously had direct payment code
//
// Created: 2026-01-22
// Security Audit Fix

import 'package:flutter/foundation.dart';

/// Error thrown when code attempts to bypass PaymentIntentService
class PaymentBlockedError extends Error {
  final String operation;
  final String location;

  PaymentBlockedError(this.operation, this.location);

  @override
  String toString() =>
      'PaymentBlockedError: $operation blocked in $location. '
      'Use PaymentIntentService.createIntent() → UnifiedPaymentPage instead.';
}

/// Utility class to block direct payment operations
class PaymentBlocker {
  /// Block direct payment operation and throw error
  /// 
  /// [operation] - Description of blocked operation (e.g., "insertExpense", "insertDebtPayment")
  /// [location] - File/class where the operation was attempted
  /// 
  /// Always throws [PaymentBlockedError]
  static Never block(String operation, String location) {
    debugPrint('🚫 PAYMENT BLOCKED: $operation in $location');
    debugPrint('   → Use PaymentIntentService.createIntent() → UnifiedPaymentPage');
    throw PaymentBlockedError(operation, location);
  }

  /// Check if a financial operation should be blocked
  /// Returns true if the operation is a payment that should use PaymentIntent
  static bool shouldBlock(String category) {
    // These categories should go through PaymentIntent flow
    const blockedCategories = [
      'NHẬP HÀNG',
      'PURCHASE',
      'THANH TOÁN CÔNG NỢ',
      'THANH TOÁN BỔ SUNG',
      'ĐIỀU CHỈNH TĂNG',
      'ĐIỀU CHỈNH GIẢM',
      'NHẬP LINH KIỆN',
    ];
    return blockedCategories.contains(category.toUpperCase());
  }
}
