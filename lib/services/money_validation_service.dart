// MoneyValidationService - Centralized validation for ALL money-related operations
//
// RULES:
// - Contains ONLY validation logic
// - Does NOT read or write database
// - Does NOT depend on UI
// - All validation throws typed errors (MoneyValidationException)
//
// Usage: Call validation methods BEFORE any money operation.
// Any money logic outside this service is considered a CRITICAL BUG.
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 1 - Money Validation Centralization)

// ============================================================================
// VALIDATION ERROR CODES
// ============================================================================

/// Error codes for money validation failures
enum MoneyValidationErrorCode {
  // Amount errors (1xx)
  amountNegative, // 101: Amount cannot be negative
  amountZero, // 102: Amount must be greater than zero
  amountExceedsMax, // 103: Amount exceeds maximum allowed
  amountInvalid, // 104: Amount format is invalid

  // Sale errors (2xx)
  salePriceZero, // 201: Sale price must be greater than zero
  saleCostNegative, // 202: Sale cost cannot be negative
  saleDiscountExceedsPrice, // 203: Discount cannot exceed total price
  saleProductOutOfStock, // 204: Product is out of stock
  saleQuantityExceedsStock, // 205: Requested quantity exceeds available stock
  saleDownPaymentExceedsTotal, // 206: Down payment exceeds total price
  saleLoanAmountInvalid, // 207: Loan amount is invalid for installment sale

  // Debt errors (3xx)
  debtPaymentExceedsRemaining, // 301: Payment amount exceeds remaining debt
  debtPaymentZero, // 302: Debt payment must be greater than zero
  debtAlreadyPaid, // 303: Debt is already fully paid
  debtAmountNegative, // 304: Debt amount cannot be negative

  // Stock errors (4xx)
  stockQuantityNegative, // 401: Stock quantity cannot be negative
  stockInsufficientQuantity, // 402: Insufficient stock quantity

  // Expense errors (5xx)
  expenseAmountZero, // 501: Expense amount must be greater than zero

  // Refund errors (6xx)
  refundExceedsOriginal, // 601: Refund amount exceeds original payment
}

// ============================================================================
// VALIDATION EXCEPTION
// ============================================================================

/// Typed exception for money validation failures
class MoneyValidationException implements Exception {
  final MoneyValidationErrorCode code;
  final String message;
  final Map<String, dynamic>? context;

  const MoneyValidationException({
    required this.code,
    required this.message,
    this.context,
  });

  @override
  String toString() => 'MoneyValidationException[$code]: $message';

  /// Convert to user-friendly Vietnamese message
  String toUserMessage() {
    switch (code) {
      // Amount errors
      case MoneyValidationErrorCode.amountNegative:
        return 'Số tiền không được âm';
      case MoneyValidationErrorCode.amountZero:
        return 'Số tiền phải lớn hơn 0';
      case MoneyValidationErrorCode.amountExceedsMax:
        return 'Số tiền vượt quá giới hạn cho phép';
      case MoneyValidationErrorCode.amountInvalid:
        return 'Số tiền không hợp lệ';

      // Sale errors
      case MoneyValidationErrorCode.salePriceZero:
        return 'Giá bán phải lớn hơn 0';
      case MoneyValidationErrorCode.saleCostNegative:
        return 'Giá vốn không được âm';
      case MoneyValidationErrorCode.saleDiscountExceedsPrice:
        return 'Giảm giá không được vượt quá giá bán';
      case MoneyValidationErrorCode.saleProductOutOfStock:
        final productName = context?['productName'] ?? 'Sản phẩm';
        return '$productName đã hết hàng';
      case MoneyValidationErrorCode.saleQuantityExceedsStock:
        final productName = context?['productName'] ?? 'Sản phẩm';
        final available = context?['available'] ?? 0;
        return '$productName chỉ còn $available trong kho';
      case MoneyValidationErrorCode.saleDownPaymentExceedsTotal:
        return 'Tiền trả trước không được vượt quá tổng tiền';
      case MoneyValidationErrorCode.saleLoanAmountInvalid:
        return 'Số tiền vay ngân hàng không hợp lệ';

      // Debt errors
      case MoneyValidationErrorCode.debtPaymentExceedsRemaining:
        final remaining = context?['remaining'] ?? 0;
        return 'Số tiền thanh toán vượt quá công nợ còn lại ($remaining)';
      case MoneyValidationErrorCode.debtPaymentZero:
        return 'Số tiền thanh toán phải lớn hơn 0';
      case MoneyValidationErrorCode.debtAlreadyPaid:
        return 'Công nợ này đã được thanh toán đủ';
      case MoneyValidationErrorCode.debtAmountNegative:
        return 'Số tiền công nợ không được âm';

      // Stock errors
      case MoneyValidationErrorCode.stockQuantityNegative:
        return 'Số lượng tồn kho không được âm';
      case MoneyValidationErrorCode.stockInsufficientQuantity:
        return 'Số lượng tồn kho không đủ';

      // Expense errors
      case MoneyValidationErrorCode.expenseAmountZero:
        return 'Số tiền chi phí phải lớn hơn 0';

      // Refund errors
      case MoneyValidationErrorCode.refundExceedsOriginal:
        return 'Số tiền hoàn trả vượt quá số tiền gốc';
    }
  }
}

// ============================================================================
// VALIDATION RESULT
// ============================================================================

/// Result wrapper for validation - use when you don't want to throw
class MoneyValidationResult {
  final bool isValid;
  final MoneyValidationException? error;

  const MoneyValidationResult._({
    required this.isValid,
    this.error,
  });

  factory MoneyValidationResult.valid() =>
      const MoneyValidationResult._(isValid: true);

  factory MoneyValidationResult.invalid(MoneyValidationException error) =>
      MoneyValidationResult._(isValid: false, error: error);

  /// Throw if invalid, do nothing if valid
  void throwIfInvalid() {
    if (!isValid && error != null) {
      throw error!;
    }
  }
}

// ============================================================================
// MONEY VALIDATION SERVICE
// ============================================================================

/// Centralized service for ALL money validation
///
/// IMPORTANT: This service contains ONLY validation logic.
/// - Does NOT read database
/// - Does NOT write database
/// - Does NOT depend on UI
///
/// All methods validate input data and either:
/// - Return MoneyValidationResult (for soft validation)
/// - Throw MoneyValidationException (for strict validation)
class MoneyValidationService {
  // ---------------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------------

  /// Maximum allowed amount (999 billion VND)
  static const int maxAmount = 999999999999;

  /// Minimum valid amount (1 VND)
  static const int minPositiveAmount = 1;

  // ---------------------------------------------------------------------------
  // AMOUNT VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate a money amount
  ///
  /// [amount] - The amount to validate
  /// [allowZero] - If true, zero is valid (default: false)
  /// [allowNegative] - If true, negative is valid (default: false)
  /// [maxValue] - Custom maximum value (default: maxAmount)
  ///
  /// Throws [MoneyValidationException] if invalid
  static void validateAmount(
    int amount, {
    bool allowZero = false,
    bool allowNegative = false,
    int? maxValue,
  }) {
    final max = maxValue ?? maxAmount;

    if (!allowNegative && amount < 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.amountNegative,
        message: 'Amount $amount is negative',
        context: {'amount': amount},
      );
    }

    if (!allowZero && amount == 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.amountZero,
        message: 'Amount cannot be zero',
        context: {'amount': amount},
      );
    }

    if (amount > max) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.amountExceedsMax,
        message: 'Amount $amount exceeds maximum $max',
        context: {'amount': amount, 'max': max},
      );
    }
  }

  /// Validate amount and return result (non-throwing version)
  static MoneyValidationResult validateAmountResult(
    int amount, {
    bool allowZero = false,
    bool allowNegative = false,
    int? maxValue,
  }) {
    try {
      validateAmount(
        amount,
        allowZero: allowZero,
        allowNegative: allowNegative,
        maxValue: maxValue,
      );
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  // ---------------------------------------------------------------------------
  // SALE VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate a sale transaction
  ///
  /// [totalPrice] - Total sale price (required > 0)
  /// [totalCost] - Total cost of goods (required >= 0)
  /// [discount] - Discount amount (must not exceed totalPrice)
  /// [products] - List of products with {name, requestedQty, availableQty}
  /// [isInstallment] - Whether this is an installment sale
  /// [downPayment] - Down payment for installment sales
  /// [loanAmount] - Loan amount from bank
  /// [loanAmount2] - Second loan amount (if applicable)
  ///
  /// Throws [MoneyValidationException] if any validation fails
  static void validateSale({
    required int totalPrice,
    required int totalCost,
    int discount = 0,
    List<SaleProductValidation>? products,
    bool isInstallment = false,
    int downPayment = 0,
    int loanAmount = 0,
    int loanAmount2 = 0,
  }) {
    // 1. Validate total price (must be > 0)
    if (totalPrice <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.salePriceZero,
        message: 'Total price must be greater than 0',
        context: {'totalPrice': totalPrice},
      );
    }

    // 2. Validate total cost (must be >= 0)
    if (totalCost < 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleCostNegative,
        message: 'Total cost cannot be negative',
        context: {'totalCost': totalCost},
      );
    }

    // 3. Validate discount (must not exceed total price)
    if (discount < 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.amountNegative,
        message: 'Discount cannot be negative',
        context: {'discount': discount},
      );
    }

    if (discount > totalPrice) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleDiscountExceedsPrice,
        message: 'Discount $discount exceeds total price $totalPrice',
        context: {'discount': discount, 'totalPrice': totalPrice},
      );
    }

    // 4. Validate products stock
    if (products != null) {
      for (final product in products) {
        _validateProductStock(product);
      }
    }

    // 5. Validate installment fields
    if (isInstallment) {
      _validateInstallmentSale(
        totalPrice: totalPrice,
        discount: discount,
        downPayment: downPayment,
        loanAmount: loanAmount,
        loanAmount2: loanAmount2,
      );
    }
  }

  /// Validate a sale and return result (non-throwing version)
  static MoneyValidationResult validateSaleResult({
    required int totalPrice,
    required int totalCost,
    int discount = 0,
    List<SaleProductValidation>? products,
    bool isInstallment = false,
    int downPayment = 0,
    int loanAmount = 0,
    int loanAmount2 = 0,
  }) {
    try {
      validateSale(
        totalPrice: totalPrice,
        totalCost: totalCost,
        discount: discount,
        products: products,
        isInstallment: isInstallment,
        downPayment: downPayment,
        loanAmount: loanAmount,
        loanAmount2: loanAmount2,
      );
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  /// Internal: Validate product stock for sale
  static void _validateProductStock(SaleProductValidation product) {
    if (product.availableQuantity <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleProductOutOfStock,
        message: 'Product ${product.name} is out of stock',
        context: {
          'productName': product.name,
          'productId': product.id,
          'available': product.availableQuantity,
        },
      );
    }

    if (product.requestedQuantity > product.availableQuantity) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleQuantityExceedsStock,
        message:
            'Requested ${product.requestedQuantity} but only ${product.availableQuantity} available',
        context: {
          'productName': product.name,
          'productId': product.id,
          'requested': product.requestedQuantity,
          'available': product.availableQuantity,
        },
      );
    }
  }

  /// Internal: Validate installment sale fields
  static void _validateInstallmentSale({
    required int totalPrice,
    required int discount,
    required int downPayment,
    required int loanAmount,
    required int loanAmount2,
  }) {
    final finalPrice = totalPrice - discount;

    // Down payment cannot exceed final price
    if (downPayment > finalPrice) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleDownPaymentExceedsTotal,
        message: 'Down payment $downPayment exceeds final price $finalPrice',
        context: {
          'downPayment': downPayment,
          'finalPrice': finalPrice,
        },
      );
    }

    // Validate loan amounts
    if (loanAmount < 0 || loanAmount2 < 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleLoanAmountInvalid,
        message: 'Loan amount cannot be negative',
        context: {
          'loanAmount': loanAmount,
          'loanAmount2': loanAmount2,
        },
      );
    }

    // Total of down payment + loans should not exceed final price unreasonably
    // Note: In reality, loans can exceed (bank pays more), but we validate basic logic
    final totalReceived = downPayment + loanAmount + loanAmount2;
    if (totalReceived > finalPrice * 2) {
      // Allow some tolerance for bank fees, but not excessive
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.saleLoanAmountInvalid,
        message:
            'Total received ($totalReceived) is unreasonably high for price $finalPrice',
        context: {
          'downPayment': downPayment,
          'loanAmount': loanAmount,
          'loanAmount2': loanAmount2,
          'totalReceived': totalReceived,
          'finalPrice': finalPrice,
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // DEBT PAYMENT VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate a debt payment
  ///
  /// [paymentAmount] - Amount being paid
  /// [totalDebt] - Original total debt amount
  /// [alreadyPaid] - Amount already paid towards this debt
  ///
  /// Throws [MoneyValidationException] if invalid
  static void validateDebtPayment({
    required int paymentAmount,
    required int totalDebt,
    required int alreadyPaid,
  }) {
    // Calculate remaining debt
    final remainingDebt = totalDebt - alreadyPaid;

    // 1. Payment must be > 0
    if (paymentAmount <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.debtPaymentZero,
        message: 'Payment amount must be greater than 0',
        context: {'paymentAmount': paymentAmount},
      );
    }

    // 2. Check if debt is already fully paid
    if (remainingDebt <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.debtAlreadyPaid,
        message: 'Debt is already fully paid',
        context: {
          'totalDebt': totalDebt,
          'alreadyPaid': alreadyPaid,
          'remaining': remainingDebt,
        },
      );
    }

    // 3. Payment cannot exceed remaining debt
    if (paymentAmount > remainingDebt) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.debtPaymentExceedsRemaining,
        message: 'Payment $paymentAmount exceeds remaining debt $remainingDebt',
        context: {
          'paymentAmount': paymentAmount,
          'totalDebt': totalDebt,
          'alreadyPaid': alreadyPaid,
          'remaining': remainingDebt,
        },
      );
    }
  }

  /// Validate debt payment and return result (non-throwing version)
  static MoneyValidationResult validateDebtPaymentResult({
    required int paymentAmount,
    required int totalDebt,
    required int alreadyPaid,
  }) {
    try {
      validateDebtPayment(
        paymentAmount: paymentAmount,
        totalDebt: totalDebt,
        alreadyPaid: alreadyPaid,
      );
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  // ---------------------------------------------------------------------------
  // DEBT CREATION VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate debt creation
  ///
  /// [totalAmount] - Total debt amount
  ///
  /// Throws [MoneyValidationException] if invalid
  static void validateDebtCreation({
    required int totalAmount,
  }) {
    if (totalAmount <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.debtAmountNegative,
        message: 'Debt amount must be greater than 0',
        context: {'totalAmount': totalAmount},
      );
    }

    validateAmount(totalAmount);
  }

  /// Validate debt creation and return result (non-throwing version)
  static MoneyValidationResult validateDebtCreationResult({
    required int totalAmount,
  }) {
    try {
      validateDebtCreation(totalAmount: totalAmount);
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  // ---------------------------------------------------------------------------
  // STOCK VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate stock quantity change
  ///
  /// [currentQuantity] - Current stock quantity
  /// [changeAmount] - Amount to change (negative for decrease)
  ///
  /// Throws [MoneyValidationException] if resulting quantity would be negative
  static void validateStockChange({
    required int currentQuantity,
    required int changeAmount,
  }) {
    final resultingQuantity = currentQuantity + changeAmount;

    if (resultingQuantity < 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.stockInsufficientQuantity,
        message:
            'Insufficient stock: current=$currentQuantity, change=$changeAmount',
        context: {
          'currentQuantity': currentQuantity,
          'changeAmount': changeAmount,
          'resultingQuantity': resultingQuantity,
        },
      );
    }
  }

  /// Validate stock change and return result (non-throwing version)
  static MoneyValidationResult validateStockChangeResult({
    required int currentQuantity,
    required int changeAmount,
  }) {
    try {
      validateStockChange(
        currentQuantity: currentQuantity,
        changeAmount: changeAmount,
      );
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  // ---------------------------------------------------------------------------
  // EXPENSE VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate expense amount
  ///
  /// [amount] - Expense amount (must be > 0)
  ///
  /// Throws [MoneyValidationException] if invalid
  static void validateExpense({
    required int amount,
  }) {
    if (amount <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.expenseAmountZero,
        message: 'Expense amount must be greater than 0',
        context: {'amount': amount},
      );
    }

    validateAmount(amount);
  }

  /// Validate expense and return result (non-throwing version)
  static MoneyValidationResult validateExpenseResult({
    required int amount,
  }) {
    try {
      validateExpense(amount: amount);
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }

  // ---------------------------------------------------------------------------
  // REFUND VALIDATION
  // ---------------------------------------------------------------------------

  /// Validate refund amount
  ///
  /// [refundAmount] - Amount to refund
  /// [originalAmount] - Original payment amount
  ///
  /// Throws [MoneyValidationException] if refund exceeds original
  static void validateRefund({
    required int refundAmount,
    required int originalAmount,
  }) {
    if (refundAmount <= 0) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.amountZero,
        message: 'Refund amount must be greater than 0',
        context: {'refundAmount': refundAmount},
      );
    }

    if (refundAmount > originalAmount) {
      throw MoneyValidationException(
        code: MoneyValidationErrorCode.refundExceedsOriginal,
        message:
            'Refund $refundAmount exceeds original payment $originalAmount',
        context: {
          'refundAmount': refundAmount,
          'originalAmount': originalAmount,
        },
      );
    }
  }

  /// Validate refund and return result (non-throwing version)
  static MoneyValidationResult validateRefundResult({
    required int refundAmount,
    required int originalAmount,
  }) {
    try {
      validateRefund(
        refundAmount: refundAmount,
        originalAmount: originalAmount,
      );
      return MoneyValidationResult.valid();
    } on MoneyValidationException catch (e) {
      return MoneyValidationResult.invalid(e);
    }
  }
}

// ============================================================================
// HELPER CLASSES
// ============================================================================

/// Product data required for sale validation
class SaleProductValidation {
  final String? id;
  final String name;
  final int requestedQuantity;
  final int availableQuantity;

  const SaleProductValidation({
    this.id,
    required this.name,
    required this.requestedQuantity,
    required this.availableQuantity,
  });

  /// Create from Product model data
  /// Use this when you have product data from database
  factory SaleProductValidation.fromProductData({
    required String? id,
    required String name,
    required int availableQuantity,
    int requestedQuantity = 1,
  }) {
    return SaleProductValidation(
      id: id,
      name: name,
      requestedQuantity: requestedQuantity,
      availableQuantity: availableQuantity,
    );
  }
}
