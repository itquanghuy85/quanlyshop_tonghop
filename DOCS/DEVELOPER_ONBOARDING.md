# Hướng Dẫn Onboarding Cho Developer Mới

> **Mục đích**: Giúp developer mới hiểu cặn kẽ cấu trúc, nguyên tắc và flow tài chính của app.

---

## 📋 Mục Lục

1. [Tổng Quan Dự Án](#1-tổng-quan-dự-án)
2. [Cấu Trúc Thư Mục](#2-cấu-trúc-thư-mục)
3. [Kiến Trúc & Nguyên Tắc](#3-kiến-trúc--nguyên-tắc)
4. [Flow Tài Chính (QUAN TRỌNG)](#4-flow-tài-chính-quan-trọng)
5. [Multi-Shop Architecture](#5-multi-shop-architecture)
6. [Security Rules](#6-security-rules)
7. [Checklist Trước Khi Code](#7-checklist-trước-khi-code)

---

## 1. Tổng Quan Dự Án

### Công nghệ
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Auth, Firestore, Storage, Cloud Functions)
- **Local DB**: SQLite (sqflite) - offline-first với real-time sync
- **State**: Không dùng state management phức tạp, dùng StatefulWidget + EventBus

### Chức năng chính
- Bán hàng (điện thoại, phụ kiện)
- Sửa chữa (nhận máy, bàn giao, thu tiền)
- Nhập kho từ NCC (nhà cung cấp)
- Quản lý công nợ (khách hàng nợ shop, shop nợ NCC)
- Chốt quỹ hàng ngày
- Báo cáo tài chính
- Multi-shop (1 owner nhiều cửa hàng)

---

## 2. Cấu Trúc Thư Mục

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

---

## 3. Kiến Trúc & Nguyên Tắc

### 3.1 Service-First Pattern
```
❌ KHÔNG: Widget → Firestore/SQLite trực tiếp
✅ ĐÚNG:  Widget → Service → DBHelper/Firestore
```

### 3.2 Offline-First với Real-Time Sync
```
1. User tạo data → Lưu SQLite (isSynced=0)
2. SyncOrchestrator → Queue sync lên Firestore
3. SyncService lắng nghe Firestore → Cập nhật SQLite
```

### 3.3 Soft Delete
```dart
// KHÔNG xóa thật, chỉ đánh dấu deleted=true
await db.update('repairs', {'deleted': 1}, where: 'id = ?');
```

### 3.4 EventBus Pattern
```dart
// Emit event khi data thay đổi
EventBus().emit('repairs_changed');

// Listen trong view
EventBus().on('repairs_changed', (_) => _loadData());
```

### 3.5 Multi-Tenant Isolation
```dart
// MỌI query PHẢI filter theo shopId
final shopId = UserService.getShopIdSync();
db.query('repairs', where: 'shopId = ?', whereArgs: [shopId]);
```

---

## 4. Flow Tài Chính (QUAN TRỌNG)

### ⚠️ NGUYÊN TẮC VÀNG

> **MỌI giao dịch tiền PHẢI đi qua PaymentIntentService**

### 4.1 PaymentIntent Flow

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

### 4.2 PaymentIntent Types

| Type | Mô tả | Direction |
|------|-------|-----------|
| `salePayment` | Thu tiền bán hàng | IN |
| `repairService` | Thu tiền sửa chữa | IN |
| `customerDebtCollection` | Thu nợ khách hàng | IN |
| `supplierDebt` | Trả nợ NCC | OUT |
| `operatingExpense` | Chi phí hoạt động | OUT |
| `salaryPayment` | Trả lương | OUT |

### 4.3 Accrual vs Cash Basis

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

### 4.4 Tránh Double-Counting

```
❌ SAI: Tính "giá vốn hàng bán" + "trả nợ NCC" = tính 2 lần

✅ ĐÚNG:
- Bán hàng: Doanh thu - Giá vốn = Lợi nhuận gộp
- Nhập hàng CÔNG NỢ: Chỉ ghi debt, KHÔNG ghi expense
- Trả nợ NCC: Ghi expense (chi phí thực tế ra quỹ)
```

### 4.5 Financial Activity Log

```dart
// GHI NHẬT KÝ vào FinancialActivityService
await FinancialActivityService.logSale(...);
await FinancialActivityService.logPurchase(...);
await FinancialActivityService.logSupplierPayment(...);
```

---

## 5. Multi-Shop Architecture

### 5.1 Cấu trúc

```
User (uid: abc123)
  └── ownerOf: [shopId1, shopId2]  // Trong shops collection

Shop (id: shopId1)
  └── ownerUid: abc123
  └── staff: [{uid: xyz, role: employee}, ...]
```

### 5.2 Chuyển Shop

```dart
// CurrentShopService.switchShop():
1. Validate ownership
2. Cancel sync subscriptions
3. Clear local SQLite
4. Update SharedPreferences
5. Restart sync for new shop
6. Emit EventBus.shopChanged
```

### 5.3 Firestore Rules

```javascript
// Check owner từ shops collection
function isShopOwner(shopId) {
  return get(/shops/$(shopId)).data.ownerUid == uid();
}

function belongsTo(shopId) {
  return isSuperAdmin() || 
         myShopId() == shopId || 
         isShopOwner(shopId);  // Multi-shop support
}
```

---

## 6. Security Rules

### 6.1 Custom Claims (set by Cloud Functions)

```javascript
{
  isSuperAdmin: boolean,  // true cho admin@huluca.com
  shopId: string,         // Shop hiện tại của user
  role: 'owner' | 'manager' | 'employee' | 'technician'
}
```

### 6.2 Role Hierarchy

```
superAdmin > owner > manager > employee/technician
```

### 6.3 File Quan Trọng

- `firestore.rules` - Firestore security rules
- `storage.rules` - Storage security rules
- `functions/index.js` - Cloud Functions

---

## 7. Checklist Trước Khi Code

### Khi thêm tính năng mới:

- [ ] Có filter theo `shopId` chưa?
- [ ] Có đi qua Service layer chưa?
- [ ] Nếu liên quan tiền → dùng `PaymentIntentService`?
- [ ] Có emit EventBus sau khi thay đổi data?
- [ ] Có log vào `FinancialActivityService` nếu cần?
- [ ] UI text bằng tiếng Việt, code/comments bằng tiếng Anh?

### Khi sửa financial logic:

- [ ] Đọc kỹ `PAYMENT_FLOW_AUDIT_REPORT.md`
- [ ] Đọc kỹ `UNIFIED_PAYMENT_GUIDE.md`
- [ ] Kiểm tra không double-counting
- [ ] Test với cả TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ
- [ ] Kiểm tra `financial_report_view.dart` và `home_view.dart`

### Khi thêm Firestore collection mới:

- [ ] Thêm rules vào `firestore.rules`
- [ ] Thêm vào `SyncService` nếu cần sync
- [ ] Thêm table vào `db_helper.dart`

---

## 📚 Tài Liệu Liên Quan

| File | Mô tả |
|------|-------|
| `DOCS/PROJECT_STRUCTURE_VI.md` | Cấu trúc chi tiết |
| `DOCS/UNIFIED_PAYMENT_GUIDE.md` | Hướng dẫn PaymentIntent |
| `DOCS/PAYMENT_FLOW_AUDIT_REPORT.md` | Audit flow tài chính |
| `DOCS/MULTI_SHOP_GUIDE.md` | Hướng dẫn multi-shop |
| `DOCS/HELP_CENTER_GUIDE.md` | Hướng dẫn sử dụng app |
| `.github/copilot-instructions.md` | AI agent instructions |

---

## 🆘 Liên Hệ Hỗ Trợ

- **Email hỗ trợ**: admin@huluca.com
- **GitHub**: https://github.com/itquanghuy85/quanlyshop

---

*Cập nhật lần cuối: 2026-02-06*
