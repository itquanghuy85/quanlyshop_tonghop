# 📁 CẤU TRÚC DỰ ÁN QUANLYSHOP

> **Phần mềm Quản lý Tiệm Sửa chữa & Mua bán Điện thoại**  
> Phiên bản: 3.4.0+10 | Flutter + Firebase

---

## 📋 MỤC LỤC

1. [Tổng quan dự án](#1-tổng-quan-dự-án)
2. [Kiến trúc hệ thống](#2-kiến-trúc-hệ-thống)
3. [Cấu trúc thư mục](#3-cấu-trúc-thư-mục)
4. [Chi tiết từng module](#4-chi-tiết-từng-module)
5. [Database Schema](#5-database-schema)
6. [Luồng dữ liệu](#6-luồng-dữ-liệu)
7. [Hệ thống phân quyền](#7-hệ-thống-phân-quyền)
8. [Các tính năng chính](#8-các-tính-năng-chính)

---

## 1. TỔNG QUAN DỰ ÁN

### 1.1 Mô tả
**QuanLyShop** là ứng dụng quản lý toàn diện cho cửa hàng sửa chữa và mua bán điện thoại, được xây dựng trên nền tảng Flutter với backend Firebase.

### 1.2 Công nghệ sử dụng
| Thành phần | Công nghệ |
|------------|-----------|
| Frontend | Flutter 3.10+ (Dart) |
| Backend | Firebase (Auth, Firestore, Storage, Functions, Messaging) |
| Local DB | SQLite (sqflite) |
| State Management | StatefulWidget + EventBus |
| Đa ngôn ngữ | flutter_localizations (vi, en) |

### 1.3 Nền tảng hỗ trợ
- ✅ Android (APK/AAB)
- ✅ iOS (IPA)
- ✅ Web
- ⚠️ Windows (hạn chế một số tính năng)
- ⚠️ macOS (hạn chế một số tính năng)

---

## 2. KIẾN TRÚC HỆ THỐNG

### 2.1 Kiến trúc tổng quan
```
┌─────────────────────────────────────────────────────────────┐
│                        UI LAYER                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    VIEWS (Screens)                       ││
│  │  • HomeView • LoginView • InventoryView • SaleListView  ││
│  │  • RepairDetailView • CustomerView • WarrantyView ...   ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    WIDGETS (Reusable)                    ││
│  │  • UnifiedSyncButton • NotificationBadge • GradientFab  ││
│  │  • PerpetualCalendar • LoadingIntroScreen ...           ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                     SERVICE LAYER                            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    SERVICES                              ││
│  │  • FirestoreService (CRUD Firestore)                    ││
│  │  • UserService (Auth, Roles, Permissions)               ││
│  │  • SyncService (Real-time Sync)                         ││
│  │  • NotificationService (Push Notifications)             ││
│  │  • PrinterService (Bluetooth/WiFi Printing)             ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                      DATA LAYER                              │
│  ┌───────────────────────┐ ┌───────────────────────────────┐│
│  │   LOCAL DB (SQLite)   │ │      CLOUD (Firebase)         ││
│  │   • Offline-first     │ │   • Firestore (NoSQL)         ││
│  │   • Real-time sync    │ │   • Firebase Auth             ││
│  │   • Soft deletes      │ │   • Firebase Storage          ││
│  └───────────────────────┘ └───────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Pattern áp dụng
- **Service-first access**: Tất cả truy cập dữ liệu qua Service classes
- **Offline-first**: Lưu local trước, sync lên cloud sau
- **Multi-tenant**: Phân tách dữ liệu theo `shopId`
- **Soft deletes**: Xóa mềm với flag `deleted: true`
- **Event-driven updates**: EventBus để thông báo thay đổi dữ liệu

---

## 3. CẤU TRÚC THƯ MỤC

```
quanlyshop/
├── 📁 android/                 # Native Android configs
│   ├── app/
│   │   ├── build.gradle.kts   # Build config, signing
│   │   └── src/main/
│   │       └── AndroidManifest.xml
│   ├── build.gradle.kts
│   ├── key.properties         # Signing keys (KHÔNG commit)
│   └── gradle/
│
├── 📁 ios/                     # Native iOS configs
│   ├── Runner/
│   │   ├── Info.plist         # App permissions
│   │   └── AppDelegate.swift
│   ├── Podfile                # iOS dependencies
│   └── Runner.xcworkspace/
│
├── 📁 web/                     # Web platform
│   ├── index.html
│   └── manifest.json
│
├── 📁 functions/               # Firebase Cloud Functions
│   ├── index.js               # Notification triggers
│   └── package.json
│
├── 📁 lib/                     # 🎯 SOURCE CODE CHÍNH
│   ├── main.dart              # Entry point
│   ├── firebase_options.dart  # Firebase config
│   │
│   ├── 📁 views/              # UI Screens (80+ files)
│   │   ├── home_view.dart
│   │   ├── login_view.dart
│   │   ├── register_view.dart
│   │   ├── inventory_view.dart
│   │   ├── sale_list_view.dart
│   │   ├── order_list_view.dart
│   │   ├── customer_view.dart
│   │   ├── warranty_view.dart
│   │   ├── expense_view.dart
│   │   ├── debt_view.dart
│   │   ├── staff_list_view.dart
│   │   ├── settings_view.dart
│   │   └── ... (70+ màn hình khác)
│   │
│   ├── 📁 services/           # Business Logic (35+ files)
│   │   ├── firestore_service.dart
│   │   ├── user_service.dart
│   │   ├── sync_service.dart
│   │   ├── notification_service.dart
│   │   ├── bluetooth_printer_service.dart
│   │   └── ... (30+ services khác)
│   │
│   ├── 📁 models/             # Data Models (27 files)
│   │   ├── repair_model.dart
│   │   ├── product_model.dart
│   │   ├── sale_order_model.dart
│   │   ├── customer_model.dart
│   │   └── ... (23+ models khác)
│   │
│   ├── 📁 widgets/            # Reusable Components (21 files)
│   │   ├── unified_sync_button.dart
│   │   ├── notification_badge.dart
│   │   ├── currency_text_field.dart
│   │   └── ... (18+ widgets khác)
│   │
│   ├── 📁 data/               # Local Database
│   │   └── db_helper.dart     # SQLite wrapper (5500+ lines)
│   │
│   ├── 📁 theme/              # UI Theme
│   │   ├── app_theme.dart
│   │   ├── app_colors.dart
│   │   ├── app_text_styles.dart
│   │   └── app_button_styles.dart
│   │
│   ├── 📁 utils/              # Utilities
│   │   ├── money_utils.dart
│   │   ├── imei_extractor.dart
│   │   ├── qr_parser.dart
│   │   └── ... (6+ utils)
│   │
│   ├── 📁 constants/          # App Constants
│   │   ├── financial_constants.dart
│   │   ├── product_constants.dart
│   │   └── partner_constants.dart
│   │
│   ├── 📁 controllers/        # State Controllers
│   │   └── fast_inventory_input_controller.dart
│   │
│   ├── 📁 core/               # Core utilities
│   │   ├── payment_blocker.dart
│   │   └── utils/
│   │       └── money_utils.dart
│   │
│   └── 📁 l10n/               # Localization
│       ├── app_localizations.dart
│       ├── app_vi.arb         # Tiếng Việt
│       └── app_en.arb         # English
│
├── 📁 assets/                  # Resources
│   ├── 📁 images/             # App images, logos
│   └── 📁 fonts/              # Custom fonts
│
├── 📁 DOCS/                    # Documentation
│   ├── PROJECT_STRUCTURE_VI.md (file này)
│   ├── USER_GUIDE_*.md
│   └── ... (các tài liệu khác)
│
├── 📁 test/                    # Unit tests
│
├── pubspec.yaml               # Dependencies
├── firebase.json              # Firebase config
├── firestore.rules            # Security rules
└── firestore.indexes.json     # DB indexes
```

---

## 4. CHI TIẾT TỪNG MODULE

### 4.1 📁 VIEWS (Màn hình UI)

#### 4.1.1 Màn hình chính (Core Views)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `main.dart` | Entry point | Khởi tạo Firebase, theme, routing |
| `home_view.dart` | Trang chủ | Dashboard, thống kê, menu chính |
| `login_view.dart` | Đăng nhập | Email/Password auth |
| `register_view.dart` | Đăng ký | Tạo tài khoản mới |
| `splash_view.dart` | Splash screen | Animation khởi động |
| `intro_view.dart` | Giới thiệu | Onboarding cho user mới |

#### 4.1.2 Module Bán hàng (Sales)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `sale_list_view.dart` | DS đơn bán | Danh sách hóa đơn bán |
| `create_sale_view.dart` | Tạo đơn bán | Tạo hóa đơn bán hàng mới |
| `sale_detail_view.dart` | Chi tiết đơn | Xem/sửa chi tiết hóa đơn |
| `unified_payment_page.dart` | Thanh toán | Xử lý thanh toán đa phương thức |

#### 4.1.3 Module Sửa chữa (Repairs)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `order_list_view.dart` | DS đơn sửa | Danh sách phiếu sửa chữa |
| `create_repair_order_view.dart` | Tạo phiếu | Tạo phiếu sửa chữa mới |
| `repair_detail_view.dart` | Chi tiết phiếu | Cập nhật trạng thái, linh kiện |
| `repair_receipt_view.dart` | In phiếu | Thiết kế và in biên lai |
| `warranty_view.dart` | Bảo hành | Quản lý danh sách bảo hành |

#### 4.1.4 Module Kho hàng (Inventory)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `inventory_view.dart` | Kho hàng | Danh sách sản phẩm tồn kho |
| `stock_in_view.dart` | Nhập kho | Nhập sản phẩm mới |
| `smart_stock_in_view.dart` | Nhập thông minh | Nhập nhanh từ QR/barcode |
| `fast_inventory_input_view.dart` | Nhập nhanh | Nhập hàng loạt |
| `fast_inventory_check_view.dart` | Kiểm kho | Đối chiếu tồn kho |
| `pending_stock_list_view.dart` | Kho tạm | Sản phẩm chờ xác nhận giá |
| `parts_inventory_view.dart` | Linh kiện | Quản lý phụ tùng, linh kiện |

#### 4.1.5 Module Nhà cung cấp (Suppliers)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `supplier_list_view.dart` | DS NCC | Danh sách nhà cung cấp |
| `supplier_view.dart` | Chi tiết NCC | Thông tin NCC |
| `supplier_form_view.dart` | Thêm/sửa NCC | Form nhập liệu NCC |
| `supplier_detail_view.dart` | Lịch sử NCC | Lịch sử giao dịch |
| `purchase_order_list_view.dart` | Đơn nhập | Danh sách đơn nhập hàng |
| `create_purchase_order_view.dart` | Tạo đơn nhập | Tạo đơn nhập hàng mới |

#### 4.1.6 Module Khách hàng (Customers)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `customer_view.dart` | DS khách | Danh sách khách hàng |
| `customer_management_view.dart` | Quản lý khách | Thông tin chi tiết khách |
| `customer_history_view.dart` | Lịch sử khách | Lịch sử mua hàng/sửa chữa |

#### 4.1.7 Module Tài chính (Finance)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `revenue_view.dart` | Doanh thu | Thống kê doanh thu |
| `revenue_report_view.dart` | Báo cáo DT | Báo cáo doanh thu chi tiết |
| `expense_view.dart` | Chi phí | Quản lý chi phí |
| `debt_view.dart` | Công nợ | Quản lý nợ khách/NCC |
| `debt_analysis_view.dart` | Phân tích nợ | Phân tích công nợ |
| `cash_closing_view.dart` | Chốt quỹ | Kiểm kê tiền cuối ngày |
| `financial_report_view.dart` | BC tài chính | Báo cáo tài chính tổng hợp |
| `financial_activity_log_view.dart` | Lịch sử TC | Log hoạt động tài chính |
| `financial_reconciliation_view.dart` | Đối soát | Đối soát sổ sách |
| `bank_installment_report_view.dart` | Trả góp | Báo cáo trả góp ngân hàng |

#### 4.1.8 Module Nhân sự (HR)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `staff_list_view.dart` | DS nhân viên | Danh sách nhân viên |
| `staff_permissions_view.dart` | Phân quyền | Cấp quyền cho nhân viên |
| `staff_performance_view.dart` | Hiệu suất | Đánh giá hiệu suất NV |
| `attendance_view.dart` | Chấm công | Điểm danh hàng ngày |
| `attendance_management_view.dart` | Quản lý CC | Xem/duyệt chấm công |
| `payroll_view.dart` | Bảng lương | Tính lương nhân viên |
| `payroll_settings_view.dart` | Cấu hình lương | Thiết lập công thức lương |
| `hr_salary_settings_view.dart` | Cài đặt HR | Cấu hình HR toàn cục |
| `work_schedule_settings_view.dart` | Ca làm việc | Thiết lập lịch làm việc |
| `hr/shop_deduction_settings_view.dart` | Khấu trừ | Cài đặt các khoản khấu trừ |

#### 4.1.9 Module Đối tác sửa chữa (Repair Partners)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `repair_partner_view.dart` | DS đối tác | Danh sách đối tác sửa chữa |
| `repair_partner_form_view.dart` | Thêm/sửa | Form nhập liệu đối tác |
| `repair_partner_detail_view.dart` | Chi tiết | Thông tin đối tác |
| `partner_management_view.dart` | Quản lý | Quản lý quan hệ đối tác |

#### 4.1.10 Module Cài đặt & Hệ thống (Settings)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `settings_view.dart` | Cài đặt | Menu cài đặt chung |
| `shop_settings_view.dart` | Cài đặt shop | Thông tin cửa hàng |
| `shop_selector_view.dart` | Chọn shop | Super admin chọn shop |
| `printer_setting_view.dart` | Máy in | Cấu hình máy in |
| `notification_settings_view.dart` | Thông báo | Cài đặt thông báo |
| `invoice_template_view.dart` | Mẫu hóa đơn | Thiết kế template in |
| `thermal_printer_design_view.dart` | Thiết kế in | Tùy chỉnh layout in nhiệt |
| `super_admin_view.dart` | Super Admin | Quản trị hệ thống |
| `audit_log_view.dart` | Nhật ký | Log hoạt động hệ thống |

#### 4.1.11 Module Tiện ích (Utilities)
| File | Mô tả | Chức năng |
|------|-------|-----------|
| `qr_scan_view.dart` | Quét QR | Quét mã QR/barcode |
| `global_search_view.dart` | Tìm kiếm | Tìm kiếm toàn cục |
| `chat_view.dart` | Chat | Trò chuyện nội bộ |
| `advanced_chat_view.dart` | Chat nâng cao | Chat với tính năng mở rộng |
| `notifications_view.dart` | Thông báo | Xem danh sách thông báo |
| `quick_input_codes_view.dart` | Mã nhanh | Quản lý mã nhập nhanh |
| `my_profile_view.dart` | Hồ sơ | Thông tin cá nhân |
| `about_developer_view.dart` | Giới thiệu | Thông tin nhà phát triển |

---

### 4.2 📁 SERVICES (Business Logic)

#### 4.2.1 Services cốt lõi
| File | Mô tả | Chức năng chính |
|------|-------|-----------------|
| `firestore_service.dart` | Firestore CRUD | Tất cả operations với Cloud Firestore |
| `user_service.dart` | Quản lý user | Auth, role, permissions, shopId |
| `sync_service.dart` | Đồng bộ dữ liệu | Real-time sync Firestore ↔ SQLite |
| `sync_orchestrator.dart` | Điều phối sync | Quản lý queue đồng bộ local → cloud |
| `notification_service.dart` | Thông báo | Push notifications, in-app alerts |

#### 4.2.2 Services tài chính
| File | Mô tả | Chức năng chính |
|------|-------|-----------------|
| `money_transaction_service.dart` | Giao dịch tiền | Xử lý các giao dịch tài chính |
| `money_validation_service.dart` | Validate tiền | Kiểm tra hợp lệ số tiền |
| `payment_intent_service.dart` | Dự định thanh toán | Quản lý thanh toán pending |
| `financial_activity_service.dart` | Log tài chính | Ghi nhận hoạt động tài chính |
| `salary_calculation_service.dart` | Tính lương | Công thức tính lương nhân viên |

#### 4.2.3 Services nghiệp vụ
| File | Mô tả | Chức năng chính |
|------|-------|-----------------|
| `customer_service.dart` | Khách hàng | CRUD khách hàng |
| `supplier_service.dart` | Nhà cung cấp | CRUD NCC, lịch sử nhập |
| `supplier_payment_service.dart` | Thanh toán NCC | Xử lý thanh toán cho NCC |
| `repair_partner_service.dart` | Đối tác sửa | Quản lý đối tác sửa chữa |
| `repair_partner_payment_service.dart` | Thanh toán ĐT | Thanh toán cho đối tác |
| `stock_entry_service.dart` | Nhập kho | Xử lý nghiệp vụ nhập kho |
| `adjustment_service.dart` | Điều chỉnh | Điều chỉnh tồn kho, giá |

#### 4.2.4 Services tiện ích
| File | Mô tả | Chức năng chính |
|------|-------|-----------------|
| `bluetooth_printer_service.dart` | In Bluetooth | In qua máy in Bluetooth |
| `wifi_printer_service.dart` | In WiFi | In qua máy in mạng |
| `thermal_printer_service.dart` | In nhiệt | Xử lý in hóa đơn nhiệt |
| `unified_printer_service.dart` | In tổng hợp | API thống nhất cho in ấn |
| `chat_service.dart` | Chat service | Xử lý tin nhắn nội bộ |
| `storage_service.dart` | Lưu trữ | Upload/download Firebase Storage |
| `encryption_service.dart` | Mã hóa | Mã hóa dữ liệu nhạy cảm |
| `connectivity_service.dart` | Kết nối mạng | Kiểm tra trạng thái mạng |
| `audit_service.dart` | Ghi log | Ghi nhật ký hoạt động |
| `logging_service.dart` | Debug log | Ghi log cho debug |

#### 4.2.5 Services đặc biệt
| File | Mô tả | Chức năng chính |
|------|-------|-----------------|
| `claims_service.dart` | Custom claims | Quản lý Firebase custom claims |
| `cash_closing_notifier.dart` | Chốt quỹ | Thông báo real-time chốt quỹ |
| `sync_health_check.dart` | Kiểm tra sync | Đánh giá sức khỏe đồng bộ |
| `sync_control.dart` | Điều khiển sync | Bật/tắt sync |
| `event_bus.dart` | Event bus | Pub/sub pattern cho events |
| `first_time_guide_service.dart` | Onboarding | Hướng dẫn người dùng mới |
| `data_migration_service.dart` | Migration | Di chuyển dữ liệu giữa versions |

---

### 4.3 📁 MODELS (Data Models)

#### 4.3.1 Models chính
| File | Class | Mô tả |
|------|-------|-------|
| `repair_model.dart` | `Repair` | Phiếu sửa chữa |
| `product_model.dart` | `Product` | Sản phẩm trong kho |
| `sale_order_model.dart` | `SaleOrder` | Đơn hàng bán |
| `customer_model.dart` | `Customer` | Thông tin khách hàng |
| `expense_model.dart` | `Expense` | Chi phí |
| `debt_model.dart` | `Debt` | Công nợ |
| `attendance_model.dart` | `Attendance` | Chấm công |

#### 4.3.2 Models phụ trợ
| File | Class | Mô tả |
|------|-------|-------|
| `purchase_order_model.dart` | `PurchaseOrder` | Đơn nhập hàng |
| `supplier_model.dart` | `Supplier` | Nhà cung cấp |
| `supplier_payment_model.dart` | `SupplierPayment` | Thanh toán NCC |
| `stock_entry_model.dart` | `StockEntry` | Phiếu nhập kho |
| `repair_partner_model.dart` | `RepairPartner` | Đối tác sửa chữa |
| `repair_partner_payment_model.dart` | `RepairPartnerPayment` | Thanh toán đối tác |
| `inventory_check_model.dart` | `InventoryCheck` | Kiểm kê kho |
| `inventory_zone_model.dart` | `InventoryZone` | Vùng/khu vực kho |

#### 4.3.3 Models tài chính & HR
| File | Class | Mô tả |
|------|-------|-------|
| `financial_activity_model.dart` | `FinancialActivity` | Hoạt động tài chính |
| `payment_intent_model.dart` | `PaymentIntent` | Dự định thanh toán |
| `employee_salary_model.dart` | `EmployeeSalary` | Lương nhân viên |
| `salary_breakdown_model.dart` | `SalaryBreakdown` | Chi tiết lương |
| `shop_deduction_settings.dart` | `ShopDeductionSettings` | Cài đặt khấu trừ |

#### 4.3.4 Models tiện ích
| File | Class | Mô tả |
|------|-------|-------|
| `chat_message_model.dart` | `ChatMessage` | Tin nhắn chat |
| `quick_input_code_model.dart` | `QuickInputCode` | Mã nhập nhanh |
| `repair_service_model.dart` | `RepairService` | Dịch vụ sửa chữa |
| `printer_types.dart` | `PrinterType` | Loại máy in |

---

### 4.4 📁 WIDGETS (UI Components)

| File | Widget | Mô tả |
|------|--------|-------|
| `unified_sync_button.dart` | `UnifiedSyncButton` | Nút sync thống nhất |
| `simple_sync_indicator.dart` | `SimpleSyncIndicator` | Indicator trạng thái sync |
| `pending_sync_indicator.dart` | `PendingSyncIndicator` | Indicator sync pending |
| `sync_status_widget.dart` | `SyncStatusWidget` | Widget hiển thị trạng thái sync |
| `notification_badge.dart` | `NotificationBadge` | Badge số thông báo |
| `notification_item.dart` | `NotificationItem` | Item thông báo trong list |
| `currency_text_field.dart` | `CurrencyTextField` | Input tiền tệ |
| `validated_text_field.dart` | `ValidatedTextField` | Input có validation |
| `debounced_search_field.dart` | `DebouncedSearchField` | Ô tìm kiếm có debounce |
| `global_search_bar.dart` | `GlobalSearchBar` | Thanh tìm kiếm toàn cục |
| `gradient_fab.dart` | `GradientFAB` | FAB với gradient |
| `custom_app_bar.dart` | `CustomAppBar` | AppBar tùy chỉnh |
| `loading_intro_screen.dart` | `LoadingIntroScreen` | Màn hình loading animation |
| `perpetual_calendar.dart` | `PerpetualCalendar` | Lịch vạn niên |
| `lazy_load_list_view.dart` | `LazyLoadListView` | List load lazy |
| `pending_stock_widget.dart` | `PendingStockWidget` | Widget kho tạm |
| `pending_payments_widget.dart` | `PendingPaymentsWidget` | Widget thanh toán pending |
| `parts_selection_dialog.dart` | `PartsSelectionDialog` | Dialog chọn linh kiện |
| `printer_selection_dialog.dart` | `PrinterSelectionDialog` | Dialog chọn máy in |
| `imei_scan_result_dialog.dart` | `ImeiScanResultDialog` | Dialog kết quả quét IMEI |
| `app_ui_helpers.dart` | UI helpers | Các helper function UI |

---

### 4.5 📁 THEME (Giao diện)

| File | Mô tả |
|------|-------|
| `app_theme.dart` | Theme chính của app (light/dark) |
| `app_colors.dart` | Bảng màu thống nhất |
| `app_text_styles.dart` | Text styles chuẩn |
| `app_button_styles.dart` | Button styles chuẩn |

**Màu chính:**
```dart
primary: Color(0xFF6A1B9A)      // Tím đậm
secondary: Color(0xFF9C27B0)    // Tím nhạt
background: Color(0xFFF0F4F8)   // Xám xanh nhạt
surface: Colors.white
error: Colors.red
success: Colors.green
warning: Colors.orange
info: Colors.blue
```

---

### 4.6 📁 UTILS (Tiện ích)

| File | Mô tả | Functions chính |
|------|-------|-----------------|
| `money_utils.dart` | Xử lý tiền tệ | `formatVND()`, `parseAmount()` |
| `imei_extractor.dart` | Trích xuất IMEI | `extractIMEI()` |
| `qr_parser.dart` | Parse mã QR | `parseQRCode()` |
| `qr_router.dart` | Routing từ QR | `routeFromQR()` |
| `sku_generator.dart` | Tạo mã SKU | `generateSKU()` |
| `repair_status_validator.dart` | Validate trạng thái | `validateStatusChange()` |
| `debouncer.dart` | Debounce actions | `Debouncer.run()` |
| `app_info.dart` | Thông tin app | `getAppVersion()` |
| `ui_constants.dart` | Hằng số UI | Padding, spacing, radius |

---

### 4.7 📁 CONSTANTS (Hằng số)

| File | Mô tả |
|------|-------|
| `financial_constants.dart` | Hằng số tài chính (thuế, phí...) |
| `product_constants.dart` | Hằng số sản phẩm (loại, trạng thái...) |
| `partner_constants.dart` | Hằng số đối tác |

---

### 4.8 📁 DATA (Database)

**File chính:** `db_helper.dart` (~5500 lines)

**Các bảng SQLite:**
| Bảng | Mô tả | Số cột |
|------|-------|--------|
| `repairs` | Phiếu sửa chữa | 35+ |
| `products` | Sản phẩm | 25+ |
| `sales` | Đơn bán | 30+ |
| `customers` | Khách hàng | 15+ |
| `suppliers` | Nhà cung cấp | 15+ |
| `expenses` | Chi phí | 12+ |
| `debts` | Công nợ | 15+ |
| `attendance` | Chấm công | 20+ |
| `audit_logs` | Nhật ký | 15+ |
| `inventory_checks` | Kiểm kho | 8+ |
| `purchase_orders` | Đơn nhập | 20+ |
| `purchase_order_items` | Chi tiết đơn nhập | 15+ |
| `supplier_payments` | Thanh toán NCC | 15+ |
| `repair_partners` | Đối tác sửa | 15+ |
| `partner_repair_history` | Lịch sử đối tác | 12+ |
| `repair_partner_payments` | Thanh toán đối tác | 12+ |
| `quick_input_codes` | Mã nhập nhanh | 10+ |
| `financial_activities` | Hoạt động TC | 12+ |
| `payment_intents` | Dự định TT | 15+ |
| `stock_entries` | Phiếu nhập | 12+ |
| `stock_entry_items` | Chi tiết nhập | 10+ |

---

## 5. DATABASE SCHEMA

### 5.1 Bảng repairs (Phiếu sửa chữa)
```sql
CREATE TABLE repairs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  customerName TEXT,
  phone TEXT,
  model TEXT,
  issue TEXT,
  accessories TEXT,
  address TEXT,
  imagePath TEXT,
  deliveredImage TEXT,
  warranty TEXT,
  partsUsed TEXT,
  status INTEGER,           -- 1: Đang sửa, 2: Chờ linh kiện, 3: Hoàn thành, 4: Đã trả
  price INTEGER,
  cost INTEGER,
  paymentMethod TEXT,
  createdAt INTEGER,
  startedAt INTEGER,
  finishedAt INTEGER,
  deliveredAt INTEGER,
  createdBy TEXT,
  repairedBy TEXT,
  deliveredBy TEXT,
  lastCaredAt INTEGER,
  isSynced INTEGER DEFAULT 0,
  deleted INTEGER DEFAULT 0,
  color TEXT,
  imei TEXT,
  condition TEXT,
  services TEXT,
  notes TEXT,
  pendingDeliveryApproval INTEGER DEFAULT 0
);
```

### 5.2 Bảng products (Sản phẩm)
```sql
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  name TEXT,
  brand TEXT,
  imei TEXT,
  cost INTEGER,
  price INTEGER,
  condition TEXT,
  status INTEGER DEFAULT 1,
  description TEXT,
  images TEXT,
  warranty TEXT,
  createdAt INTEGER,
  supplier TEXT,
  type TEXT DEFAULT 'DIEN_THOAI',  -- DIEN_THOAI, PHU_KIEN, LINH_KIEN
  quantity INTEGER DEFAULT 1,
  color TEXT,
  isSynced INTEGER DEFAULT 0,
  capacity TEXT,
  paymentMethod TEXT,
  isPending INTEGER DEFAULT 0,      -- Kho tạm
  pendingSupplier TEXT
);
```

### 5.3 Bảng sales (Đơn bán)
```sql
CREATE TABLE sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  customerName TEXT,
  phone TEXT,
  address TEXT,
  productNames TEXT,
  productImeis TEXT,
  totalPrice INTEGER,
  totalCost INTEGER,
  discount INTEGER DEFAULT 0,
  paymentMethod TEXT,
  sellerName TEXT,
  soldAt INTEGER,
  notes TEXT,
  gifts TEXT,
  isInstallment INTEGER DEFAULT 0,
  downPayment INTEGER DEFAULT 0,
  downPaymentMethod TEXT,
  loanAmount INTEGER DEFAULT 0,
  installmentTerm TEXT,
  bankName TEXT,
  bankName2 TEXT,
  loanAmount2 INTEGER DEFAULT 0,
  warranty TEXT,
  settlementPlannedAt INTEGER,
  settlementReceivedAt INTEGER,
  settlementAmount INTEGER DEFAULT 0,
  settlementFee INTEGER DEFAULT 0,
  settlementNote TEXT,
  settlementCode TEXT,
  isSynced INTEGER DEFAULT 0
);
```

---

## 6. LUỒNG DỮ LIỆU

### 6.1 Luồng Đồng bộ (Sync Flow)
```
┌─────────────┐     Real-time      ┌─────────────┐
│   FIRESTORE │ ◀──────────────▶  │   SQLite    │
│   (Cloud)   │    Listener        │   (Local)   │
└─────────────┘                    └─────────────┘
       │                                  │
       │                                  │
       ▼                                  ▼
┌─────────────────────────────────────────────────┐
│                 SyncService                      │
│  • initRealTimeSync() - Subscribe to changes    │
│  • _handleFirestoreChanges() - Update local     │
│  • Soft delete handling (deleted: true)         │
└─────────────────────────────────────────────────┘
       │                                  │
       ▼                                  ▼
┌─────────────────────────────────────────────────┐
│              SyncOrchestrator                    │
│  • enqueue() - Queue local changes              │
│  • processBatch() - Push to Firestore           │
│  • Retry on failure                             │
└─────────────────────────────────────────────────┘
```

### 6.2 Luồng Tạo đơn sửa chữa
```
User tạo đơn sửa
       │
       ▼
┌─────────────────┐
│ CreateRepairView│
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Validate      ┌─────────────┐
│   UserService   │◀──────────────── │  Input Form  │
│ (validatePhone) │                   └─────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐     Insert        ┌─────────────┐
│   DBHelper      │──────────────────▶│   SQLite    │
│ (insertRepair)  │                   │ repairs     │
└────────┬────────┘                   └─────────────┘
         │
         ▼
┌─────────────────┐     Add           ┌─────────────┐
│FirestoreService │──────────────────▶│  Firestore  │
│ (addRepair)     │                   │  repairs    │
└────────┬────────┘                   └─────────────┘
         │
         ▼
┌─────────────────┐
│NotificationSvc  │──▶ Push notification to team
│ (sendCloudNoti) │
└─────────────────┘
```

### 6.3 Luồng Bán hàng
```
User tạo đơn bán
       │
       ▼
┌─────────────────┐
│ CreateSaleView  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Chọn sản phẩm   │◀── Từ InventoryView hoặc QR scan
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Thanh toán      │◀── UnifiedPaymentPage
│ (Cash/Bank/     │    (Tiền mặt/Chuyển khoản/
│  Installment)   │     Trả góp ngân hàng)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Cập nhật tồn kho│──▶ Giảm quantity trong products
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Tạo công nợ     │──▶ Nếu trả góp → tạo Debt
│ (nếu có)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ In hóa đơn      │──▶ Bluetooth/WiFi printer
└─────────────────┘
```

---

## 7. HỆ THỐNG PHÂN QUYỀN

### 7.1 Các vai trò (Roles)
| Role | Mô tả | Quyền hạn |
|------|-------|-----------|
| `super_admin` | Quản trị viên hệ thống | Toàn quyền, xem tất cả shops |
| `owner` | Chủ cửa hàng | Toàn quyền trong shop của mình |
| `admin` | Quản lý | Gần như owner, một số hạn chế |
| `staff` | Nhân viên | Theo quyền được cấp |

### 7.2 Các quyền chi tiết
```dart
// Quyền xem
allowViewRepairs       // Xem đơn sửa chữa
allowViewSales         // Xem đơn bán hàng
allowViewInventory     // Xem kho hàng
allowViewRevenue       // Xem doanh thu
allowViewExpenses      // Xem chi phí
allowViewDebts         // Xem công nợ
allowViewWarranty      // Xem bảo hành
allowViewCustomers     // Xem khách hàng
allowViewSuppliers     // Xem nhà cung cấp

// Quyền tạo/sửa
allowCreateRepair      // Tạo đơn sửa
allowUpdateRepair      // Cập nhật đơn sửa
allowCreateSale        // Tạo đơn bán
allowAddProduct        // Thêm sản phẩm
allowEditProduct       // Sửa sản phẩm
allowDeleteProduct     // Xóa sản phẩm
allowAddExpense        // Thêm chi phí

// Quyền quản lý
allowManageStaff       // Quản lý nhân viên
allowManageSettings    // Quản lý cài đặt
allowApproveDelivery   // Duyệt trả máy
allowPrint             // In hóa đơn
allowExport            // Xuất báo cáo
```

### 7.3 Cơ chế kiểm tra quyền
```dart
// Trong code
final permissions = await UserService.getCurrentUserPermissions();
if (permissions['allowViewRevenue'] == true) {
  // Cho phép xem doanh thu
}

// Super admin check
if (UserService.isCurrentUserSuperAdmin()) {
  // Bypass tất cả quyền
}
```

---

## 8. CÁC TÍNH NĂNG CHÍNH

### 8.1 Tính năng Bán hàng
- ✅ Tạo đơn bán nhanh
- ✅ Quét QR/barcode để thêm sản phẩm
- ✅ Thanh toán đa phương thức (tiền mặt, chuyển khoản, trả góp)
- ✅ Trả góp qua ngân hàng (hỗ trợ 2 ngân hàng)
- ✅ Tính chiết khấu
- ✅ In hóa đơn nhiệt
- ✅ Ghi nhận bảo hành
- ✅ Theo dõi tất toán trả góp

### 8.2 Tính năng Sửa chữa
- ✅ Tiếp nhận máy sửa với ảnh
- ✅ Workflow trạng thái (Đang sửa → Chờ LK → Hoàn thành → Đã trả)
- ✅ Ghi nhận linh kiện sử dụng
- ✅ Phân công thợ sửa
- ✅ Tính giá dịch vụ + linh kiện
- ✅ Duyệt trả máy
- ✅ In phiếu biên nhận
- ✅ Quản lý bảo hành

### 8.3 Tính năng Kho hàng
- ✅ Quản lý tồn kho theo IMEI
- ✅ Nhập hàng từ NCC
- ✅ Kho tạm (sản phẩm chờ giá)
- ✅ Nhập nhanh từ QR/barcode
- ✅ Kiểm kê kho
- ✅ Quản lý linh kiện
- ✅ Theo dõi giá vốn/giá bán
- ✅ Phân loại (Điện thoại, Phụ kiện, Linh kiện)

### 8.4 Tính năng Tài chính
- ✅ Thống kê doanh thu theo ngày/tuần/tháng
- ✅ Quản lý chi phí
- ✅ Quản lý công nợ (nợ khách, nợ NCC)
- ✅ Chốt quỹ cuối ngày
- ✅ Báo cáo tài chính tổng hợp
- ✅ Theo dõi trả góp ngân hàng
- ✅ Log hoạt động tài chính

### 8.5 Tính năng Nhân sự
- ✅ Quản lý nhân viên
- ✅ Phân quyền chi tiết
- ✅ Chấm công (check in/out với ảnh)
- ✅ Quản lý ca làm việc
- ✅ Tính lương tự động
- ✅ Đánh giá hiệu suất
- ✅ Cài đặt các khoản khấu trừ

### 8.6 Tính năng Hệ thống
- ✅ Đồng bộ real-time (offline-first)
- ✅ Push notifications
- ✅ Chat nội bộ
- ✅ Tìm kiếm toàn cục
- ✅ Nhật ký hoạt động
- ✅ Backup/restore
- ✅ Đa ngôn ngữ (vi/en)
- ✅ In hóa đơn Bluetooth/WiFi

---

## 📞 THÔNG TIN LIÊN HỆ

**Nhà phát triển:** Huluca Tech  
**Email:** support@huluca.com  
**Hotline:** 0909.xxx.xxx

---

*Tài liệu được cập nhật lần cuối: Tháng 1/2026*  
*Phiên bản app: 3.4.0+10*
