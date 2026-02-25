# HULUCA Shop Manager — Complete Technical Documentation

> **App Name:** HULUCA Shop Manager (`quanlyshop`)
> **Package:** `com.huluca.shopmanager`
> **Version:** 10.1.0+172
> **Flutter SDK:** >=3.10.0 <4.0.0
> **Firebase Project:** huyaka-1809
> **Region:** asia-southeast1

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture & Patterns](#2-architecture--patterns)
3. [Entry Point — main.dart](#3-entry-point--maindart)
4. [Data Models (31 files)](#4-data-models-31-files)
5. [Services Layer (43 files, 65 classes)](#5-services-layer-43-files-65-classes)
6. [Views Layer (80+ files)](#6-views-layer-80-files)
7. [Widgets (28 files)](#7-widgets-28-files)
8. [Theme System](#8-theme-system)
9. [Constants](#9-constants)
10. [Utilities (12 files)](#10-utilities-12-files)
11. [Controllers](#11-controllers)
12. [Core Infrastructure](#12-core-infrastructure)
13. [Localization (i18n)](#13-localization-i18n)
14. [Local Database — SQLite](#14-local-database--sqlite)
15. [Firestore Rules](#15-firestore-rules)
16. [Firestore Indexes](#16-firestore-indexes)
17. [Cloud Functions](#17-cloud-functions)
18. [Firebase Configuration](#18-firebase-configuration)
19. [Dependencies](#19-dependencies)
20. [Multi-Industry Support](#20-multi-industry-support)
21. [Security & Encryption](#21-security--encryption)
22. [Sync Architecture](#22-sync-architecture)
23. [Navigation & Routing](#23-navigation--routing)
24. [Permission System](#24-permission-system)
25. [Payment System](#25-payment-system)

---

## 1. Project Overview

HULUCA Shop Manager is a **multi-tenant, offline-first, multi-industry** shop management application built with Flutter and Firebase. It manages:

- **Repair orders** — phone/electronics repair tracking with a 4-step status workflow
- **Sales & inventory** — POS, stock management, IMEI tracking, purchase orders
- **Financial management** — expenses, debts, cash closing, comprehensive financial reports
- **HR** — attendance, salary calculation with tiered commissions, insurance, PIT tax
- **Customer & supplier management** — CRM with spend/repair history
- **Real-time team chat** — text, image, file, reactions, mentions, read receipts
- **Thermal/Bluetooth/WiFi printer support** — receipts, labels, salary slips
- **QR code scanning** — IMEI extraction, product lookup
- **Multi-shop** support — single owner can manage multiple shops

### Key Architectural Decisions

| Decision | Implementation |
|----------|---------------|
| Multi-tenant isolation | `shopId` on every document, enforced in Firestore rules via Custom Claims |
| Offline-first | SQLite (`sqflite`) as primary data store, Firestore as cloud sync target |
| Role-based access | Custom Claims (`role`, `shopId`, `isSuperAdmin`) synced via Cloud Functions |
| Data encryption | AES-256-CBC encryption of sensitive fields before cloud upload |
| Conflict resolution | `updatedAt` timestamp comparison + `isSynced` flag; local changes always preserved |
| Soft deletes | `deleted: true` flag in Firestore; local DB marks deleted but retains records |
| Multi-industry | `businessType` field (electronics/food/fashion/general) with per-type feature flags |

---

## 2. Architecture & Patterns

```
+--------------------------------------------------+
|                    UI Layer                        |
|  lib/views/     lib/widgets/    lib/theme/         |
+--------------------------------------------------+
|                 Service Layer                      |
|  lib/services/  (43 files, 65 classes)             |
|  - FirestoreService (cloud CRUD)                   |
|  - SyncService (real-time sync)                    |
|  - UserService (auth, roles, permissions)          |
|  - PaymentIntentService (unified payments)         |
|  - NotificationService (FCM + local)               |
|  - EncryptionService (AES-256)                     |
|  - SyncOrchestrator (offline queue)                |
|  - ... and 36 more                                 |
+--------------------------------------------------+
|                Data Layer                          |
|  lib/data/db_helper.dart  (SQLite - 7024 lines)    |
|  lib/models/              (31 model files)         |
+--------------------------------------------------+
|             Infrastructure                         |
|  Firebase Auth   -> Custom Claims                  |
|  Firestore       -> Cloud data + Rules             |
|  Cloud Functions -> 17 functions                   |
|  Firebase Storage -> Images/files                  |
|  Firebase Messaging -> FCM push                    |
+--------------------------------------------------+
```

### Core Design Patterns

1. **Service-First Access** — All Firebase/DB operations go through service classes. Widgets never access Firebase SDK directly.
2. **Singleton Services** — `SyncOrchestrator`, `ClaimsService`, `CurrentShopService`, `EventBus` use singleton pattern.
3. **Static Services** — `FirestoreService`, `UserService`, `SyncService`, `NotificationService` use static methods.
4. **EventBus Pattern** — `EventBus` (broadcast `StreamController`) emits named events (`debts_changed`, `sales_changed`, `repairs_changed`, `expenses_changed`, `products_changed`, `shopChanged`) for cross-widget communication.
5. **Upsert Pattern** — Both SQLite and Firestore use `SetOptions(merge: true)` / `INSERT OR REPLACE` for idempotent writes.
6. **PaymentBlocker Pattern** — `PaymentBlocker.block()` throws `PaymentBlockedError` when code tries to bypass `PaymentIntentService` for payments.

---

## 3. Entry Point — main.dart

**File:** `lib/main.dart` (552 lines)

### Bootstrap Flow

```
main()
+-- Platform check (iOS vs Android)
|   +-- iOS: Show splash first, init Firebase in postFrameCallback
|   +-- Android: Init Firebase, runApp, defer notifications/connectivity
+-- Universal: runZonedGuarded for global error handling
+-- MyApp (StatefulWidget)
|   +-- Locale management via SharedPreferences
|   +-- MaterialApp with AppTheme.lightTheme
|   +-- initialRoute -> SplashView
+-- AuthGate (StatefulWidget)
    +-- StreamBuilder on FirebaseAuth.authStateChanges
    +-- user == null -> LoginView
    +-- user != null -> FutureBuilder(_getRoleAfterSync)
        +-- _getRoleAfterSync:
            +-- UserService.syncUserInfo(uid, email)
            +-- CurrentShopService.init()
            +-- Check super admin (admin@huluca.com)
            +-- UserService.ensureShopId()
            +-- Background: downloadAllFromCloud()
            +-- Background: SyncOrchestrator.init() + syncAll()
            +-- Background: CashClosingNotifier.check()
            +-- Background: PaymentIntentService.initialize()
            +-- Background: SyncHealthCheck.runFullCheck()
            +-- Auto-clear local DB when shop/user changes
            +-- Route:
                +-- Super admin -> ShopSelectorView
                +-- Regular user -> HomeView(role)
```

### Key Behaviors

- **Global error handler**: `runZonedGuarded` catches uncaught errors, logs via `debugPrint`
- **iOS deferred init**: Prevents white screen by showing splash before Firebase init
- **Shop change detection**: Compares stored `lastShopId` with current; clears SQLite if different
- **User change detection**: Compares stored `lastUserId`; clears SQLite if different user
- **Claims sync**: `ClaimsService().refreshMyClaims()` called during auth to ensure token has correct shopId/role

---

## 4. Data Models (31 files)

All models in `lib/models/` with `toMap()` / `fromMap()` / `copyWith()` serialization.

### 4.1 Core Business Models

#### Repair (`repair_model.dart`, 264 lines)

| Field | Type | Description |
|-------|------|-------------|
| id | int? | SQLite auto-increment |
| firestoreId | String? | Firestore document ID |
| customerName | String | Customer name |
| phone | String | Phone number |
| isWalkIn | bool | Walk-in customer flag |
| model | String | Device model |
| issue | String | Problem description |
| accessories | String | Accessories list |
| status | int | 1=Nhan (Received), 2=Dang sua (Repairing), 3=Xong (Done), 4=Da giao (Delivered) |
| price | int | Repair price charged |
| cost | int | Repair cost |
| paymentMethod | String | cash/transfer/debt |
| services | List\<RepairService\> | Individual repair services |
| pendingDeliveryApproval | bool | Needs manager approval for delivery |
| color | String | Device color |
| imei | String | Device IMEI |
| condition | String | Device condition on receipt |
| notes | String | Internal notes |
| createdBy | String | Staff who created |
| createdAt | int | Epoch milliseconds |
| startedAt | int? | Repair start time |
| finishedAt | int? | Repair finish time |
| deliveredAt | int? | Delivery time |
| lastCaredAt | int? | Last status update time |
| deleted | bool | Soft delete flag |
| isSynced | bool | Local sync status |
| shopId | String? | Multi-tenant isolation |

#### Product (`product_model.dart`, 296 lines)

| Field | Type | Description |
|-------|------|-------------|
| id | int? | SQLite auto-increment |
| firestoreId | String? | Firestore doc ID |
| shopId | String? | Multi-tenant |
| name | String | Product name |
| brand | String | Brand name |
| model | String | Product model |
| imei | String? | Serial/IMEI |
| cost | int | Cost price |
| price | int | Sale price |
| condition | String | New/Used/Grade A-D |
| status | int | 1=Available, 0=Sold/Deleted |
| type | String | DIEN_THOAI / LINH_KIEN / PHU_KIEN |
| quantity | int | Stock quantity |
| color | String | Color |
| capacity | String | Storage capacity |
| size | String? | Physical size (fashion) |
| isPending | bool | In staging warehouse |
| pendingSupplier | String? | Supplier for staging |
| categoryId | String? | Category reference |
| unit | String? | Unit of measure |
| expiryDate | int? | Expiry date (food industry) |
| batchNumber | String? | Batch number (food industry) |
| variantParentId | String? | Parent product for variants (fashion) |
| customData | Map? | Extensible fields |

**Type normalization**: `_normalizeType()` converts Vietnamese text to ASCII constants (`dien thoai` -> `DIEN_THOAI`, `linh kien` -> `LINH_KIEN`, `phu kien` -> `PHU_KIEN`).

#### SaleOrder (`sale_order_model.dart`, 205 lines)

| Field | Type | Description |
|-------|------|-------------|
| customerName | String | Customer |
| phone | String | Phone |
| isWalkIn | bool | Walk-in flag |
| productNames | String | Sold product names |
| productImeis | String | Sold product IMEIs |
| totalPrice | int | Total sale price |
| totalCost | int | Total cost |
| discount | int | Discount amount |
| paymentMethod | String | Payment method |
| isInstallment | bool | Bank installment flag |
| downPayment | int | Down payment (installment) |
| loanAmount | int | Bank 1 loan |
| bankName | String | Bank 1 name |
| loanAmount2 | int | Bank 2 loan |
| bankName2 | String | Bank 2 name |
| settlementPlannedAt | int? | Expected settlement date |
| settlementReceivedAt | int? | Actual settlement received |
| settlementAmount | int | Settlement amount |
| settlementFee | int | Settlement fee |
| settlementNote | String | Settlement note |
| settlementCode | String | Settlement reference code |
| cashAmount | int | Cash portion |
| transferAmount | int | Transfer portion |

**Computed:** `finalPrice = totalPrice - discount`, `remainingDebt`, `isPaid`

#### Customer (`customer_model.dart`)
Fields: name, phone, email, address, totalSpent, totalRepairs, totalRepairCost, shopId, deleted.

#### Expense (`expense_model.dart`)
Fields: title, amount, category, date, paymentMethod, type (`'CHI'` = expense / `'THU'` = income).

#### Debt (`debt_model.dart`)

| Field | Type | Description |
|-------|------|-------------|
| personName | String | Person name |
| phone | String | Phone |
| totalAmount | int | Total debt |
| paidAmount | int | Paid so far |
| type | String | CUSTOMER_OWES / SHOP_OWES / OTHER_CUSTOMER_OWES / OTHER_SHOP_OWES / OWE / OWED |
| status | String | ACTIVE / PAID / CANCELLED |
| linkedId | String? | Linked sale/repair ID |

### 4.2 HR Models

#### Attendance (`attendance_model.dart`)
Fields: userId, email, name, dateKey (yyyy-MM-dd), checkInAt, checkOutAt, overtimeOn, status (pending/approved/rejected), isLate, isEarlyLeave, location, workSchedule.

#### EmployeeSalarySettings (`employee_salary_model.dart`)
- Base: baseSalary, dailyRate, salaryType (monthly/daily/hourly)
- Commissions: saleCommType (percent/fixed_per_order/tiered), repairCommType
- Tiered: 3 tiers with thresholds and rates
- Allowances: transport, meal, phone, other
- Targets: monthlyTarget, targetBonusPercent, overtimeRate

#### SalaryBreakdown (`salary_breakdown_model.dart`)
Comprehensive calculation: workDays, baseAmount, commissions (sales + repairs), allowances, deductions (late/early/absence), insurance (BHXH/BHYT/BHTN), PIT tax, customAdjustments -> netSalary.

#### ShopDeductionSettings (`shop_deduction_settings_model.dart`)
Late/early leave/absence deduction rates, PIT settings, social/health/unemployment insurance rates.

### 4.3 Financial Models

#### PaymentIntent (`payment_intent_model.dart`)
- **Status**: pending -> completed / cancelled / failed
- **Types** (17): supplierPayment, customerDebtPayment, repairPayment, salePayment, expensePayment, salaryPayment, repairPartnerPayment, supplierDebtPayment, refund, inventoryPurchase, cashAdjustment, transferBetweenAccounts, otherIncome, otherExpense, settlementPayment, debtCollection, staffAdvance
- **Direction**: income / expense

#### FinancialActivity (`financial_activity_model.dart`)
Activity types: SALE, PURCHASE, EXPENSE, DEBT_COLLECT, DEBT_PAY, SETTLEMENT, REFUND, ADJUSTMENT. Direction: IN/OUT. Tracks balanceAfterCash/Bank.

### 4.4 Supply Chain Models

#### Supplier (`supplier_model.dart`)
Fields: name, phone, email, address, note, active, favorite, shopId.

#### PurchaseOrder (`purchase_order_model.dart`)
Fields: orderCode, supplierId, supplierName, items (List\<PurchaseItem\>), totalAmount, status, notes.

#### StockEntry (`stock_entry_model.dart`)
Status: draft/confirmed/cancelled. Type: quick/staging. Items with full product info.

### 4.5 Communication Models

#### ChatMessage (`chat_message_model.dart`)
Advanced chat: messageType (text/image/file/system/linked_order), reply support, reactions, read receipts, mentions, pinned messages, priority levels.

### 4.6 Configuration Models

#### ShopSettings (`shop_settings_model.dart`)
```dart
businessType: electronics | food | fashion | general
enableRepair: bool     // Repair module
enableExpiry: bool     // Expiry tracking (food)
enableVariants: bool   // Size/color variants (fashion)
enableSerial: bool     // IMEI/serial tracking
enableWarranty: bool   // Warranty tracking
enableBatch: bool      // Batch numbers (food)
defaultUnit: String    // Default measurement unit
expiryWarningDays: int // Days before expiry warning
lowStockWarning: int   // Low stock threshold
```
Factory constructors: `ShopSettings.electronics()`, `.food()`, `.fashion()`, `.general()`

#### ProductCategory (`product_category_model.dart`)
Tree structure with parentId, per-category feature flags: trackExpiry, trackSerial, hasVariants, hasWarranty, customFields map.

#### ProductVariant (`product_variant_model.dart`)
Fields: productId, sku, size, color, colorCode, material, style, costPrice, salePrice, quantity, barcode.

### 4.7 Other Models

| Model | File | Purpose |
|-------|------|---------|
| RepairService | repair_service_model.dart | Individual service within a repair |
| RepairPartner | repair_partner_model.dart | External repair partner/vendor |
| RepairPartnerPayment | repair_partner_payment_model.dart | Payments to repair partners |
| SupplierPayment | supplier_payment_model.dart | Payments to suppliers |
| QuickInputCode | quick_input_code_model.dart | Barcode/QR quick input codes |
| InventoryCheck | inventory_check_model.dart | Stock-take records |
| InventoryZone | inventory_zone_model.dart | Physical inventory zones |
| LabelTemplate | label_template_model.dart | Printer label templates |
| PartnerRepairHistory | partner_repair_history_model.dart | Repair history with partners |
| SupplierImportHistory | supplier_import_history_model.dart | Import batch history |
| SupplierProductPrices | supplier_product_prices_model.dart | Supplier price tracking |
| PrinterType | printer_types.dart | Enum: bluetooth/wifi/usb |

---

## 5. Services Layer (43 files, 65 classes)

All services in `lib/services/`. Most use static methods with `FirebaseFirestore.instance` and `DBHelper()`.

### 5.1 Core Services

#### FirestoreService (`firestore_service.dart`, 1941 lines)

Central Firestore CRUD. All methods are `static`. Key patterns:
- Every write adds `shopId` from `UserService.getCurrentShopId()`
- Sensitive data encrypted via `EncryptionService.encryptMap(data)` before upload
- Money amounts validated via `MoneyValidationService.validateAmount()` before writes
- Uses `SetOptions(merge: true)` for all upserts
- Soft deletes: `update({'deleted': true, 'updatedAt': serverTimestamp()})`
- System notifications via `_notifyAll()` -> FCM push + system chat message

**Methods by Category:**

| Category | Methods |
|----------|---------|
| Purchase Orders | `addPurchaseOrder()`, `_updateInventoryFromPurchaseOrder()` (weighted avg cost) |
| Repairs | `addRepair()`, `upsertRepair()`, `deleteRepair()` |
| Sales | `addSale()`, `updateSaleCloud()`, `deleteSale()` |
| Products | `addProduct()`, `updateProductCloud()`, `deleteProduct()` |
| Chat | `sendChat()`, `chatStream()` |
| Audit | `addAuditLogCloud()` |
| Debts | `addDebtCloud()`, `addDebtPaymentCloud()`, `executeDebtPaymentTransaction()` |
| Expenses | `addExpenseCloud()`, `updateExpenseCloud()`, `deleteExpenseCloud()`, `getExpenseStream()` |
| Attendance | `addAttendance()`, `updateAttendanceCloud()`, `deleteAttendance()`, `getAttendanceStream()` |
| Cash Closing | `upsertCashClosingCloud()`, `getCashClosingFromCloud()`, `getCashClosingStream()` |
| Shop Reset | `resetEntireShopData()` — batch-deletes 17 collections (400 docs/batch) |
| Customers | `addCustomer()`, `updateCustomer()`, `deleteCustomer()`, `deleteCustomerById()` |
| Suppliers | `addSupplier()`, `updateSupplier()`, `deleteSupplier()` |
| Quick Input | `addQuickInputCode()`, `updateQuickInputCode()`, `deleteQuickInputCode()`, `getQuickInputCodesForShop()` |
| Notifications | `createNotification()`, `getUserNotifications()`, `markNotificationAsRead()`, `getUnreadCount()` |
| Repair Partners | `addRepairPartner()`, `updateRepairPartner()`, `deleteRepairPartnerByFirestoreId()` |
| Partner History | `addPartnerRepairHistory()` |
| Supplier History | `addSupplierImportHistory()`, `addSupplierProductPrices()` |
| Salary Settings | `getEmployeeSalarySettings()`, `getEmployeeSalarySettingByStaffId()`, `saveEmployeeSalarySettings()`, `deleteEmployeeSalarySettings()`, `getShopDefaultSalarySettings()`, `saveShopDefaultSalarySettings()`, `getStaffByShopId()` |
| Deductions | `getShopDeductionSettings()`, `saveShopDeductionSettings()` |
| Custom Adjustments | `getCustomSalaryAdjustments()`, `getAllCustomSalaryAdjustments()`, `addCustomSalaryAdjustment()`, `updateCustomSalaryAdjustment()`, `deleteCustomSalaryAdjustment()` |

**Firestore Transactions (race-condition fixes):**
1. **`executeDebtPaymentTransaction()`** — Atomic read-validate-update debt + create payment record. Prevents race conditions with concurrent debt payments.
2. **`executeSaleTransaction()`** — Atomic stock check + stock deduction + sale creation + optional debt creation. Detects `OUT_OF_STOCK` and `SHOP_MISMATCH`. Prevents overselling with concurrent sales.

**Purchase order inventory update (`_updateInventoryFromPurchaseOrder`):**
- Auto-updates product quantity with weighted average cost calculation
- Creates new products if they don't exist

---

#### UserService (`user_service.dart`, 1223 lines)

Authentication, role management, permissions. All methods `static`.

**Key state:**
```dart
static String? _cachedShopId;
static String? _cachedUid;
static String? _adminSelectedShopId;
static bool? _cachedCanViewCostPrice;
```

**Authentication:**
- `_isSuperAdmin(user)` -> checks `email == 'admin@huluca.com'`
- `isCurrentUserSuperAdmin()` -> current user check
- `isCurrentUserAdmin()` -> checks super admin OR role owner/manager
- `getCurrentUserName()` -> displayName fallback chain: Auth -> Firestore -> email prefix

**ShopId Management:**
- `getCurrentShopId()` -> Cache -> Super admin selected -> Firestore user doc
- `getShopIdSync()` -> Synchronous cache access
- `ensureShopId(maxRetries: 5)` -> Retries with 1s delay
- `isShopIdReady()` -> Quick check
- `updateCachedShopId()` -> External cache update
- `getShopIdFast()` -> From Custom Claims (no Firestore read)

**Role System (hierarchy):**
```
superAdmin (admin@huluca.com)  ->  all access
          |
        owner  ->  full shop access
          |
       manager  ->  business access, limited finance
          |
    employee / technician  ->  basic operations
          |
         user  ->  minimal access (default)
```

- `getUserRole(uid)` -> Claims first -> Firestore fallback
- `getRoleFast()` -> Claims only

**User Sync:**
- `syncUserInfo(uid, email)` -> Creates shop if new user -> Sets user data -> Triggers claims refresh -> Waits for claims sync (up to 8 retries for new shops)

**Invite System:**
- `createInviteCode(shopId)` -> 8-char code, 7-day expiry
- `getInvite(code)` -> Validates existence, expiry, used status
- `useInviteCode(code, uid)` -> Assigns user to shop

**Validation:**
- `validateName(name, loc)` -> Non-empty
- `validatePhone(phone, loc)` -> 9-12 cleaned digits
- `validateIMEI(imei, loc)` -> 4-5 digits (internal code) or 15 digits (standard IMEI)
- `validateModel(model, loc)` -> 2-50 chars

---

#### SyncService (`sync_service.dart`, 3007 lines)

Real-time Firestore -> SQLite sync with conflict resolution.

**Initialization:**
```dart
static Future<void> initRealTimeSync(VoidCallback onDataChanged)
```
1. Cancels existing subscriptions
2. Gets shopId, verifies Custom Claims match
3. Auto-cleanup orphan records (`cleanupOrphanRepairParts`, `forceMarkRepairPartsSynced`)
4. Subscribes to 12+ Firestore collections:
   - repairs, sales, products, expenses, debts, debt_payments, users, attendance, customers, suppliers, quick_input_codes, repair_partners, partner_repair_history, supplier_payments, repair_partner_payments, cash_closings, purchase_orders, stock_entries, etc.

**Conflict Resolution (`_shouldAcceptCloudData`):**
- Local record doesn't exist -> **accept cloud**
- Local `isSynced == true` -> **accept cloud** (no pending local changes)
- Local `isSynced == false` -> **REJECT cloud** (preserve local changes) + enqueue local for push via SyncOrchestrator
- This prevents race conditions where cloud echoes overwrite local edits

**Key Methods:**
- `initRealTimeSync(callback)` -> Subscribe to all collections with shop filtering
- `downloadAllFromCloud()` -> Full download (batches of 50 to avoid blocking)
- `syncAllToCloud()` -> Push all unsynced local data
- `syncRepairData()` -> Targeted repair sync
- `syncPaymentRelatedData()` -> Targeted payment sync
- `syncCustomersFromCloud()` -> Customer sync
- `cancelAllSubscriptions()` -> Cleanup
- `forceReinitializeSync()` -> Cancel + reinit
- `_subscribeToCollection()` -> Generic subscription helper with error handling and auto-resubscribe

**Event emission:** After each batch sync, emits `EventBus` events (`repairs_changed`, `sales_changed`, `debts_changed`, etc.) to trigger UI updates.

---

#### SyncOrchestrator (`sync_orchestrator.dart`, 916 lines)

Offline-first sync queue (local -> cloud). Singleton pattern.

**Entity Types (19):**
```dart
enum SyncEntityType {
  repair, sale, product, expense, debt, customer, supplier,
  attendance, repairPart, quickInputCode, debtPayment,
  supplierPayment, partnerPayment, repairPartner, auditLog,
  cashClosing, adjustmentEntry, purchaseOrder, supplierImportHistory
}
```

**Features:**
- Queue stored in SQLite `sync_queue` table
- Auto-sync when network restored (listens to `Connectivity`)
- Max 3 retries before marking as failed
- Stream-based UI updates for pending count and sync status
- Deduplication in queue (same entity+operation replaces older entry)

---

#### NotificationService (`notification_service.dart`, 1226 lines)

FCM + local notifications.

**Features:**
- Rate limiting: max 3 notifications per 10 seconds
- FCM token management with 6-hour refresh interval
- 5 notification channels: `new_order`, `payment`, `inventory`, `staff`, `system`
- Background message handling (`handleBackgroundMessage`)
- Permission management for Android 13+
- Per-type toggle via SharedPreferences
- `listenToNotifications()` -> Firestore real-time listener for shop notifications
- `sendCloudNotification()` -> Cloud Function call for FCM multicast
- `showSnackBar()` -> In-app notification via `ScaffoldMessenger`

---

#### ClaimsService (`claims_service.dart`, 244 lines)

Custom Claims management. Singleton pattern.

**Claims Structure (in JWT):**
```json
{
  "role": "owner|manager|employee|technician|user",
  "shopId": "shop_document_id",
  "isSuperAdmin": true
}
```

**Methods:**
- `batchSyncAllClaims()` -> Super admin only, calls Cloud Function to sync all users
- `syncUserClaims(uid)` -> Sync specific user via `syncUserClaimsV2` Cloud Function
- `refreshMyClaims()` -> Self-refresh via `refreshMyClaimsV2` + force token refresh
- `getMyClaims()` -> View current claims + sync status
- `getClaimsFromToken(forceRefresh)` -> Read from ID token (local, fast, cached 5 min)
- `getRoleFromClaims()`, `getShopIdFromClaims()`, `isSuperAdmin()`, `isOwner()` — quick helpers

---

#### CurrentShopService (`current_shop_service.dart`, 352 lines)

Multi-shop support for owners. Singleton pattern.

**Features:**
- Persists active shop to SharedPreferences
- `getActiveShopId()` -> Priority: super admin selected > owner's active > user profile
- `hasMultipleShops()` -> Check if owner has multiple shops
- `getOwnedShops()` -> Query by `ownerUid`
- `switchShop(newShopId)` -> Validates ownership -> clears SQLite -> updates UserService cache -> reinitializes EncryptionService + CategoryService + SyncService
- Backward compatible for single-shop users

---

### 5.2 Financial Services

#### PaymentIntentService (`payment_intent_service.dart`, 852 lines)

**Central payment gateway.** All payments MUST go through this service.

- Manages PaymentIntent lifecycle: `create -> execute -> complete/cancel/fail`
- Persists intents to SQLite `payment_intents` table
- In-memory cache + SQLite backing store
- History limited to last 100 completed/cancelled intents
- Validates via `MoneyValidationService` before execution
- Executes via `MoneyTransactionService`
- Clears cache on shop change

#### MoneyValidationService
Validates monetary amounts, sale totals, debt payments. Throws `MoneyValidationException` on invalid operations. Called automatically by `FirestoreService` before every financial write.

#### MoneyTransactionService
Executes actual financial transactions after validation. Records transactions as `FinancialActivity` entries.

#### AdjustmentService
Cash/inventory adjustment entries with `AdjustmentResult`.

#### FinancialActivityService
Logs all financial activities (sales, purchases, expenses, debt collections, settlements). Provides audit trail for all money movements.

#### CashClosingNotifier
Checks and alerts for uncompleted daily cash closings. Triggered during app startup.

---

### 5.3 HR Services

#### SalaryCalculationService
Comprehensive salary calculation:
- `baseSalary` (monthly/daily/hourly depending on salaryType)
- `+ commissions` (sales: fixed/percent/tiered; repairs: fixed/percent/tiered)
- `+ allowances` (transport, meal, phone, other)
- `- deductions` (late arrivals, early leaves, absences)
- `- insurance` (BHXH 8%, BHYT 1.5%, BHTN 1%)
- `- PIT` (personal income tax)
- `+ customAdjustments` (bonuses/penalties)
- `= netSalary`

#### SalarySlipPdfService
Generates PDF salary slips for printing. Uses `pdf` package.

---

### 5.4 Printer Services

| Service | Purpose |
|---------|---------|
| BluetoothPrinterService | Bluetooth thermal printer via `print_bluetooth_thermal` |
| WifiPrinterService | WiFi/network printer via `esc_pos_printer` |
| ThermalPrinterService | Generic thermal printer abstraction |
| UnifiedPrinterService | Unified API across all printer types + label printing |
| LabelSettingsService | Shop-specific label template configuration |

---

### 5.5 Sync & Data Services

| Service | Purpose |
|---------|---------|
| SyncHealthCheck | Validates sync integrity: local vs cloud record counts, detects orphans |
| ConnectivityService | Network status monitoring via `connectivity_plus` |
| DataMigrationService | Database migration helpers, orphan data detection |
| StorageService | Firebase Storage for image uploads |
| ShopDeletionService | Safe shop deletion with cascade |
| AuditService | Audit log service |
| LoggingService | Structured logging |

---

### 5.6 Business Domain Services

| Service | Purpose |
|---------|---------|
| CustomerService | Customer CRUD + stats (totalSpent, totalRepairs) |
| SupplierService | Supplier CRUD |
| SupplierPaymentService | Supplier payment tracking |
| RepairPartnerService | External repair partner management |
| RepairPartnerPaymentService | Partner payment tracking |
| StockEntryService | Stock entry management (quick/staging) |
| CategoryService | Product category tree management |
| VariantService | Product variant management (fashion) with `VariantWarningCounts`, `CommonSizes`, `CommonColors` |
| ExpiryAlertService | Expiry date alerts (food) with `ExpiryStats`, `BatchInfo` |
| BusinessTypeHelper | Multi-industry terminology + feature flags with `BusinessTerminology` |
| ChatService | Advanced chat with reactions, replies, read receipts |
| FirstTimeGuideService | Onboarding guide for new users with `GuideStep` |

---

### 5.7 Security Services

#### EncryptionService (`encryption_service.dart`, 187 lines)

AES-256-CBC encryption for cloud data.

**Key derivation:** `SHA256(shopId + masterSecret)` -> 32-byte key
**IV:** `MD5('IV_' + shopId)` -> 16-byte IV

**Encrypted fields (23):** customerName, phone, address, email, notes, issue, imei, productImeis, sellerName, personName, bankName, description, accessories, warranty, and more.

**Format:** Encrypted values prefixed with `ENC:` marker for detection. Decryption auto-detects encrypted values.

**Methods:**
- `init(shopId)` -> Derive key from shopId
- `encrypt(plainText)` -> Returns `ENC:base64`
- `decrypt(cipherText)` -> Strips prefix, decodes
- `encryptMap(data)` -> Encrypts all sensitive fields in a map
- `decryptMap(data)` -> Decrypts all sensitive fields in a map
- `isEnabled` / `setEnabled(bool)` -> Toggle via SharedPreferences

---

#### EventBus (`event_bus.dart`)

Simple broadcast event bus using `StreamController<String>.broadcast()`.

```dart
EventBus().emit('repairs_changed');
EventBus().stream.listen((event) { ... });

// Standard events:
'shop_changed', 'repairs_changed', 'sales_changed',
'debts_changed', 'expenses_changed', 'products_changed'
```

---

### 5.8 Complete Service Catalog (65 classes across 43 files)

| File | Classes |
|------|---------|
| firestore_service.dart | FirestoreService |
| user_service.dart | UserService |
| sync_service.dart | SyncService |
| sync_orchestrator.dart | SyncOrchestrator, SyncQueueItem, SyncResult |
| notification_service.dart | NotificationService |
| claims_service.dart | ClaimsService |
| current_shop_service.dart | CurrentShopService |
| payment_intent_service.dart | PaymentIntentService, PaymentExecutionResult |
| money_transaction_service.dart | MoneyTransactionService |
| money_validation_service.dart | MoneyValidationService, MoneyValidationException, MoneyValidationResult |
| adjustment_service.dart | AdjustmentService, AdjustmentResult |
| financial_activity_service.dart | FinancialActivityService |
| encryption_service.dart | EncryptionService |
| event_bus.dart | EventBus |
| connectivity_service.dart | ConnectivityService |
| sync_health_check.dart | SyncHealthCheck, SyncCheckResult, SyncHealthReport |
| customer_service.dart | CustomerService |
| supplier_service.dart | SupplierService |
| supplier_payment_service.dart | SupplierPaymentService |
| repair_partner_service.dart | RepairPartnerService |
| repair_partner_payment_service.dart | RepairPartnerPaymentService |
| stock_entry_service.dart | StockEntryService |
| category_service.dart | CategoryService |
| variant_service.dart | VariantService, VariantWarningCounts, CommonSizes, CommonColors |
| expiry_alert_service.dart | ExpiryAlertService, ExpiryStats, BatchInfo |
| business_type_helper.dart | BusinessTypeHelper, BusinessTerminology |
| chat_service.dart | ChatService |
| salary_calculation_service.dart | SalaryCalculationService |
| salary_slip_pdf_service.dart | SalarySlipPdfService |
| cash_closing_notifier.dart | CashClosingNotifier |
| bluetooth_printer_service.dart | BluetoothPrinterService |
| wifi_printer_service.dart | WifiPrinterService |
| thermal_printer_service.dart | ThermalPrinterService |
| unified_printer_service.dart | UnifiedPrinterService |
| label_settings_service.dart | LabelSettingsService, ShopLabelSettings |
| storage_service.dart | StorageService |
| data_migration_service.dart | DataMigrationService, OrphanDataInfo |
| shop_deletion_service.dart | ShopDeletionService, ShopDeletionResult |
| audit_service.dart | AuditService |
| logging_service.dart | LoggingService |
| first_time_guide_service.dart | FirstTimeGuideService, GuideStep |
| sale_product_validation.dart | SaleProductValidation |

---

## 6. Views Layer (80+ files)

All views in `lib/views/`. Main screen is `HomeView` with bottom navigation.

### 6.1 Core Views

| View | File | Description |
|------|------|-------------|
| SplashView | splash_view.dart | Loading/splash screen |
| LoginView | login_view.dart | Firebase Auth login |
| HomeView | home_view.dart (6470 lines) | Main dashboard with bottom navigation |
| ShopSelectorView | shop_selector_view.dart | Super admin shop picker |
| SuperAdminView | super_admin_view.dart | Super admin dashboard |
| UserGuideView | user_guide_view.dart | In-app user guide |
| AboutDeveloperView | about_developer_view.dart | About screen |

### 6.2 HomeView Bottom Navigation Tabs

HomeView uses dynamic bottom navigation based on permissions and business type:

| Tab | Condition | Content |
|-----|-----------|---------|
| Home | Always visible | Dashboard with stats |
| Sales | `allowViewSales` | SaleListView |
| Repairs | `allowViewRepairs` AND electronics only | OrderListView |
| Inventory | `allowViewInventory` | InventoryView |
| Expiry | Food shops + `allowViewInventory` | ExpiryManagementView |
| Variants | Fashion shops + `allowViewInventory` | VariantManagementView |
| Staff | `allowManageStaff` | Staff management tabs |
| Finance | `allowViewRevenue` | Financial dashboard |
| Settings | Always (unless admin-locked) | App settings |

**Dashboard Stats:**
- totalPendingRepair, todaySaleCount, todayRepairDone
- revenueToday, todayNewRepairs, todayExpense
- totalDebtRemain, expiringWarranties, unreadChatCount

**Auto-sync timer:** Every 60 seconds
**EventBus listener:** Reacts to debts_changed, sales_changed, repairs_changed, expenses_changed, products_changed, shopChanged

### 6.3 Business Views

| View | Purpose |
|------|---------|
| CreateRepairOrderView | New repair order form with IMEI scan |
| CreateSaleView | POS / new sale form |
| OrderListView | Repair orders list with filtering |
| SaleListView | Sales list with search and filters |
| InventoryView | Product inventory with categories |
| FastInventoryInputView | Quick stock entry with barcode scanning |
| FastInventoryCheckView | Stock-take with zone tracking |
| SmartStockInView | Smart stock-in with supplier selection |
| PendingStockListView | Staging warehouse items |
| SupplierListView | Supplier management |
| SupplierDetailView | Supplier detail + payment history |
| CustomerManagementView | Customer CRM |
| WarrantyView | Warranty tracking |
| QuickInputCodesView | Barcode/QR codes setup |
| QRScanView | QR code scanner |

### 6.4 Financial Views

| View | Purpose |
|------|---------|
| RevenueView | Revenue dashboard |
| ExpenseView | Expense management |
| DebtView | Debt management |
| CashClosingView | Daily cash closing |
| FinancialReportView | Comprehensive financial reports |
| FinancialActivityLogView | Activity log |
| BankInstallmentReportView | Bank installment tracking |

### 6.5 HR Views

| View | Purpose |
|------|---------|
| StaffListView | Staff management |
| StaffPerformanceView | Performance metrics |
| AttendanceView | Employee attendance (self-service) |
| AttendanceManagementView | Attendance admin for managers |
| WorkScheduleSettingsView | Work schedule configuration |
| HRSalarySettingsView | Salary settings per employee |
| PayrollView | Payroll review and processing |

### 6.6 Settings & Communication

| View | Purpose |
|------|---------|
| ShopSettingsView | Shop configuration |
| SettingsView | General app settings |
| PrinterSettingsView | Printer setup |
| NotificationsView | Notification center |
| NotificationSettingsView | Notification preferences |
| AdvancedChatView | Team chat with rich features |
| GlobalSearchView | Cross-entity search |

### 6.7 Industry-Specific Views

| Subdirectory | Views |
|-------------|-------|
| `views/food/` | ExpiryManagementView |
| `views/fashion/` | VariantManagementView |
| `views/hr/` | AddCustomAdjustmentDialog, ShopDeductionSettingsView |
| `views/onboarding/` | BusinessTypeWizard |

---

## 7. Widgets (28 files)

Reusable UI components in `lib/widgets/`.

| Widget | Purpose |
|--------|---------|
| CustomAppBar | Gradient app bar with Zalo Blue theme |
| CurrencyTextField | Currency input field with formatting |
| DebouncedSearchField | Search with debounce timer |
| DynamicFormBuilder | Dynamic form generation |
| GlobalSearchBar | Cross-entity search bar |
| GradientFab | Gradient floating action button with animation |
| LoadingIntroScreen | Onboarding intro screen |
| NotificationBadge | Badge with unread count |
| PerpetualCalendar | Calendar widget |
| SyncStatusWidget | Sync status display |
| SimpleSyncIndicator | Compact sync indicator |
| UnifiedSyncButton | Sync button + SyncCenterSheet |
| ValidatedTextField | Text field with validation |
| VariantSelector | Product variant picker (fashion) |
| VariantBadge | Variant display badge |
| VariantQuickSelect | Quick variant selector |
| VariantSelectionDialog | Full variant selection dialog |
| VariantStockWidget | Variant stock display |
| ShopSwitcherWidget | Multi-shop switcher |
| CurrentShopIndicator | Current shop display |
| SectionCard | Card container |
| SimpleCard | Basic card |
| InfoRow | Key-value info row |
| StatusBadge | Status display badge |
| CompactActionButton | Small action button |
| SafeStreamBuilder | Error-safe StreamBuilder wrapper |
| PrinterSelectionDialog | Printer picker dialog |
| PendingSyncIndicator | Pending sync count indicator |
| SyncStatusDialog | Sync status dialog |
| SyncActionButton | One-tap sync button |
| PendingStockWidget | Staging warehouse widget |
| IMEIScanResultDialog | IMEI scan result display |

---

## 8. Theme System

All in `lib/theme/`.

### AppColors (`app_colors.dart`)
```dart
primary       = Color(0xFF4D8EE9)  // Blue
primaryDark   = Color(0xFF0068FF)  // Zalo Blue
secondary     = Color(0xFFFF9800)  // Orange
background    = Color(0xFFF8FAFF)  // Light blue-white
surface       = Colors.white
onSurface     = Color(0xFF1A1A2E)  // Dark navy
error         = Color(0xFFE53935)  // Red
success       = Color(0xFF43A047)  // Green
warning       = Color(0xFFFF9800)  // Orange
info          = Color(0xFF1E88E5)  // Blue
```

Status colors: active (green), inactive (grey), pending (orange), completed (blue), cancelled (red).

### AppTextStyles (`app_text_styles.dart`)
- Font: Roboto
- Compact sizing: h1=22, h2=18, h3=16, h4=14, body1=11, body2=10, caption=10, overline=9
- All styles include color from AppColors

### AppButtonStyles (`app_button_styles.dart`)
- `buttonHeight = 48`, `borderRadius = 8`
- Styles: elevated, outlined, text, danger, success, small, large

### AppTheme (`app_theme.dart`, 278 lines)
Complete `lightTheme` with:
- Zalo Blue gradient AppBar (`toolbarHeight: 44`)
- Custom bottom navigation, tab bar, card, input decoration
- Dialog, snackbar, chip, FAB themes
- Consistent color application from AppColors

---

## 9. Constants

### FinancialConstants (`financial_constants.dart`, 449 lines)
```dart
enum PaymentMethod { cash, transfer, debt, installment, mixed, bank }
enum MoneySourceType { // 11 types
  cashRegister, bankAccount, momo, zalopay, shoppeepay,
  vnpay, creditCard, otherEwallet, otherSource, tempHold, customerDeposit
}
enum MoneyDirection { income, expense, transfer }
```

### ProductConstants (`product_constants.dart`, 419 lines)
- Colors: 16 standard colors (Den, Trang, Do, Xanh, etc.)
- Brands: 10 (Apple, Samsung, Xiaomi, OPPO, etc.)
- Capacities: 6 (32GB - 1TB)
- Conditions: 7 (Moi 100%, 99%, 98%, 97%, 95%, Likenew, Da su dung)
- Payment methods: 3 (Tien mat, Chuyen khoan, Tra gop)
- Units: 18 (cai, chiec, kg, lit, hop, goi, etc.) — multi-industry
- Clothing sizes: XS, S, M, L, XL, XXL, XXXL, FREE

### PartnerConstants (`partner_constants.dart`)
Payment methods and status constants for repair partners.

---

## 10. Utilities (12 files)

All in `lib/utils/`.

| Utility | Class | Purpose |
|---------|-------|---------|
| app_info.dart | AppInfo | App version and build info |
| app_logger.dart | AppLogger | Structured logging |
| debouncer.dart | Debouncer | Action debouncing |
| imei_extractor.dart | IMEIExtractor, IMEIExtractResult | Extract IMEI from complex QR codes |
| money_input_formatter.dart | MoneyInputFormatter | Currency input formatting (TextInputFormatter) |
| money_utils.dart | MoneyUtils | Money formatting utilities |
| qr_parser.dart | QRParser | QR code content parsing |
| qr_router.dart | QRRouter | Route to appropriate view based on QR content |
| repair_status_validator.dart | RepairStatusValidator | Validates repair status transitions (enforces 1->2->3->4 flow) |
| sku_generator.dart | SKUGenerator | Auto-generate SKU codes |
| ui_constants.dart | UIConstants | UI dimension constants |
| vietnamese_utils.dart | VietnameseUtils | Vietnamese text utilities (diacritics, normalization) |

---

## 11. Controllers

### FastInventoryInputController (`controllers/fast_inventory_input_controller.dart`)
Controller for the fast inventory input feature — manages barcode scanning + quick stock entry workflow.

---

## 12. Core Infrastructure

Files in `lib/core/`.

### AppConfig (`core/app_config.dart`)
```dart
class AppConfig {
  // Build mode
  static bool get isDebug => ...
  static bool get isRelease => ...

  // Sync config
  static const syncIntervalSeconds = 60;
  static const syncBatchSize = 50;

  // Cache config
  static const cacheExpiryMinutes = 30;

  // DB config
  static const dbVersion = 80;
  static const dbName = 'repair_shop_v22.db';

  // Pagination
  static const defaultPageSize = 20;
}

class EnvConfig {
  static const appName = 'HULUCA Shop Manager';
  static const packageName = 'com.huluca.shopmanager';
}
```

### PaymentBlocker (`core/payment_blocker.dart`)
```dart
class PaymentBlockedError implements Exception { ... }

class PaymentBlocker {
  static void block() {
    throw PaymentBlockedError(
      'Direct payment bypassed! Use PaymentIntentService.'
    );
  }
}
```

### MoneyUtils (`core/utils/money_utils.dart`)
Currency formatting utilities (core-level, separate from `lib/utils/money_utils.dart`).

---

## 13. Localization (i18n)

### Configuration
```yaml
# pubspec.yaml
flutter:
  generate: true
```

### Files
| File | Lines | Purpose |
|------|-------|---------|
| app_vi.arb | ~2405 | Vietnamese translations (template) |
| app_en.arb | ~2594 | English translations |
| app_localizations.dart | Generated | Localization class |
| app_localizations_vi.dart | Generated | Vietnamese implementation |
| app_localizations_en.dart | Generated | English implementation |

### Key Categories (~2400+ keys)
- **App-wide:** appName, homeTab, salesTab, repairsTab, inventoryTab, staffTab, financeTab, settingsTab
- **Business:** customerName, phone, address, price, cost, discount, totalPrice, quantity
- **Repair:** repairStatus, received, repairing, done, delivered
- **Sales:** saleOrder, soldBy, paymentMethod, installment
- **Finance:** revenue, expense, debt, cashClosing, profit
- **HR:** attendance, salary, checkIn, checkOut, workSchedule
- **Validation:** nameRequired, phoneLengthInvalid, imeiDigitsOnly
- **Multi-industry:** variants, expiry, batchNumber, unit

---

## 14. Local Database — SQLite

### Configuration
- **File:** `lib/data/db_helper.dart` (7024 lines)
- **DB Name:** `repair_shop_v22.db`
- **Version:** 80
- **Pattern:** Singleton with `DBHelper()`

### Tables (30+)

| Table | Key Fields | Purpose |
|-------|-----------|---------|
| repairs | firestoreId, shopId, customerName, phone, status, price, cost, isSynced | Repair orders |
| products | firestoreId, shopId, name, imei, cost, price, quantity, type, status, isSynced | Product inventory |
| sales | firestoreId, shopId, customerName, totalPrice, totalCost, soldAt, isSynced | Sale orders |
| customers | firestoreId, shopId, name, phone, totalSpent, totalRepairs | Customer records |
| suppliers | firestoreId, shopId, name, phone, active, favorite | Supplier records |
| expenses | firestoreId, shopId, title, amount, category, date, type | Expenses/income |
| debts | firestoreId, shopId, personName, totalAmount, paidAmount, type, status | Debt records |
| attendance | firestoreId, shopId, userId, dateKey, checkInAt, checkOutAt, status | Attendance |
| audit_logs | firestoreId, shopId, userId, action, entityType, entityId | Audit trail |
| inventory_checks | firestoreId, shopId, checkDate, totalCounted | Stock-take records |
| supplier_payments | firestoreId, shopId, supplierId, amount, paymentDate | Supplier payments |
| repair_partner_payments | firestoreId, shopId, partnerId, amount | Partner payments |
| cash_closings | firestoreId, shopId, dateKey, openingCash, closingCash | Daily cash closing |
| employee_salary_settings | shopId, staffId, baseSalary, salaryType | Salary config |
| purchase_orders | firestoreId, shopId, orderCode, supplierId, totalAmount | Purchase orders |
| work_schedules | firestoreId, shopId, userId, dayOfWeek, startTime, endTime | Work schedules |
| debt_payments | firestoreId, shopId, debtId, amount, paidAt | Debt payment records |
| quick_input_codes | firestoreId, shopId, name, code, isActive | Quick input codes |
| supplier_product_prices | firestoreId, shopId, supplierId, productName | Supplier prices |
| supplier_import_history | firestoreId, shopId, supplierId, importDate | Import history |
| repair_partners | firestoreId, shopId, name, phone, active | Repair partners |
| partner_repair_history | firestoreId, shopId, partnerId, repairId | Partner history |
| repair_parts | firestoreId, shopId, repairId, partName, cost | Repair parts |
| sync_queue | entityType, entityId, operation, status, retryCount | Offline sync queue |
| sales_returns | firestoreId, shopId, saleId, returnDate | Sale returns |
| sales_return_items | returnId, productId, quantity, reason | Return items |
| financial_activity_log | firestoreId, shopId, activityType, amount, direction | Financial log |
| shop_settings | shopId, businessType, enableRepair, enableExpiry | Shop config |
| product_categories | firestoreId, shopId, name, parentId | Category tree |
| product_variants | firestoreId, shopId, productId, sku, size, color | Product variants |
| payment_intents | id, shopId, type, status, amount, direction | Payment intents |
| payroll_locks | shopId, month, year, lockedAt | Payroll lock |

### Key Patterns

1. **Upsert by firestoreId:** Most tables use `firestoreId` as unique key for cloud sync
2. **isSynced flag:** Tracks whether local record has been pushed to cloud (false = pending local changes)
3. **Soft deletes:** `deleted` column instead of physical deletion
4. **Type normalization:** `_typeWhereClause` handles Vietnamese <-> ASCII type compatibility
5. **Shop isolation:** `_getCurrentShopId()` and `_ensureValidShopId()` helpers

### Migration Path (v18 -> v80)
Extensive `onUpgrade` with `ALTER TABLE` migrations adding columns for:
- Multi-industry fields (categoryId, unit, expiryDate, batchNumber, variantParentId)
- Payment improvements (cashAmount, transferAmount, settlement fields)
- HR additions (overtimeOn, isLate, isEarlyLeave, workSchedule)
- Sync improvements (sync_queue table, isSynced on all tables)
- Financial activity log
- Product variants and categories

---

## 15. Firestore Rules

**File:** `firestore.rules` (1081 lines)

### Structure (12 sections)

1. **Core Functions** (lines 1-60)
2. **Auth & User Management** (users, shops, invites)
3. **Core Business** (repairs, sales, products, variants, stock_entries, customers)
4. **Finance** (expenses, debts, debt_payments, cash_closings, adjustment_entries, payment_intents)
5. **Suppliers** (suppliers, supplier_payments, purchase_orders, supplier_import_history, supplier_product_prices)
6. **Repair Partners** (repair_partners, repair_partner_payments, partner_repair_history)
7. **HR & Attendance** (attendance, work_schedules)
8. **Chat & Messaging** (chats, chat_messages, chat_online, chat_typing)
9. **Notifications** (notifications, shop_notifications)
10. **System Data** (audit_logs **IMMUTABLE**, quick_input_codes, repair_parts, financial_activities, supplier_debts)
11. **HR & Salary Settings** (shop_deduction_settings, employee_salary_settings, shop_salary_defaults + subcollections)
12. **Catch-All Deny**

### Core Helper Functions
```javascript
function isAuth() { return request.auth != null; }
function isSuperAdmin() { return request.auth.token.isSuperAdmin == true; }
function myShopId() { return request.auth.token.shopId; }
function belongsTo(data) { return data.shopId == myShopId(); }
function docInMyShop() { return belongsTo(resource.data); }
function newDocInMyShop() { return belongsTo(request.resource.data); }
function myRole() { return request.auth.token.role; }
function isOwner() { return myRole() == 'owner'; }
function isManager() { return myRole() == 'manager'; }
function isStaff() { return isOwner() || isManager()
                    || myRole() == 'employee' || myRole() == 'technician'; }
```

### Protected Fields
- **Users:** can never set `isAdmin`, `isSuperAdmin`, `balance`
- **Shops:** only owner can update, `ownerUid` protected after creation
- **Audit logs:** **IMMUTABLE** (create only, no update/delete)

### Access Patterns
- **Super admin:** Full access to everything
- **Owner:** Full access within their shop
- **Manager:** CRUD within shop, cannot change roles
- **Employee/Technician:** Read + create within shop, limited updates
- All non-super-admin operations filtered by `shopId` in Custom Claims

---

## 16. Firestore Indexes

**File:** `firestore.indexes.json` — 15 composite indexes

| Collection | Fields | Purpose |
|-----------|--------|---------|
| chats | shopId + createdAt (desc) | Shop chat feed |
| shop_notifications | shopId + createdAt (desc) | Shop notifications |
| repairs | shopId + createdAt (desc) | Shop repairs list |
| products | shopId + status + createdAt (desc) | Active products |
| sales | shopId + soldAt (desc) | Sales feed |
| sales | shopId + deleted + soldAt (desc) | Non-deleted sales |
| expenses | shopId + date (desc) | Expenses feed |
| customers | shopId + deleted + name (asc) | Customer list |
| debts | shopId + status + createdAt (desc) | Active debts |
| debts | shopId + deleted + createdAt (desc) | Non-deleted debts |
| suppliers | shopId + active (desc) + name (asc) | Active suppliers |
| suppliers | shopId + deleted + active (desc) + name (asc) | Non-deleted suppliers |
| cash_closings | shopId + dateKey (desc) | Cash closing history |
| stock_entries | shopId + status + createdAt (desc) | Stock entries |
| stock_entries | shopId + type + createdAt (desc) | Stock by type |

---

## 17. Cloud Functions

**File:** `functions/index.js` (1244 lines)
**Runtime:** Node.js, Firebase Functions v2
**Region:** asia-southeast1

### Functions

| Function | Trigger | Purpose |
|----------|---------|---------|
| `syncUserClaims` | onDocumentWritten(`users/{userId}`) | Auto-sync Custom Claims when user doc changes |
| `refreshMyClaims` | onCall | User self-refreshes their claims |
| `updateUserRole` | onCall | Change user role (with hierarchy enforcement) |
| `addUserToShop` | onCall | Assign user to shop with role |
| `removeUserFromShop` | onCall | Remove user from shop |
| `getUserClaims` | onCall | Debug: view user's current claims |
| `notifyNewRepair` | onDocumentCreated(`repairs/{id}`) | FCM push for new repairs |
| `notifyNewChat` | onDocumentCreated(`chats/{id}`) | FCM multicast to shop members |
| `notifyStatusChange` | onDocumentUpdated(`repairs/{id}`) | FCM for repair status changes |
| `createStaffAccount` | onCall | Create Firebase Auth user + Firestore doc with permissions |
| `cleanupDeletedRepairs` | onSchedule (every 24h) | Opt-in cleanup of soft-deleted repairs |
| `sendShopNotification` | onCall | Role-based FCM push to shop members |
| `batchSyncAllClaims` | onCall (super admin, 9min timeout) | Batch sync all user claims |
| `syncUserClaimsV2` | onCall | Sync single user claims (v2) |
| `refreshMyClaimsV2` | onCall | Self-refresh claims (v2) |
| `getMyClaimsV2` | onCall | View current claims with sync status |
| `cleanupFCMTokens` | onSchedule (weekly Sun 3AM) | Remove old/duplicate FCM tokens |

### Claims Sync Logic
```
syncUserClaims trigger:
1. Read user doc (role, shopId, email)
2. Check super admin email (admin@huluca.com)
3. Set Custom Claims: { role, shopId, isSuperAdmin }
4. Update user doc: { claimsSyncedAt: serverTimestamp }
```

### FCM Token Management
- Tokens stored per-user in Firestore with metadata
- Weekly cleanup removes tokens >30 days old
- Deduplication on token refresh

---

## 18. Firebase Configuration

**File:** `lib/firebase_options.dart`

```dart
// Android only configured
apiKey: 'AIzaSyCajnpTNFifxkq37IqwT7Zj5bA6dJ64FPg'
appId: '1:51200928212:android:c0d1e9d964b3213b910e41'
messagingSenderId: '51200928212'
projectId: 'huyaka-1809'
storageBucket: 'huyaka-1809.firebasestorage.app'
```

**Android config:** `android/app/google-services.json`

---

## 19. Dependencies

### Core Firebase
```yaml
firebase_core: ^3.15.2
firebase_auth: ^5.3.0
cloud_firestore: ^5.3.0
cloud_functions: ^5.3.0
firebase_messaging: ^15.1.0
firebase_storage: ^12.4.10
```

### Local Database
```yaml
sqflite: ^2.3.0
shared_preferences: ^2.2.2
```

### UI & Charts
```yaml
fl_chart: ^0.65.0
intl: ^0.19.0
introduction_screen: ^3.1.12
flutter_slidable: ^3.0.1
```

### Printing
```yaml
print_bluetooth_thermal: ^1.1.1
esc_pos_printer: ^4.1.0
pdf: ^3.10.7
printing: ^5.11.1
```

### QR & Scanning
```yaml
qr_flutter: ^4.1.0
mobile_scanner: ^5.1.1
```

### Connectivity & Platform
```yaml
connectivity_plus: ^6.0.3
geolocator: ^13.0.2
permission_handler: ^11.3.1
package_info_plus: ^8.0.0
url_launcher: ^6.2.4
share_plus: ^9.0.0
```

### Data & Security
```yaml
encrypt: ^5.0.3
crypto: ^3.0.3
excel: ^4.0.2
file_picker: ^8.0.0+1
```

### Media
```yaml
image_picker: ^1.0.7
flutter_image_compress: ^2.2.0
gal: ^2.3.0
flutter_keyboard_visibility: ^6.0.0
```

### Bluetooth
```yaml
flutter_blue_plus: ^1.32.4
```

### Notifications
```yaml
flutter_local_notifications: ^17.1.2
```

---

## 20. Multi-Industry Support

### Business Types
```dart
enum: electronics | food | fashion | general
```

### Feature Flags per Business Type

| Feature | Electronics | Food | Fashion | General |
|---------|------------|------|---------|---------|
| enableRepair | Yes | No | No | No |
| enableSerial (IMEI) | Yes | No | No | No |
| enableWarranty | Yes | No | No | No |
| enableExpiry | No | Yes | No | No |
| enableBatch | No | Yes | No | No |
| enableVariants | No | No | Yes | No |

### BusinessTypeHelper + BusinessTerminology
Dynamic UI terminology that changes based on business type. E.g., product names and labels adapt to the industry context.

### Industry-Specific Views
- **Food:** `views/food/expiry_management_view.dart` — Expiry tracking, batch management
- **Fashion:** `views/fashion/variant_management_view.dart` — Size/color variant management
- **Onboarding:** `views/onboarding/business_type_wizard.dart` — New shop business type selection

---

## 21. Security & Encryption

### Security Layers

1. **Firebase Auth** — Email/password authentication
2. **Custom Claims** — role, shopId, isSuperAdmin in JWT token
3. **Firestore Rules** — 1081 lines of server-side access control
4. **AES-256-CBC Encryption** — Client-side encryption of sensitive fields before cloud upload
5. **PaymentBlocker** — Prevents bypassing unified payment flow
6. **MoneyValidationService** — Validates all monetary operations
7. **Audit Logs** — Immutable audit trail (create-only in Firestore rules)

### Super Admin Protection
- Hardcoded email: `admin@huluca.com`
- Identified in: UserService, Firestore Rules, Cloud Functions
- Has: Full access, shop management, batch claim sync

### Encryption Details
- Algorithm: AES-256-CBC
- Key: SHA256(shopId + masterSecret) = 32 bytes
- IV: MD5('IV_' + shopId) = 16 bytes
- Marker: `ENC:` prefix on encrypted values
- 23 sensitive fields encrypted before cloud storage
- Auto-detect on decryption (handles mixed encrypted/plain data)

---

## 22. Sync Architecture

### Data Flow

```
+-----------+     +----------------+     +-----------+
|  SQLite   | <-> | SyncService    | <-> | Firestore |
| (offline) |     | SyncOrchest.   |     |  (cloud)  |
+-----------+     +----------------+     +-----------+
     |                   |                     |
  DBHelper          EventBus             Cloud Functions
  (7024 lines)      (broadcast)          (17 functions)
```

### Sync Strategies

1. **Real-time Cloud -> Local** (`SyncService.initRealTimeSync`)
   - Firestore `snapshots()` listeners on 12+ collections
   - Conflict resolution via `_shouldAcceptCloudData()`
   - EventBus notifications for UI refresh

2. **Queue-based Local -> Cloud** (`SyncOrchestrator`)
   - SQLite `sync_queue` table
   - Auto-sync on network restore
   - Max 3 retries, then mark failed
   - Deduplication

3. **Bulk Download** (`SyncService.downloadAllFromCloud`)
   - Full collection download in batches of 50
   - Yields to main thread between batches (`Future.delayed(Duration.zero)`)
   - Used on first login or shop switch

4. **Health Check** (`SyncHealthCheck.runFullCheck`)
   - Compares local vs cloud record counts
   - Detects orphan records
   - Auto-fix capability

### Conflict Resolution Rules
1. Local record doesn't exist -> Accept cloud data
2. Local `isSynced == true` -> Accept cloud data (no pending changes)
3. Local `isSynced == false` -> **REJECT cloud data**, enqueue local for push
4. This prevents echo-back from cloud overwriting local edits

---

## 23. Navigation & Routing

### App Entry
```
SplashView -> AuthGate:
  +-- No user -> LoginView
  +-- Authenticated:
      +-- Super admin -> ShopSelectorView
      +-- Regular user -> HomeView(role)
```

### HomeView Navigation
- **Bottom Nav:** 6-9 tabs based on permissions and business type
- **Each tab contains:** Embedded views or navigates via `Navigator.push`
- **Drawer:** Settings, language, developer info
- **FAB:** Quick actions (new sale, new repair)

### Key Navigation Targets from HomeView
```
HomeView
+-- OrderListView (repairs)
+-- SaleListView (sales)
+-- CreateRepairOrderView
+-- CreateSaleView
+-- InventoryView
+-- FastInventoryInputView
+-- FastInventoryCheckView
+-- SmartStockInView
+-- PendingStockListView
+-- SupplierListView
+-- QuickInputCodesView
+-- CustomerManagementView
+-- RevenueView
+-- ExpenseView
+-- DebtView
+-- CashClosingView
+-- FinancialReportView
+-- FinancialActivityLogView
+-- BankInstallmentReportView
+-- WarrantyView
+-- StaffListView
+-- StaffPerformanceView
+-- AttendanceView
+-- AttendanceManagementView
+-- WorkScheduleSettingsView
+-- HRSalarySettingsView
+-- AdvancedChatView
+-- QRScanView
+-- ShopSettingsView
+-- PrinterSettingsView
+-- NotificationsView
+-- NotificationSettingsView
+-- GlobalSearchView
+-- SuperAdminView
+-- AboutDeveloperView
+-- UserGuideView
+-- ExpiryManagementView (food)
+-- VariantManagementView (fashion)
+-- BusinessTypeWizard (onboarding)
```

---

## 24. Permission System

### Role Hierarchy
```
superAdmin (admin@huluca.com)  ->  all access
owner                          ->  full shop access
manager                        ->  business access, limited finance
employee                       ->  basic operations, no finance
technician                     ->  repairs + parts only
user                           ->  minimal access (default)
```

### Permission Matrix (defaults)

| Permission | Owner | Manager | Employee | Technician | User |
|-----------|-------|---------|----------|------------|------|
| allowViewSales | Yes | Yes | Yes | No | No |
| allowViewRepairs | Yes | Yes | Yes | Yes | Yes |
| allowViewInventory | Yes | Yes | Yes | No | No |
| allowViewParts | Yes | Yes | Yes | Yes | Yes |
| allowViewSuppliers | Yes | Yes | Yes | No | No |
| allowViewCustomers | Yes | Yes | Yes | Yes | Yes |
| allowViewPurchaseOrders | Yes | Yes | Yes | No | No |
| allowCreatePurchaseOrders | Yes | Yes | No | No | No |
| allowViewWarranty | Yes | Yes | Yes | Yes | No |
| allowViewChat | Yes | Yes | Yes | Yes | Yes |
| allowViewAttendance | Yes | Yes | Yes | Yes | Yes |
| allowViewPrinter | Yes | Yes | Yes | Yes | Yes |
| allowViewRevenue | Yes | No | No | No | No |
| allowViewExpenses | Yes | No | No | No | No |
| allowViewDebts | Yes | No | No | No | No |
| allowViewCostPrice | Yes | Yes | No | No | No |
| allowViewSettings | Yes | Yes | No | No | No |
| allowManageStaff | Yes | Yes | No | No | No |

### Lock Mechanisms

1. **Owner-level:** Per-user permission overrides stored in Firestore user doc
2. **Super Admin-level:** Shop-wide flags:
   - `appLocked` -> Lock entire shop
   - `adminFinanceLocked` -> Lock finance for managers
   - `staffSalesLocked` -> Lock sales for staff
   - `staffInventoryLocked` -> Lock inventory for staff
   - `staffDebtLocked` -> Lock debts for staff
   - `staffSettingsLocked` -> Lock settings for staff/managers

### Lock Source Tracking
- `lockedByAdmin` -> List of permissions locked by super admin
- `lockedByOwner` -> List of permissions overridden by shop owner
- UI shows different messages based on lock source

---

## 25. Payment System

### Unified Payment Flow

```
Business Module -> Create PaymentIntent -> PaymentIntentService
                                                |
                                          Validation
                                     (MoneyValidationService)
                                                |
                                          Execution
                                     (MoneyTransactionService)
                                                |
                                          Record Activity
                                    (FinancialActivityService)
                                                |
                                         Sync to cloud
```

### PaymentBlocker Guard
```dart
// In any module that might bypass payments:
PaymentBlocker.block(); // Throws PaymentBlockedError

// Only PaymentIntentService can execute payments
```

### Payment Intent Types (17)
```
supplierPayment, customerDebtPayment, repairPayment, salePayment,
expensePayment, salaryPayment, repairPartnerPayment, supplierDebtPayment,
refund, inventoryPurchase, cashAdjustment, transferBetweenAccounts,
otherIncome, otherExpense, settlementPayment, debtCollection, staffAdvance
```

### Atomic Transactions
1. **Debt Payment:** `FirestoreService.executeDebtPaymentTransaction()` — Prevents race conditions
2. **Sale:** `FirestoreService.executeSaleTransaction()` — Prevents overselling with stock check

---

## Appendix: File Counts

| Directory | Files | Lines (approx) |
|-----------|-------|----------------|
| lib/models/ | 31 | ~4,000 |
| lib/services/ | 43 | ~25,000 |
| lib/views/ | 80+ | ~40,000 |
| lib/widgets/ | 28 | ~8,000 |
| lib/data/ | 1 | 7,024 |
| lib/utils/ | 12 | ~2,000 |
| lib/theme/ | 4 | ~1,100 |
| lib/constants/ | 3 | ~970 |
| lib/core/ | 3+ | ~300 |
| lib/l10n/ | 5 | ~5,000 |
| lib/controllers/ | 1 | ~200 |
| functions/ | 3 | ~1,300 |
| Firestore rules | 1 | 1,081 |
| **Total** | **~215** | **~95,000** |

---

*Documentation generated from comprehensive codebase analysis. Last updated: 2025.*
