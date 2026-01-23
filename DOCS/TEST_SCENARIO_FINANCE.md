# KỊCH BẢN TEST TOÀN BỘ HỆ THỐNG TÀI CHÍNH
**Ngày test:** ___/___/2026  
**Người test:** _______________

---

## 🔰 BƯỚC 0: CHUẨN BỊ - TẠO SHOP MỚI

### Thao tác:
1. Đăng xuất khỏi shop hiện tại
2. Tạo tài khoản shop mới hoàn toàn
3. Đăng nhập vào shop mới

### ✅ Kiểm tra số liệu ban đầu (phải = 0):
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Tab Tài chính | Tổng quan doanh thu | 0đ | | |
| Tab Tài chính | Thanh toán chờ xử lý | Trống (0 item) | | |
| Chốt quỹ | Tiền mặt | 0đ | | |
| Chốt quỹ | Ngân hàng | 0đ | | |
| Quản lý công nợ | Tất cả tab | Trống | | |
| Nhật ký tài chính | Tất cả tab | Trống | | |

**⚠️ Nếu "Thanh toán chờ xử lý" có dữ liệu cũ → BÁO LỖI DATA ISOLATION**

---

## 📝 BƯỚC 1: TẠO ĐỐI TÁC & NHÀ CUNG CẤP

### 1.1 Tạo Nhà cung cấp
**Vào:** Quản lý đối tác → Nhà cung cấp → + Thêm mới

| Trường | Giá trị nhập |
|--------|--------------|
| Tên NCC | `NCC Linh Kiện ABC` |
| SĐT | `0912345678` |
| Địa chỉ | `123 Nguyễn Trãi, Q1` |

**Bấm Lưu** → Ghi nhận: ✓ Tạo thành công / ✗ Lỗi: _______

### 1.2 Tạo Đối tác sửa chữa
**Vào:** Quản lý đối tác → Đối tác sửa chữa → + Thêm mới

| Trường | Giá trị nhập |
|--------|--------------|
| Tên đối tác | `Đối Tác Sửa Main XYZ` |
| SĐT | `0909888777` |
| Chuyên môn | `Sửa main, IC` |

**Bấm Lưu** → Ghi nhận: ✓ Tạo thành công / ✗ Lỗi: _______

---

## 📱 BƯỚC 2: NHẬP KHO PHỤ TÙNG (CÔNG NỢ NCC)

### Thao tác:
**Vào:** Quản lý kho → Phụ tùng → + Nhập mới (hoặc Nhập kho mới → Phụ kiện)

| Trường | Giá trị nhập |
|--------|--------------|
| Tên sản phẩm | `Pin iPhone 12` |
| Số lượng | `5` |
| Giá nhập/cái | `200,000đ` |
| **Tổng tiền nhập** | **`1,000,000đ`** |
| Nhà cung cấp | `NCC Linh Kiện ABC` |
| Phương thức TT | **CÔNG NỢ** |

**Bấm Xác nhận nhập kho**

### ✅ Kiểm tra sau bước 2:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Kho phụ tùng | Pin iPhone 12 | 5 cái | | |
| Quản lý công nợ → Nợ NCC | NCC Linh Kiện ABC | **1,000,000đ** | | |
| Thanh toán chờ xử lý | Chờ chi | **1,000,000đ** | | |
| Chốt quỹ | Chi tiền mặt | **0đ** (chưa trả) | | |
| Chốt quỹ | Chi ngân hàng | **0đ** (chưa trả) | | |
| Nhật ký tài chính → Nhập hàng | Ghi nhận | 1 giao dịch 1,000,000đ | | |

---

## 💰 BƯỚC 3: THANH TOÁN CÔNG NỢ NCC (1 PHẦN - TIỀN MẶT)

### Thao tác:
**Vào:** Quản lý công nợ → Tab "Shop nợ NCC" → Chọn `NCC Linh Kiện ABC`

| Trường | Giá trị |
|--------|---------|
| Tổng nợ hiện tại | 1,000,000đ |
| Số tiền thanh toán | `500,000đ` |
| Phương thức | **TIỀN MẶT** |

**Bấm Thanh toán**

### ✅ Kiểm tra sau bước 3:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Quản lý công nợ → Nợ NCC | NCC Linh Kiện ABC | **500,000đ** (còn lại) | | |
| Chốt quỹ | Chi tiền mặt | **-500,000đ** | | |
| Chốt quỹ | Chi ngân hàng | **0đ** | | |
| Nhật ký tài chính | Thanh toán NCC | **-500,000đ** (TM) | | |

---

## 💳 BƯỚC 4: THANH TOÁN CÔNG NỢ NCC (PHẦN CÒN LẠI - CHUYỂN KHOẢN)

### Thao tác:
**Vào:** Quản lý công nợ → Tab "Shop nợ NCC" → Chọn `NCC Linh Kiện ABC`

| Trường | Giá trị |
|--------|---------|
| Tổng nợ hiện tại | 500,000đ |
| Số tiền thanh toán | `500,000đ` |
| Phương thức | **CHUYỂN KHOẢN** |

**Bấm Thanh toán**

### ✅ Kiểm tra sau bước 4:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Quản lý công nợ → Nợ NCC | NCC Linh Kiện ABC | **0đ** (hết nợ) | | |
| Chốt quỹ | Chi tiền mặt | **-500,000đ** | | |
| Chốt quỹ | Chi ngân hàng | **-500,000đ** | | |
| Chốt quỹ | Tổng chi | **-1,000,000đ** | | |
| Nhật ký tài chính | Thanh toán NCC | 2 giao dịch (500k TM + 500k CK) | | |

---

## 🔧 BƯỚC 5: TẠO ĐƠN SỬA CHỮA

### Thao tác:
**Vào:** Tab Sửa chữa → + Thêm đơn sửa mới

| Trường | Giá trị nhập |
|--------|--------------|
| Tên khách | `Nguyễn Văn Test` |
| SĐT | `0901234567` |
| Model máy | `iPhone 12 Pro Max` |
| Màu | `Xanh Pacific` |
| IMEI | `123456789012345` |
| Lỗi | `Hỏng màn hình, không nhận sạc` |
| Giá dự kiến | `3,000,000đ` |

**Bấm Lưu**

### ✅ Kiểm tra sau bước 5:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Danh sách đơn sửa | Đơn mới | Hiển thị, trạng thái "Chờ xử lý" | | |
| Chốt quỹ | Thu | **0đ** (chưa giao) | | |
| Doanh thu | Sửa chữa | **0đ** (chưa hoàn thành) | | |

---

## 🛠️ BƯỚC 6: THÊM DỊCH VỤ NỘI BỘ (SỬ DỤNG PHỤ TÙNG TRONG KHO)

### Thao tác:
**Vào:** Chi tiết đơn sửa → + THÊM DỊCH VỤ → Dịch vụ nội bộ

| Trường | Giá trị nhập |
|--------|--------------|
| Tên dịch vụ | `Thay màn hình zin` |
| Giá thu khách | `2,000,000đ` |
| Giá vốn (linh kiện) | `1,200,000đ` |

**Bấm Lưu**

### ✅ Kiểm tra sau bước 6:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Chi tiết đơn sửa | Dịch vụ | Thay màn hình - 2,000,000đ | | |
| Chi tiết đơn sửa | Tổng giá | **2,000,000đ** | | |
| Chi tiết đơn sửa | Giá vốn | **1,200,000đ** | | |

---

## 🤝 BƯỚC 7: THÊM DỊCH VỤ TỪ ĐỐI TÁC (CÔNG NỢ)

### Thao tác:
**Vào:** Chi tiết đơn sửa → + THÊM DỊCH VỤ → Dịch vụ từ đối tác

| Trường | Giá trị nhập |
|--------|--------------|
| Đối tác | `Đối Tác Sửa Main XYZ` |
| Tên dịch vụ | `Sửa IC sạc` |
| Giá thu khách | `800,000đ` |
| Giá trả đối tác | `500,000đ` |
| Phương thức TT đối tác | **CÔNG NỢ** |

**Bấm Lưu**

### ✅ Kiểm tra sau bước 7:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Chi tiết đơn sửa | Tổng giá | **2,800,000đ** (2tr + 800k) | | |
| Chi tiết đơn sửa | Giá vốn | **1,700,000đ** (1.2tr + 500k) | | |
| Quản lý công nợ → Nợ đối tác | Đối Tác Sửa Main XYZ | **500,000đ** | | |
| Thanh toán chờ xử lý | Chờ chi (đối tác) | **500,000đ** | | |

---

## ✅ BƯỚC 8: HOÀN THÀNH ĐƠN SỬA (GIAO MÁY - TIỀN MẶT)

### Thao tác:
1. **Vào:** Chi tiết đơn sửa
2. Chuyển trạng thái: **Chờ xử lý → Đang sửa → Đã xong**
3. Chọn phương thức thanh toán: **TIỀN MẶT**
4. Bấm **Giao máy** (hoặc Yêu cầu duyệt → Duyệt)

| Trường | Giá trị |
|--------|---------|
| Tổng thu khách | `2,800,000đ` |
| Phương thức | **TIỀN MẶT** |

### ✅ Kiểm tra sau bước 8:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Danh sách đơn sửa | Trạng thái | "Đã giao" | | |
| Chốt quỹ | Thu tiền mặt | **+2,800,000đ** | | |
| Chốt quỹ | Chi tiền mặt | **-500,000đ** (từ bước 3) | | |
| Nhật ký tài chính → Sửa chữa | Ghi nhận | **+2,800,000đ** | | |
| Tab Tài chính → Doanh thu | Sửa chữa | **2,800,000đ** | | |
| Tab Tài chính → Lợi nhuận | Ròng | **1,100,000đ** (2.8tr - 1.7tr vốn) | | |

---

## 💸 BƯỚC 9: THANH TOÁN NỢ ĐỐI TÁC (CHUYỂN KHOẢN)

### Thao tác:
**Vào:** Tab Tài chính → Thanh toán (hoặc Quản lý công nợ → Nợ đối tác)

| Trường | Giá trị |
|--------|---------|
| Đối tác | Đối Tác Sửa Main XYZ |
| Số tiền nợ | 500,000đ |
| Thanh toán | `500,000đ` |
| Phương thức | **CHUYỂN KHOẢN** |

**Bấm Thanh toán**

### ✅ Kiểm tra sau bước 9:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Quản lý công nợ → Nợ đối tác | Đối Tác Sửa Main XYZ | **0đ** (hết nợ) | | |
| Chốt quỹ | Chi ngân hàng | **-1,000,000đ** (500k NCC + 500k đối tác) | | |
| Nhật ký tài chính | Thanh toán đối tác | **-500,000đ** (CK) | | |
| Thanh toán chờ xử lý | Chờ chi | **0 item** (đã thanh toán hết) | | |

---

## 📦 BƯỚC 10: NHẬP KHO ĐIỆN THOẠI (CÔNG NỢ)

### Thao tác:
**Vào:** Nhập kho mới → Tab Điện thoại

| Trường | Giá trị nhập |
|--------|--------------|
| Tên sản phẩm | `iPhone 14 Pro Max 256GB` |
| IMEI | `999888777666555` |
| Màu | `Tím Deep Purple` |
| Tình trạng | `99% - Like New` |
| Giá nhập | `25,000,000đ` |
| Giá bán | `28,000,000đ` |
| Nhà cung cấp | `NCC Linh Kiện ABC` |
| Phương thức TT | **CÔNG NỢ** |

**Bấm Xác nhận** → Vào Hàng chờ xác nhận → **Xác nhận vào kho**

### ✅ Kiểm tra sau bước 10:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Quản lý kho → Điện thoại | iPhone 14 Pro Max | 1 máy, giá bán 28tr | | |
| Quản lý công nợ → Nợ NCC | NCC Linh Kiện ABC | **25,000,000đ** | | |
| Thanh toán chờ xử lý | Chờ chi | **25,000,000đ** | | |
| Chốt quỹ | Chi | Không thay đổi (chưa trả) | | |

---

## 🎁 BƯỚC 11: NHẬP KHO PHỤ KIỆN (TIỀN MẶT - TRẢ NGAY)

### Thao tác:
**Vào:** Nhập kho mới → Tab Phụ kiện

| Trường | Giá trị nhập |
|--------|--------------|
| Tên sản phẩm | `Ốp lưng iPhone 14 Pro Max` |
| Số lượng | `10` |
| Giá nhập/cái | `80,000đ` |
| **Tổng tiền nhập** | **`800,000đ`** |
| Giá bán/cái | `150,000đ` |
| Nhà cung cấp | `NCC Linh Kiện ABC` |
| Phương thức TT | **TIỀN MẶT** |

**Bấm Xác nhận**

### ✅ Kiểm tra sau bước 11:
| Trang | Mục kiểm tra | Giá trị mong đợi | Giá trị thực tế | ✓/✗ |
|-------|--------------|------------------|-----------------|-----|
| Quản lý kho → Phụ kiện | Ốp lưng iPhone 14 | 10 cái | | |
| Quản lý công nợ → Nợ NCC | NCC Linh Kiện ABC | **25,000,000đ** (không đổi) | | |
| Chốt quỹ | Chi tiền mặt | **-1,300,000đ** (500k cũ + 800k mới) | | |
| Nhật ký tài chính → Nhập hàng | Ghi nhận | **-800,000đ** (TM) | | |

---

## 📊 BẢNG TỔNG HỢP SỐ LIỆU CUỐI CÙNG

### Sau khi hoàn thành tất cả 11 bước:

#### CHỐT QUỸ HÔM NAY:
| Mục | Tiền mặt | Ngân hàng | Tổng |
|-----|----------|-----------|------|
| **THU** | +2,800,000đ | 0đ | +2,800,000đ |
| **CHI** | -1,300,000đ | -1,000,000đ | -2,300,000đ |
| **SỐ DƯ** | **+1,500,000đ** | **-1,000,000đ** | **+500,000đ** |

#### CHI TIẾT THU:
| Nguồn | Số tiền | Phương thức |
|-------|---------|-------------|
| Sửa chữa (Đơn Nguyễn Văn Test) | +2,800,000đ | Tiền mặt |
| **TỔNG THU** | **+2,800,000đ** | |

#### CHI TIẾT CHI:
| Mục | Số tiền | Phương thức |
|-----|---------|-------------|
| Thanh toán NCC (Pin iPhone 12) | -500,000đ | Tiền mặt |
| Thanh toán NCC (Pin iPhone 12) | -500,000đ | Chuyển khoản |
| Thanh toán đối tác sửa chữa | -500,000đ | Chuyển khoản |
| Nhập kho phụ kiện (Ốp lưng) | -800,000đ | Tiền mặt |
| **TỔNG CHI** | **-2,300,000đ** | |

#### CÔNG NỢ CÒN LẠI:
| Loại | Đối tượng | Số tiền |
|------|-----------|---------|
| Shop nợ NCC | NCC Linh Kiện ABC | **25,000,000đ** |
| Shop nợ Đối tác | Đối Tác Sửa Main XYZ | **0đ** |
| Khách nợ Shop | | **0đ** |
| **TỔNG NỢ PHẢI TRẢ** | | **25,000,000đ** |

#### DOANH THU & LỢI NHUẬN:
| Mục | Số tiền |
|-----|---------|
| Doanh thu sửa chữa | 2,800,000đ |
| Doanh thu bán hàng | 0đ |
| **TỔNG DOANH THU** | **2,800,000đ** |
| Giá vốn sửa chữa | -1,700,000đ |
| Chi phí khác | 0đ |
| **LỢI NHUẬN RÒNG** | **1,100,000đ** |

---

## 📝 BẢNG BÁO CÁO TEST (GỬI LẠI CHO DEV)

**Copy bảng này và điền số liệu thực tế:**

```
=== BÁO CÁO TEST TÀI CHÍNH ===
Ngày test: ___/___/2026
Shop ID: _________________

CHỐT QUỸ:
- Thu TM: _________ (mong đợi: +2,800,000đ)
- Thu CK: _________ (mong đợi: 0đ)
- Chi TM: _________ (mong đợi: -1,300,000đ)
- Chi CK: _________ (mong đợi: -1,000,000đ)
- Số dư TM: _______ (mong đợi: +1,500,000đ)
- Số dư CK: _______ (mong đợi: -1,000,000đ)

CÔNG NỢ:
- Nợ NCC: _________ (mong đợi: 25,000,000đ)
- Nợ đối tác: _____ (mong đợi: 0đ)
- Khách nợ: _______ (mong đợi: 0đ)

DOANH THU:
- Sửa chữa: _______ (mong đợi: 2,800,000đ)
- Bán hàng: _______ (mong đợi: 0đ)
- Lợi nhuận: ______ (mong đợi: 1,100,000đ)

NHẬT KÝ TÀI CHÍNH:
- Số giao dịch thu: ___ (mong đợi: 1)
- Số giao dịch chi: ___ (mong đợi: 4)

THANH TOÁN CHỜ XỬ LÝ:
- Số item: _________ (mong đợi: 1 - nợ NCC 25tr)

LỖI PHÁT HIỆN:
1. _________________________________
2. _________________________________
3. _________________________________
```

---

Gửi báo cáo này lại cho tôi để kiểm tra và fix lỗi!

---

# BẢNG SỐ LIỆU TEST PaymentIntent

## Các PaymentIntent được tạo trong Test

Khi chạy `PaymentIntentTestView`, các test case sẽ tạo các PaymentIntent sau:

### CHỜ THU (Income - Màu xanh lá)
| Test | ID | Type | Số tiền | Mô tả | Person |
|------|----|----- |---------|-------|--------|
| Test 1 | test_sale_debt_xxx | customerDebtCollection | **500,000đ** | Công nợ bán hàng - KH Test | Khách Test 1 |
| Test 5 | test_repair_delivery_xxx | repairService | **1,000,000đ** | Thu tiền sửa máy | Nguyễn Văn Test |
| Test 11 | test_execute_xxx | customerDebtCollection | **300,000đ** | Test execute payment | KH Test Execute |
| Test 14 | test_duplicate_xxx | customerDebtCollection | **100,000đ** | Test duplicate ID | - |
| **TỔNG CHỜ THU** | | | **1,900,000đ** | | |

### CHỜ CHI (Expense - Màu cam)
| Test | ID | Type | Số tiền | Mô tả | Person |
|------|----|----- |---------|-------|--------|
| Test 2 | test_purchase_debt_xxx | supplierDebt | **2,000,000đ** | Nhập hàng từ NCC Test | NCC Test ABC |
| Test 3 | test_stockin_debt_xxx | supplierDebt | **1,500,000đ** | Nhập kho SP Test | NCC Linh Kiện XYZ |
| Test 4 | test_parts_debt_xxx | supplierDebt | **800,000đ** | Nhập linh kiện màn hình | NCC Màn Hình ABC |
| Test 9 | test_supplier_payment_xxx | supplierDebt | **2,000,000đ** | Trả nợ NCC Điện thoại ABC | NCC Điện thoại ABC |
| Test 10 | test_partner_payment_xxx | repairPartnerDebt | **500,000đ** | Trả tiền thợ Minh | Thợ Minh |
| Test 12 | test_cancel_xxx | supplierDebt | **400,000đ** | Test cancel payment | NCC Test Cancel |
| **TỔNG CHỜ CHI** | | | **7,200,000đ** | | |

---

## BẢNG CHỐT QUỸ DỰ KIẾN SAU KHI CHẠY TEST

### Nếu TẤT CẢ các PaymentIntent được Execute (thanh toán):

#### Giả định thanh toán:
- Test 11 execute bằng **TIỀN MẶT** → Thu TM +300,000đ
- Test 12 bị **CANCEL** → Không tính

#### CHỐT QUỸ (Giả định thanh toán tất cả bằng TM):

| Loại | Tiền mặt | Ngân hàng | Tổng |
|------|----------|-----------|------|
| **THU** | | | |
| - Công nợ KH (Test 1) | +500,000đ | | +500,000đ |
| - Sửa chữa (Test 5) | +1,000,000đ | | +1,000,000đ |
| - Execute (Test 11) | +300,000đ | | +300,000đ |
| - Duplicate (Test 14) | +100,000đ | | +100,000đ |
| **Tổng THU** | **+1,900,000đ** | **0đ** | **+1,900,000đ** |
| | | | |
| **CHI** | | | |
| - Nhập hàng NCC (Test 2) | -2,000,000đ | | -2,000,000đ |
| - Nhập kho (Test 3) | -1,500,000đ | | -1,500,000đ |
| - Linh kiện (Test 4) | -800,000đ | | -800,000đ |
| - Trả nợ NCC (Test 9) | -2,000,000đ | | -2,000,000đ |
| - Thợ ngoài (Test 10) | -500,000đ | | -500,000đ |
| ~~- Cancel (Test 12)~~ | ~~-400,000đ~~ | | ~~(ĐÃ HỦY)~~ |
| **Tổng CHI** | **-6,800,000đ** | **0đ** | **-6,800,000đ** |
| | | | |
| **SỐ DƯ** | **-4,900,000đ** | **0đ** | **-4,900,000đ** |

---

## KIỂM TRA SAU KHI CHẠY TEST

### 1. Chạy Test PaymentIntent
**Vào:** Settings → Test PaymentIntent → "Chạy tất cả Test"

**Kết quả mong đợi:**
- [ ] 15/15 tests PASSED (màu xanh lá)
- [ ] 0 tests FAILED (màu đỏ)

### 2. Xem Pending Payments
**Bấm:** "Xem CHỜ THU/CHI"

| Mục | Số lượng | Tổng tiền |
|-----|----------|-----------|
| CHỜ THU | ~4 items | ~1,900,000đ |
| CHỜ CHI | ~5 items | ~6,800,000đ |
| **Tổng pending** | ~9 items | |

**Lưu ý:** Test 11 đã execute, Test 12 đã cancel → không còn trong pending

### 3. Check Database
**Bấm:** "Check DB"

- [ ] Table payment_intents TỒN TẠI
- [ ] Số records > 0
- [ ] Columns bao gồm: intentId, type, amount, status, shopId, etc.

### 4. Kiểm tra Data Isolation
**Thao tác:** Đăng xuất → Đăng nhập shop khác → Chạy lại test

**Mong đợi:**
- [ ] Shop mới KHÔNG thấy PaymentIntent của shop cũ
- [ ] "Xem CHỜ THU/CHI" hiện TRỐNG cho shop mới

---

## MẪU BÁO CÁO TEST PaymentIntent

```
=== BÁO CÁO TEST PAYMENTINTENT ===
Ngày: ___/___/2026
Shop ID: _________________

KẾT QUẢ TEST:
- Passed: ___/15
- Failed: ___/15

PENDING PAYMENTS:
- CHỜ THU: ___ items, tổng: ______đ (mong đợi: ~4 items, ~1.9tr)
- CHỜ CHI: ___ items, tổng: ______đ (mong đợi: ~5 items, ~6.8tr)

DATABASE CHECK:
- Table exists: ✓/✗
- Records count: ___

DATA ISOLATION:
- Shop mới có thấy data cũ không: CÓ/KHÔNG (mong đợi: KHÔNG)

LỖI PHÁT HIỆN:
1. Test ___ failed: _________________
2. _________________________________
```

---

## TỔNG HỢP SỐ LIỆU TEST PaymentIntent

### Sau khi chạy đầy đủ 15 tests:

| Metric | Giá trị |
|--------|---------|
| Tổng PaymentIntent tạo | ~11 intents |
| PaymentIntent CHỜ THU | ~4 intents |
| PaymentIntent CHỜ CHI | ~6 intents |
| Đã Execute (Test 11) | 1 intent (300K) |
| Đã Cancel (Test 12) | 1 intent (400K) |
| Đã Delete (Test 13, 14) | 2-3 intents |
| **Còn lại pending** | ~6-7 intents |

### Chi tiết số tiền:
| Loại | Số tiền pending | Ghi chú |
|------|-----------------|---------|
| **Tổng CHỜ THU** | ~1,600,000đ | Trừ 300K đã execute |
| **Tổng CHỜ CHI** | ~6,400,000đ | Trừ 400K đã cancel |
| **Balance** | **-4,800,000đ** | Âm = Chi nhiều hơn Thu |
