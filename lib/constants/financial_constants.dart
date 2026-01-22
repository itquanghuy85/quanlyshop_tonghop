// Financial Constants - Centralized enums and constants for money operations
//
// PURPOSE:
// - Eliminate scattered string literals throughout the app
// - Single source of truth for all financial types
// - Type-safe money operations
//
// RULES:
// - Contains ONLY enums and constants
// - Does NOT contain business logic
// - Does NOT depend on any service
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 2 - Enum & Constants)

// ============================================================================
// PAYMENT METHOD
// ============================================================================

/// Payment methods used throughout the app
enum PaymentMethod {
  cash('TIỀN MẶT', 'Tiền mặt'),
  transfer('CHUYỂN KHOẢN', 'Chuyển khoản'),
  debt('CÔNG NỢ', 'Công nợ'),
  installment('TRẢ GÓP', 'Trả góp'),
  mixed('KẾT HỢP', 'Kết hợp'),
  bank('NGÂN HÀNG', 'Ngân hàng');

  final String code;
  final String displayName;

  const PaymentMethod(this.code, this.displayName);

  /// Get enum from string code (case-insensitive)
  static PaymentMethod fromCode(String? code) {
    if (code == null || code.isEmpty) return PaymentMethod.cash;
    final upperCode = code.toUpperCase().trim();
    return PaymentMethod.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => PaymentMethod.cash,
    );
  }

  /// Check if this payment affects cash balance
  bool get affectsCash => this == PaymentMethod.cash || this == PaymentMethod.mixed;

  /// Check if this payment affects bank balance
  bool get affectsBank =>
      this == PaymentMethod.transfer ||
      this == PaymentMethod.bank ||
      this == PaymentMethod.mixed;

  /// Check if this creates debt
  bool get createsDebt => this == PaymentMethod.debt || this == PaymentMethod.installment;
}

// ============================================================================
// MONEY SOURCE TYPE
// ============================================================================

/// Source of money movement (where money comes from or goes to)
enum MoneySourceType {
  // Income sources (IN)
  sale('SALE', 'Bán hàng', MoneyDirection.income),
  debtCollection('DEBT_COLLECT', 'Thu nợ khách', MoneyDirection.income),
  settlement('SETTLEMENT', 'Tất toán ngân hàng', MoneyDirection.income),
  refundReceived('REFUND_RECEIVED', 'Nhận hoàn tiền', MoneyDirection.income),
  otherIncome('OTHER_IN', 'Thu khác', MoneyDirection.income),

  // Expense sources (OUT)
  purchase('PURCHASE', 'Nhập hàng', MoneyDirection.expense),
  expense('EXPENSE', 'Chi phí', MoneyDirection.expense),
  debtPayment('DEBT_PAY', 'Trả nợ NCC', MoneyDirection.expense),
  salary('SALARY', 'Trả lương', MoneyDirection.expense),
  refundGiven('REFUND_GIVEN', 'Hoàn tiền khách', MoneyDirection.expense),
  otherExpense('OTHER_OUT', 'Chi khác', MoneyDirection.expense),

  // Adjustment (can be either)
  adjustment('ADJUSTMENT', 'Điều chỉnh', MoneyDirection.adjustment);

  final String code;
  final String displayName;
  final MoneyDirection defaultDirection;

  const MoneySourceType(this.code, this.displayName, this.defaultDirection);

  /// Get enum from string code
  static MoneySourceType fromCode(String? code) {
    if (code == null || code.isEmpty) return MoneySourceType.otherIncome;
    final upperCode = code.toUpperCase().trim();
    return MoneySourceType.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => MoneySourceType.otherIncome,
    );
  }

  /// Check if this is an income type
  bool get isIncome => defaultDirection == MoneyDirection.income;

  /// Check if this is an expense type
  bool get isExpense => defaultDirection == MoneyDirection.expense;
}

// ============================================================================
// MONEY DIRECTION
// ============================================================================

/// Direction of money flow
enum MoneyDirection {
  income('IN', 'Thu'),
  expense('OUT', 'Chi'),
  adjustment('ADJ', 'Điều chỉnh');

  final String code;
  final String displayName;

  const MoneyDirection(this.code, this.displayName);

  /// Get enum from string code
  static MoneyDirection fromCode(String? code) {
    if (code == null || code.isEmpty) return MoneyDirection.income;
    final upperCode = code.toUpperCase().trim();
    if (upperCode == 'IN' || upperCode == 'INCOME') return MoneyDirection.income;
    if (upperCode == 'OUT' || upperCode == 'EXPENSE') return MoneyDirection.expense;
    return MoneyDirection.adjustment;
  }
}

// ============================================================================
// MONEY TRANSACTION TYPE
// ============================================================================

/// Types of financial transactions
enum MoneyTransactionType {
  // Sales
  sale('SALE', 'Bán hàng'),
  saleInstallment('SALE_INSTALLMENT', 'Bán trả góp'),
  saleDebt('SALE_DEBT', 'Bán công nợ'),

  // Purchases
  purchase('PURCHASE', 'Nhập hàng'),
  purchaseDebt('PURCHASE_DEBT', 'Nhập hàng công nợ'),

  // Expenses
  expense('EXPENSE', 'Chi phí'),
  salary('SALARY', 'Trả lương'),

  // Debt operations
  debtCollect('DEBT_COLLECT', 'Thu nợ khách'),
  debtPay('DEBT_PAY', 'Trả nợ NCC'),

  // Bank operations
  settlement('SETTLEMENT', 'Tất toán NH'),
  bankDeposit('BANK_DEPOSIT', 'Nộp tiền vào NH'),
  bankWithdraw('BANK_WITHDRAW', 'Rút tiền từ NH'),

  // Refunds
  refundToCustomer('REFUND_TO_CUSTOMER', 'Hoàn tiền khách'),
  refundFromSupplier('REFUND_FROM_SUPPLIER', 'Nhận hoàn từ NCC'),

  // Adjustments
  adjustment('ADJUSTMENT', 'Điều chỉnh'),
  opening('OPENING', 'Số dư đầu kỳ'),
  closing('CLOSING', 'Số dư cuối kỳ');

  final String code;
  final String displayName;

  const MoneyTransactionType(this.code, this.displayName);

  /// Get enum from string code
  static MoneyTransactionType fromCode(String? code) {
    if (code == null || code.isEmpty) return MoneyTransactionType.adjustment;
    final upperCode = code.toUpperCase().trim();
    return MoneyTransactionType.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => MoneyTransactionType.adjustment,
    );
  }
}

// ============================================================================
// DEBT TYPE
// ============================================================================

/// Types of debt
enum DebtType {
  /// Customer owes shop (receivable - phải thu)
  customerOwes('CUSTOMER_OWES', 'Khách nợ shop'),

  /// Shop owes supplier (payable - phải trả)
  shopOwes('SHOP_OWES', 'Shop nợ NCC'),

  /// Other receivable
  otherReceivable('OTHER_CUSTOMER_OWES', 'Phải thu khác'),

  /// Other payable
  otherPayable('OTHER_SHOP_OWES', 'Phải trả khác'),

  /// Legacy: OWE (customer owes) - for backward compatibility
  legacyOwe('OWE', 'Nợ (cũ)'),

  /// Legacy: OWED (shop owes) - for backward compatibility
  legacyOwed('OWED', 'Bị nợ (cũ)');

  final String code;
  final String displayName;

  const DebtType(this.code, this.displayName);

  /// Get enum from string code
  static DebtType fromCode(String? code) {
    if (code == null || code.isEmpty) return DebtType.customerOwes;
    final upperCode = code.toUpperCase().trim();
    return DebtType.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => DebtType.customerOwes,
    );
  }

  /// Check if this is a receivable (customer owes shop)
  bool get isReceivable =>
      this == DebtType.customerOwes ||
      this == DebtType.otherReceivable ||
      this == DebtType.legacyOwe;

  /// Check if this is a payable (shop owes someone)
  bool get isPayable =>
      this == DebtType.shopOwes ||
      this == DebtType.otherPayable ||
      this == DebtType.legacyOwed;

  /// Convert legacy types to new types
  DebtType toModernType() {
    switch (this) {
      case DebtType.legacyOwe:
        return DebtType.customerOwes;
      case DebtType.legacyOwed:
        return DebtType.shopOwes;
      default:
        return this;
    }
  }
}

// ============================================================================
// DEBT STATUS
// ============================================================================

/// Status of a debt
enum DebtStatus {
  active('ACTIVE', 'Còn nợ'),
  paid('PAID', 'Đã thanh toán'),
  cancelled('CANCELLED', 'Đã hủy'),
  overdue('OVERDUE', 'Quá hạn');

  final String code;
  final String displayName;

  const DebtStatus(this.code, this.displayName);

  /// Get enum from string code
  static DebtStatus fromCode(String? code) {
    if (code == null || code.isEmpty) return DebtStatus.active;
    final upperCode = code.toUpperCase().trim();
    // Handle legacy 'UNPAID' as 'ACTIVE'
    if (upperCode == 'UNPAID') return DebtStatus.active;
    return DebtStatus.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => DebtStatus.active,
    );
  }

  /// Check if debt can accept payment
  bool get canAcceptPayment => this == DebtStatus.active || this == DebtStatus.overdue;
}

// ============================================================================
// EXPENSE CATEGORY
// ============================================================================

/// Categories for expenses
enum ExpenseCategory {
  rent('RENT', 'Thuê mặt bằng'),
  utilities('UTILITIES', 'Điện/Nước/Internet'),
  salary('SALARY', 'Lương nhân viên'),
  supplies('SUPPLIES', 'Vật tư/Linh kiện'),
  equipment('EQUIPMENT', 'Thiết bị'),
  marketing('MARKETING', 'Marketing/Quảng cáo'),
  transport('TRANSPORT', 'Vận chuyển'),
  maintenance('MAINTENANCE', 'Bảo trì/Sửa chữa'),
  tax('TAX', 'Thuế/Phí'),
  other('OTHER', 'Chi phí khác');

  final String code;
  final String displayName;

  const ExpenseCategory(this.code, this.displayName);

  /// Get enum from string code
  static ExpenseCategory fromCode(String? code) {
    if (code == null || code.isEmpty) return ExpenseCategory.other;
    final upperCode = code.toUpperCase().trim();
    return ExpenseCategory.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => ExpenseCategory.other,
    );
  }
}

// ============================================================================
// REFERENCE TYPE (for linking transactions)
// ============================================================================

/// Types of references for financial activities
enum FinancialReferenceType {
  sale('sale', 'Đơn bán hàng'),
  repair('repair', 'Đơn sửa chữa'),
  expense('expense', 'Chi phí'),
  debt('debt', 'Công nợ'),
  debtPayment('debt_payment', 'Thanh toán nợ'),
  supplierPayment('supplier_payment', 'Thanh toán NCC'),
  purchaseOrder('purchase_order', 'Đơn nhập hàng'),
  product('product', 'Sản phẩm'),
  attendance('attendance', 'Chấm công'),
  salarySlip('salary_slip', 'Phiếu lương');

  final String code;
  final String displayName;

  const FinancialReferenceType(this.code, this.displayName);

  /// Get enum from string code
  static FinancialReferenceType fromCode(String? code) {
    if (code == null || code.isEmpty) return FinancialReferenceType.sale;
    final lowerCode = code.toLowerCase().trim();
    return FinancialReferenceType.values.firstWhere(
      (e) => e.code == lowerCode,
      orElse: () => FinancialReferenceType.sale,
    );
  }
}

// ============================================================================
// FINANCIAL CONSTANTS
// ============================================================================

/// Financial system constants
class FinancialConstants {
  FinancialConstants._(); // Private constructor - cannot instantiate

  /// Maximum allowed amount (999 billion VND)
  static const int maxAmount = 999999999999;

  /// Minimum positive amount (1 VND)
  static const int minPositiveAmount = 1;

  /// Default currency code
  static const String currencyCode = 'VND';

  /// Default locale for formatting
  static const String locale = 'vi_VN';

  /// Thousand separator
  static const String thousandSeparator = '.';

  /// Decimal separator (not used for VND)
  static const String decimalSeparator = ',';

  /// Default payment method
  static const PaymentMethod defaultPaymentMethod = PaymentMethod.cash;

  /// Default debt type for customer debts
  static const DebtType defaultCustomerDebtType = DebtType.customerOwes;

  /// Default debt type for supplier debts
  static const DebtType defaultSupplierDebtType = DebtType.shopOwes;

  /// Default debt status
  static const DebtStatus defaultDebtStatus = DebtStatus.active;

  /// Default expense category
  static const ExpenseCategory defaultExpenseCategory = ExpenseCategory.other;
}

// ============================================================================
// MONEY VALIDATION ERROR CODE (MAPPING WITH PHASE 1)
// ============================================================================
// Note: MoneyValidationErrorCode is defined in money_validation_service.dart
// This section provides helper extensions for error code categorization
// DO NOT DUPLICATE the enum - import from money_validation_service.dart

/// Extension to categorize error codes by domain
/// Usage: Import MoneyValidationErrorCode from money_validation_service.dart
/// then use these extensions for categorization
extension MoneyValidationErrorCodeCategory on int {
  /// Check if error code is amount-related (1xx)
  bool get isAmountError => this >= 100 && this < 200;

  /// Check if error code is sale-related (2xx)
  bool get isSaleError => this >= 200 && this < 300;

  /// Check if error code is debt-related (3xx)
  bool get isDebtError => this >= 300 && this < 400;

  /// Check if error code is stock-related (4xx)
  bool get isStockError => this >= 400 && this < 500;

  /// Check if error code is expense-related (5xx)
  bool get isExpenseError => this >= 500 && this < 600;

  /// Check if error code is refund-related (6xx)
  bool get isRefundError => this >= 600 && this < 700;
}

// ============================================================================
// ERROR CODE MAPPING TABLE (Reference only - actual enum in Phase 1)
// ============================================================================
// Amount errors (1xx):
//   101 - amountNegative
//   102 - amountZero
//   103 - amountExceedsMax
//   104 - amountInvalid
//
// Sale errors (2xx):
//   201 - salePriceZero
//   202 - saleCostNegative
//   203 - saleDiscountExceedsPrice
//   204 - saleProductOutOfStock
//   205 - saleQuantityExceedsStock
//   206 - saleDownPaymentExceedsTotal
//   207 - saleLoanAmountInvalid
//
// Debt errors (3xx):
//   301 - debtPaymentExceedsRemaining
//   302 - debtPaymentZero
//   303 - debtAlreadyPaid
//   304 - debtAmountNegative
//
// Stock errors (4xx):
//   401 - stockQuantityNegative
//   402 - stockInsufficientQuantity
//
// Expense errors (5xx):
//   501 - expenseAmountZero
//
// Refund errors (6xx):
//   601 - refundExceedsOriginal
