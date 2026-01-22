# UNIFIED PAYMENT FLOW - Refactoring Plan

## Overview

This document outlines the plan to unify ALL payment flows into a single, centralized system using `PaymentIntent` and the `UnifiedPaymentPage`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          BUSINESS MODULES                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Debt View    │  │ Sale View    │  │ Repair View  │  │ Expense View │    │
│  │              │  │              │  │              │  │              │    │
│  │ Creates      │  │ Creates      │  │ Creates      │  │ Creates      │    │
│  │ PaymentIntent│  │ PaymentIntent│  │ PaymentIntent│  │ PaymentIntent│    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │
│         │                 │                 │                 │            │
│         └────────────────┬┴─────────────────┴─────────────────┘            │
│                          │                                                  │
│                          ▼                                                  │
│           ┌──────────────────────────────┐                                  │
│           │   UnifiedPaymentPage (UI)    │  ◄── ONLY UI that writes money  │
│           │   - Display payment info     │                                  │
│           │   - Select payment method    │                                  │
│           │   - Confirm action           │                                  │
│           └──────────────┬───────────────┘                                  │
│                          │                                                  │
│                          ▼                                                  │
│           ┌──────────────────────────────┐                                  │
│           │   PaymentIntentService       │  ◄── ONLY service that executes │
│           │   - Validate via MVS         │                                  │
│           │   - Execute payment          │                                  │
│           │   - Record to ledger via MTS │                                  │
│           └──────────────┬───────────────┘                                  │
│                          │                                                  │
│         ┌────────────────┼────────────────┐                                 │
│         ▼                ▼                ▼                                 │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐                             │
│   │ MVS      │    │ MTS      │    │ DBHelper │                             │
│   │ Validate │    │ Ledger   │    │ Update   │                             │
│   └──────────┘    └──────────┘    └──────────┘                             │
│                                                                             │
│   MVS = MoneyValidationService                                              │
│   MTS = MoneyTransactionService                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## PaymentIntent Data Structure

```dart
class PaymentIntent {
  String id;                    // Unique identifier
  PaymentIntentType type;       // Type of payment
  int amount;                   // Amount (always positive)
  PaymentIntentStatus status;   // PENDING, COMPLETED, CANCELLED, FAILED
  PaymentMethod? paymentMethod; // Selected payment method
  String description;           // Description
  String? referenceId;          // Reference to source entity
  String? referenceType;        // Type of reference
  String? personName;           // Person involved
  String? personPhone;          // Phone number
  String? notes;                // Additional notes
  String createdBy;             // Creator
  int createdAt;                // Creation timestamp
  String? paidBy;               // Executor
  int? paidAt;                  // Execution timestamp
  String? ledgerEntryId;        // Ledger entry ID
  Map<String, dynamic>? metadata; // Additional data
}
```

---

## PaymentIntentType (All Payment Cases)

| Type | Code | Description |
|------|------|-------------|
| Supplier Debt | `SUPPLIER_DEBT` | Trả nợ NCC |
| Supplier Purchase | `SUPPLIER_PURCHASE` | Thanh toán nhập hàng |
| Customer Debt Collection | `CUSTOMER_DEBT_COLLECT` | Thu nợ khách |
| Customer Refund | `CUSTOMER_REFUND` | Hoàn tiền khách |
| Repair Service | `REPAIR_SERVICE` | Thanh toán sửa chữa |
| Repair Partner Debt | `REPAIR_PARTNER_DEBT` | Trả nợ đối tác sửa chữa |
| Sale Payment | `SALE_PAYMENT` | Thanh toán bán hàng |
| Sale Installment | `SALE_INSTALLMENT` | Thanh toán trả góp |
| Inventory Purchase | `INVENTORY_PURCHASE` | Thanh toán nhập kho |
| Parts Stock In | `PARTS_STOCK_IN` | Thanh toán nhập linh kiện |
| Operating Expense | `OPERATING_EXPENSE` | Chi phí vận hành |
| Utility Expense | `UTILITY_EXPENSE` | Chi phí tiện ích |
| Salary Payment | `SALARY_PAYMENT` | Trả lương nhân viên |
| Bonus Payment | `BONUS_PAYMENT` | Thưởng nhân viên |
| Other Debt | `OTHER_DEBT` | Nợ khác |
| Other Expense | `OTHER_EXPENSE` | Chi phí khác |
| Other Income | `OTHER_INCOME` | Thu nhập khác |

---

## Files Created

| File | Purpose |
|------|---------|
| `lib/models/payment_intent_model.dart` | PaymentIntent data structure |
| `lib/services/payment_intent_service.dart` | Central payment execution service |
| `lib/views/unified_payment_page.dart` | Unified Payment Page UI |

---

## Refactoring Plan - Old Payment Logic to Remove

### HIGH PRIORITY - Direct DB Writes (MUST FIX)

These locations write money directly to the database and MUST be refactored to use PaymentIntent.

| File | Line | Current Code | Action |
|------|------|--------------|--------|
| `debt_view.dart` | 444 | `await db.insertDebtPayment(paymentData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `debt_view.dart` | 492 | `await db.insertDebtPayment(paymentData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `supplier_detail_view.dart` | 349 | `await _db.insertDebtPayment(paymentData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `supplier_list_view.dart` | 964 | `await _db.insertDebtPayment(paymentData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `expense_view.dart` | 502 | `await db.insertExpense(expData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `create_purchase_order_view.dart` | 230 | `await db.insertExpense(exp)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `create_purchase_order_view.dart` | 641 | `await db.insertExpense(expense)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `fast_stock_in_view.dart` | 890 | `await db.insertExpense(exp)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `stock_in_view.dart` | 838 | `await db.insertExpense(expense)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `inventory_view.dart` | 2945 | `await db.insertExpense(expData)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `inventory_view.dart` | 3528 | `await db.insertExpense(exp)` | Replace with PaymentIntent → UnifiedPaymentPage |
| `parts_inventory_view.dart` | 1291 | `await db.insertExpense({...})` | Replace with PaymentIntent → UnifiedPaymentPage |
| `sale_detail_view.dart` | 350 | `await db.insertExpense(expData)` | Replace with PaymentIntent → UnifiedPaymentPage |

### MEDIUM PRIORITY - Debt Creation (Affects Money Flow)

| File | Line | Current Code | Action |
|------|------|--------------|--------|
| `debt_view.dart` | 1553, 1679, 1823 | `await db.insertDebt(newDebtData)` | Keep as debt creation, but payment via UnifiedPaymentPage |
| `repair_detail_view.dart` | 257, 688, 1969 | `await db.insertDebt(debtData)` | Keep as debt creation, but payment via UnifiedPaymentPage |
| `inventory_view.dart` | 2967 | `await db.insertDebt(debtData)` | Keep as debt creation, but payment via UnifiedPaymentPage |
| `parts_inventory_view.dart` | 1260 | `await db.insertDebt({...})` | Keep as debt creation, but payment via UnifiedPaymentPage |
| `create_sale_view.dart` | 958 | `await db.insertDebt(debtDataForTransaction)` | Keep as debt creation, but payment via UnifiedPaymentPage |
| `sale_detail_view.dart` | 600 | `await db.insertDebt(newDebt)` | Keep as debt creation, but payment via UnifiedPaymentPage |

---

## Migration Strategy

### Phase 1: Non-Breaking Introduction (Current)
- ✅ Create PaymentIntent model
- ✅ Create PaymentIntentService
- ✅ Create UnifiedPaymentPage
- ✅ Document refactoring plan

### Phase 2: New Flows Use Unified System
- New payment flows MUST use PaymentIntent + UnifiedPaymentPage
- Existing flows continue to work (but are marked as legacy)

### Phase 3: Gradual Migration
- Migrate one module at a time
- Start with lowest-risk modules (e.g., expense_view.dart)
- Test thoroughly before moving to next module

### Phase 4: Deprecate Old Flows
- Add deprecation warnings to old payment methods
- Log all direct DB writes for monitoring

### Phase 5: Remove Old Logic
- Remove deprecated payment logic
- All payments go through UnifiedPaymentPage

---

## Example Migration: expense_view.dart

### BEFORE (Direct DB Write)
```dart
// In expense_view.dart line 502
final expenseId = await db.insertExpense(expData);
```

### AFTER (PaymentIntent Flow)
```dart
// Create PaymentIntent
final intent = PaymentIntentFactory.forOperatingExpense(
  amount: amount,
  description: note,
  createdBy: userName,
);

// Navigate to UnifiedPaymentPage
final result = await UnifiedPaymentPage.navigateWithIntent(context, intent);

// Handle result
if (result != null && result.success) {
  // Payment completed successfully
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Đã ghi nhận chi phí')),
  );
}
```

---

## Example Migration: debt_view.dart (Debt Payment)

### BEFORE (Direct DB Write)
```dart
// In debt_view.dart line 444
await db.insertDebtPayment(paymentData);
```

### AFTER (PaymentIntent Flow)
```dart
// Create PaymentIntent
final intent = PaymentIntentFactory.forSupplierDebt(
  debtId: debt.firestoreId!,
  amount: paymentAmount,
  supplierName: debt.personName,
  supplierPhone: debt.phone,
  createdBy: userName,
);

// Navigate to UnifiedPaymentPage
final result = await UnifiedPaymentPage.navigateWithIntent(context, intent);

// Handle result
if (result != null && result.success) {
  // Refresh debt list
  _loadDebts();
}
```

---

## Validation Rules

| Rule | Description |
|------|-------------|
| Single Execution | PaymentIntent can only be executed ONCE |
| Validation First | MoneyValidationService MUST pass before execution |
| Ledger Recording | All payments recorded via MoneyTransactionService |
| Status Transitions | PENDING → COMPLETED or PENDING → CANCELLED |

---

## Critical Bug Definition

> **Any payment that does not go through the centralized UnifiedPaymentPage is considered a CRITICAL FINANCIAL BUG.**

This includes:
- Direct `db.insertExpense()` calls from UI
- Direct `db.insertDebtPayment()` calls from UI
- Any money write outside PaymentIntentService

---

## Monitoring Checklist

After migration, verify:
- [ ] All payments appear in the ledger
- [ ] No duplicate payments
- [ ] No payments with missing ledger entries
- [ ] All PaymentIntent statuses are correct
- [ ] No direct DB writes in Views for money operations

---

## Files Summary

| Category | Files |
|----------|-------|
| **NEW (Created)** | |
| Model | `lib/models/payment_intent_model.dart` |
| Service | `lib/services/payment_intent_service.dart` |
| View | `lib/views/unified_payment_page.dart` |
| Doc | `DOCS/UNIFIED_PAYMENT_REFACTORING_PLAN.md` |
| **TO MIGRATE (24 locations)** | |
| High Priority | 13 direct expense/payment DB writes |
| Medium Priority | 11 debt creation locations (need payment routing) |

---

## Timeline Recommendation

| Week | Action |
|------|--------|
| Week 1 | Review and approve architecture |
| Week 2 | Migrate expense_view.dart (lowest risk) |
| Week 3 | Migrate debt_view.dart payment methods |
| Week 4 | Migrate supplier payment methods |
| Week 5 | Migrate inventory/parts payment methods |
| Week 6 | Migrate sale/repair payment methods |
| Week 7 | Testing and bug fixes |
| Week 8 | Remove deprecated code |

---

*Document created: 2026-01-22*
*Author: AI Assistant (Phase 6 - Unified Payment)*
