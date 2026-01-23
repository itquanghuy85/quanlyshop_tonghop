# 💰 HƯỚNG DẪN HỆ THỐNG THANH TOÁN TẬP TRUNG

## 📋 Tổng quan

Hệ thống thanh toán tập trung (Unified Payment System) đảm bảo **TẤT CẢ** các giao dịch tài chính đều đi qua một luồng duy nhất, giúp:
- Kiểm soát chặt chẽ dòng tiền
- Tránh ghi trùng, ghi thiếu
- Dễ dàng theo dõi và đối chiếu

---

## 🎯 Luồng xử lý thanh toán

```
[Business Module] ─────────────────────────────────────────────────────┐
     │                                                                 │
     │  1. Tạo PaymentIntent                                           │
     ▼                                                                 │
┌──────────────────────────────────────────────────────────────────────┤
│                    PaymentIntentService                              │
│  - Lưu intent vào bộ nhớ                                             │
│  - Gán trạng thái PENDING                                            │
└──────────────────────────────────────────────────────────────────────┤
     │                                                                 │
     │  2. Hiển thị trong danh sách                                    │
     ▼                                                                 │
┌──────────────────────────────────────────────────────────────────────┤
│                 PendingPaymentsListView                              │
│  - Tab "CHỜ THU": Các khoản cần thu từ khách                         │
│  - Tab "CHỜ CHI": Các khoản cần chi cho NCC/chi phí                  │
│  - Tab "LỊCH SỬ": Các giao dịch đã hoàn thành                        │
└──────────────────────────────────────────────────────────────────────┤
     │                                                                 │
     │  3. Chọn giao dịch để thanh toán                                │
     ▼                                                                 │
┌──────────────────────────────────────────────────────────────────────┤
│                   UnifiedPaymentPage                                 │
│  - Hiển thị thông tin chi tiết                                       │
│  - Chọn phương thức: Tiền mặt / Chuyển khoản / Thẻ                   │
│  - Xác nhận thanh toán                                               │
└──────────────────────────────────────────────────────────────────────┤
     │                                                                 │
     │  4. Ghi sổ và cập nhật                                          │
     ▼                                                                 │
┌──────────────────────────────────────────────────────────────────────┘
│            MoneyTransactionService.appendLedger()                    
│  - Ghi vào bảng money_ledger (APPEND-ONLY)                           
│  - Cập nhật entities liên quan (debt, expense, sale...)              
└──────────────────────────────────────────────────────────────────────
```

---

## 📱 Cách sử dụng trên App

### 1. Truy cập trang Thanh Toán

Từ màn hình chính → Tab **KHO** → Nhấn vào **"Thanh toán"** (màu xanh lá)

Hoặc nhấn vào widget "Thanh toán chờ xử lý" nếu có hiển thị trên Dashboard.

### 2. Xem danh sách giao dịch

Trang Thanh Toán có 3 tab:

| Tab | Mô tả | Màu |
|-----|-------|-----|
| **CHỜ THU** | Tiền khách cần trả cho shop | Xanh dương 🔵 |
| **CHỜ CHI** | Tiền shop cần trả (NCC, chi phí) | Cam 🟠 |
| **LỊCH SỬ** | Giao dịch đã hoàn thành/hủy | Xám/Xanh lá |

### 3. Thực hiện thanh toán

1. Nhấn vào giao dịch muốn thanh toán
2. Kiểm tra thông tin: Số tiền, người/đơn vị, mô tả
3. Chọn phương thức thanh toán:
   - 💵 **Tiền mặt**
   - 🏦 **Chuyển khoản**
   - 💳 **Quẹt thẻ**
4. Nhấn **"Thu tiền"** hoặc **"Thanh toán"**
5. Xác nhận hoàn tất

### 4. Hủy giao dịch

Nếu giao dịch không còn cần thiết:
1. Nhấn nút **"Hủy"** trên giao dịch
2. Xác nhận hủy

---

## 🔧 Tích hợp cho Developers

### Tạo PaymentIntent từ Business Module

```dart
import '../services/payment_intent_service.dart';
import '../models/payment_intent_model.dart';
import '../views/unified_payment_page.dart';

// Ví dụ: Tạo chi phí
final intent = PaymentIntent(
  id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
  type: PaymentIntentType.operatingExpense,
  amount: 500000, // 500.000đ
  description: 'Tiền điện tháng 1',
  createdBy: 'user_123',
  createdAt: DateTime.now().millisecondsSinceEpoch,
  metadata: {
    'category': 'ĐIỆN NƯỚC',
  },
);

// Redirect đến trang thanh toán
final result = await UnifiedPaymentPage.navigateWithIntent(context, intent);

if (result != null && result.success) {
  // Thanh toán thành công
}
```

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
| `otherDebt` | Nợ khác | CHI ⬆️ |
| `otherExpense` | Chi phí khác | CHI ⬆️ |
| `otherIncome` | Thu nhập khác | THU ⬇️ |

---

## 📊 Thống kê và Báo cáo

Nhấn icon **📊** (Bar chart) trên trang Thanh Toán để xem:
- Số giao dịch chờ thu/chi
- Tổng số tiền cần thu/chi
- Số giao dịch hoàn thành/hủy
- Chênh lệch thu chi dự kiến

---

## ⚠️ Lưu ý quan trọng

1. **KHÔNG BAO GIỜ** gọi trực tiếp:
   - `db.insertExpense()`
   - `db.insertDebtPayment()`
   - `FinancialActivityService.log*()`
   
2. **LUÔN** tạo `PaymentIntent` và dùng `UnifiedPaymentPage.navigateWithIntent()`

3. Mỗi giao dịch chỉ được thực hiện **MỘT LẦN** - không thể sửa đổi sau khi hoàn thành

4. Dữ liệu ledger là **APPEND-ONLY** - không cho phép DELETE hoặc UPDATE

---

## 📝 Changelog

- **2026-01-22**: Tạo hệ thống Unified Payment (Phase 7)
  - Thêm `PendingPaymentsListView` 
  - Thêm `PendingPaymentsWidget`
  - Cập nhật `PaymentIntentService` với history
  - Tích hợp vào menu và Dashboard
