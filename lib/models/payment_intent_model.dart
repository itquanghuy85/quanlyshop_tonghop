// PaymentIntent Model - Central data structure for ALL payment requests
//
// PURPOSE:
// - Unify all payment flows into one single structure
// - Business modules create PaymentIntent, NOT execute payments
// - Only the Unified Payment Page can execute payments
//
// RULES:
// - PaymentIntent can only be paid ONCE
// - Status transitions: PENDING → COMPLETED or PENDING → CANCELLED
// - No direct DB write outside Payment Page
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 6 - Unified Payment)

import '../constants/financial_constants.dart';

/// Status of a PaymentIntent
enum PaymentIntentStatus {
  pending('PENDING', 'Chờ thanh toán'),
  completed('COMPLETED', 'Đã thanh toán'),
  cancelled('CANCELLED', 'Đã hủy'),
  failed('FAILED', 'Thất bại');

  final String code;
  final String displayName;

  const PaymentIntentStatus(this.code, this.displayName);

  static PaymentIntentStatus fromCode(String? code) {
    if (code == null || code.isEmpty) return PaymentIntentStatus.pending;
    final upperCode = code.toUpperCase().trim();
    return PaymentIntentStatus.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => PaymentIntentStatus.pending,
    );
  }
}

/// Type of payment (what is being paid for)
enum PaymentIntentType {
  // Supplier payments
  supplierDebt('SUPPLIER_DEBT', 'Trả nợ NCC'),
  supplierPurchase('SUPPLIER_PURCHASE', 'Thanh toán nhập hàng'),

  // Customer payments
  customerDebtCollection('CUSTOMER_DEBT_COLLECT', 'Thu nợ khách'),
  customerRefund('CUSTOMER_REFUND', 'Hoàn tiền khách'),

  // Repair payments
  repairService('REPAIR_SERVICE', 'Thanh toán sửa chữa'),
  repairPartnerDebt('REPAIR_PARTNER_DEBT', 'Trả nợ đối tác sửa chữa'),

  // Sales payments
  salePayment('SALE_PAYMENT', 'Thanh toán bán hàng'),
  saleInstallment('SALE_INSTALLMENT', 'Thanh toán trả góp'),

  // Inventory payments
  inventoryPurchase('INVENTORY_PURCHASE', 'Thanh toán nhập kho'),
  partsStockIn('PARTS_STOCK_IN', 'Thanh toán nhập linh kiện'),

  // Operating expenses
  operatingExpense('OPERATING_EXPENSE', 'Chi phí vận hành'),
  utilityExpense('UTILITY_EXPENSE', 'Chi phí tiện ích'),

  // Salary
  salaryPayment('SALARY_PAYMENT', 'Trả lương nhân viên'),
  bonusPayment('BONUS_PAYMENT', 'Thưởng nhân viên'),

  // Other
  otherDebt('OTHER_DEBT', 'Nợ khác'),
  otherExpense('OTHER_EXPENSE', 'Chi phí khác'),
  otherIncome('OTHER_INCOME', 'Thu nhập khác');

  final String code;
  final String displayName;

  const PaymentIntentType(this.code, this.displayName);

  static PaymentIntentType fromCode(String? code) {
    if (code == null || code.isEmpty) return PaymentIntentType.otherExpense;
    final upperCode = code.toUpperCase().trim();
    return PaymentIntentType.values.firstWhere(
      (e) => e.code == upperCode,
      orElse: () => PaymentIntentType.otherExpense,
    );
  }

  /// Get the money direction for this payment type
  MoneyDirection get direction {
    switch (this) {
      case PaymentIntentType.customerDebtCollection:
      case PaymentIntentType.salePayment:
      case PaymentIntentType.saleInstallment:
      case PaymentIntentType.repairService:
      case PaymentIntentType.otherIncome:
        return MoneyDirection.income;
      default:
        return MoneyDirection.expense;
    }
  }

  /// Check if this is an income type
  bool get isIncome => direction == MoneyDirection.income;

  /// Check if this is an expense type
  bool get isExpense => direction == MoneyDirection.expense;
}

/// Central data structure for ALL payment requests
///
/// Business modules create PaymentIntent objects and redirect to the
/// Unified Payment Page. Only the Payment Page can execute payments.
class PaymentIntent {
  /// Unique identifier for this payment intent
  final String id;

  /// Type of payment
  final PaymentIntentType type;

  /// Amount to be paid (always positive)
  final int amount;

  /// Current status of the payment intent
  PaymentIntentStatus status;

  /// Payment method selected (null until payment is executed)
  PaymentMethod? paymentMethod;

  /// Description of the payment
  final String description;

  /// Reference to the source entity (e.g., debt ID, sale ID, etc.)
  final String? referenceId;

  /// Type of the reference (e.g., 'debt', 'sale', 'expense')
  final String? referenceType;

  /// Person or entity involved (customer name, supplier name, etc.)
  final String? personName;

  /// Phone number of the person involved
  final String? personPhone;

  /// Additional notes
  String? notes;

  /// Who created this payment intent
  final String createdBy;

  /// When this payment intent was created
  final int createdAt;

  /// Who executed the payment (set when completed)
  String? paidBy;

  /// When the payment was executed (set when completed)
  int? paidAt;

  /// Ledger entry ID (set when payment is recorded)
  String? ledgerEntryId;

  /// Metadata for additional context (e.g., installment details)
  final Map<String, dynamic>? metadata;

  PaymentIntent({
    required this.id,
    required this.type,
    required this.amount,
    this.status = PaymentIntentStatus.pending,
    this.paymentMethod,
    required this.description,
    this.referenceId,
    this.referenceType,
    this.personName,
    this.personPhone,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    this.paidBy,
    this.paidAt,
    this.ledgerEntryId,
    this.metadata,
  });

  /// Check if this payment intent can be executed
  bool get canExecute => status == PaymentIntentStatus.pending;

  /// Check if this payment intent has been completed
  bool get isCompleted => status == PaymentIntentStatus.completed;

  /// Check if this payment intent has been cancelled
  bool get isCancelled => status == PaymentIntentStatus.cancelled;

  /// Get the money direction
  MoneyDirection get direction => type.direction;

  /// Check if this is an income payment
  bool get isIncome => type.isIncome;

  /// Check if this is an expense payment
  bool get isExpense => type.isExpense;

  /// Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.code,
      'amount': amount,
      'status': status.code,
      'paymentMethod': paymentMethod?.code,
      'description': description,
      'referenceId': referenceId,
      'referenceType': referenceType,
      'personName': personName,
      'personPhone': personPhone,
      'notes': notes,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'paidBy': paidBy,
      'paidAt': paidAt,
      'ledgerEntryId': ledgerEntryId,
      'metadata': metadata,
    };
  }

  /// Create from Map
  factory PaymentIntent.fromMap(Map<String, dynamic> map) {
    return PaymentIntent(
      id: map['id'] ?? '',
      type: PaymentIntentType.fromCode(map['type']),
      amount: map['amount'] ?? 0,
      status: PaymentIntentStatus.fromCode(map['status']),
      paymentMethod: map['paymentMethod'] != null
          ? PaymentMethod.fromCode(map['paymentMethod'])
          : null,
      description: map['description'] ?? '',
      referenceId: map['referenceId'],
      referenceType: map['referenceType'],
      personName: map['personName'],
      personPhone: map['personPhone'],
      notes: map['notes'],
      createdBy: map['createdBy'] ?? '',
      createdAt: map['createdAt'] ?? 0,
      paidBy: map['paidBy'],
      paidAt: map['paidAt'],
      ledgerEntryId: map['ledgerEntryId'],
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'])
          : null,
    );
  }

  /// Create a copy with updated fields
  PaymentIntent copyWith({
    String? id,
    PaymentIntentType? type,
    int? amount,
    PaymentIntentStatus? status,
    PaymentMethod? paymentMethod,
    String? description,
    String? referenceId,
    String? referenceType,
    String? personName,
    String? personPhone,
    String? notes,
    String? createdBy,
    int? createdAt,
    String? paidBy,
    int? paidAt,
    String? ledgerEntryId,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentIntent(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      description: description ?? this.description,
      referenceId: referenceId ?? this.referenceId,
      referenceType: referenceType ?? this.referenceType,
      personName: personName ?? this.personName,
      personPhone: personPhone ?? this.personPhone,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      paidBy: paidBy ?? this.paidBy,
      paidAt: paidAt ?? this.paidAt,
      ledgerEntryId: ledgerEntryId ?? this.ledgerEntryId,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'PaymentIntent(id: $id, type: ${type.code}, amount: $amount, status: ${status.code})';
  }
}

// ============================================================================
// FACTORY METHODS FOR COMMON PAYMENT INTENTS
// ============================================================================

/// Factory class to create PaymentIntent objects for different scenarios
class PaymentIntentFactory {
  /// Create a payment intent for supplier debt payment
  static PaymentIntent forSupplierDebt({
    required String debtId,
    required int amount,
    required String supplierName,
    String? supplierPhone,
    required String createdBy,
    String? notes,
  }) {
    return PaymentIntent(
      id: 'pi_supplier_debt_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.supplierDebt,
      amount: amount,
      description: 'Trả nợ NCC: $supplierName',
      referenceId: debtId,
      referenceType: 'debt',
      personName: supplierName,
      personPhone: supplierPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
    );
  }

  /// Create a payment intent for customer debt collection
  static PaymentIntent forCustomerDebtCollection({
    required String debtId,
    required int amount,
    required String customerName,
    String? customerPhone,
    required String createdBy,
    String? notes,
  }) {
    return PaymentIntent(
      id: 'pi_customer_debt_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.customerDebtCollection,
      amount: amount,
      description: 'Thu nợ từ: $customerName',
      referenceId: debtId,
      referenceType: 'debt',
      personName: customerName,
      personPhone: customerPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
    );
  }

  /// Create a payment intent for repair service
  static PaymentIntent forRepairService({
    required String repairId,
    required int amount,
    required String customerName,
    String? customerPhone,
    required String createdBy,
    String? notes,
  }) {
    return PaymentIntent(
      id: 'pi_repair_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.repairService,
      amount: amount,
      description: 'Thanh toán sửa chữa cho: $customerName',
      referenceId: repairId,
      referenceType: 'repair',
      personName: customerName,
      personPhone: customerPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
    );
  }

  /// Create a payment intent for sale payment
  static PaymentIntent forSalePayment({
    required String saleId,
    required int amount,
    required String customerName,
    String? customerPhone,
    required String createdBy,
    String? notes,
    bool isInstallment = false,
  }) {
    return PaymentIntent(
      id: 'pi_sale_${DateTime.now().millisecondsSinceEpoch}',
      type: isInstallment
          ? PaymentIntentType.saleInstallment
          : PaymentIntentType.salePayment,
      amount: amount,
      description: isInstallment
          ? 'Thanh toán trả góp từ: $customerName'
          : 'Thanh toán bán hàng từ: $customerName',
      referenceId: saleId,
      referenceType: 'sale',
      personName: customerName,
      personPhone: customerPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
      metadata: {'isInstallment': isInstallment},
    );
  }

  /// Create a payment intent for inventory purchase
  static PaymentIntent forInventoryPurchase({
    required String purchaseOrderId,
    required int amount,
    required String supplierName,
    String? supplierPhone,
    required String createdBy,
    String? notes,
  }) {
    return PaymentIntent(
      id: 'pi_inventory_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.inventoryPurchase,
      amount: amount,
      description: 'Thanh toán nhập hàng từ: $supplierName',
      referenceId: purchaseOrderId,
      referenceType: 'purchase_order',
      personName: supplierName,
      personPhone: supplierPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
    );
  }

  /// Create a payment intent for parts stock-in
  static PaymentIntent forPartsStockIn({
    required String stockInId,
    required int amount,
    required String supplierName,
    String? supplierPhone,
    required String createdBy,
    String? notes,
  }) {
    return PaymentIntent(
      id: 'pi_parts_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.partsStockIn,
      amount: amount,
      description: 'Thanh toán nhập linh kiện từ: $supplierName',
      referenceId: stockInId,
      referenceType: 'parts_stock_in',
      personName: supplierName,
      personPhone: supplierPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
    );
  }

  /// Create a payment intent for operating expense
  static PaymentIntent forOperatingExpense({
    required int amount,
    required String description,
    required String createdBy,
    String? notes,
    ExpenseCategory? category,
  }) {
    return PaymentIntent(
      id: 'pi_expense_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.operatingExpense,
      amount: amount,
      description: description,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
      metadata: category != null ? {'category': category.code} : null,
    );
  }

  /// Create a payment intent for salary payment
  static PaymentIntent forSalaryPayment({
    required String staffId,
    required int amount,
    required String staffName,
    required String createdBy,
    String? notes,
    String? period,
  }) {
    return PaymentIntent(
      id: 'pi_salary_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.salaryPayment,
      amount: amount,
      description: 'Trả lương: $staffName${period != null ? ' ($period)' : ''}',
      referenceId: staffId,
      referenceType: 'staff',
      personName: staffName,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
      metadata: period != null ? {'period': period} : null,
    );
  }

  /// Create a payment intent for customer refund
  static PaymentIntent forCustomerRefund({
    required String referenceId,
    required int amount,
    required String customerName,
    String? customerPhone,
    required String createdBy,
    String? notes,
    String? refundReason,
  }) {
    return PaymentIntent(
      id: 'pi_refund_${DateTime.now().millisecondsSinceEpoch}',
      type: PaymentIntentType.customerRefund,
      amount: amount,
      description: 'Hoàn tiền cho: $customerName',
      referenceId: referenceId,
      referenceType: 'refund',
      personName: customerName,
      personPhone: customerPhone,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      notes: notes,
      metadata: refundReason != null ? {'reason': refundReason} : null,
    );
  }
}
