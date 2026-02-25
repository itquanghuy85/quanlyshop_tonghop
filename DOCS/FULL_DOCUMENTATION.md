# HULUCA Shop Manager (Quản Lý Shop) — Complete Project Structure

> **App Name:** HULUCA Shop Manager  
> **Package:** `com.huluca.shopmanager`  
> **Version:** 10.1.0+170  
> **SDK:** Flutter (Dart) ≥3.10.0 <4.0.0  
> **Generated:** 2026-02-26  

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Views (lib/views/)](#2-views)
3. [Models (lib/models/)](#3-models)
4. [Services (lib/services/)](#4-services)
5. [Widgets (lib/widgets/)](#5-widgets)
6. [Data Layer (lib/data/)](#6-data-layer)
7. [Constants (lib/constants/)](#7-constants)
8. [Theme (lib/theme/)](#8-theme)
9. [Controllers (lib/controllers/)](#9-controllers)
10. [Core (lib/core/)](#10-core)
11. [Utils (lib/utils/)](#11-utils)
12. [Assets & Localization (lib/assets/, lib/l10n/)](#12-assets--localization)
13. [Entry Point (lib/main.dart)](#13-entry-point)
14. [Dependencies (pubspec.yaml)](#14-dependencies)
15. [Firestore Collections](#15-firestore-collections)
16. [SQLite Local Tables](#16-sqlite-local-tables)
17. [Navigation Structure](#17-navigation-structure)
18. [Security & Roles](#18-security--roles)

---

## 1. Architecture Overview

```
lib/
├── main.dart                  # App entry point, Firebase init, AuthGate, global error handling
├── firebase_options.dart      # Firebase configuration (auto-generated)
├── assets/                    # Bundled fonts & images
├── constants/                 # Enums, static constants
├── controllers/               # MVC controllers
├── core/                      # App config, payment blocker, core utils
├── data/                      # SQLite DB helper, repositories
├── l10n/                      # Localization (Vietnamese/English)
├── models/                    # Data models (Firestore + SQLite)
├── services/                  # Business logic, Firebase integration, sync
├── theme/                     # Colors, text styles, button styles, theme
├── utils/                     # Utility classes (formatters, validators, parsers)
├── views/                     # All screens/pages
│   ├── hr/                    # HR sub-screens (salary, deductions)
│   ├── fashion/               # Fashion industry screens (variants)
│   ├── food/                  # Food industry screens (expiry)
│   └── onboarding/            # Business type wizard
└── widgets/                   # Reusable UI components
```

**Key Patterns:**
- **Offline-first:** SQLite local DB (`sqflite`) + Firestore real-time sync
- **Multi-tenant:** All data isolated by `shopId`
- **Role-based:** superAdmin > owner > manager > employee/technician
- **Multi-industry:** Electronics (default), Fashion, Food — controlled by feature flags
- **Service-first:** No direct Firebase calls from widgets; all through service classes

---

## 2. Views (lib/views/)

### Root-level Views

| File | Class | Description |
|------|-------|-------------|
| `home_view.dart` | `HomeView` | Main dashboard with bottom navigation (Home/Sales/Repairs/Inventory/Expiry/Variants/Staff/Finance/Settings tabs) |
| `login_view.dart` | `LoginView` | Firebase Auth login screen |
| `register_view.dart` | `RegisterView` | User registration screen |
| `splash_view.dart` | `SplashView` | Splash/loading screen shown at app start |
| `intro_view.dart` | `IntroView` | App introduction/onboarding carousel |
| `shop_selector_view.dart` | `ShopSelectorView` | Super admin shop selection screen |
| `settings_view.dart` | `SettingsView` | App settings (language, theme, data management) |
| `shop_settings_view.dart` | `ShopSettingsView` | Shop-specific settings (name, business type, modules) |
| `my_profile_view.dart` | `MyProfileView` | User profile editing |
| `about_developer_view.dart` | `AboutDeveloperView` | Developer information / about page |
| `super_admin_view.dart` | `SuperAdminView` | Super admin management panel |
| `user_guide_view.dart` | `UserGuideView` | In-app user guide / help |
| `help_center_view.dart` | `HelpCenterView` | Help center with searchable articles |

### Sales & Orders

| File | Class | Description |
|------|-------|-------------|
| `create_sale_view.dart` | `CreateSaleView` | Create new sale order |
| `sale_list_view.dart` | `SaleListView` | List all sale orders |
| `sale_detail_view.dart` | `SaleDetailView` | Sale order detail with edit/cancel |
| `sale_invoice_preview_view.dart` | `SaleInvoicePreviewView` | Preview sale invoice before printing |
| `sale_invoice_template_view.dart` | `SaleInvoiceTemplateView` | Customize sale invoice template |
| `order_list_view.dart` | `OrderListView` | Combined order listing (repairs + sales) |

### Repairs

| File | Class | Description |
|------|-------|-------------|
| `create_repair_order_view.dart` | `CreateRepairOrderView` | Create new repair order |
| `repair_detail_view.dart` | `RepairDetailView` | Repair order detail and status updates |
| `repair_receipt_view.dart` | `RepairReceiptView` | Generate repair receipt for customer |
| `repair_invoice_preview_view.dart` | `RepairInvoicePreviewView` | Preview repair invoice |
| `repair_invoice_template_view.dart` | `RepairInvoiceTemplateView` | Customize repair invoice template |
| `warranty_view.dart` | `WarrantyView` | Warranty tracking and management |

### Repair Partners

| File | Class | Description |
|------|-------|-------------|
| `repair_partner_view.dart` | `RepairPartnerView` | List repair partners (outsource technicians) |
| `repair_partner_detail_view.dart` | `RepairPartnerDetailView` | Partner detail with history/payments |
| `repair_partner_form_view.dart` | `RepairPartnerFormView` | Add/edit repair partner form |
| `partner_management_view.dart` | `PartnerManagementView` | Partner management dashboard |

### Inventory & Products

| File | Class | Description |
|------|-------|-------------|
| `inventory_view.dart` | `InventoryView` | Product inventory management (list, search, filter) |
| `fast_inventory_input_view.dart` | `FastInventoryInputView` | Quick product entry with barcode/QR |
| `fast_inventory_check_view.dart` | `FastInventoryCheckView` | Physical inventory check/verification |
| `fast_stock_in_view.dart` | `FastStockInView` | Rapid stock-in entry |
| `smart_stock_in_view.dart` | `SmartStockInView` | Smart stock entry with supplier integration |
| `pending_stock_list_view.dart` | `PendingStockListView` | List pending/draft stock entries |
| `parts_inventory_view.dart` | `PartsInventoryViewContent` | Repair parts inventory management |
| `category_management_view.dart` | `CategoryManagementView` | Product category CRUD (multi-industry) |
| `quick_input_codes_view.dart` | `QuickInputCodesView` | Quick input code templates |
| `quick_input_library_view.dart` | `QuickInputLibraryView` | Library of saved quick input codes |
| `quick_input_management_view.dart` | `QuickInputManagementView` | Manage quick input code presets |

### Customers

| File | Class | Description |
|------|-------|-------------|
| `customer_management_view.dart` | `CustomerManagementView` | Customer list/search/CRUD |
| `customer_history_view.dart` | `CustomerHistoryView` | Customer transaction history |

### Suppliers

| File | Class | Description |
|------|-------|-------------|
| `supplier_list_view.dart` | `SupplierListView` | List all suppliers |
| `supplier_detail_view.dart` | `SupplierDetailView` | Supplier detail with import history |
| `supplier_details_dialog.dart` | `SupplierDetailsDialog` | Quick supplier info dialog |
| `supplier_form_view.dart` | `SupplierFormView` | Add/edit supplier form |
| `create_purchase_order_view.dart` | `CreatePurchaseOrderView` | Create purchase order to supplier |
| `purchase_order_list_view.dart` | `PurchaseOrderListView` | List all purchase orders |

### Finance

| File | Class | Description |
|------|-------|-------------|
| `revenue_view.dart` | `RevenueView` | Revenue dashboard with charts |
| `expense_view.dart` | `ExpenseView` | Expense tracking and management |
| `debt_view.dart` | `DebtView` | Debt management (customer/shop debts) |
| `cash_closing_view.dart` | `CashClosingView` | Daily cash closing / reconciliation |
| `financial_report_view.dart` | `FinancialReportView` | Comprehensive financial reports |
| `financial_activity_log_view.dart` | `FinancialActivityLogView` | Financial activity audit trail |
| `bank_installment_report_view.dart` | `BankInstallmentReportView` | Bank installment tracking |
| `adjustment_history_view.dart` | `AdjustmentHistoryView` | View history of cash adjustments |

### HR & Staff

| File | Class | Description |
|------|-------|-------------|
| `staff_list_view.dart` | `StaffListView` | Staff roster management |
| `staff_permissions_view.dart` | `StaffPermissionsView` | Configure staff access permissions |
| `staff_performance_view.dart` | `StaffPerformanceView` | Staff performance metrics/KPIs |
| `attendance_view.dart` | `AttendanceView` | Employee attendance check-in/out |
| `attendance_management_view.dart` | `AttendanceManagementView` | Manager attendance review/approval |
| `payroll_view.dart` | `PayrollView` | Payroll calculation and salary slips |
| `hr_salary_settings_view.dart` | `HRSalarySettingsView` | HR salary configuration |
| `work_schedule_settings_view.dart` | `WorkScheduleSettingsView` | Work schedule / shift configuration |

### Printing & Labels

| File | Class | Description |
|------|-------|-------------|
| `printer_settings_view.dart` | `PrinterSettingsView` | Printer setup (Bluetooth/WiFi) |
| `printer_setting_view.dart` | `PrinterSettingView` | Individual printer configuration |
| `thermal_printer_design_view.dart` | `ThermalPrinterDesignView` | Design thermal print layouts |
| `label_designer_view.dart` | `LabelDesignerView` | Drag-and-drop label designer |
| `label_settings_view.dart` | `LabelSettingsView` | Label template settings |
| `imei_qr_print_view.dart` | `ImeiQrPrintView` | Print IMEI/QR labels |
| `imei_qr_printer_view.dart` | `ImeiQrPrinterView` | IMEI/QR code printer interface |
| `pty_print_designer_view.dart` | `PtyPrintDesignerView` | Property label print designer |
| `invoice_template_view.dart` | `InvoiceTemplateView` | Invoice template customization |

### Communication

| File | Class | Description |
|------|-------|-------------|
| `advanced_chat_view.dart` | `AdvancedChatView` | In-shop team chat with reactions/pins |
| `notifications_view.dart` | `NotificationsView` | Notification center |
| `notification_settings_view.dart` | `NotificationSettingsView` | Configure notification preferences |

### Search & QR

| File | Class | Description |
|------|-------|-------------|
| `global_search_view.dart` | `GlobalSearchView` | Cross-module search |
| `global_search_results_view.dart` | `GlobalSearchResultsView` | Search results display |
| `qr_scan_view.dart` | `QrScanView` | QR/barcode scanner |

### Audit

| File | Class | Description |
|------|-------|-------------|
| `audit_log_view.dart` | `AuditLogView` | View immutable audit logs |

### Sub-folder: `views/hr/`

| File | Class | Description |
|------|-------|-------------|
| `shop_deduction_settings_view.dart` | `ShopDeductionSettingsView` | Shop-level salary deduction/insurance/tax settings |
| `add_custom_adjustment_dialog.dart` | `AddCustomAdjustmentDialog` | Dialog to add custom salary bonus/deduction |

### Sub-folder: `views/fashion/`

| File | Class | Description |
|------|-------|-------------|
| `variant_management_view.dart` | `VariantManagementView` | Product variant (size/color) management for fashion shops |

### Sub-folder: `views/food/`

| File | Class | Description |
|------|-------|-------------|
| `expiry_management_view.dart` | `ExpiryManagementView` | Product expiry date tracking for food shops |

### Sub-folder: `views/onboarding/`

| File | Class | Description |
|------|-------|-------------|
| `business_type_wizard.dart` | `BusinessTypeWizard` | Multi-industry setup wizard (electronics/fashion/food) |

---

## 3. Models (lib/models/)

| File | Class | Key Fields |
|------|-------|------------|
| `repair_model.dart` | `Repair` | customerName, phone, model, issue, status (1-4), price, cost, paymentMethod, partsUsed, createdAt, repairedBy, warranty, imei, services |
| `product_model.dart` | `Product` | name, brand, model, imei, cost, price, condition, quantity, type (DIEN_THOAI/PHU_KIEN/LINH_KIEN/QUAN_AO/GIAY_DEP), category, expiryDate, batchNumber |
| `sale_order_model.dart` | `SaleOrder` | customerName, productNames, productImeis, totalPrice, totalCost, discount, paymentMethod, isInstallment, downPayment, installmentMonths |
| `customer_model.dart` | `Customer` | name, phone, email, address, totalSpent, totalRepairs |
| `debt_model.dart` | `Debt` | personName, totalAmount, paidAmount, type (CUSTOMER_OWES/SHOP_OWES), status (ACTIVE/PAID/CANCELLED), linkedId |
| `expense_model.dart` | `Expense` | title, amount, category, date, paymentMethod, type (CHI) |
| `attendance_model.dart` | `Attendance` | userId, dateKey, checkInAt, checkOutAt, overtimeOn, status (pending/approved/rejected), isLate, isEarlyLeave |
| `supplier_model.dart` | `Supplier` | name, phone, email, address, active, favorite, importCount, totalAmount |
| `supplier_payment_model.dart` | `SupplierPayment` | supplierId, amount, paidAt, paymentMethod |
| `supplier_import_history_model.dart` | `SupplierImportHistory` | supplierId, batchId, importDate, totalQuantity, totalCost |
| `supplier_product_prices_model.dart` | `SupplierProductPrices` | supplierId, productId, costPrice, sellingPrice, quantity, remainingQuantity |
| `purchase_order_model.dart` | `PurchaseOrder` / `PurchaseItem` | orderCode, supplierName, items[], totalAmount, status (PENDING/CONFIRMED) |
| `repair_partner_model.dart` | `RepairPartner` | name, phone, note, active |
| `repair_partner_payment_model.dart` | `RepairPartnerPayment` | partnerId, amount, paidAt, paymentMethod |
| `partner_repair_history_model.dart` | `PartnerRepairHistory` | repairOrderId, partnerId, customerName, deviceModel, partnerCost |
| `employee_salary_model.dart` | `EmployeeSalarySettings` | staffId, baseSalary, dailyRate, salaryType (monthly/daily/hourly), saleCommType, saleCommValue, repairCommType, repairCommValue, transportAllowance, mealAllowance, monthlyTarget, overtimeRate |
| `salary_breakdown_model.dart` | `SalaryBreakdown` | staffId, workDays, totalWorkHours, overtimeHours, lateDays, saleOrderCount, saleRevenue, baseSalary, calculatedSaleComm, calculatedRepairComm, socialInsurance, healthInsurance, personalIncomeTax, totalSalary |
| `shop_deduction_settings.dart` | `ShopDeductionSettings` | enableLateDeduction, lateDeductionPerTime, enablePIT, pitDeductionSelf, enableSocialInsurance, socialInsuranceRate, enableHealthInsurance, healthInsuranceRate, insuranceBaseSalary |
| `payment_intent_model.dart` | `PaymentIntent` | intentId, type, amount, status, metadata — payment pipeline |
| `financial_activity_model.dart` | `FinancialActivity` | type, amount, relatedType, relatedId — financial ledger entries |
| `product_category_model.dart` | `ProductCategory` | name, parentId, trackExpiry, trackSerial, hasVariants, hasWarranty, defaultWarrantyDays, customFields, sortOrder |
| `product_variant_model.dart` | `ProductVariant` | productId, sku, size, color, colorCode, material, style, costPrice, salePrice, quantity, barcode |
| `shop_settings_model.dart` | `ShopSettings` | businessType (electronics/fashion/food), enableRepair, enableExpiry, enableVariants, enableSerial, enableWarranty, enableBatch, defaultUnit, expiryWarningDays |
| `stock_entry_model.dart` | `StockEntry` / `StockEntryItem` | items[], status (draft/confirmed/cancelled), name, quantity, cost, imei, brand, model, sku, size, productType |
| `chat_message_model.dart` | `ChatMessage` | message, senderId, reactions, isPinned, linkedType |
| `inventory_check_model.dart` | `InventoryCheck` | type, checkDate, itemsJson, status, isCompleted |
| `inventory_zone_model.dart` | `InventoryZone` | name, expectedProductCodes, scannedCounts |
| `label_template_model.dart` | `LabelTemplate` | name, type, size, fields, shopInfo, cpkFormula, isDefault |
| `quick_input_code_model.dart` | `QuickInputCode` | code, name, type, brand, model, capacity, cost, price |
| `repair_service_model.dart` | `RepairService` | service definition for repair orders |
| `printer_types.dart` | *(enums)* | Printer type enums (Bluetooth/WiFi) |

---

## 4. Services (lib/services/)

### Authentication & User Management

| File | Class | Key Methods |
|------|-------|-------------|
| `user_service.dart` | `UserService` | `syncUserInfo()`, `getUserRole()`, `getCurrentShopId()`, `ensureShopId()`, `isCurrentUserSuperAdmin()`, `validatePhone()`, `validateName()`, `clearCache()` |
| `claims_service.dart` | `ClaimsService` | `getRoleFromClaims()`, `getShopIdFromClaims()`, `isSuperAdmin()`, `isOwner()`, `forceRefresh()`, `startClaimsSync()` |
| `current_shop_service.dart` | `CurrentShopService` | `init()`, `getActiveShopId()`, `hasMultipleShops()`, `switchShop()`, `clearActiveShop()` |

### Firestore & Sync

| File | Class | Key Methods |
|------|-------|-------------|
| `firestore_service.dart` | `FirestoreService` | `addRepair()`, `addSale()`, `addProduct()`, `addPurchaseOrder()`, `upsertRepair()`, `deleteRepair()`, `updateSaleCloud()` — all Firestore CRUD with shopId filtering |
| `sync_service.dart` | `SyncService` | `initRealTimeSync()`, `downloadAllFromCloud()`, `cancelAllSubscriptions()` — real-time Firestore→SQLite sync |
| `sync_orchestrator.dart` | `SyncOrchestrator` | `init()`, `enqueue()`, `syncAll()` — local→cloud sync queue |
| `sync_health_check.dart` | `SyncHealthCheck` | `runFullCheck()`, `autoFix()` — data consistency checker |
| `sync_control.dart` | *(sync flags)* | Sync control utilities |
| `connectivity_service.dart` | `ConnectivityService` | `initialize()`, `testConnection()`, `manualSync()` — network state management |

### Business Operations

| File | Class | Key Methods |
|------|-------|-------------|
| `customer_service.dart` | `CustomerService` | `getCustomers()`, `addCustomer()`, `searchCustomers()`, `getCustomerByPhone()`, `updateCustomerStatsAfterSale()` |
| `supplier_service.dart` | `SupplierService` | `getSuppliers()`, `addSupplier()`, `getSupplierImportHistory()`, `getSupplierProductPrices()` |
| `supplier_payment_service.dart` | `SupplierPaymentService` | `getSupplierPayments()`, `addSupplierPayment()` |
| `repair_partner_service.dart` | `RepairPartnerService` | `getRepairPartners()`, `addRepairPartner()`, `addPartnerRepairHistory()`, `createPartnerHistoryForRepair()` |
| `repair_partner_payment_service.dart` | `RepairPartnerPaymentService` | `getPartnerPayments()`, `addPartnerPayment()` |
| `stock_entry_service.dart` | `StockEntryService` | `createEntry()`, `confirmEntry()`, `cancelEntry()`, `getPendingEntries()`, `getPendingCount()` |
| `category_service.dart` | `CategoryService` | `getShopSettings()`, `saveShopSettings()`, `getCategories()`, `addCategory()` |
| `variant_service.dart` | `VariantService` | `createVariant()`, `updateVariant()`, `getVariantsByProduct()`, `getVariantByBarcode()`, `updateQuantity()` |
| `expiry_alert_service.dart` | `ExpiryAlertService` | `getExpiredProducts()`, `getNearExpiryProducts()`, `getExpiryStats()`, `checkAndNotifyExpiry()` |
| `business_type_helper.dart` | `BusinessTypeHelper` | `getSettings()`, `isElectronics()`, `isFood()`, `isFashion()`, `isRepairEnabled()`, `isExpiryEnabled()` |
| `chat_service.dart` | `ChatService` | `sendTextMessage()`, `sendImageMessage()`, `addReaction()`, `editMessage()`, `pinMessage()` |

### Finance

| File | Class | Key Methods |
|------|-------|-------------|
| `payment_intent_service.dart` | `PaymentIntentService` | `initialize()`, `createIntent()`, `getPendingIntents()`, `getAllIntents()` — centralized payment flow |
| `financial_activity_service.dart` | `FinancialActivityService` | `logSale()`, `logExpense()`, `logPurchase()`, `logDebtCollection()`, `logRepair()` — financial ledger |
| `money_transaction_service.dart` | `MoneyTransactionService` | `appendLedger()`, `getLedgerEntries()` |
| `money_validation_service.dart` | `MoneyValidationService` | `validateAmount()`, `validateSale()`, `validateDebtPayment()`, `validateStockChange()` |
| `adjustment_service.dart` | `AdjustmentService` | `getLockedDateKey()`, `canEditDirectly()`, `adjustPartCost()`, `adjustPayment()`, `paySupplierDebt()` |
| `cash_closing_notifier.dart` | `CashClosingNotifier` | `init()`, `isDateLocked()`, `canPerformTransaction()` — real-time cash closing status |
| `salary_calculation_service.dart` | `SalaryCalculationService` | `calculateMonthlySalary()`, `calculateAllStaffSalaries()`, `getShopDeductionSettings()`, `saveShopDeductionSettings()`, `getCustomAdjustments()` |
| `salary_slip_pdf_service.dart` | `SalarySlipPdfService` | `generateSalarySlipPdf()`, `printSalarySlipThermal()`, `shareSalarySlip()`, `generateAllStaffSalaryPdf()` |

### Printing

| File | Class | Key Methods |
|------|-------|-------------|
| `bluetooth_printer_service.dart` | `BluetoothPrinterService` | `connect()`, `disconnect()`, `getPairedPrinters()`, `printBytes()` |
| `wifi_printer_service.dart` | `WifiPrinterService` | `connect()`, `printBytes()`, `disconnect()` |
| `thermal_printer_service.dart` | `ThermalPrinterService` | `printDeviceLabel()`, `printDeviceLabelWifi()`, `testConnection()` |
| `unified_printer_service.dart` | `UnifiedPrinterService` | Unified print API with template support |
| `label_settings_service.dart` | `LabelSettingsService` | `getTemplates()`, `getDefaultTemplate()`, `addCustomTemplate()` |

### Infrastructure

| File | Class | Key Methods |
|------|-------|-------------|
| `notification_service.dart` | `NotificationService` | `init()`, `listenToNotifications()`, `refreshFCMToken()`, `showSnackBar()`, `handleBackgroundMessage()` |
| `audit_service.dart` | `AuditService` | `logAction()` — immutable action logging |
| `encryption_service.dart` | `EncryptionService` | `init()`, `encrypt()`, `decrypt()` |
| `storage_service.dart` | `StorageService` | `uploadAndGetUrl()`, `uploadMultipleImages()` — Firebase Storage |
| `logging_service.dart` | `LoggingService` | `log()`, `logError()` |
| `event_bus.dart` | `EventBus` | `emit()`, `on()`, `off()` — in-app event system |
| `data_migration_service.dart` | `DataMigrationService` | `findOrphanData()`, `findAllOrphanData()` |
| `shop_deletion_service.dart` | `ShopDeletionService` | `deleteShopSafe()`, `canDeleteShop()` |
| `first_time_guide_service.dart` | `FirstTimeGuideService` | `hasShownGuide()`, `showGuideIfNeeded()`, `showCarouselGuide()` |

---

## 5. Widgets (lib/widgets/)

| File | Class | Description |
|------|-------|-------------|
| `app_ui_helpers.dart` | `AppUIHelpers` | Common UI helper methods |
| `currency_text_field.dart` | `CurrencyTextField` | Money input with VNĐ formatting |
| `custom_app_bar.dart` | `CustomAppBar` | Branded app bar with standard styling |
| `debounced_search_field.dart` | `DebouncedSearchField` | Search input with debounce |
| `dynamic_form_builder.dart` | `DynamicFormBuilder` | Dynamically generate forms from config |
| `expiry_badge.dart` | `ExpiryBadge` | Color-coded expiry status badge |
| `global_search_bar.dart` | `GlobalSearchBar` | Top-level search bar widget |
| `gradient_fab.dart` | `GradientFAB` | Floating action button with gradient |
| `imei_scan_result_dialog.dart` | `ImeiScanResultDialog` | Dialog showing IMEI scan results |
| `lazy_load_list_view.dart` | `LazyLoadListView` | Paginated list with infinite scroll |
| `loading_intro_screen.dart` | `LoadingIntroScreen` | Animated loading screen during sync |
| `notification_badge.dart` | `NotificationBadge` | Badge showing unread notification count |
| `notification_item.dart` | `NotificationItem` | Individual notification list item |
| `parts_selection_dialog.dart` | `PartsSelectionDialog` | Dialog for selecting repair parts |
| `pending_stock_widget.dart` | `PendingStockWidget` | Badge/indicator for pending stock entries |
| `pending_sync_indicator.dart` | `PendingSyncIndicator` | Shows pending sync count |
| `perpetual_calendar.dart` | `PerpetualCalendar` | Calendar widget for date selection |
| `printer_selection_dialog.dart` | `PrinterSelectionDialog` | Dialog to choose printer |
| `print_label_dialog.dart` | `PrintLabelDialog` | Dialog for print label options |
| `print_label_dialog_v2.dart` | `PrintLabelDialogV2` | Updated label print dialog |
| `safe_stream_builder.dart` | `SafeStreamBuilder` | StreamBuilder with error handling |
| `section_card.dart` | `SectionCard` | Styled card for section grouping |
| `shop_switcher_widget.dart` | `ShopSwitcherWidget` | Multi-shop switcher dropdown |
| `simple_sync_indicator.dart` | `SimpleSyncIndicator` | Minimal sync status indicator |
| `sync_status_widget.dart` | `SyncStatusWidget` | Detailed sync status display |
| `unified_sync_button.dart` | `UnifiedSyncButton` | One-tap sync/refresh button |
| `validated_text_field.dart` | `ValidatedTextField` | Text field with built-in validation |
| `variant_selector.dart` | `VariantSelector` | Size/color variant picker (fashion) |

---

## 6. Data Layer (lib/data/)

| File | Class | Description |
|------|-------|-------------|
| `db_helper.dart` | `DBHelper` | SQLite database wrapper — singleton, version 80, 25+ tables. Offline-first patterns with `isSynced` flags, `firestoreId` keys, upsert/soft-delete methods |
| `help_center_repository.dart` | `HelpCategory` / `HelpCenterRepository` | In-app help articles data source |
| `user_guide_repository.dart` | `GuideModule` / `UserGuideRepository` | User guide content data source |

---

## 7. Constants (lib/constants/)

| File | Class | Description |
|------|-------|-------------|
| `financial_constants.dart` | *(enums)* | `PaymentMethod` enum (cash/transfer/debt/installment/mixed/bank), `DebtType`, `ExpenseCategory`, `FinancialActivityType`, `MoneyDirection` — centralized financial enums |
| `partner_constants.dart` | `PartnerConstants` | Payment methods for partners, status constants |
| `product_constants.dart` | `ProductConstants` | Color lists, brand lists (IPHONE/SAMSUNG/OPPO...), capacity list, conditions, product types, size lists |

---

## 8. Theme (lib/theme/)

| File | Class | Description |
|------|-------|-------------|
| `app_theme.dart` | `AppTheme` | `lightTheme` — Material ThemeData for the entire app |
| `app_colors.dart` | `AppColors` | App color palette (primary, surface, error, background, etc.) |
| `app_text_styles.dart` | `AppTextStyles` | Typography styles (headline, subtitle, body, caption) |
| `app_button_styles.dart` | `AppButtonStyles` | Reusable button styles (primary, secondary, outline, danger) |

---

## 9. Controllers (lib/controllers/)

| File | Class | Description |
|------|-------|-------------|
| `fast_inventory_input_controller.dart` | `FastInventoryInputController` | Business logic controller for fast inventory input |

---

## 10. Core (lib/core/)

| File | Class | Description |
|------|-------|-------------|
| `app_config.dart` | `AppConfig` / `EnvConfig` | App-wide config: sync timeouts, cache settings, image compression, pagination, feature flags. `EnvConfig` for app name, package name, support email |
| `payment_blocker.dart` | `PaymentBlocker` / `PaymentBlockedError` | Guards against direct payment operations that bypass `PaymentIntentService` |

### Sub-folder: `core/utils/`

| File | Class | Description |
|------|-------|-------------|
| `money_utils.dart` | `MoneyUtils` | VNĐ formatting, parsing, compact display (canonical money utility) |

---

## 11. Utils (lib/utils/)

| File | Class | Description |
|------|-------|-------------|
| `app_info.dart` | `AppInfo` | App version, build number from `package_info_plus` |
| `app_logger.dart` | `AppLogger` | Structured logging utility |
| `debouncer.dart` | `Debouncer` | Configurable debounce utility |
| `imei_extractor.dart` | `IMEIExtractResult` | Extract IMEI numbers from scanned text |
| `money_input_formatter.dart` | `MoneyInputFormatter` | `TextInputFormatter` for VNĐ input (dot separators) |
| `money_utils.dart` | `MoneyUtils` | *(duplicate of core/utils — legacy compatibility)* |
| `qr_parser.dart` | `QRParser` | Parse QR code content into structured data |
| `qr_router.dart` | `QRRouter` | Route to appropriate screen based on QR content |
| `repair_status_validator.dart` | `RepairStatusValidator` | Validate repair status transitions (1→2→3→4) |
| `sku_generator.dart` | `SKUGenerator` | Auto-generate SKU codes for products |
| `ui_constants.dart` | `UIConstants` | Shared UI dimension/spacing constants |
| `vietnamese_utils.dart` | `VietnameseUtils` | Vietnamese string normalization, diacritics handling |

---

## 12. Assets & Localization

### `lib/assets/`
- `fonts/Roboto-Bold.ttf` — Bold font for PDF generation
- `fonts/Roboto-Regular.ttf` — Regular font for PDF generation
- `images/icon.png` — App icon

### `lib/l10n/` (Localization)

| File | Description |
|------|-------------|
| `app_vi.arb` | Vietnamese translations (template) |
| `app_en.arb` | English translations |
| `app_localizations.dart` | Generated localization delegate |
| `app_localizations_vi.dart` | Generated Vietnamese localization |
| `app_localizations_en.dart` | Generated English localization |

**Supported locales:** `vi` (Vietnamese, default), `en` (English)

---

## 13. Entry Point (lib/main.dart)

**Flow:**
1. `main()` → `runZonedGuarded()` for global error handling
2. Initialize Firebase (deferred on iOS for faster splash)
3. Initialize `NotificationService`, `ConnectivityService`
4. Run `MyApp` → `MaterialApp` with `SplashView` as home
5. `SplashView` → `AuthGate`
6. `AuthGate` listens to `FirebaseAuth.authStateChanges()`:
   - **Not logged in** → `LoginView`
   - **Super admin** → `ShopSelectorView`
   - **Normal user** → sync data → `HomeView`
7. Background init: `SyncService.downloadAllFromCloud()`, `SyncOrchestrator`, `CashClosingNotifier`, `PaymentIntentService`

---

## 14. Dependencies (pubspec.yaml)

### Firebase
| Package | Version | Purpose |
|---------|---------|---------|
| `firebase_core` | ^3.15.2 | Firebase initialization |
| `firebase_auth` | ^5.3.0 | Authentication |
| `cloud_firestore` | ^5.3.0 | NoSQL database |
| `cloud_functions` | ^5.3.0 | Cloud Functions |
| `firebase_messaging` | ^15.1.0 | Push notifications |
| `firebase_storage` | ^12.4.10 | File/image storage |

### Data & Storage
| Package | Version | Purpose |
|---------|---------|---------|
| `sqflite` | ^2.3.0 | SQLite local database |
| `shared_preferences` | ^2.5.4 | Key-value persistent storage |
| `path` | ^1.8.3 | File path utilities |
| `path_provider` | ^2.1.5 | App directory paths |

### UI & Charts
| Package | Version | Purpose |
|---------|---------|---------|
| `cupertino_icons` | ^1.0.6 | iOS-style icons |
| `fl_chart` | ^0.66.0 | Charts (revenue, performance) |
| `photo_view` | ^0.15.0 | Zoomable image viewer |
| `introduction_screen` | ^3.1.14 | Onboarding carousel |
| `qr_flutter` | ^4.1.0 | QR code generation |

### Printing & Labels
| Package | Version | Purpose |
|---------|---------|---------|
| `print_bluetooth_thermal` | ^1.1.0 | Bluetooth thermal printing |
| `flutter_esc_pos_utils` | ^1.0.1 | ESC/POS command generation |
| `pdf` | ^3.11.0 | PDF generation |
| `printing` | ^5.14.0 | PDF printing/sharing |
| `barcode` | ^2.2.6 | Barcode generation |
| `barcode_image` | ^2.0.2 | Barcode-to-image |

### Scanning & Input
| Package | Version | Purpose |
|---------|---------|---------|
| `mobile_scanner` | ^7.0.1 | Camera barcode/QR scanner |
| `image_picker` | ^1.0.7 | Camera/gallery image picker |
| `file_picker` | ^8.0.0 | File selection |

### Data Processing
| Package | Version | Purpose |
|---------|---------|---------|
| `intl` | 0.20.2 | Date/number formatting |
| `excel` | ^4.0.0 | Excel import/export |
| `csv` | ^6.0.0 | CSV import/export |
| `encrypt` | ^5.0.3 | Data encryption |
| `crypto` | ^3.0.3 | Cryptographic hashing |

### Sharing & Communication
| Package | Version | Purpose |
|---------|---------|---------|
| `share_plus` | ^12.0.1 | Native share sheet |
| `url_launcher` | ^6.3.2 | Open URLs/phone/email |
| `gal` | ^2.3.2 | Save to gallery |
| `screenshot` | ^3.0.0 | Widget screenshot capture |

### Platform & Connectivity
| Package | Version | Purpose |
|---------|---------|---------|
| `connectivity_plus` | ^6.0.0 | Network status monitoring |
| `permission_handler` | ^11.3.1 | Runtime permission management |
| `geolocator` | ^12.0.0 | GPS/location services |
| `flutter_blue_plus` | ^1.35.3 | Bluetooth Low Energy |
| `package_info_plus` | ^8.0.0 | App meta info |
| `flutter_image_compress` | ^2.3.0 | Image compression |
| `flutter_local_notifications` | ^17.1.2 | Local notifications |
| `timezone` | ^0.9.2 | Timezone handling |
| `flutter_keyboard_visibility` | *(transitive)* | Keyboard state |

### Dev Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Unit/widget testing |
| `flutter_lints` | ^3.0.0 | Lint rules |
| `flutter_launcher_icons` | ^0.11.0 | App icon generation |

---

## 15. Firestore Collections

All collections use `shopId` for multi-tenant isolation. Super admin bypasses filtering.

### Auth & Users (`SECTION 2`)
| Collection | Document ID | Key Fields | Access |
|------------|-------------|------------|--------|
| `users` | `{userId}` | email, role, shopId, name | Any auth user (read) |
| `shops` | `{shopId}` | ownerUid, name | Shop members + owner |
| `shops/{shopId}/settings` | `{settingId}` | businessType, enableRepair, enableExpiry, enableVariants | Shop members |
| `shops/{shopId}/custom_salary_adjustments` | `{adjustmentId}` | staffId, amount, name | Owner only |
| `shops/{shopId}/product_categories` | `{categoryId}` | name, shopId | Manager+ |
| `invites` | `{inviteCode}` | shopId, role, createdBy, used | Any auth (read) |

### Core Business (`SECTION 3`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `repairs` | customerName, phone, model, issue, status (1-4), price, cost | Shop members |
| `sales` | customerName, productNames, totalPrice, totalCost, soldAt | Employee+ |
| `products` | name, cost, price, quantity, type | Employee+ |
| `product_variants` | productId, sku, size, color, costPrice, salePrice, quantity | Employee+ |
| `stock_entries` | status (draft/confirmed/cancelled), items, shopId | Employee+ |
| `customers` | name, phone | Shop members |

### Finance (`SECTION 4`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `expenses` | title, amount, category, date | Manager+ |
| `debts` | personName, totalAmount, paidAmount, type | Shop members |
| `debt_payments` | amount, paidAt | Staff |
| `cash_closings` | shopId, date, cashStart, cashEnd | Manager+ |
| `adjustment_entries` | shopId, amount, type | Manager+ |
| `payment_intents` | intentId, type, amount | Staff |

### Suppliers (`SECTION 5`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `suppliers` | name, phone | Employee+ |
| `supplier_payments` | supplierId, amount, paidAt | Manager+ |
| `purchase_orders` | shopId | Manager+ |
| `supplier_import_history` | supplierId | Employee+ |
| `supplier_product_prices` | supplierId, productName, price | Employee+ |

### Repair Partners (`SECTION 6`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `repair_partners` | name, phone | Employee+ |
| `repair_partner_payments` | partnerId, amount, paidAt | Manager+ |
| `partner_repair_history` | partnerId, repairId | Employee+ |

### HR & Attendance (`SECTION 7`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `attendance` | userId, dateKey, checkInAt, checkOutAt, status | Own records or Manager+ |
| `work_schedules` | userId, startTime, endTime, workDays | Shop members |

### Chat & Messaging (`SECTION 8`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `chats` | message, senderId | Shop members |
| `chat_messages` | message, senderId | Shop members |
| `chat_online` | userId | Any auth |
| `chat_typing` | userId | Any auth |

### Notifications (`SECTION 9`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `notifications` | userId, shopId | Own or shop-wide |
| `shop_notifications` | shopId | Shop members |

### System Data (`SECTION 10`)
| Collection | Key Fields | Access |
|------------|------------|--------|
| `audit_logs` | action, userId, createdAt — **IMMUTABLE** | Manager+ (read), any auth (create) |
| `quick_input_codes` | code, shopId | Shop members |
| `repair_parts` | partName | Employee+ |
| `financial_activities` | type, amount | Manager+ |
| `supplier_debts` | supplierId, amount | Employee+ |

### HR & Salary Settings (`SECTION 11`)
| Collection | Document ID | Key Fields | Access |
|------------|-------------|------------|--------|
| `shop_deduction_settings` | `{shopId}` | deduction/insurance/tax config | Owner (write), Manager+ (read) |
| `employee_salary_settings` | `{settingId}` | staffId, baseSalary, commissions | Manager+ |
| `shop_salary_defaults` | `{shopId}` | working hours, overtime rate | Owner |

---

## 16. SQLite Local Tables

Database: `repair_shop_v22.db` (version 80)

| Table | Key Columns | Purpose |
|-------|-------------|---------|
| `repairs` | firestoreId, customerName, phone, model, issue, status, price, cost | Repair orders (offline cache) |
| `products` | firestoreId, name, brand, model, imei, cost, price, quantity, type, category, expiryDate | Product inventory |
| `sales` | firestoreId, customerName, productNames, totalPrice, discount, isInstallment | Sale orders |
| `customers` | firestoreId, name, phone, totalSpent, totalRepairs | Customer records |
| `suppliers` | firestoreId, name, phone, importCount, totalAmount | Supplier records |
| `expenses` | firestoreId, title, amount, category, date, type | Expense entries |
| `debts` | firestoreId, personName, totalAmount, paidAmount, type, status | Debt tracking |
| `debt_payments` | firestoreId, debtId, amount, paidAt | Debt payment records |
| `attendance` | firestoreId, userId, dateKey, checkInAt, checkOutAt, status | Attendance records |
| `audit_logs` | firestoreId, action, userId, description | Audit trail |
| `inventory_checks` | firestoreId, type, checkDate, itemsJson, status | Inventory verification |
| `supplier_payments` | firestoreId, supplierId, amount, paidAt | Supplier payment records |
| `repair_partner_payments` | firestoreId, partnerId, amount, paidAt | Partner payment records |
| `cash_closings` | dateKey, cashStart, cashEnd, bankStart, bankEnd | Daily cash reconciliation |
| `payroll_settings` | baseSalary, saleCommPercent, repairProfitPercent | Payroll configuration |
| `payroll_locks` | monthKey, locked, lockedBy | Monthly payroll lock |
| `employee_salary_settings` | staffId, baseSalary, salaryType, commissions, allowances | Per-employee salary config |
| `purchase_orders` | firestoreId, orderCode, supplierName, itemsJson, status | Purchase orders |
| `work_schedules` | userId, startTime, endTime, workDays | Work schedule config |
| `quick_input_codes` | firestoreId, code, name, type, brand, cost, price | Quick input templates |
| `supplier_product_prices` | supplierId, productName, costPrice | Supplier price tracking |
| `supplier_import_history` | supplierId, productName, imei, quantity, costPrice | Import history |
| `repair_partners` | firestoreId, name, phone, active | Repair partner records |
| `partner_repair_history` | repairOrderId, partnerId, partnerCost | Partner repair history |
| `repair_parts` | firestoreId, partName, cost, price, quantity | Repair parts inventory |
| `sync_queue` | entityType, entityId, operation, status, retryCount | Pending sync operations |
| `sales_returns` | salesOrderId, returnDate, totalReturnAmount | Sale returns |
| `product_categories` | firestoreId, name, parentId, trackExpiry, hasVariants | Dynamic categories |
| `product_variants` | firestoreId, productId, sku, size, color, quantity | Product variants |

All tables include `isSynced INTEGER DEFAULT 0` for sync tracking.

---

## 17. Navigation Structure

### App Flow
```
SplashView → AuthGate
  ├── (Not logged in) → LoginView ↔ RegisterView
  ├── (Super Admin) → ShopSelectorView → HomeView
  └── (Normal User) → HomeView
```

### HomeView Bottom Navigation Tabs
```
┌─────────┬─────────┬──────────┬───────────┬─────────┬──────────┬──────────┐
│  Home   │  Sales  │ Repairs* │ Inventory │ HSD/Var†│  Staff‡  │ Finance§ │ Settings │
└─────────┴─────────┴──────────┴───────────┴─────────┴──────────┴──────────┘
  * Repairs tab: only visible when enableRepair=true (electronics shops)
  † HSD tab: visible when enableExpiry=true (food); Variants tab: when enableVariants=true (fashion)
  ‡ Staff tab: requires allowManageStaff permission
  § Finance tab: requires allowViewRevenue permission
```

### Home Tab — Dashboard Cards & Quick Actions
Links to:
- `CreateSaleView` — New sale
- `CreateRepairOrderView` — New repair
- `OrderListView` — All orders
- `SaleListView` — Sale list
- `RevenueView` — Revenue dashboard
- `ExpenseView` — Expenses
- `DebtView` — Debts
- `WarrantyView` — Warranty
- `FastInventoryInputView` — Quick stock entry
- `SmartStockInView` — Smart stock entry
- `PendingStockListView` — Pending stock
- `SupplierListView` — Suppliers
- `CustomerManagementView` — Customers
- `GlobalSearchView` — Search
- `AdvancedChatView` — Team chat
- `AttendanceView` — Check-in/out
- `StaffPerformanceView` — Staff KPIs
- `NotificationsView` — Notifications
- `CashClosingView` — Cash closing
- `FinancialReportView` — Financial reports
- `FinancialActivityLogView` — Activity log
- `BankInstallmentReportView` — Installments
- `PrinterSettingsView` — Printer setup
- `QrScanView` — QR scanner
- `ExpiryManagementView` — Expiry (food)
- `VariantManagementView` — Variants (fashion)
- `HRSalarySettingsView` — Salary settings
- `PayrollView` — Payroll
- `UserGuideView` — Help
- `AboutDeveloperView` — About

### Settings Tab
Links to:
- `ShopSettingsView` — Shop config
- `StaffPermissionsView` — Permissions
- `WorkScheduleSettingsView` — Schedules
- `NotificationSettingsView` — Notification prefs
- `PrinterSettingsView` — Printer config
- `LabelSettingsView` — Label templates
- `CategoryManagementView` — Categories
- `QuickInputManagementView` — Quick inputs
- `AuditLogView` — Audit logs
- `SuperAdminView` — Admin panel (super admin only)
- Language switch (vi/en)

---

## 18. Security & Roles

### Role Hierarchy
```
superAdmin (admin@huluca.com)
  └── owner (shop creator)
      └── manager
          ├── employee
          └── technician
```

### Custom Claims (set by Cloud Functions)
- `isSuperAdmin: boolean`
- `shopId: string`
- `role: owner | manager | employee | technician | user`

### Key Security Rules
- **Multi-tenant isolation:** All queries filtered by `shopId` (from claims or users collection)
- **Super admin bypass:** `admin@huluca.com` has full access
- **Protected fields:** `shopId`, `isAdmin`, `balance`, `ownerUid` cannot be changed by client
- **Audit logs:** Write-once, immutable (no update or delete)
- **Catch-all deny:** Any undefined collection returns `false`
- **Soft deletes:** Records marked `deleted: true` rather than removed

---

*End of Project Structure Documentation*
