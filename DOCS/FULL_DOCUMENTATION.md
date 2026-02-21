# 📚 TÀI LIỆU TỔNG HỢP DỰ ÁN QUANLYSHOP (HULUCA)

> **Phần mềm Quản lý Tiệm Sửa chữa & Mua bán Điện thoại / Shop Đa Ngành**
> Phiên bản: 3.4.0+10 | Flutter + Firebase
> Cập nhật: 02/2026

---

## 📋 MỤC LỤC TỔNG

### PHẦN A: QUY TẮC & ONBOARDING
- [A1. Nguyên tắc làm việc](#a1-nguyên-tắc-làm-việc)
- [A2. Onboarding cho Developer mới](#a2-onboarding-cho-developer-mới)

### PHẦN B: CẤU TRÚC DỰ ÁN
- [B1. Tổng quan dự án](#b1-tổng-quan-dự-án)
- [B2. Kiến trúc hệ thống](#b2-kiến-trúc-hệ-thống)
- [B3. Cấu trúc thư mục chi tiết](#b3-cấu-trúc-thư-mục-chi-tiết)
- [B4. Database Schema](#b4-database-schema)
- [B5. Luồng dữ liệu](#b5-luồng-dữ-liệu)
- [B6. Hệ thống phân quyền](#b6-hệ-thống-phân-quyền)
- [B7. Các tính năng chính](#b7-các-tính-năng-chính)

### PHẦN C: HỆ THỐNG THANH TOÁN
- [C1. Unified Payment System](#c1-unified-payment-system)
- [C2. Báo cáo kiểm tra luồng thanh toán](#c2-báo-cáo-kiểm-tra-luồng-thanh-toán)

### PHẦN D: MULTI-SHOP
- [D1. Multi-Shop hướng dẫn sử dụng](#d1-multi-shop-hướng-dẫn-sử-dụng)
- [D2. Multi-Shop Production Checklist](#d2-multi-shop-production-checklist)

### PHẦN E: MỞ RỘNG ĐA NGÀNH
- [E1. Hướng dẫn mở rộng đa ngành](#e1-hướng-dẫn-mở-rộng-đa-ngành)

### PHẦN F: TRUNG TÂM HƯỚNG DẪN
- [F1. Help Center Guide](#f1-help-center-guide)

### PHẦN G: HƯỚNG DẪN SỬ DỤNG (USER GUIDE)
- [G1. Hướng dẫn Tiếng Việt - Phần 1](#g1-hướng-dẫn-tiếng-việt---phần-1)
- [G2. Hướng dẫn Tiếng Việt - Phần 2](#g2-hướng-dẫn-tiếng-việt---phần-2)
- [G3. User Guide (English)](#g3-user-guide-english)

---

---

# PHẦN A: QUY TẮC & ONBOARDING

---

## A1. Nguyên tắc làm việc

> Nguồn gốc: `DOCS/nguyentac.md`

App đã product lên CH Play: "Đọc file copilot-instructions.md và DEVELOPER_ONBOARDING.md để hiểu cấu trúc dự án trước khi bắt đầu."

Và thực hiện các yêu cầu nâng cấp hoặc chỉnh sửa các lỗi sau: (app đã product lên store mọi thay đổi đều phải test, flutter run đảm bảo ko lỗi build, git commit kèm theo lý do rõ ràng):

**Mối quan hệ giữa các file tài liệu:**

```
┌─────────────────────────────┐
│ copilot-instructions.md    │  ← AI đọc để hiểu cấu trúc
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│ DEVELOPER_ONBOARDING.md    │  ← Dev mới đọc đầu tiên
└─────────────────────────────┘
              │
    ┌─────────┼─────────┬─────────────────┐
    ▼         ▼         ▼                 ▼
┌────────┐ ┌────────┐ ┌────────────┐ ┌────────────────────┐
│PAYMENT │ │UNIFIED │ │MULTI_SHOP  │ │MULTI_INDUSTRY     │
│FLOW    │ │PAYMENT │ │GUIDE       │ │EXPANSION_GUIDE    │
│AUDIT   │ │GUIDE   │ │            │ │                    │
└────────┘ └────────┘ └────────────┘ └────────────────────┘
   Audit     Cách sử    Multi-shop     Mở rộng đa ngành
   tài chính dụng PI    architecture   (thời trang)
```

---

## A2. Onboarding cho Developer mới

> Nguồn gốc: `DOCS/DEVELOPER_ONBOARDING.md`

### A2.1 Tổng Quan Dự Án

#### Công nghệ
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions)
- **Local DB**: SQLite (sqflite) - offline-first với real-time sync
- **State**: Không dùng state management phức tạp, dùng StatefulWidget + EventBus

#### Chức năng chính
- Bán hàng (điện thoại, phụ kiện)
- Sửa chữa (nhận máy, bàn giao, thu tiền)
- Nhập kho từ NCC (nhà cung cấp)
- Quản lý công nợ (khách hàng nợ shop, shop nợ NCC)
- Chốt quỹ hàng ngày
- Báo cáo tài chính
- Multi-shop (1 owner nhiều cửa hàng)

### A2.2 Cấu Trúc Thư Mục

```
lib/
├── main.dart              # Entry point, Firebase init, AuthGate
├── firebase_options.dart  # Firebase config (auto-generated)
│
├── models/                # Data models (toMap/fromMap)
│   ├── product_model.dart
│   ├── sale_order_model.dart
│   ├── repair_model.dart
│   ├── debt_model.dart
│   ├── payment_intent_model.dart  # ⭐ QUAN TRỌNG
│   └── ...
│
├── services/              # Business logic & external integrations
│   ├── firestore_service.dart     # Firestore CRUD
│   ├── user_service.dart          # Auth, role, shopId
│   ├── sync_service.dart          # Real-time sync Firestore → SQLite
│   ├── payment_intent_service.dart # ⭐ Central payment service
│   ├── money_transaction_service.dart
│   ├── money_validation_service.dart
│   ├── current_shop_service.dart  # Multi-shop management
│   └── ...
│
├── data/
│   └── db_helper.dart     # SQLite wrapper (version 17+)
│
├── views/                 # UI screens
│   ├── home_view.dart
│   ├── create_sale_view.dart
│   ├── repair_detail_view.dart
│   ├── financial_report_view.dart
│   ├── unified_payment_page.dart  # ⭐ Trang thanh toán chung
│   └── ...
│
├── widgets/               # Reusable UI components
├── constants/             # App constants, financial_constants.dart
├── theme/                 # Colors, text styles
└── l10n/                  # Localization (VI/EN)
```

### A2.3 Kiến Trúc & Nguyên Tắc

#### Service-First Pattern
```
❌ KHÔNG: Widget → Firestore/SQLite trực tiếp
✅ ĐÚNG:  Widget → Service → DBHelper/Firestore
```

#### Offline-First với Real-Time Sync
```
1. User tạo data → Lưu SQLite (isSynced=0)
2. SyncOrchestrator → Queue sync lên Firestore
3. SyncService lắng nghe Firestore → Cập nhật SQLite
```

#### Soft Delete
```dart
// KHÔNG xóa thật, chỉ đánh dấu deleted=true
await db.update('repairs', {'deleted': 1}, where: 'id = ?');
```

#### EventBus Pattern
```dart
// Emit event khi data thay đổi
EventBus().emit('repairs_changed');
// Listen trong view
EventBus().on('repairs_changed', (_) => _loadData());
```

#### Multi-Tenant Isolation
```dart
// MỌI query PHẢI filter theo shopId
final shopId = UserService.getShopIdSync();
db.query('repairs', where: 'shopId = ?', whereArgs: [shopId]);
```

### A2.4 Flow Tài Chính (QUAN TRỌNG)

#### ⚠️ NGUYÊN TẮC VÀNG

> **MỌI giao dịch tiền PHẢI đi qua PaymentIntentService**

#### PaymentIntent Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Business View  │ ──▶ │ PaymentIntent   │ ──▶ │ UnifiedPayment  │
│  (Sale, Repair) │     │ Service.create  │     │     Page        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Ledger Entry   │ ◀── │ PaymentIntent   │ ◀── │  User confirms  │
│  (Ghi sổ)       │     │ Service.execute │     │  payment method │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

#### PaymentIntent Types

| Type | Mô tả | Direction |
|------|-------|-----------|
| `salePayment` | Thu tiền bán hàng | IN |
| `repairService` | Thu tiền sửa chữa | IN |
| `customerDebtCollection` | Thu nợ khách hàng | IN |
| `supplierDebt` | Trả nợ NCC | OUT |
| `operatingExpense` | Chi phí hoạt động | OUT |
| `salaryPayment` | Trả lương | OUT |

#### Accrual vs Cash Basis

```
┌─────────────────────────────────────────────────────────────┐
│                    ACCRUAL BASIS (Dồn tích)                 │
│  - Doanh thu ghi khi BÁN (không phải khi thu tiền)          │
│  - Chi phí ghi khi PHÁT SINH (không phải khi chi tiền)      │
│  - Công nợ KHÔNG ảnh hưởng lợi nhuận ngay                   │
└─────────────────────────────────────────────────────────────┘

Ví dụ:
- Bán máy 10tr CÔNG NỢ → Doanh thu +10tr, Lợi nhuận tính ngay
- Thu nợ 10tr → Quỹ +10tr nhưng KHÔNG cộng thêm lợi nhuận
```

#### Tránh Double-Counting

```
❌ SAI: Tính "giá vốn hàng bán" + "trả nợ NCC" = tính 2 lần

✅ ĐÚNG:
- Bán hàng: Doanh thu - Giá vốn = Lợi nhuận gộp
- Nhập hàng CÔNG NỢ: Chỉ ghi debt, KHÔNG ghi expense
- Trả nợ NCC: Ghi expense (chi phí thực tế ra quỹ)
```

### A2.5 Multi-Shop Architecture

#### Cấu trúc
```
User (uid: abc123)
  └── ownerOf: [shopId1, shopId2]

Shop (id: shopId1)
  └── ownerUid: abc123
  └── staff: [{uid: xyz, role: employee}, ...]
```

#### Chuyển Shop
```dart
// CurrentShopService.switchShop():
1. Validate ownership
2. Cancel sync subscriptions
3. Clear local SQLite
4. Update SharedPreferences
5. Restart sync for new shop
6. Emit EventBus.shopChanged
```

#### Firestore Rules
```javascript
function isShopOwner(shopId) {
  return get(/shops/$(shopId)).data.ownerUid == uid();
}
function belongsTo(shopId) {
  return isSuperAdmin() || myShopId() == shopId || isShopOwner(shopId);
}
```

### A2.6 Security Rules

#### Custom Claims (set by Cloud Functions)
```javascript
{
  isSuperAdmin: boolean,  // true cho admin@huluca.com
  shopId: string,         // Shop hiện tại của user
  role: 'owner' | 'manager' | 'employee' | 'technician'
}
```

#### Role Hierarchy
```
superAdmin > owner > manager > employee/technician
```

### A2.7 Checklist Trước Khi Code

**Khi thêm tính năng mới:**
- [ ] Có filter theo `shopId` chưa?
- [ ] Có đi qua Service layer chưa?
- [ ] Nếu liên quan tiền → dùng `PaymentIntentService`?
- [ ] Có emit EventBus sau khi thay đổi data?
- [ ] Có log vào `FinancialActivityService` nếu cần?
- [ ] UI text bằng tiếng Việt, code/comments bằng tiếng Anh?

**Khi sửa financial logic:**
- [ ] Đọc kỹ phần C (Hệ thống thanh toán)
- [ ] Kiểm tra không double-counting
- [ ] Test với cả TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ

**Khi thêm Firestore collection mới:**
- [ ] Thêm rules vào `firestore.rules`
- [ ] Thêm vào `SyncService` nếu cần sync
- [ ] Thêm table vào `db_helper.dart`

---

---

# PHẦN B: CẤU TRÚC DỰ ÁN

> Nguồn gốc: `DOCS/PROJECT_STRUCTURE_VI.md`

---

## B1. Tổng quan dự án

### Mô tả
**QuanLyShop** là ứng dụng quản lý toàn diện cho cửa hàng sửa chữa và mua bán điện thoại, được xây dựng trên nền tảng Flutter với backend Firebase.

### Công nghệ sử dụng
| Thành phần | Công nghệ |
|------------|-----------|
| Frontend | Flutter 3.10+ (Dart) |
| Backend | Firebase (Auth, Firestore, Storage, Functions, Messaging) |
| Local DB | SQLite (sqflite) |
| State Management | StatefulWidget + EventBus |
| Đa ngôn ngữ | flutter_localizations (vi, en) |

### Nền tảng hỗ trợ
- ✅ Android (APK/AAB)
- ✅ iOS (IPA)
- ✅ Web
- ⚠️ Windows (hạn chế một số tính năng)
- ⚠️ macOS (hạn chế một số tính năng)

---

## B2. Kiến trúc hệ thống

### Kiến trúc tổng quan
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

### Pattern áp dụng
- **Service-first access**: Tất cả truy cập dữ liệu qua Service classes
- **Offline-first**: Lưu local trước, sync lên cloud sau
- **Multi-tenant**: Phân tách dữ liệu theo `shopId`
- **Soft deletes**: Xóa mềm với flag `deleted: true`
- **Event-driven updates**: EventBus để thông báo thay đổi dữ liệu

---

## B3. Cấu trúc thư mục chi tiết

```
quanlyshop/
├── 📁 android/                 # Native Android configs
├── 📁 ios/                     # Native iOS configs
├── 📁 web/                     # Web platform
├── 📁 functions/               # Firebase Cloud Functions
│   ├── index.js               # Notification triggers
│   └── package.json
│
├── 📁 lib/                     # 🎯 SOURCE CODE CHÍNH
│   ├── main.dart              # Entry point
│   ├── firebase_options.dart  # Firebase config
│   ├── 📁 views/              # UI Screens (80+ files)
│   ├── 📁 services/           # Business Logic (35+ files)
│   ├── 📁 models/             # Data Models (27 files)
│   ├── 📁 widgets/            # Reusable Components (21 files)
│   ├── 📁 data/               # Local Database
│   ├── 📁 theme/              # UI Theme
│   ├── 📁 utils/              # Utilities
│   ├── 📁 constants/          # App Constants
│   ├── 📁 controllers/        # State Controllers
│   ├── 📁 core/               # Core utilities
│   └── 📁 l10n/               # Localization
│
├── 📁 assets/                  # Resources (images, fonts)
├── 📁 DOCS/                    # Documentation
├── 📁 test/                    # Unit tests
├── pubspec.yaml               # Dependencies
├── firebase.json              # Firebase config
├── firestore.rules            # Security rules
└── firestore.indexes.json     # DB indexes
```

### Views (Màn hình UI)

#### Màn hình chính
| File | Mô tả |
|------|-------|
| `main.dart` | Entry point - Khởi tạo Firebase, theme, routing |
| `home_view.dart` | Dashboard, thống kê, menu chính |
| `login_view.dart` | Email/Password auth |
| `register_view.dart` | Tạo tài khoản mới |

#### Module Bán hàng
| File | Mô tả |
|------|-------|
| `sale_list_view.dart` | Danh sách hóa đơn bán |
| `create_sale_view.dart` | Tạo hóa đơn bán hàng mới |
| `sale_detail_view.dart` | Xem/sửa chi tiết hóa đơn |
| `unified_payment_page.dart` | Xử lý thanh toán đa phương thức |

#### Module Sửa chữa
| File | Mô tả |
|------|-------|
| `order_list_view.dart` | Danh sách phiếu sửa chữa |
| `create_repair_order_view.dart` | Tạo phiếu sửa chữa mới |
| `repair_detail_view.dart` | Cập nhật trạng thái, linh kiện |
| `repair_receipt_view.dart` | Thiết kế và in biên lai |
| `warranty_view.dart` | Quản lý danh sách bảo hành |

#### Module Kho hàng
| File | Mô tả |
|------|-------|
| `inventory_view.dart` | Danh sách sản phẩm tồn kho |
| `stock_in_view.dart` | Nhập sản phẩm mới |
| `smart_stock_in_view.dart` | Nhập nhanh từ QR/barcode |
| `fast_inventory_input_view.dart` | Nhập hàng loạt |
| `fast_inventory_check_view.dart` | Đối chiếu tồn kho |
| `pending_stock_list_view.dart` | Sản phẩm chờ xác nhận giá |
| `parts_inventory_view.dart` | Quản lý phụ tùng, linh kiện |

#### Module Nhà cung cấp
| File | Mô tả |
|------|-------|
| `supplier_list_view.dart` | Danh sách nhà cung cấp |
| `supplier_form_view.dart` | Form nhập liệu NCC |
| `supplier_detail_view.dart` | Lịch sử giao dịch |
| `purchase_order_list_view.dart` | Danh sách đơn nhập hàng |
| `create_purchase_order_view.dart` | Tạo đơn nhập hàng mới |

#### Module Khách hàng
| File | Mô tả |
|------|-------|
| `customer_view.dart` | Danh sách khách hàng |
| `customer_management_view.dart` | Thông tin chi tiết khách |
| `customer_history_view.dart` | Lịch sử mua hàng/sửa chữa |

#### Module Tài chính
| File | Mô tả |
|------|-------|
| `revenue_view.dart` | Thống kê doanh thu |
| `expense_view.dart` | Quản lý chi phí (hỗ trợ embedded mode) |
| `debt_view.dart` | Quản lý nợ khách/NCC |
| `cash_closing_view.dart` | Kiểm kê tiền cuối ngày |
| `financial_report_view.dart` | Báo cáo tài chính tổng hợp (hỗ trợ embedded mode) |
| `financial_activity_log_view.dart` | Log hoạt động tài chính (hỗ trợ embedded mode) |
| `bank_installment_report_view.dart` | Báo cáo trả góp ngân hàng (hỗ trợ embedded mode) |
| **`financial_hub_view.dart`** | **⭐ Trang tổng hợp tài chính - gộp 4 view trên vào 1 TabBar** |
| `pending_payments_list_view.dart` | Trung tâm thanh toán |
| `unified_payment_page.dart` | Trang thực hiện thanh toán (DO NOT MODIFY) |

#### Module Nhân sự
| File | Mô tả |
|------|-------|
| `staff_list_view.dart` | Danh sách nhân viên |
| `staff_permissions_view.dart` | Cấp quyền cho nhân viên |
| `staff_performance_view.dart` | Đánh giá hiệu suất NV |
| `attendance_view.dart` | Điểm danh hàng ngày |
| `attendance_management_view.dart` | Xem/duyệt chấm công |
| `payroll_view.dart` | Tính lương nhân viên |
| `payroll_settings_view.dart` | Thiết lập công thức lương |
| `hr_salary_settings_view.dart` | Cấu hình HR toàn cục |
| `work_schedule_settings_view.dart` | Thiết lập lịch làm việc |

#### Module Cài đặt & Hệ thống
| File | Mô tả |
|------|-------|
| `settings_view.dart` | Menu cài đặt chung |
| `shop_settings_view.dart` | Thông tin cửa hàng |
| `shop_selector_view.dart` | Super admin chọn shop |
| `printer_setting_view.dart` | Cấu hình máy in |
| `notification_settings_view.dart` | Cài đặt thông báo |
| `invoice_template_view.dart` | Thiết kế template in |
| `super_admin_view.dart` | Quản trị hệ thống |
| `audit_log_view.dart` | Log hoạt động hệ thống |

#### Module Tiện ích
| File | Mô tả |
|------|-------|
| `qr_scan_view.dart` | Quét mã QR/barcode |
| `global_search_view.dart` | Tìm kiếm toàn cục |
| `chat_view.dart` | Trò chuyện nội bộ |
| `notifications_view.dart` | Xem danh sách thông báo |

### Services (Business Logic)

#### Services cốt lõi
| File | Chức năng chính |
|------|-----------------|
| `firestore_service.dart` | Tất cả operations với Cloud Firestore |
| `user_service.dart` | Auth, role, permissions, shopId |
| `sync_service.dart` | Real-time sync Firestore ↔ SQLite |
| `sync_orchestrator.dart` | Quản lý queue đồng bộ local → cloud |
| `notification_service.dart` | Push notifications, in-app alerts |

#### Services tài chính
| File | Chức năng chính |
|------|-----------------|
| `money_transaction_service.dart` | Xử lý các giao dịch tài chính |
| `money_validation_service.dart` | Kiểm tra hợp lệ số tiền |
| `payment_intent_service.dart` | Quản lý thanh toán pending |
| `financial_activity_service.dart` | Ghi nhận hoạt động tài chính |
| `salary_calculation_service.dart` | Công thức tính lương nhân viên |

#### Services nghiệp vụ
| File | Chức năng chính |
|------|-----------------|
| `customer_service.dart` | CRUD khách hàng |
| `supplier_service.dart` | CRUD NCC, lịch sử nhập |
| `supplier_payment_service.dart` | Xử lý thanh toán cho NCC |
| `repair_partner_service.dart` | Quản lý đối tác sửa chữa |
| `stock_entry_service.dart` | Xử lý nghiệp vụ nhập kho |

#### Services tiện ích
| File | Chức năng chính |
|------|-----------------|
| `bluetooth_printer_service.dart` | In qua máy in Bluetooth |
| `wifi_printer_service.dart` | In qua máy in mạng |
| `unified_printer_service.dart` | API thống nhất cho in ấn |
| `chat_service.dart` | Xử lý tin nhắn nội bộ |
| `storage_service.dart` | Upload/download Firebase Storage |
| `encryption_service.dart` | Mã hóa dữ liệu nhạy cảm |
| `connectivity_service.dart` | Kiểm tra trạng thái mạng |
| `audit_service.dart` | Ghi nhật ký hoạt động |

### Models (Data Models)

#### Models chính
| File | Class | Mô tả |
|------|-------|-------|
| `repair_model.dart` | `Repair` | Phiếu sửa chữa |
| `product_model.dart` | `Product` | Sản phẩm trong kho |
| `sale_order_model.dart` | `SaleOrder` | Đơn hàng bán |
| `customer_model.dart` | `Customer` | Thông tin khách hàng |
| `expense_model.dart` | `Expense` | Chi phí |
| `debt_model.dart` | `Debt` | Công nợ |
| `attendance_model.dart` | `Attendance` | Chấm công |

#### Models phụ trợ
| File | Class | Mô tả |
|------|-------|-------|
| `purchase_order_model.dart` | `PurchaseOrder` | Đơn nhập hàng |
| `supplier_model.dart` | `Supplier` | Nhà cung cấp |
| `stock_entry_model.dart` | `StockEntry` | Phiếu nhập kho |
| `repair_partner_model.dart` | `RepairPartner` | Đối tác sửa chữa |
| `financial_activity_model.dart` | `FinancialActivity` | Hoạt động tài chính |
| `payment_intent_model.dart` | `PaymentIntent` | Dự định thanh toán |
| `employee_salary_model.dart` | `EmployeeSalary` | Lương nhân viên |

### Widgets (UI Components)

| File | Mô tả |
|------|-------|
| `unified_sync_button.dart` | Nút sync thống nhất |
| `notification_badge.dart` | Badge số thông báo |
| `currency_text_field.dart` | Input tiền tệ |
| `validated_text_field.dart` | Input có validation |
| `debounced_search_field.dart` | Ô tìm kiếm có debounce |
| `gradient_fab.dart` | FAB với gradient |
| `loading_intro_screen.dart` | Màn hình loading animation |
| `perpetual_calendar.dart` | Lịch vạn niên |
| `lazy_load_list_view.dart` | List load lazy |
| `parts_selection_dialog.dart` | Dialog chọn linh kiện |

### Theme (Giao diện)

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

### Constants

| File | Mô tả |
|------|-------|
| `financial_constants.dart` | Hằng số tài chính (thuế, phí...) |
| `product_constants.dart` | Hằng số sản phẩm (loại, trạng thái...) |
| `partner_constants.dart` | Hằng số đối tác |

### Utils

| File | Functions chính |
|------|-----------------|
| `money_utils.dart` | `formatVND()`, `parseAmount()` |
| `imei_extractor.dart` | `extractIMEI()` |
| `qr_parser.dart` | `parseQRCode()` |
| `sku_generator.dart` | `generateSKU()` |
| `repair_status_validator.dart` | `validateStatusChange()` |
| `debouncer.dart` | `Debouncer.run()` |

---

## B4. Database Schema

### Bảng repairs (Phiếu sửa chữa)
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
  status INTEGER,           -- 1: Đang sửa, 2: Chờ LK, 3: Hoàn thành, 4: Đã trả
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

### Bảng products (Sản phẩm)
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
  isPending INTEGER DEFAULT 0,
  pendingSupplier TEXT
);
```

### Bảng sales (Đơn bán)
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

### Tất cả các bảng SQLite

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

## B5. Luồng dữ liệu

### Luồng Đồng bộ (Sync Flow)

```
┌─────────────┐     Real-time      ┌─────────────┐
│   FIRESTORE │ ◀──────────────▶  │   SQLite    │
│   (Cloud)   │    Listener        │   (Local)   │
└─────────────┘                    └─────────────┘
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

### Backbone Đồng bộ

**Quy tắc then chốt:**
- **shopId là "hàng rào dữ liệu"**: listener/query đều filter theo shopId; super admin phải chọn shop trước.
- **Xung đột ưu tiên local pending**: local chưa sync mà "mới hơn" cloud → **không ghi đè local**, mà **enqueue** để đẩy lên cloud.
- **Soft delete**: Firestore `deleted: true` → local xoá/đánh dấu xoá tương ứng.
- **SQLite không nhận Timestamp**: tất cả `Timestamp` phải convert sang milliseconds trước khi upsert.

### Backbone Dòng tiền

**Quy tắc then chốt:**
- **Không "tính/validate rải rác"**: validation phải tập trung ở `MoneyValidationService`.
- **Không "thu/chi trực tiếp" từ module**: thực thi thanh toán phải đi qua `PaymentIntentService` (intent chỉ execute 1 lần).
- **Sổ cái append-only**: `MoneyTransactionService` chỉ ghi thêm, không update/delete.
- **Chốt quỹ là "cổng chặn"**: nếu ngày bị khoá thì app chặn giao dịch và thông báo rõ.

### Luồng Tạo đơn sửa chữa

```
User tạo đơn → CreateRepairView → UserService (validate) → DBHelper (insert SQLite)
→ FirestoreService (add Firestore) → NotificationService (push to team)
```

### Luồng Bán hàng

```
User tạo đơn → CreateSaleView → Chọn SP (từ kho/QR) → UnifiedPaymentPage
→ Cập nhật tồn kho → Tạo công nợ (nếu trả góp) → In hóa đơn
```

---

## B6. Hệ thống phân quyền

### Các vai trò
| Role | Mô tả | Quyền hạn |
|------|-------|-----------|
| `super_admin` | Quản trị viên hệ thống | Toàn quyền, xem tất cả shops |
| `owner` | Chủ cửa hàng | Toàn quyền trong shop của mình |
| `admin` | Quản lý | Gần như owner, một số hạn chế |
| `staff` | Nhân viên | Theo quyền được cấp |

### Các quyền chi tiết
```dart
// Quyền xem
allowViewRepairs, allowViewSales, allowViewInventory,
allowViewRevenue, allowViewExpenses, allowViewDebts,
allowViewWarranty, allowViewCustomers, allowViewSuppliers

// Quyền tạo/sửa
allowCreateRepair, allowUpdateRepair, allowCreateSale,
allowAddProduct, allowEditProduct, allowDeleteProduct, allowAddExpense

// Quyền quản lý
allowManageStaff, allowManageSettings, allowApproveDelivery,
allowPrint, allowExport
```

### Cơ chế kiểm tra quyền
```dart
final permissions = await UserService.getCurrentUserPermissions();
if (permissions['allowViewRevenue'] == true) {
  // Cho phép xem doanh thu
}
if (UserService.isCurrentUserSuperAdmin()) {
  // Bypass tất cả quyền
}
```

---

## B7. Các tính năng chính

### Bán hàng
- ✅ Tạo đơn bán nhanh, quét QR/barcode
- ✅ Thanh toán đa phương thức (tiền mặt, chuyển khoản, trả góp)
- ✅ Trả góp qua ngân hàng (hỗ trợ 2 ngân hàng)
- ✅ In hóa đơn nhiệt, ghi nhận bảo hành

### Sửa chữa
- ✅ Tiếp nhận máy sửa với ảnh
- ✅ Workflow trạng thái (Đang sửa → Chờ LK → Hoàn thành → Đã trả)
- ✅ Ghi nhận linh kiện, phân công thợ, duyệt trả máy, in phiếu biên nhận

### Kho hàng
- ✅ Quản lý tồn kho theo IMEI, nhập hàng từ NCC
- ✅ Kho tạm (sản phẩm chờ giá), nhập nhanh từ QR/barcode, kiểm kê kho

### Tài chính
- ✅ Thống kê doanh thu, quản lý chi phí, quản lý công nợ
- ✅ Chốt quỹ cuối ngày, báo cáo tài chính tổng hợp, log hoạt động

### Nhân sự
- ✅ Quản lý nhân viên, phân quyền chi tiết
- ✅ Chấm công (check in/out với ảnh), tính lương tự động

### Hệ thống
- ✅ Đồng bộ real-time (offline-first), Push notifications
- ✅ Chat nội bộ, tìm kiếm toàn cục, đa ngôn ngữ (vi/en)
- ✅ In hóa đơn Bluetooth/WiFi

---

---

# PHẦN C: HỆ THỐNG THANH TOÁN

---

## C1. Unified Payment System

> Nguồn gốc: `DOCS/UNIFIED_PAYMENT_GUIDE.md`

### Tổng quan

Hệ thống thanh toán tập trung đảm bảo **TẤT CẢ** các giao dịch tài chính đều đi qua một luồng duy nhất.

### Luồng xử lý

```
[Business Module] → PaymentIntentService (PENDING) → PendingPaymentsListView
→ UnifiedPaymentPage (chọn PTTT) → MoneyTransactionService.appendLedger() (ghi sổ)
```

### Các tab trên trang Thanh Toán

| Tab | Mô tả | Màu |
|-----|-------|-----|
| **CHỜ THU** | Tiền khách cần trả cho shop | Xanh dương 🔵 |
| **CHỜ CHI** | Tiền shop cần trả (NCC, chi phí) | Cam 🟠 |
| **LỊCH SỬ** | Giao dịch đã hoàn thành/hủy | Xám/Xanh lá |

### Các loại PaymentIntent

| Type | Mô tả | Hướng tiền |
|------|-------|-----------|
| `supplierDebt` | Trả nợ NCC | CHI ⬆️ |
| `supplierPurchase` | Thanh toán nhập hàng | CHI ⬆️ |
| `customerDebtCollection` | Thu nợ khách | THU ⬇️ |
| `customerRefund` | Hoàn tiền khách | CHI ⬆️ |
| `repairService` | Thanh toán sửa chữa | THU ⬇️ |
| `repairPartnerDebt` | Trả nợ đối tác SC | CHI ⬆️ |
| `salePayment` | Thanh toán bán hàng | THU ⬇️ |
| `saleInstallment` | Thanh toán trả góp | THU ⬇️ |
| `inventoryPurchase` | Thanh toán nhập kho | CHI ⬆️ |
| `partsStockIn` | Thanh toán nhập LK | CHI ⬆️ |
| `operatingExpense` | Chi phí vận hành | CHI ⬆️ |
| `utilityExpense` | Chi phí tiện ích | CHI ⬆️ |
| `salaryPayment` | Trả lương | CHI ⬆️ |
| `bonusPayment` | Thưởng nhân viên | CHI ⬆️ |
| `otherIncome` | Thu nhập khác | THU ⬇️ |

### Tích hợp cho Developer

```dart
import '../services/payment_intent_service.dart';
import '../models/payment_intent_model.dart';
import '../views/unified_payment_page.dart';

final intent = PaymentIntent(
  id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
  type: PaymentIntentType.operatingExpense,
  amount: 500000,
  description: 'Tiền điện tháng 1',
  createdBy: 'user_123',
  createdAt: DateTime.now().millisecondsSinceEpoch,
  metadata: {'category': 'ĐIỆN NƯỚC'},
);

final result = await UnifiedPaymentPage.navigateWithIntent(context, intent);
```

### ⚠️ Lưu ý quan trọng

1. **KHÔNG BAO GIỜ** gọi trực tiếp `db.insertExpense()`, `db.insertDebtPayment()`, `FinancialActivityService.log*()`
2. **LUÔN** tạo `PaymentIntent` và dùng `UnifiedPaymentPage.navigateWithIntent()`
3. Mỗi giao dịch chỉ được thực hiện **MỘT LẦN**
4. Dữ liệu ledger là **APPEND-ONLY** - không cho phép DELETE hoặc UPDATE

---

## C2. Báo cáo kiểm tra luồng thanh toán

> Nguồn gốc: `DOCS/PAYMENT_FLOW_AUDIT_REPORT.md`

**Ngày thực hiện:** 2025-01-XX | **Phiên bản:** 10.0.7

### Kết quả
- ✅ **4 file test/debug đã xóa** (debt_analysis_view, currency_input_demo, payment_intent_test_view, attendance_salary_test_view)
- ✅ **2 view đã sửa PaymentIntent** (inventory_view, fast_stock_in_view)
- ⚠️ **4 nhóm view trùng chức năng** (đề xuất hợp nhất - ưu tiên thấp)

### Các PaymentIntentType được sử dụng

| Type | Sử dụng trong |
|------|---------------|
| `supplierDebt` | inventory_view, fast_stock_in_view, parts_inventory_view |
| `customerDebtCollection` | debt_management_view |
| `repairService` | repair_detail_view |
| `repairPartnerDebt` | repair_detail_view |
| `inventoryPurchase` | inventory_view, fast_stock_in_view |
| `partsStockIn` | parts_inventory_view |
| `operatingExpense` | expenses_list_view |

### Đề xuất hợp nhất View (ưu tiên thấp)

**Nhóm Nhập Kho** (5 views → 2): Giữ `inventory_view` + `fast_stock_in_view`

**Nhóm Đối Tác** (5 views → 3): Giữ `suppliers_view` + `supplier_transactions_view` + `repair_partners_view`

**Nhóm Tài Chính** (8 views → 4): Giữ `debt_management_view` + `expenses_list_view` + `unified_payment_page` + `financial_activity_log_view`

**Nhóm Cài Đặt** (6 views → 3): Giữ `settings_view` + `admin_settings_view` + `user_management_view`

---

---

# PHẦN D: MULTI-SHOP

---

## D1. Multi-Shop hướng dẫn sử dụng

> Nguồn gốc: `DOCS/MULTI_SHOP_GUIDE.md`

### Tổng quan
Multi-Shop Phase 1 cho phép **chủ cửa hàng (owner)** quản lý nhiều chi nhánh từ một tài khoản duy nhất.

### Tính năng

**1. Chuyển đổi Shop**
- Vị trí: Cài đặt → Chọn cửa hàng
- Điều kiện: Chỉ hiển thị khi user có role `owner` VÀ sở hữu >= 2 shops

**2. Shop Indicator**
- Vị trí: AppBar của Home view
- Chỉ hiển thị khi owner có >= 2 shops

**3. Tạo chi nhánh mới**
- Vị trí: Settings → Chọn cửa hàng → "Tạo chi nhánh mới"
- Tự động đặt shop mới làm shop hoạt động

### Data Isolation
```
User login → Check ownedShops → if count >= 2 → Show ShopSwitcher
                              → if count == 1 → Hide ShopSwitcher
```

### Khi chuyển shop
1. Cancel tất cả Firestore subscriptions
2. Clear local SQLite cache
3. Re-init EncryptionService
4. Restart SyncService với shopId mới
5. Emit EventBus.shopChanged
6. Notify tất cả listeners để reload UI

### API Reference

```dart
final service = CurrentShopService();
await service.init();
String? shopId = await service.getActiveShopId();
bool success = await service.switchShop(newShopId);
List<Map<String, dynamic>> shops = await service.getOwnedShops();
await service.clear();

// Lắng nghe khi shop thay đổi
EventBus.on(EventBus.shopChanged, (data) {
  // Reload UI data
});
```

### Files chính

| File | Mô tả |
|------|-------|
| `lib/services/current_shop_service.dart` | Service quản lý activeShopId |
| `lib/widgets/shop_switcher_widget.dart` | UI dropdown chọn shop |
| `lib/views/settings_view.dart` | Tích hợp ShopSwitcher |
| `lib/views/home_view.dart` | Shop indicator + EventBus listener |

### Troubleshooting

**ShopSwitcher không hiển thị:** Check role phải là `owner`, check ownedShops phải >= 2

**Data không reload sau switch:** Check EventBus listener trong HomeView

**Lỗi khi tạo chi nhánh:** Check Firestore permissions, check internet

### Phase 2 Roadmap
- [ ] Staff assignment per shop
- [ ] Shop-level permissions
- [ ] Cross-shop reporting
- [ ] Shop transfer ownership
- [ ] Shop archiving

---

## D2. Multi-Shop Production Checklist

> Nguồn gốc: `DOCS/MULTI_SHOP_PHASE1_CHECKLIST.md`

### Files Created/Modified

**New Files:**
- `lib/services/current_shop_service.dart`
- `lib/widgets/shop_switcher_widget.dart`

**Modified Files:**
- `lib/main.dart` - Added CurrentShopService import and init
- `lib/views/settings_view.dart` - Integrated ShopSwitcherWidget
- `lib/l10n/app_en.arb` - Added localization keys
- `lib/l10n/app_vi.arb` - Added Vietnamese translations

### Test Cases

1. **Single Shop User** → NO shop switcher, all data loads normally
2. **Owner with ONE Shop** → NO shop switcher
3. **Owner with MULTIPLE Shops** → ShopSwitcher shows, can switch, data reloads
4. **App Restart Persistence** → Still on selected shop after kill/reopen
5. **Cache Clear on Switch** → Old data NOT visible, new shop data loads
6. **Firestore Security Rules** → Cannot read Shop B data while on Shop A
7. **Super Admin** → Can select any shop
8. **Logout/Login Cycle** → Cleared on logout, persisted on login

### Rollback Plan
1. Remove ShopSwitcherWidget from settings_view.dart
2. Remove CurrentShopService.init() from main.dart
3. Remove CurrentShopService.clear() calls

### Deployment Steps
1. `flutter test`
2. `flutter build apk --release`
3. Test APK on physical device
4. Upload to Play Console internal testing
5. Promote to production after 24h testing

---

---

# PHẦN E: MỞ RỘNG ĐA NGÀNH

> Nguồn gốc: `DOCS/MULTI_INDUSTRY_EXPANSION_GUIDE.md`

---

## E1. Hướng dẫn mở rộng đa ngành

### Mục tiêu: Từ "Phone Shop" → "Multi-Industry Shop"

```
         HIỆN TẠI                          SAU MỞ RỘNG
    ┌─────────────┐                   ┌─────────────────┐
    │   📱 ĐIỆN   │                   │    🏪 SHOP      │
    │   THOẠI     │                   │    ĐA NGÀNH     │
    └─────────────┘                   └────────┬────────┘
                                              │
                               ┌──────────────┼──────────────┐
                               ▼              ▼              ▼
                        ┌───────────┐ ┌───────────┐ ┌───────────┐
                        │ 📱 ĐIỆN TỬ│ │🍎THỰC PHẨM│ │👕THỜI TRANG│
                        └───────────┘ └───────────┘ └───────────┘
```

### Nguyên tắc vàng
- ✅ **BACKWARD COMPATIBLE**: Shops hiện tại KHÔNG bị ảnh hưởng
- ✅ **MODULAR**: Tính năng theo ngành, bật/tắt linh hoạt
- ✅ **EXTENSIBLE**: Dễ thêm ngành mới trong tương lai
- ✅ **DATA SAFE**: Migration không mất dữ liệu cũ

### Module hóa theo ngành

```
┌─────────────────────────────────────────────────────────────┐
│                        SHOP CORE                             │
│  (Auth, Multi-shop, Payment, Reporting, Sync, HR)           │
│  ✓ Không thay đổi logic tài chính                           │
│  ✓ PaymentIntentService giữ nguyên                          │
└─────────────────────────────────────────────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  📱 ĐIỆN TỬ     │   │  🍎 THỰC PHẨM   │   │  👕 THỜI TRANG  │
│ IMEI, Sửa chữa │   │ HSD, Quản lý lô │   │ Size/màu, SKU  │
│ Bảo hành       │   │ Đơn vị (kg)     │   │ Tồn kho matrix │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

### Bảng so sánh tính năng

| Tính năng | 📱 Điện tử | 🍎 Thực phẩm | 👕 Thời trang | 📦 Tổng hợp |
|-----------|-----------|-------------|--------------|-------------|
| IMEI/Serial | ✅ | ❌ | ❌ | Tùy chọn |
| Sửa chữa | ✅ | ❌ | ❌ | Tùy chọn |
| Bảo hành | ✅ | ❌ | ❌ | Tùy chọn |
| Hạn sử dụng | ❌ | ✅ | ❌ | Tùy chọn |
| Quản lý lô | ❌ | ✅ | ❌ | Tùy chọn |
| Đơn vị tính | ❌ | ✅ | ❌ | Tùy chọn |
| Size | ❌ | ❌ | ✅ | Tùy chọn |
| Màu sắc | ✅ | ❌ | ✅ | Tùy chọn |
| Biến thể (SKU) | ❌ | ❌ | ✅ | Tùy chọn |

### Danh mục mặc định theo ngành

**📱 Điện tử**: Điện thoại, Máy tính bảng, Laptop, Phụ kiện, Linh kiện

**🍎 Thực phẩm**: Rau củ, Trái cây, Thịt cá, Đồ khô, Đồ hộp, Đồ uống, Đông lạnh

**👕 Thời trang**: Áo, Quần, Váy/Đầm, Giày dép, Túi xách, Phụ kiện

**📦 Tổng hợp**: Tự do tạo danh mục

### Schema Database mới

#### Bảng `shop_settings`
```sql
CREATE TABLE shop_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  businessType TEXT NOT NULL,  -- 'electronics', 'food', 'fashion', 'general'
  enableRepair INTEGER DEFAULT 0,
  enableExpiry INTEGER DEFAULT 0,
  enableVariants INTEGER DEFAULT 0,
  enableSerial INTEGER DEFAULT 0,
  defaultUnit TEXT DEFAULT 'cái',
  expiryWarningDays INTEGER DEFAULT 7,
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

#### Bảng `categories`
```sql
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  name TEXT NOT NULL,
  parentId TEXT,
  icon TEXT,
  color TEXT,
  sortOrder INTEGER DEFAULT 0,
  trackExpiry INTEGER DEFAULT 0,
  trackSerial INTEGER DEFAULT 0,
  hasVariants INTEGER DEFAULT 0,
  hasWarranty INTEGER DEFAULT 0,
  defaultUnit TEXT DEFAULT 'cái',
  customFields TEXT,  -- JSON
  isActive INTEGER DEFAULT 1,
  deleted INTEGER DEFAULT 0,
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

#### Bảng `product_variants`
```sql
CREATE TABLE product_variants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  productId TEXT NOT NULL,
  sku TEXT,
  size TEXT,
  color TEXT,
  cost INTEGER,
  price INTEGER,
  quantity INTEGER DEFAULT 0,
  barcode TEXT,
  isActive INTEGER DEFAULT 1,
  deleted INTEGER DEFAULT 0,
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

### Giai đoạn triển khai

**Phase 1: Core Extension (2-3 tuần)**
- ShopSettings model + service
- Category model + service + UI
- Mở rộng Product với categoryId, customData
- Migrate type → categoryId
- Update db_helper, sync_service, firestore.rules

**Phase 2: Module Thực phẩm (2-3 tuần)**
- expiryDate, batchNumber vào Product
- ExpiryAlertService
- UI "Sắp hết hạn", đơn vị tính động

**Phase 3: Module Thời trang (2-3 tuần)**
- ProductVariant model + service
- UI quản lý variants (size, color)
- Barcode cho từng variant

**Phase 4: Tổng quát hóa (1-2 tuần)**
- Custom fields UI builder
- Onboarding wizard chọn ngành
- Ẩn/hiện module theo businessType

**Phase 5: Testing & QA (1-2 tuần)**

**TOTAL: ~2.5-3 tháng**

### Quy tắc phát triển

#### KHÔNG phá vỡ logic hiện tại
```
❌ KHÔNG SỬA: PaymentIntentService, SalaryCalculationService, Repair flow
✅ CHỈ THÊM MỚI: Models mới, Views mới, Services mới
```

#### Feature Flags
```dart
class FeatureFlags {
  static bool hasRepairModule(String businessType) => businessType == 'electronics';
  static bool hasExpiryTracking(String businessType) => businessType == 'food';
  static bool hasVariants(String businessType) => businessType == 'fashion';
}
```

### Files quan trọng

| File | Sửa? |
|------|------|
| `lib/models/product_model.dart` | ✅ Thêm fields |
| `lib/data/db_helper.dart` | ✅ Thêm tables |
| `lib/services/sync_service.dart` | ✅ Thêm collections |
| `lib/services/payment_intent_service.dart` | ❌ KHÔNG SỬA |
| `lib/services/salary_calculation_service.dart` | ❌ KHÔNG SỬA |
| `firestore.rules` | ✅ Thêm rules |

---

---

# PHẦN F: TRUNG TÂM HƯỚNG DẪN

> Nguồn gốc: `DOCS/HELP_CENTER_GUIDE.md`

---

## F1. Help Center Guide

### Mục tiêu
- Cung cấp tài liệu chính thức cho nhân sự sử dụng app Shopmanager.
- Đảm bảo nội dung luôn đồng bộ giữa dữ liệu nội bộ và giao diện người dùng.
- Chuẩn hóa quy trình thêm/chỉnh sửa các chủ đề hướng dẫn mới.

### Kiến trúc tính năng

**Tệp nguồn dữ liệu:** `lib/data/help_center_repository.dart` chứa danh sách `HelpCategory` và `HelpTopic`.

Mỗi `HelpTopic` bao gồm:
- `id`: định danh duy nhất, dạng `topic_ten_chu_de`
- `categoryId`: trỏ về `HelpCategory.id`
- `title`, `summary`, `steps`: nội dung hiển thị chính
- Metadata: `difficulty`, `estimatedTime`, `prerequisites`, `resources`, `tips`, `audience`, `relatedTopicIds`, `isFeatured`

**Giao diện:** `lib/views/help_center_view.dart` - tìm kiếm, danh mục, chủ đề nổi bật, chi tiết từng bước.

### Quy trình bổ sung nội dung

1. **Xác định danh mục**
2. **Tạo/Chỉnh sửa HelpTopic** với đầy đủ trường bắt buộc
3. **Rà soát ngôn ngữ**: Nội dung hiển thị tiếng Việt, comment code tiếng Anh
4. **Kiểm thử**: `flutter run` hoặc `flutter test`

### Best Practices
- `summary` súc tích 2-3 câu
- `steps` dạng mệnh lệnh, mỗi bước < 120 ký tự
- `difficulty`: Dễ, Trung bình, Nâng cao
- `isFeatured` tối đa 4 chủ đề
- Đảm bảo `relatedTopicIds` trỏ đúng topic đã tồn tại

### Lộ trình
- Kết nối `resources` với URL hoặc viewer
- Đồng bộ nội dung với Firestore
- Bổ sung hình ảnh/video minh họa

---

---

# PHẦN G: HƯỚNG DẪN SỬ DỤNG (USER GUIDE)

---

## G1. Hướng dẫn Tiếng Việt - Phần 1

> Nguồn gốc: `DOCS/hdsd/USER_GUIDE_PART1_VI.md`

### 1. Giới thiệu chung

**QuanLyShop** là phần mềm quản lý toàn diện dành cho các cửa hàng sửa chữa và mua bán điện thoại:
- 📱 Quản lý bán hàng: Tạo hóa đơn, theo dõi doanh thu, quản lý trả góp
- 🔧 Quản lý sửa chữa: Tiếp nhận máy, theo dõi tiến độ, quản lý bảo hành
- 📦 Quản lý kho: Nhập/xuất hàng, kiểm kê, theo dõi tồn kho
- 💰 Quản lý tài chính: Doanh thu, chi phí, công nợ, báo cáo
- 👥 Quản lý nhân sự: Nhân viên, chấm công, tính lương
- 🖨️ In hóa đơn: Hỗ trợ máy in nhiệt Bluetooth/WiFi

**Yêu cầu:** Android 6.0+ | iOS 12.0+ | Web (Chrome, Firefox, Safari)

### 2. Đăng ký & Đăng nhập

**Đăng ký:** Chỉ chủ shop đăng ký → Nhập email, mật khẩu, tên shop, SĐT → Xác nhận email

**Đăng nhập:** Email + Mật khẩu → Nhấn "ĐĂNG NHẬP"

**Quên mật khẩu:** Nhấn "Quên mật khẩu?" → Nhập email → Kiểm tra email đặt lại

### 3. Màn hình chính (Home)

```
┌─────────────────────────────────────┐
│  🔔 Thông báo     🔍 Tìm kiếm      │
├─────────────────────────────────────┤
│     📊 THỐNG KÊ NHANH               │
│     • Doanh thu hôm nay            │
│     • Đơn sửa chưa xong            │
│     • Đơn bán hôm nay              │
├─────────────────────────────────────┤
│     📱 SHORTCUTS                    │
│     • Tạo đơn sửa nhanh            │
│     • Bán hàng nhanh               │
│     • Quét QR                       │
├─────────────────────────────────────┤
│  🏠  🛒  🔧  📦  👥  💰  ⚙️       │
│ Home Bán Sửa Kho HR  TC  Cài      │
└─────────────────────────────────────┘
```

**Đồng bộ:** Xanh = OK | Vàng = Đang sync | Đỏ = Lỗi

### 4. Module Bán hàng

**Tạo đơn bán:**
1. Chọn khách hàng (tìm hoặc tạo mới)
2. Chọn sản phẩm (từ kho / quét QR / nhập IMEI)
3. Xác nhận giá bán, chiết khấu
4. Chọn PTTT: Tiền mặt / Chuyển khoản / Trả góp ngân hàng
5. Nhập bảo hành
6. Xác nhận → In hóa đơn

**Trả góp ngân hàng:** Nhập trả trước + ngân hàng + số tiền vay + kỳ hạn

**In hóa đơn:** Bluetooth/WiFi thermal printer, tùy chỉnh mẫu in tại Cài đặt → Thiết kế hóa đơn

### 5. Module Sửa chữa

**Trạng thái đơn sửa:**
| Trạng thái | Màu | Mô tả |
|------------|-----|-------|
| 🟠 Đang sửa | Cam | Đang sửa |
| 🔵 Chờ linh kiện | Xanh | Chờ LK |
| 🟢 Hoàn thành | Xanh lá | Sửa xong |
| 🔴 Đã trả máy | Đỏ | Đã giao |

**Tiếp nhận máy:** Nhập thông tin khách → Thông tin máy (model, IMEI, tình trạng) → Mô tả lỗi → Phụ kiện kèm theo → Chụp ảnh → Ước tính giá → Tạo phiếu

**Cập nhật tiến độ:** Chuyển trạng thái → Ghi linh kiện → Phân công thợ

**Trả máy:** Kiểm tra trước mặt khách → Thu tiền → Chụp ảnh trả → Nhấn "TRẢ MÁY"

**Bảo hành:** Xem tại "Siêu trung tâm bảo hành" - Xanh > 30 ngày, Cam 10-30 ngày, Đỏ < 10 ngày

### 6. Module Khách hàng

- Tự động tạo khi tạo đơn sửa/bán
- Xem lịch sử sửa chữa + mua hàng
- Chỉ xóa khách KHÔNG có lịch sử giao dịch

---

## G2. Hướng dẫn Tiếng Việt - Phần 2

> Nguồn gốc: `DOCS/hdsd/USER_GUIDE_PART2_VI.md`

### 7. Module Kho hàng

**Loại sản phẩm:** Điện thoại (IMEI, dung lượng) | Phụ kiện | Linh kiện

**Thêm SP:** Chọn loại → Nhập thông tin → Giá vốn/bán → NCC, bảo hành → Chụp ảnh → Lưu

**Nhập nhanh:** Quét QR/barcode liên tiếp → Điều chỉnh → Xác nhận

**Kho tạm:** SP chưa định giá → Badge "TẠM" cam → Nhập giá bán → Chuyển kho chính

**Kiểm kê kho:** Tạo phiên → Nhập số thực tế → So sánh → Điều chỉnh tự động

**Linh kiện:** Kho riêng cho sửa chữa, tự động trừ khi cập nhật đơn sửa

### 8. Module Nhà cung cấp

**Thêm NCC:** Tên, người liên hệ, SĐT, email, địa chỉ

**Tạo đơn nhập:** Chọn NCC → Thêm SP → Thanh toán (trả ngay hoặc công nợ) → Tự động nhập kho

**Thanh toán NCC:** Vào chi tiết NCC → Xem công nợ → Thanh toán → Chọn PTTT

### 9. Module Tài chính

**Doanh thu:** Từ bán hàng + sửa chữa, lọc theo ngày/tuần/tháng

**Chi phí:** Danh mục: Mặt bằng, Nhân sự, Hàng hóa, Thiết bị, Marketing, Khác

**Công nợ:** Nợ khách (phải thu) + Nợ NCC (phải trả), thu/thanh toán từng phần

**Chốt quỹ cuối ngày:**
```
Tiền đầu ngày + Thu trong ngày - Chi trong ngày = Lý thuyết
→ Nhập thực tế → So sánh chênh lệch → Chốt
```

**Báo cáo:** Doanh thu, Lợi nhuận, Công nợ, Trả góp → Xuất Excel/PDF

### 10. Module Nhân sự

**Quản lý NV:** Thêm bằng email + mật khẩu, phân vai trò (Owner/Admin/Staff)

**Phân quyền:** Bật/tắt từng quyền (xem, tạo/sửa, quản lý)

**Chấm công:** Check in/out với ảnh → Quản lý xem thống kê

**Tính lương:** Lương cơ bản + Phụ cấp + Hoa hồng - Khấu trừ (BHXH, BHYT) = Thực lãnh

### 11. Module Cài đặt

- **Thông tin shop**: Tên, địa chỉ, SĐT, logo
- **Máy in**: Bluetooth hoặc WiFi thermal printer
- **Thiết kế hóa đơn**: Header, nội dung, footer, QR
- **Thông báo**: Bật/tắt từng loại
- **Ngôn ngữ**: Tiếng Việt / English
- **Sao lưu/Khôi phục**: Backup lên Firebase Storage

### 12. Tính năng nâng cao

- **Quét QR/Barcode**: Sản phẩm, IMEI, QR thanh toán
- **Mã nhập nhanh**: Tạo QR tùy chỉnh → Quét → Auto fill
- **Chat nội bộ**: Text + hình ảnh + liên kết đơn hàng
- **Tìm kiếm toàn cục**: Khách, đơn sửa, đơn bán, sản phẩm
- **Đối tác sửa chữa**: Quản lý tiệm khác gửi máy sửa

### 13. Xử lý sự cố

| Vấn đề | Giải pháp |
|--------|-----------|
| Không đăng nhập được | Kiểm tra email/mật khẩu, đặt lại mật khẩu, kiểm tra mạng |
| Dữ liệu không đồng bộ | Kiểm tra mạng, sync thủ công, đăng xuất/đăng nhập lại |
| Máy in không hoạt động | Kiểm tra Bluetooth/WiFi, pin, kết nối lại |
| App chạy chậm | Đóng app khác, xóa cache, cập nhật phiên bản mới |
| Mất dữ liệu | Khôi phục từ bản backup gần nhất |

### 14. FAQ

| Câu hỏi | Trả lời |
|---------|---------|
| Thêm nhân viên? | Nhân sự → + Thêm → Nhập thông tin → Tạo tài khoản → Phân quyền |
| Dùng nhiều thiết bị? | Có, đăng nhập cùng tài khoản → tự động đồng bộ |
| Xuất báo cáo? | Tài chính → Báo cáo → Chọn loại → Icon 📤 → Excel/PDF |
| Hoàn tác xóa nhầm? | Hệ thống xóa mềm, liên hệ admin khôi phục trong 30 ngày |
| Không xem được doanh thu? | Cần quyền "Xem doanh thu", liên hệ Chủ shop |
| In hóa đơn từ ĐT? | Kết nối Bluetooth thermal printer → In từ chi tiết đơn |
| Tạo QR sản phẩm? | Chi tiết SP → Icon QR → Lưu/in |

---

## G3. User Guide (English)

> Nguồn gốc: `DOCS/hdsd/USER_GUIDE_EN.md`

### 1. Introduction

**QuanLyShop (Huluca)** is a comprehensive management software for phone repair and sales shops:
- 📱 Sales Management, 🔧 Repair Management, 📦 Inventory Management
- 💰 Finance Management, 👥 HR Management, 🖨️ Invoice Printing

**Requirements:** Android 6.0+ | iOS 12.0+ | Web (latest browsers)

### 2. Registration & Login

Only shop owners register. Staff accounts are created by the owner.

Steps: Open app → "REGISTER" → Fill info → "REGISTER" → Verify email → Login

### 3. Home Dashboard

| Tab | Function |
|-----|----------|
| 🏠 Home | Dashboard, overview |
| 🛒 Sales | Sales management |
| 🔧 Repair | Repair orders |
| 📦 Inventory | Stock management |
| 👥 HR | Staff, attendance |
| 💰 Finance | Revenue, expenses, debts |
| ⚙️ Settings | Shop and system settings |

### 4. Sales Module

Create Sales Order → Select Customer → Add Products (scan/search) → Payment → Confirm → Print

Warranty Types: 1-to-1 exchange | Standard repair | No warranty

Installment: Select "Installment" → Enter down payment → System calculates debt

### 5. Repair Module

| Status | Color |
|--------|-------|
| Waiting/Queued | 🟡 Yellow |
| In Progress | 🔵 Blue |
| Completed | 🟢 Green |
| Delivered | ⚪ Gray |
| Cancelled | 🔴 Red |

Receive Device → Update Status → Add Parts → Complete → Notify Customer → Deliver → Print Warranty

### 6. Inventory Module

Categories: Phones (IMEI tracked) | Accessories | Parts

Pending Stock: Products without price → Orange badge → Set price → Move to main stock

### 7. Finance Module

- Revenue tracking (Sales + Repairs)
- Expense management (categorized)
- Debt management (Customer receivable + Supplier payable)
- Daily cash closing (reconciliation)
- Reports (Daily, Monthly, Product Performance, Staff Performance, Debt Aging)

### 8. HR Module

Role Permissions: Owner (full) > Manager (configurable) > Employee (configurable)

Attendance: Check-in/out with selfie + location

Salary: Monthly/Daily/Hourly base + Commission + Allowances - Deductions

### 9. Settings

- Shop Profile, Printer Setup (58mm/80mm Bluetooth/WiFi thermal)
- Notifications, Data Sync

### 10. Troubleshooting

| Error | Solution |
|-------|----------|
| "Network Error" | Check internet |
| "Permission Denied" | Contact admin |
| "Sync Failed" | Check connection, retry |
| "Invalid Data" | Check required fields |

### Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | Success, Paid, Completed |
| 🟡 Yellow | Pending, Warning |
| 🔵 Blue | In Progress, Info |
| 🟠 Orange | Partial, Staging |
| 🔴 Red | Error, Cancelled, Overdue |

---

---

## � CẬP NHẬT: GỘP TRANG QUẢN LÝ TÀI CHÍNH (v10.0.9 - 02/2026)

### Tổng quan thay đổi

Trang Tài chính trên trang chủ đã được **tinh gọn** đáng kể, gộp nhiều trang rời rạc vào một giao diện duy nhất mà **không mất bất kỳ tính năng nào**.

### Trước vs Sau

| Mục | Trước | Sau |
|-----|-------|-----|
| Số điểm điều hướng | 10 (có 2 bị trùng) | 6 (không trùng) |
| Quick Actions | Chỉ có Chốt quỹ | Chốt quỹ + Thanh toán |
| Báo cáo + Chi phí + Trả góp + Nhật ký | 4 mục riêng biệt | Gộp vào 1 trang "Báo cáo TC" |
| Grid báo cáo | 2x2 + 2x1 + 5 menu item | 1 grid 2x2 gọn gàng |
| View mồ côi | 2 (không ai dùng) | Đã xóa |

### Cách sử dụng mới

#### 1. Tab Tài chính trên Trang chủ (đã gọn hơn)

Khi bấm vào tab **Tài chính** ở thanh điều hướng dưới cùng, bạn sẽ thấy giao diện mới gọn hơn:

```
┌─────────────────────────────────────┐
│ 💰 QUẢN LÝ TÀI CHÍNH              │
├─────────────────────────────────────┤
│ 📊 Tổng quan hôm nay               │
│ ┌──────────┐ ┌──────────┐          │
│ │ THU: xx  │ │ CHI: xx  │          │
│ └──────────┘ └──────────┘          │
│ ┌───── LỢI NHUẬN RÒNG ───────┐    │
│ │         xxx,xxxđ            │    │
│ └─────────────────────────────┘    │
│ ┌───── CÔNG NỢ ──────────────┐    │
│ │         xxx,xxxđ     ▷     │    │
│ └─────────────────────────────┘    │
├─────────────────────────────────────┤
│ ⚡ Thao tác nhanh                   │
│ ┌──────────┐ ┌──────────┐          │
│ │ Chốt quỹ │ │Thanh toán│          │
│ └──────────┘ └──────────┘          │
├─────────────────────────────────────┤
│ 📈 Báo cáo & Phân tích             │
│ ┌──────────┐ ┌──────────┐          │
│ │Tổng quan │ │ Công nợ  │          │
│ │ doanh thu│ │          │          │
│ ├──────────┤ ├──────────┤          │
│ │ Báo cáo  │ │ Bảo hành │          │
│ │ tài chính│ │          │          │
│ └──────────┘ └──────────┘          │
└─────────────────────────────────────┘
```

**4 ô grid:**
- **Tổng quan doanh thu** → Mở trang Revenue (giữ nguyên)
- **Công nợ** → Mở trang Debt (giữ nguyên)
- **Báo cáo tài chính** → ⭐ Mở trang **Financial Hub mới** (gộp 4 view)
- **Bảo hành** → Mở trang Warranty (giữ nguyên)

#### 2. Trang Báo cáo Tài chính (Financial Hub) - MỚI

Khi bấm vào ô **"Báo cáo tài chính"**, bạn sẽ vào trang tổng hợp mới với **4 tab ở trên cùng**:

```
┌─────────────────────────────────────┐
│ ← Quản lý Tài chính                │
├─────────────────────────────────────┤
│ 📊Báo cáo │ 💸Chi phí │ 🏦Trả góp │ 📋Nhật ký │
├─────────────────────────────────────┤
│                                     │
│    (Nội dung thay đổi theo tab)     │
│                                     │
└─────────────────────────────────────┘
```

**Tab 1: Báo cáo** (Financial Report)
- Xem tất cả giao dịch tiền: bán hàng, sửa chữa, chi phí, nhập hàng, thu nợ, trả nợ
- Lọc theo: Tất cả / Thu / Chi
- Bộ lọc nâng cao: theo loại giao dịch, khoảng thời gian, tìm kiếm
- Summary card: Tổng thu - Tổng chi = Lợi nhuận

**Tab 2: Chi phí** (Expense)
- Xem danh sách chi phí shop (cố định, phát sinh, lương, mặt bằng...)
- Thêm chi phí mới bằng nút ➕ ở góc dưới phải
- Lọc theo: Ngày / Tuần / Tháng
- Biểu đồ thống kê chi phí
- Truy cập nhanh trang Nhập kho

**Tab 3: Trả góp** (Bank Installment)
- Thống kê tất cả đơn bán trả góp qua ngân hàng
- Lọc theo ngân hàng, theo thời gian
- Xem tổng tiền, đã nhận, chờ nhận cho từng ngân hàng

**Tab 4: Nhật ký** (Activity Log)
- **Sub-tab Tài chính**: Xem log thu/chi/nợ theo thời gian, có tìm kiếm + bộ lọc
- **Sub-tab Hệ thống**: Xem log hành động của người dùng (thêm/sửa/xóa)

#### 3. Các trang vẫn truy cập riêng được

Tất cả 4 view bên trong Financial Hub vẫn hoạt động bình thường nếu mở riêng lẻ từ nơi khác trong app. Chế độ `embedded: true` chỉ tắt AppBar riêng khi view được nhúng vào Financial Hub.

### Các view đã xóa

| View | Lý do |
|------|-------|
| `transaction_detail_view.dart` | View mồ côi - không có nút nào trong app dẫn tới. Chức năng đã được bao phủ bởi `financial_report_view.dart` |
| `financial_reconciliation_view.dart` | View mồ côi - không có nút nào trong app dẫn tới. Chức năng đối soát đã có trong `cash_closing_view.dart` |

### Lưu ý cho Developer

- Khi thêm view tài chính mới, cân nhắc thêm vào Financial Hub như một tab thay vì tạo trang riêng
- 4 view hỗ trợ `embedded` parameter: set `embedded: true` khi nhúng vào container khác (không có Scaffold)
- `unified_payment_page.dart` và `PaymentIntentService` **KHÔNG ĐƯỢC SỬA** theo quy định dự án

---

## �📞 THÔNG TIN LIÊN HỆ

**Nhà phát triển:** Huluca Tech
- **Email:** itquanghuy85@gmail.com / admin@huluca.com
- **Hotline:** +84964.09.59.79
- **GitHub:** https://github.com/itquanghuy85/quanlyshop

---

*Tài liệu tổng hợp được tạo: 02/2026*
*Phiên bản app: 3.4.0+10*
