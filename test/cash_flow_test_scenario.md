# KỊCH BẢN TEST DÒNG TIỀN - SHOP MỚI

## 🎯 MỤC TIÊU
Kiểm tra tính chính xác của hệ thống dòng tiền (Cash Closing) với shop trống dữ liệu.

---

## 📋 ĐIỀU KIỆN TRƯỚC KHI TEST

### 1. Chuẩn bị Shop mới
- [ ] Đăng ký tài khoản mới hoặc tạo shop mới hoàn toàn
- [ ] Đảm bảo không có dữ liệu: 0 sản phẩm, 0 đơn bán, 0 chi phí
- [ ] Xác nhận ngày hôm nay chưa được chốt quỹ

### 2. Thiết lập quỹ ban đầu (VỐN KHỞI ĐIỂM)
**Vào CHỐT QUỸ → Tab "Lịch sử" → Chốt quỹ ngày hôm qua:**
- Quỹ tiền mặt đầu kỳ: **10,000,000đ**
- Quỹ ngân hàng đầu kỳ: **5,000,000đ**
→ **Tổng vốn: 15,000,000đ**

---

## 🧪 KỊCH BẢN TEST (Thứ tự thực hiện)

### BƯỚC 1: NHẬP HÀNG (Chi tiền - Tiền mặt)
**Thao tác:** Vào "Nhập hàng" → Thêm sản phẩm:
- Tên: `IPHONE TEST 01`
- IMEI: `111111111111111`
- Giá nhập: **3,000,000đ**
- Thanh toán: **TIỀN MẶT**

**Kỳ vọng:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt | 10,000,000 - 3,000,000 = **7,000,000đ** |
| Ngân hàng | **5,000,000đ** (không đổi) |
| Tổng quỹ | **12,000,000đ** |

---

### BƯỚC 2: BÁN HÀNG (Thu tiền - Tiền mặt)
**Thao tác:** Vào "Bán hàng" → Chọn sản phẩm vừa nhập:
- Khách hàng: `KHACH TEST`
- SĐT: `0912345678`
- Giá bán: **5,000,000đ**
- Thanh toán: **TIỀN MẶT**

**Kỳ vọng:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt | 7,000,000 + 5,000,000 = **12,000,000đ** |
| Ngân hàng | **5,000,000đ** (không đổi) |
| Tổng quỹ | **17,000,000đ** |
| Lợi nhuận | 5,000,000 - 3,000,000 = **2,000,000đ** |

---

### BƯỚC 3: CHI PHÍ (Chi tiền - Ngân hàng)
**Thao tác:** Vào "Chi phí" → Thêm chi phí:
- Tiêu đề: `TIỀN ĐIỆN THÁNG 1`
- Số tiền: **500,000đ**
- Danh mục: `ĐIỆN NƯỚC`
- Thanh toán: **CHUYỂN KHOẢN**

**Kỳ vọng:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt | **12,000,000đ** (không đổi) |
| Ngân hàng | 5,000,000 - 500,000 = **4,500,000đ** |
| Tổng quỹ | **16,500,000đ** |
| Lợi nhuận | 2,000,000 - 500,000 = **1,500,000đ** |

---

### BƯỚC 4: BÁN HÀNG CÔNG NỢ (Không ảnh hưởng quỹ tiền)
**Thao tác:** Nhập thêm sản phẩm mới + Bán công nợ:

4.1. Nhập hàng mới:
- Tên: `IPHONE TEST 02`
- IMEI: `222222222222222`
- Giá nhập: **4,000,000đ**
- Thanh toán: **TIỀN MẶT**

4.2. Bán công nợ:
- Khách hàng: `KHACH NO`
- SĐT: `0987654321`
- Giá bán: **6,000,000đ**
- Thanh toán: **CÔNG NỢ**

**Kỳ vọng:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt | 12,000,000 - 4,000,000 = **8,000,000đ** |
| Ngân hàng | **4,500,000đ** (không đổi) |
| Tổng quỹ | **12,500,000đ** |
| Doanh thu | 5,000,000 + 6,000,000 = **11,000,000đ** (bao gồm công nợ) |
| Giá vốn | 3,000,000 + 4,000,000 = **7,000,000đ** |
| Lợi nhuận | 11,000,000 - 7,000,000 - 500,000 = **3,500,000đ** |

---

### BƯỚC 5: THU NỢ (Thu tiền - Ngân hàng)
**Thao tác:** Vào "Quản lý nợ" → Tìm nợ của KHACH NO → Thu tiền:
- Số tiền thu: **3,000,000đ** (thu một phần)
- Thanh toán: **CHUYỂN KHOẢN**

**Kỳ vọng:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt | **8,000,000đ** (không đổi) |
| Ngân hàng | 4,500,000 + 3,000,000 = **7,500,000đ** |
| Tổng quỹ | **15,500,000đ** |
| Lợi nhuận | **3,500,000đ** (KHÔNG ĐỔI - vì doanh thu đã tính ở bước 4) |
| Công nợ còn lại | 6,000,000 - 3,000,000 = **3,000,000đ** |

---

## ✅ BẢNG TỔNG HỢP KIỂM TRA

| # | Thao tác | TM trước | TM sau | NH trước | NH sau | Quỹ | Đúng? |
|---|----------|----------|--------|----------|--------|-----|-------|
| 0 | Vốn đầu | - | 10,000,000 | - | 5,000,000 | 15,000,000 | ☐ |
| 1 | Nhập hàng TM | 10,000,000 | 7,000,000 | 5,000,000 | 5,000,000 | 12,000,000 | ☐ |
| 2 | Bán hàng TM | 7,000,000 | 12,000,000 | 5,000,000 | 5,000,000 | 17,000,000 | ☐ |
| 3 | Chi phí CK | 12,000,000 | 12,000,000 | 5,000,000 | 4,500,000 | 16,500,000 | ☐ |
| 4a | Nhập hàng 2 | 12,000,000 | 8,000,000 | 4,500,000 | 4,500,000 | 12,500,000 | ☐ |
| 4b | Bán công nợ | 8,000,000 | 8,000,000 | 4,500,000 | 4,500,000 | 12,500,000 | ☐ |
| 5 | Thu nợ CK | 8,000,000 | 8,000,000 | 4,500,000 | 7,500,000 | 15,500,000 | ☐ |

---

## 📊 KIỂM TRA LỢI NHUẬN (ACCRUAL BASIS)

Cuối ngày, vào **CHỐT QUỸ** kiểm tra:

| Chỉ số | Giá trị kỳ vọng | Thực tế | Đúng? |
|--------|-----------------|---------|-------|
| Doanh thu bán hàng | 11,000,000đ | | ☐ |
| Giá vốn hàng bán | 7,000,000đ | | ☐ |
| Chi phí khác | 500,000đ | | ☐ |
| **Lợi nhuận ròng** | **3,500,000đ** | | ☐ |
| Thu nợ (K5) | 3,000,000đ | | ☐ |
| **Quỹ cuối kỳ** | **15,500,000đ** | | ☐ |

---

## ⚠️ LƯU Ý QUAN TRỌNG

1. **Bán công nợ (K3)**: Vẫn tính vào doanh thu và giá vốn ngay lúc bán (Accrual Basis)
2. **Thu nợ (K5)**: CHỈ tăng quỹ tiền, KHÔNG tăng thêm doanh thu hay lợi nhuận
3. **Nhập hàng**: Tính vào CHI (cashOut/bankOut), không ảnh hưởng lợi nhuận cho đến khi bán
4. **Chốt quỹ**: Phải chốt quỹ ngày hôm qua trước để có số dư đầu kỳ

---

## 🔧 NẾU SAI - KIỂM TRA

1. Xem **debug log** trong console để theo dõi `cashIn`, `cashOut`, `bankIn`, `bankOut`
2. Kiểm tra collection Firestore: `sales`, `expenses`, `debt_payments`, `cash_closings`
3. Kiểm tra local SQLite database
4. So sánh số liệu giữa các thiết bị (nếu có)

---

**Tác giả:** AI Assistant  
**Ngày tạo:** 15/01/2026  
**Phiên bản:** 1.0
