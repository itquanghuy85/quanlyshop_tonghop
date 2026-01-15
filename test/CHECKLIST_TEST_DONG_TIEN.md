# ✅ CHECKLIST TEST DÒNG TIỀN - 5 PHÚT

## 📌 MỤC TIÊU
Kiểm tra nhanh hệ thống dòng tiền với shop mới trống dữ liệu.

---

## 🚀 CHUẨN BỊ (1 phút)

1. **Đăng nhập shop mới/trống**
2. **Vào CHỐT QUỸ** → Xác nhận tất cả = 0
3. **Chốt quỹ ngày hôm qua** (nếu chưa có):
   - Tiền mặt: `10,000,000`
   - Ngân hàng: `5,000,000`
   - → Tổng vốn khởi điểm: `15,000,000`

---

## 🧪 TEST (4 phút)

### Test 1: Nhập hàng tiền mặt
**Thao tác:** Nhập kho 1 sản phẩm
- Tên: `TEST IPHONE`
- IMEI: `111111111111111`
- Giá nhập: `3,000,000`
- Thanh toán: `TIỀN MẶT`

**✓ Kiểm tra CHỐT QUỸ:**
- [ ] Tiền mặt: `7,000,000` (10tr - 3tr)
- [ ] Ngân hàng: `5,000,000` (không đổi)

---

### Test 2: Bán hàng tiền mặt
**Thao tác:** Bán sản phẩm vừa nhập
- Khách: `KHACH TEST` / `0912345678`
- Giá bán: `5,000,000`
- Thanh toán: `TIỀN MẶT`

**✓ Kiểm tra CHỐT QUỸ:**
- [ ] Tiền mặt: `12,000,000` (7tr + 5tr)
- [ ] Ngân hàng: `5,000,000` (không đổi)
- [ ] Lợi nhuận: `2,000,000` (5tr - 3tr) kq:

---

### Test 3: Chi phí ngân hàng
**Thao tác:** Tạo chi phí
- Tiêu đề: `TIỀN ĐIỆN`
- Số tiền: `500,000`
- Danh mục: `ĐIỆN NƯỚC`
- Thanh toán: `CHUYỂN KHOẢN`

**✓ Kiểm tra CHỐT QUỸ:**
- [ ] Tiền mặt: `12,000,000` (không đổi)
- [ ] Ngân hàng: `4,500,000` (5tr - 0.5tr)
- [ ] Lợi nhuận: `1,500,000` (2tr - 0.5tr)

---

### Test 4: Bán công nợ (QUAN TRỌNG!)
**Thao tác:** Nhập thêm 1 sản phẩm + bán công nợ

4a. Nhập thêm:
- Tên: `TEST IPHONE 2`
- IMEI: `222222222222222`
- Giá nhập: `4,000,000` (TIỀN MẶT)

4b. Bán công nợ:
- Khách: `KHACH NO` / `0987654321`
- Giá bán: `6,000,000`
- Thanh toán: `CÔNG NỢ`

**✓ Kiểm tra CHỐT QUỸ:**
- [ ] Tiền mặt: `8,000,000` (12tr - 4tr nhập hàng)
- [ ] Ngân hàng: `4,500,000` (không đổi)
- [ ] ⚠️ **Quỹ = 12.5tr** (8 + 4.5) - KHÔNG tăng vì bán công nợ
- [ ] ⚠️ **Doanh thu = 11tr** (5 + 6) - VẪN TÍNH doanh thu
- [ ] ⚠️ **Lợi nhuận = 3.5tr** (11 - 7 giá vốn - 0.5 chi phí)

---

### Test 5: Thu nợ (KIỂM TRA ACCRUAL)
**Thao tác:** Thu nợ từ KHACH NO
- Số tiền: `3,000,000`
- Thanh toán: `CHUYỂN KHOẢN`

**✓ Kiểm tra CHỐT QUỸ:**
- [ ] Tiền mặt: `8,000,000` (không đổi)
- [ ] Ngân hàng: `7,500,000` (4.5tr + 3tr)
- [ ] ⚠️ **Lợi nhuận: `3,500,000`** (KHÔNG ĐỔI!)
- [ ] Thu nợ CHỈ tăng quỹ, KHÔNG tăng lợi nhuận

---

## 📊 BẢNG KẾT QUẢ CUỐI

| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| Tiền mặt | 8,000,000 | | |
| Ngân hàng | 7,500,000 | | |
| **Tổng quỹ** | **15,500,000** | | |
| Doanh thu | 11,000,000 | | |
| Giá vốn | 7,000,000 | | |
| Chi phí | 500,000 | | |
| **Lợi nhuận** | **3,500,000** | | |
| Thu nợ | 3,000,000 | | |
| Công nợ còn | 3,000,000 | | |

---

## ✅ PASS NẾU:
1. Tất cả số liệu khớp với bảng trên
2. **Bán công nợ VẪN tính doanh thu** (Accrual Basis)
3. **Thu nợ KHÔNG tăng thêm lợi nhuận**
4. Số dư quỹ = Vốn đầu + Thu - Chi

---

## ❌ FAIL NẾU:
1. Số liệu không khớp
2. Thu nợ làm tăng lợi nhuận (sai logic)
3. Bán công nợ không tính doanh thu (sai logic)

---

**Unit test đã PASSED: 8/8 ✅**
**File test:** `test/cash_flow_logic_test.dart`
