# Backlog Cải Tiến - Shop Management App

> Cập nhật: 2026-01-09
> **Status: ✅ TẤT CẢ ĐÃ TRIỂN KHAI**

---

## ✅ HOÀN THÀNH

### BUG-001: Race condition khi thanh toán công nợ đồng thời ✅

**Vấn đề:** Hai user thanh toán cùng lúc có thể gây sai số dư.

**Giải pháp đã triển khai:**
- Thêm `executeDebtPaymentTransaction()` trong `FirestoreService` sử dụng Firestore `runTransaction()`
- Transaction đảm bảo atomic: đọc debt → validate → update paidAmount → tạo payment record
- `debt_view.dart` sử dụng transaction khi có firestoreId, fallback offline-first khi chưa sync

**Files đã sửa:**
- `lib/services/firestore_service.dart` - Thêm method `executeDebtPaymentTransaction`
- `lib/views/debt_view.dart` - Update `_payDebt` để sử dụng transaction

---

### BUG-003: Double-sync sale/debt khi tạo đơn trả góp ✅

**Vấn đề:** Đã có sẵn - `executeSaleTransaction()` trong `FirestoreService` đã xử lý atomic.

**Giải pháp:**
- Code đã có `WriteBatch` pattern trong transaction
- Sale và debt được tạo trong cùng 1 Firestore transaction

**Files liên quan:**
- `lib/services/firestore_service.dart` - `executeSaleTransaction()`
- `lib/views/create_sale_view.dart` - Sử dụng transaction

---

### BUG-006: Notify chốt quỹ real-time cho các thiết bị khác ✅

**Vấn đề:** Khi admin chốt quỹ, các thiết bị khác không biết.

**Giải pháp đã triển khai:**
- Tạo `CashClosingNotifier` service để listen Firestore `cash_closings` collection
- Auto sync trạng thái chốt quỹ vào local DB
- Hiển thị snackbar notification khi quỹ bị chốt/mở khóa
- Emit event `cash_closing_changed` qua EventBus

**Files đã tạo/sửa:**
- `lib/services/cash_closing_notifier.dart` - **MỚI** - Realtime listener service
- `lib/main.dart` - Khởi tạo `CashClosingNotifier.instance.init()` sau sync

---

### IMPROVE-001: Validate repair status transition ✅

**Vấn đề:** Có thể chuyển status repair tùy ý.

**Giải pháp đã triển khai:**
- Tạo `RepairStatusValidator` class với state machine
- Define allowed transitions:
  - PENDING → REPAIRING, COMPLETED
  - REPAIRING → COMPLETED, PENDING
  - COMPLETED → DELIVERED, REPAIRING
  - DELIVERED → (terminal state)
- `repair_detail_view.dart` validate trước khi update

**Files đã tạo/sửa:**
- `lib/utils/repair_status_validator.dart` - **MỚI** - State machine class
- `lib/views/repair_detail_view.dart` - Sử dụng validator trong `_updateStatus()`

---

### IMPROVE-002: Auto-close debt khi remain = 0 ✅

**Vấn đề:** Đã có sẵn trong code.

**Giải pháp:**
- `DBHelper.updateDebtPaid()` đã có logic:
  ```sql
  status = CASE WHEN (paidAmount + ?) >= totalAmount THEN "paid" ELSE "unpaid" END
  ```
- Khi `paidAmount >= totalAmount`, status tự động chuyển thành 'paid'

**Files liên quan:**
- `lib/data/db_helper.dart` - `updateDebtPaid()` method

---

## 📋 Tổng kết triển khai

| ID | Status | Files Changed |
|----|--------|---------------|
| BUG-001 | ✅ Done | firestore_service.dart, debt_view.dart |
| BUG-003 | ✅ Already exists | firestore_service.dart, create_sale_view.dart |
| BUG-006 | ✅ Done | cash_closing_notifier.dart (new), main.dart |
| IMPROVE-001 | ✅ Done | repair_status_validator.dart (new), repair_detail_view.dart |
| IMPROVE-002 | ✅ Already exists | db_helper.dart |

---

*Maintained by: Development Team*
*Last Updated: 2026-01-09*
