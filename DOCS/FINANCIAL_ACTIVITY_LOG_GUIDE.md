# HƯỚNG DẪN TRANG NHẬT KÝ TÀI CHÍNH

## Tổng quan

Trang **Nhật ký tài chính** (`FinancialActivityLogView`) là một công cụ theo dõi mọi hoạt động tài chính trong shop. Trang này chỉ hiển thị dữ liệu (READ-ONLY), không cho phép sửa/xóa, phục vụ mục đích kiểm soát và audit.

## Vị trí trong App

📱 **Home → Tab Tài chính → Nhật ký tài chính**

## Các loại hoạt động được ghi nhận

| Icon | Loại | Mô tả |
|------|------|-------|
| 🛒 | SALE | Bán hàng (tiền mặt, chuyển khoản, công nợ, trả góp) |
| 📦 | PURCHASE | Nhập hàng từ NCC |
| 💸 | EXPENSE | Chi phí |
| 💰 | DEBT_COLLECT | Thu nợ từ khách hàng |
| 💳 | DEBT_PAY | Thanh toán NCC |
| 🏦 | SETTLEMENT | Tất toán từ ngân hàng (trả góp) |
| 🔧 | REPAIR | Thu tiền sửa chữa |

## Hướng tiền (Direction)

- **IN** (📥 Thu vào): Tiền vào quỹ shop
- **OUT** (📤 Chi ra): Tiền ra khỏi quỹ shop
- **DEBT** (📋 Công nợ): Chưa ảnh hưởng quỹ ngay (bán công nợ, nhập công nợ)

## Bộ lọc

1. **Khoảng thời gian**: Chọn từ ngày → đến ngày
2. **Loại hoạt động**: Tất cả, Bán hàng, Nhập hàng, Chi phí, Thu nợ, Trả NCC, Tất toán
3. **Hướng tiền**: Tất cả, Thu vào, Chi ra, Công nợ
4. **Tìm kiếm**: Theo tên khách, SĐT, mô tả

## Điểm tích hợp tự động

Nhật ký được ghi tự động khi:

| Hành động | File | Dòng code |
|-----------|------|-----------|
| Bán hàng | `create_sale_view.dart` | Sau `db.upsertSale()` |
| Chi phí | `expense_view.dart` | Sau `db.insertExpense()` |
| Thu nợ KH | `debt_view.dart` | Sau `db.insertDebtPayment()` |
| Tất toán NH | `sale_detail_view.dart` | Sau cập nhật settlement |
| Trả NCC | `supplier_payment_service.dart` | Sau `addSupplierPayment()` |
| Nhập hàng | `stock_in_view.dart` | Sau `insertSupplierImportHistory()` |

## Database

**Table**: `financial_activity_log`
**DB Version**: 61

```sql
CREATE TABLE financial_activity_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  activityType TEXT NOT NULL,       -- SALE, PURCHASE, EXPENSE...
  amount INTEGER NOT NULL,          -- Số tiền
  direction TEXT NOT NULL,          -- IN, OUT, DEBT
  paymentMethod TEXT,               -- TIỀN MẶT, CHUYỂN KHOẢN...
  referenceType TEXT,               -- sale, expense, debt_payment...
  referenceId TEXT,                 -- firestoreId của giao dịch gốc
  title TEXT NOT NULL,              -- Tiêu đề ngắn
  description TEXT,                 -- Mô tả chi tiết
  customerName TEXT,
  phone TEXT,
  productInfo TEXT,
  balanceAfterCash INTEGER,         -- Số dư quỹ sau GD (optional)
  balanceAfterBank INTEGER,         -- Số dư NH sau GD (optional)
  createdAt INTEGER NOT NULL,
  createdBy TEXT,
  shopId TEXT,
  isSynced INTEGER DEFAULT 0,
  extraData TEXT                    -- JSON cho data bổ sung
);
```

## API Service

**File**: `lib/services/financial_activity_service.dart`

```dart
// Ghi log bán hàng
await FinancialActivityService.logSale(
  firestoreId: sale.firestoreId,
  totalPrice: 10000000,
  paymentMethod: 'TIỀN MẶT',
  customerName: 'NGUYEN VAN A',
  phone: '0901234567',
  productNames: 'iPhone 13',
  sellerName: 'NV1',
);

// Ghi log chi phí
await FinancialActivityService.logExpense(
  firestoreId: 'exp_123',
  amount: 500000,
  paymentMethod: 'TIỀN MẶT',
  title: 'Điện nước',
  category: 'Vận hành',
);

// Ghi log thu nợ
await FinancialActivityService.logDebtCollection(
  firestoreId: 'pay_123',
  amount: 5000000,
  paymentMethod: 'CHUYỂN KHOẢN',
  customerName: 'TRAN VAN B',
  phone: '0912345678',
);

// Ghi log tất toán NH
await FinancialActivityService.logSettlement(
  saleFirestoreId: 'sale_xxx',
  amount: 15000000,
  bankName: 'Home Credit',
  customerName: 'LE THI C',
  productNames: 'Samsung S24',
  settlementFee: 200000,
);

// Ghi log thanh toán NCC
await FinancialActivityService.logSupplierPayment(
  firestoreId: 'sup_pay_123',
  amount: 20000000,
  paymentMethod: 'CHUYỂN KHOẢN',
  supplierName: 'NCC ABC',
);

// Ghi log nhập hàng
await FinancialActivityService.logPurchase(
  firestoreId: 'purchase_123',
  amount: 8000000,
  paymentMethod: 'CÔNG NỢ',
  productName: 'iPhone 14',
  supplierName: 'NCC XYZ',
  quantity: 1,
);
```

## Lưu ý quan trọng

1. **Chỉ xem, không sửa**: Trang này chỉ để kiểm tra, không cho phép thay đổi dữ liệu
2. **Ghi tự động**: Không cần ghi thủ công, các điểm quan trọng đã được tích hợp
3. **Không ảnh hưởng logic cũ**: Feature này chỉ bổ sung, không thay đổi logic tài chính hiện có
4. **Dọn dẹp tự động** (optional): Có thể gọi `FinancialActivityService.cleanOldLogs(365)` để xóa log cũ hơn 1 năm

## Test nhanh

1. Mở app → Tab Tài chính → Nhật ký tài chính
2. Kiểm tra trang hiển thị đúng (nếu chưa có data sẽ hiện "Chưa có hoạt động")
3. Thực hiện 1 giao dịch bán hàng
4. Quay lại trang Nhật ký → Kiểm tra có record mới
5. Thử bộ lọc theo loại, theo ngày
6. Tap vào record để xem chi tiết
