# 📱 HƯỚNG DẪN SỬ DỤNG QUANLYSHOP - PHẦN 2

> **Phần mềm Quản lý Tiệm Sửa chữa & Mua bán Điện thoại**  
> Tài liệu training cho người dùng mới (Tiếp theo Phần 1)

---

## 📋 MỤC LỤC PHẦN 2

7. [Module Kho hàng](#7-module-kho-hàng)
8. [Module Nhà cung cấp](#8-module-nhà-cung-cấp)
9. [Module Tài chính](#9-module-tài-chính)
10. [Module Nhân sự](#10-module-nhân-sự)
11. [Module Cài đặt](#11-module-cài-đặt)
12. [Tính năng nâng cao](#12-tính-năng-nâng-cao)
13. [Xử lý sự cố](#13-xử-lý-sự-cố)
14. [Câu hỏi thường gặp (FAQ)](#14-câu-hỏi-thường-gặp-faq)

---

## 7. MODULE KHO HÀNG

### 7.1 Tổng quan

Module Kho hàng giúp bạn:
- Quản lý sản phẩm tồn kho
- Nhập hàng từ nhà cung cấp
- Quản lý kho tạm (sản phẩm chưa định giá)
- Kiểm kê kho hàng
- Quản lý linh kiện sửa chữa

### 7.2 Xem danh sách kho

1. Nhấn tab **📦 Kho** trên thanh điều hướng
2. Danh sách sản phẩm hiển thị

**Bộ lọc sản phẩm:**
```
┌─────────────────────────────────────┐
│  🔍 [Tìm kiếm theo tên/IMEI...]    │
├─────────────────────────────────────┤
│  📱 Điện thoại  🎧 Phụ kiện  🔧 LK │
│  [Tất cả▼] [Còn hàng▼] [Mới nhất▼] │
└─────────────────────────────────────┘
```

- **Loại**: Điện thoại / Phụ kiện / Linh kiện
- **Trạng thái**: Còn hàng / Hết hàng / Tất cả
- **Sắp xếp**: Mới nhất / Giá cao-thấp / Tên A-Z

**Thông tin mỗi sản phẩm:**
- STT + Icon loại sản phẩm
- Tên sản phẩm
- IMEI (nếu có) + Dung lượng
- Số lượng tồn
- Giá vốn / Giá bán
- Màu sắc, tình trạng

**Màu sắc hiển thị:**
- 🟢 Trắng: Còn hàng
- 🟠 Cam: Kho tạm (chờ định giá)
- 🔴 Đỏ: Hết hàng (quantity = 0)

### 7.3 Thêm sản phẩm mới

**Bước 1: Mở form thêm sản phẩm**
- Nhấn nút **➕** hoặc **"NHẬP KHO"**

**Bước 2: Chọn loại sản phẩm**
```
┌─────────────────────────────────────┐
│  📦 LOẠI SẢN PHẨM                  │
├─────────────────────────────────────┤
│  ● Điện thoại                      │
│  ○ Phụ kiện                        │
│  ○ Linh kiện                       │
└─────────────────────────────────────┘
```

**Bước 3: Nhập thông tin sản phẩm**

*Đối với Điện thoại:*
```
┌─────────────────────────────────────┐
│  📱 THÔNG TIN SẢN PHẨM             │
├─────────────────────────────────────┤
│  Tên máy*:     [iPhone 14 Pro Max_] │
│  IMEI (5 số)*: [12345_____________] │
│  Dung lượng:   [256GB____________▼] │
│  Màu sắc:      [Đen______________▼] │
│  Tình trạng:   [99% - Like new___▼] │
│  Số lượng:     [1_________________] │
└─────────────────────────────────────┘
```

*Đối với Phụ kiện/Linh kiện:*
```
┌─────────────────────────────────────┐
│  🎧 THÔNG TIN SẢN PHẨM             │
├─────────────────────────────────────┤
│  Tên SP*:      [Ốp lưng iPhone 14_] │
│  Mã SKU:       [OL-IP14-001_______] │
│  Số lượng:     [10________________] │
│  Màu sắc:      [Đen, Trắng, Hồng__] │
└─────────────────────────────────────┘
```

**Bước 4: Nhập giá**
```
┌─────────────────────────────────────┐
│  💰 GIÁ CẢ                         │
├─────────────────────────────────────┤
│  Giá vốn (nhập): [22,000,000___] đ │
│  Giá bán:        [25,000,000___] đ │
│                                     │
│  💡 Lợi nhuận dự kiến: 3,000,000 đ │
│     Tỷ suất: 13.6%                 │
└─────────────────────────────────────┘
```

**Bước 5: Thông tin bổ sung**
```
┌─────────────────────────────────────┐
│  📋 THÔNG TIN BỔ SUNG              │
├─────────────────────────────────────┤
│  Nhà cung cấp:  [Thế Giới DĐ____▼] │
│  Bảo hành:      [12 tháng_______▼] │
│  PTTT nhập:     [Tiền mặt_______▼] │
│  Mô tả:         [________________] │
└─────────────────────────────────────┘
```

**Bước 6: Chụp ảnh sản phẩm (tùy chọn)**
- Nhấn **"📷 CHỤP ẢNH"**
- Có thể thêm nhiều ảnh

**Bước 7: Lưu sản phẩm**
- Nhấn **"LƯU SẢN PHẨM"**

### 7.4 Nhập hàng nhanh (Smart Stock In)

**Dùng khi:** Nhập nhiều sản phẩm cùng lúc từ NCC

1. Vào **Kho** > **Nhập hàng thông minh**
2. Chọn nhà cung cấp
3. Quét QR/barcode liên tiếp
4. Mỗi sản phẩm quét sẽ tự động thêm vào danh sách
5. Điều chỉnh giá/số lượng nếu cần
6. Nhấn **"XÁC NHẬN NHẬP KHO"**

### 7.5 Kho tạm (Pending Stock)

**Kho tạm là gì?**
- Sản phẩm đã nhập nhưng CHƯA định giá bán
- Hiển thị với badge **"TẠM"** màu cam
- Không thể bán cho đến khi định giá

**Xem kho tạm:**
1. Vào **Kho** > **Kho tạm**
2. Hoặc từ Home, nhấn widget **"Kho tạm"**

**Xử lý kho tạm:**
1. Nhấn vào sản phẩm
2. Nhập giá bán
3. Nhấn **"XÁC NHẬN GIÁ"**
4. Sản phẩm chuyển sang kho chính

### 7.6 Kiểm kê kho

**Tính năng kiểm kê** giúp đối chiếu số lượng thực tế với số liệu trên hệ thống.

**Bước 1: Tạo phiên kiểm kê**
1. Vào **Kho** > **Kiểm kê kho**
2. Nhấn **"TẠO KIỂM KÊ MỚI"**
3. Chọn loại kiểm kê:
   - **Toàn bộ**: Kiểm tất cả sản phẩm
   - **Theo loại**: Chỉ điện thoại/phụ kiện/linh kiện
   - **Ngẫu nhiên**: Chọn ngẫu nhiên một số SP

**Bước 2: Nhập số lượng thực tế**
```
┌─────────────────────────────────────┐
│  📋 KIỂM KÊ                        │
├─────────────────────────────────────┤
│  SP: iPhone 14 Pro Max 256GB Đen   │
│  Hệ thống: 3                       │
│  Thực tế:  [__2__]                 │
│  Chênh lệch: -1 ⚠️                 │
├─────────────────────────────────────┤
│  SP: Ốp lưng iPhone 14             │
│  Hệ thống: 15                      │
│  Thực tế:  [_15__]                 │
│  Chênh lệch: 0 ✅                  │
└─────────────────────────────────────┘
```

**Bước 3: Hoàn tất kiểm kê**
- Nhấn **"HOÀN TẤT"**
- Hệ thống tự động điều chỉnh số lượng
- Ghi log kiểm kê để truy vết

### 7.7 Quản lý linh kiện

**Linh kiện** dùng cho sửa chữa, khác với sản phẩm bán.

**Xem linh kiện:**
1. Vào **Kho** > **Linh kiện**
2. Danh sách linh kiện hiển thị

**Thêm linh kiện:**
1. Nhấn **"+ THÊM LINH KIỆN"**
2. Nhập: Tên, số lượng, giá vốn, giá bán
3. Nhấn **"LƯU"**

**Sử dụng linh kiện:**
- Khi cập nhật đơn sửa, chọn linh kiện từ danh sách
- Số lượng tự động giảm

### 7.8 Chỉnh sửa/Xóa sản phẩm

**Chỉnh sửa:**
1. Nhấn vào sản phẩm
2. Nhấn icon ✏️ **"Sửa"**
3. Chỉnh sửa thông tin
4. Nhấn **"LƯU"**

**Xóa sản phẩm:**
1. Nhấn giữ sản phẩm
2. Chọn **"Xóa"**
3. Nhập mật khẩu xác nhận (nếu yêu cầu)
4. Xác nhận xóa

> **Lưu ý:** Không thể xóa sản phẩm đã có trong đơn bán.

---

## 8. MODULE NHÀ CUNG CẤP

### 8.1 Tổng quan

Module Nhà cung cấp giúp bạn:
- Quản lý danh sách NCC
- Theo dõi lịch sử nhập hàng
- Quản lý công nợ với NCC
- Thanh toán cho NCC

### 8.2 Xem danh sách NCC

1. Từ Home, nhấn **"Nhà cung cấp"**
2. Hoặc vào **Kho** > **Nhà cung cấp**

**Thông tin hiển thị:**
- Tên NCC
- Người liên hệ
- Số điện thoại
- Số lần nhập hàng
- Tổng giá trị đã nhập
- Trạng thái (Đang hoạt động / Tạm ngưng)

### 8.3 Thêm NCC mới

1. Nhấn **"+ THÊM NCC"**
2. Nhập thông tin:
```
┌─────────────────────────────────────┐
│  🏭 THÔNG TIN NCC                  │
├─────────────────────────────────────┤
│  Tên NCC*:        [Thế Giới Di Động]│
│  Người liên hệ:   [Anh Minh________]│
│  Số điện thoại*:  [0909123456_____] │
│  Email:           [minh@tgdd.vn___] │
│  Địa chỉ:         [123 Nguyễn Trãi] │
│  Ghi chú:         [NCC chính______] │
│                                     │
│  ☑ Đánh dấu yêu thích              │
└─────────────────────────────────────┘
```
3. Nhấn **"LƯU"**

### 8.4 Tạo đơn nhập hàng

**Bước 1: Chọn NCC**
1. Vào chi tiết NCC
2. Nhấn **"TẠO ĐƠN NHẬP"**
3. Hoặc: **Kho** > **Đơn nhập hàng** > **"+"**

**Bước 2: Thêm sản phẩm**
```
┌─────────────────────────────────────┐
│  📦 SẢN PHẨM NHẬP                  │
├─────────────────────────────────────┤
│  [+ THÊM SẢN PHẨM]                 │
│                                     │
│  1. iPhone 14 Pro Max 256GB Đen    │
│     Số lượng: 2  |  Giá: 22,000,000│
│                          [Xóa]     │
│                                     │
│  2. iPhone 14 128GB Trắng          │
│     Số lượng: 3  |  Giá: 15,000,000│
│                          [Xóa]     │
├─────────────────────────────────────┤
│  Tổng số lượng: 5                  │
│  Tổng giá trị:  89,000,000 đ       │
└─────────────────────────────────────┘
```

**Bước 3: Thanh toán**
```
┌─────────────────────────────────────┐
│  💳 THANH TOÁN                     │
├─────────────────────────────────────┤
│  Tổng tiền:       89,000,000 đ     │
│  Đã thanh toán:   [50,000,000__] đ │
│  Còn nợ:          39,000,000 đ     │
│                                     │
│  PTTT: [Tiền mặt_______________▼]  │
└─────────────────────────────────────┘
```

**Bước 4: Xác nhận**
- Nhấn **"TẠO ĐƠN NHẬP"**
- Sản phẩm tự động thêm vào kho
- Công nợ NCC được tạo (nếu có)

### 8.5 Thanh toán cho NCC

1. Vào chi tiết NCC
2. Xem danh sách công nợ
3. Nhấn **"THANH TOÁN"**
4. Nhập số tiền thanh toán
5. Chọn phương thức (Tiền mặt/CK)
6. Nhấn **"XÁC NHẬN"**

### 8.6 Xem lịch sử nhập hàng

1. Vào chi tiết NCC
2. Tab **"Lịch sử nhập"**
3. Danh sách đơn nhập hiển thị:
   - Mã đơn nhập
   - Ngày nhập
   - Số sản phẩm
   - Tổng giá trị
   - Trạng thái thanh toán

---

## 9. MODULE TÀI CHÍNH

### 9.1 Tổng quan

Module Tài chính giúp bạn:
- Theo dõi doanh thu
- Quản lý chi phí
- Quản lý công nợ
- Chốt quỹ cuối ngày
- Xem báo cáo tài chính

### 9.2 Xem doanh thu

1. Nhấn tab **💰 Tài chính** > **Doanh thu**

**Màn hình doanh thu:**
```
┌─────────────────────────────────────┐
│  📊 DOANH THU                      │
├─────────────────────────────────────┤
│  [Hôm nay▼]  📅 01/01/2026         │
├─────────────────────────────────────┤
│  💰 Tổng doanh thu:   15,500,000 đ │
│  🛒 Từ bán hàng:      12,000,000 đ │
│  🔧 Từ sửa chữa:       3,500,000 đ │
├─────────────────────────────────────┤
│  📈 BIỂU ĐỒ DOANH THU              │
│  [Biểu đồ cột theo ngày/tuần/tháng]│
├─────────────────────────────────────┤
│  📋 CHI TIẾT GIAO DỊCH             │
│  • 10:30 - Bán iPhone 14: 24,000,000│
│  • 11:15 - Sửa Samsung: 500,000    │
│  • ...                              │
└─────────────────────────────────────┘
```

**Bộ lọc thời gian:**
- Hôm nay
- Hôm qua
- 7 ngày qua
- Tháng này
- Tùy chọn (chọn ngày bắt đầu - kết thúc)

### 9.3 Quản lý chi phí

**Xem danh sách chi phí:**
1. Vào **Tài chính** > **Chi phí**

**Thêm chi phí mới:**
1. Nhấn **"+ THÊM CHI PHÍ"**
2. Nhập thông tin:
```
┌─────────────────────────────────────┐
│  💸 THÊM CHI PHÍ                   │
├─────────────────────────────────────┤
│  Tiêu đề*:    [Tiền điện tháng 1__]│
│  Số tiền*:    [2,500,000_______] đ │
│  Danh mục:    [Điện nước________▼] │
│  Ngày:        [📅 01/01/2026______]│
│  PTTT:        [Tiền mặt_________▼] │
│  Ghi chú:     [__________________ ]│
└─────────────────────────────────────┘
```
3. Nhấn **"LƯU"**

**Danh mục chi phí:**
- 🏠 Mặt bằng (thuê nhà, điện, nước)
- 👥 Nhân sự (lương, thưởng)
- 📦 Hàng hóa (nhập hàng, vận chuyển)
- 🔧 Thiết bị (công cụ, máy móc)
- 📣 Marketing (quảng cáo, khuyến mãi)
- 📋 Khác

### 9.4 Quản lý công nợ

**Xem danh sách công nợ:**
1. Vào **Tài chính** > **Công nợ**

**Các loại công nợ:**
```
┌─────────────────────────────────────┐
│  📋 CÔNG NỢ                        │
├─────────────────────────────────────┤
│  Tab: [Nợ khách] [Nợ NCC] [Tất cả] │
├─────────────────────────────────────┤
│  🔴 NỢ KHÁCH HÀNG                  │
│  Tổng: 25,000,000 đ (5 khoản)      │
│                                     │
│  • Nguyễn Văn A: 5,000,000 đ       │
│    Đơn bán #123 - 15/01/2026       │
│  • Trần Thị B: 10,000,000 đ        │
│    Đơn sửa #456 - 10/01/2026       │
├─────────────────────────────────────┤
│  🟠 NỢ NHÀ CUNG CẤP                │
│  Tổng: 39,000,000 đ (2 khoản)      │
│                                     │
│  • Thế Giới DĐ: 39,000,000 đ       │
│    Đơn nhập #789 - 05/01/2026      │
└─────────────────────────────────────┘
```

**Thu nợ khách hàng:**
1. Nhấn vào khoản nợ
2. Nhấn **"THU NỢ"**
3. Nhập số tiền thu
4. Chọn PTTT
5. Nhấn **"XÁC NHẬN"**

**Thanh toán nợ NCC:**
1. Nhấn vào khoản nợ
2. Nhấn **"THANH TOÁN"**
3. Nhập số tiền
4. Chọn PTTT
5. Nhấn **"XÁC NHẬN"**

### 9.5 Chốt quỹ cuối ngày

**Tính năng chốt quỹ** giúp kiểm kê tiền mặt cuối ngày.

**Quy trình chốt quỹ:**
1. Vào **Tài chính** > **Chốt quỹ**
2. Hệ thống hiển thị:
```
┌─────────────────────────────────────┐
│  💵 CHỐT QUỸ NGÀY 01/01/2026       │
├─────────────────────────────────────┤
│  📥 THU TRONG NGÀY                 │
│  • Bán hàng (tiền mặt): 5,000,000  │
│  • Sửa chữa (tiền mặt): 1,500,000  │
│  • Thu nợ:              2,000,000  │
│  ─────────────────────────────────  │
│  Tổng thu:              8,500,000 đ│
├─────────────────────────────────────┤
│  📤 CHI TRONG NGÀY                 │
│  • Chi phí điện nước:   500,000    │
│  • Trả nợ NCC:        2,000,000    │
│  ─────────────────────────────────  │
│  Tổng chi:              2,500,000 đ│
├─────────────────────────────────────┤
│  💰 TIỀN MẶT CUỐI NGÀY             │
│  Đầu ngày:            10,000,000 đ │
│  + Thu:                8,500,000 đ │
│  - Chi:                2,500,000 đ │
│  ─────────────────────────────────  │
│  Lý thuyết:           16,000,000 đ │
│  Thực tế:    [_______________] đ   │
│  Chênh lệch:           0 đ ✅       │
├─────────────────────────────────────┤
│        [HỦY]     [CHỐT QUỸ]        │
└─────────────────────────────────────┘
```

3. Nhập số tiền thực tế đếm được
4. Nếu chênh lệch, ghi chú lý do
5. Nhấn **"CHỐT QUỸ"**

### 9.6 Báo cáo tài chính

**Xem báo cáo:**
1. Vào **Tài chính** > **Báo cáo**

**Các loại báo cáo:**

1. **Báo cáo doanh thu:**
   - Doanh thu theo ngày/tuần/tháng
   - So sánh với kỳ trước
   - Top sản phẩm bán chạy

2. **Báo cáo lợi nhuận:**
   - Doanh thu - Chi phí - Giá vốn
   - Lợi nhuận gộp / Lợi nhuận ròng
   - Tỷ suất lợi nhuận

3. **Báo cáo công nợ:**
   - Tổng nợ phải thu
   - Tổng nợ phải trả
   - Nợ quá hạn

4. **Báo cáo trả góp:**
   - Danh sách trả góp đang chờ
   - Tiền tất toán dự kiến
   - Đã tất toán trong kỳ

**Xuất báo cáo:**
- Nhấn icon **📤** để xuất Excel/PDF
- Chọn khoảng thời gian
- Chọn định dạng file
- Lưu hoặc chia sẻ

---

## 10. MODULE NHÂN SỰ

### 10.1 Tổng quan

Module Nhân sự giúp bạn:
- Quản lý danh sách nhân viên
- Phân quyền truy cập
- Quản lý chấm công
- Tính lương tự động
- Đánh giá hiệu suất

### 10.2 Quản lý nhân viên

**Xem danh sách:**
1. Nhấn tab **👥 Nhân sự**

**Thêm nhân viên mới:**
1. Nhấn **"+ THÊM NHÂN VIÊN"**
2. Nhập thông tin:
```
┌─────────────────────────────────────┐
│  👤 THÔNG TIN NHÂN VIÊN            │
├─────────────────────────────────────┤
│  Họ tên*:      [Nguyễn Văn A______]│
│  Email*:       [a.nguyen@shop.vn__]│
│  Mật khẩu*:    [••••••••__________]│
│  SĐT:          [0909123456________]│
│  Địa chỉ:      [123 ABC, Quận 1___]│
│  Vai trò:      [Nhân viên_______▼] │
└─────────────────────────────────────┘
```
3. Nhấn **"TẠO TÀI KHOẢN"**

**Các vai trò:**
- **Chủ shop (Owner)**: Toàn quyền
- **Quản lý (Admin)**: Gần như owner, hạn chế xóa
- **Nhân viên (Staff)**: Theo quyền được cấp

### 10.3 Phân quyền nhân viên

1. Vào chi tiết nhân viên
2. Nhấn **"PHÂN QUYỀN"**
3. Bật/tắt các quyền:

```
┌─────────────────────────────────────┐
│  🔐 PHÂN QUYỀN: Nguyễn Văn A       │
├─────────────────────────────────────┤
│  📋 QUYỀN XEM                      │
│  ☑ Xem đơn sửa chữa                │
│  ☑ Xem đơn bán hàng                │
│  ☑ Xem kho hàng                    │
│  ☐ Xem doanh thu                   │
│  ☐ Xem chi phí                     │
│  ☐ Xem công nợ                     │
├─────────────────────────────────────┤
│  ✏️ QUYỀN TẠO/SỬA                  │
│  ☑ Tạo đơn sửa chữa                │
│  ☑ Cập nhật đơn sửa                │
│  ☑ Tạo đơn bán                     │
│  ☐ Thêm sản phẩm                   │
│  ☐ Sửa sản phẩm                    │
│  ☐ Xóa sản phẩm                    │
├─────────────────────────────────────┤
│  ⚙️ QUYỀN QUẢN LÝ                  │
│  ☐ Quản lý nhân viên               │
│  ☐ Quản lý cài đặt                 │
│  ☐ Duyệt trả máy                   │
│  ☑ In hóa đơn                      │
│  ☐ Xuất báo cáo                    │
├─────────────────────────────────────┤
│        [HỦY]        [LƯU]          │
└─────────────────────────────────────┘
```

4. Nhấn **"LƯU"**

### 10.4 Chấm công

**Nhân viên chấm công:**
1. Vào **Nhân sự** > **Chấm công**
2. Nhấn **"CHECK IN"** khi đến
3. Chụp ảnh xác nhận (tùy chọn)
4. Nhấn **"CHECK OUT"** khi về

**Màn hình chấm công:**
```
┌─────────────────────────────────────┐
│  ⏰ CHẤM CÔNG - 01/01/2026         │
├─────────────────────────────────────┤
│            08:30 AM                 │
│                                     │
│      [📷 CHECK IN]                  │
│                                     │
│  Trạng thái: Chưa chấm công        │
│  Ca làm việc: 08:00 - 17:00        │
└─────────────────────────────────────┘
```

**Sau khi check in:**
```
┌─────────────────────────────────────┐
│  ⏰ CHẤM CÔNG - 01/01/2026         │
├─────────────────────────────────────┤
│  ✅ Đã check in: 08:30             │
│                                     │
│      [📷 CHECK OUT]                 │
│                                     │
│  Thời gian làm việc: 4h 30m        │
└─────────────────────────────────────┘
```

**Quản lý xem chấm công:**
1. Vào **Nhân sự** > **Quản lý chấm công**
2. Xem danh sách chấm công của tất cả NV
3. Duyệt/từ chối nếu cần
4. Xem thống kê:
   - Số ngày công
   - Giờ làm thêm
   - Đi muộn/về sớm

### 10.5 Tính lương

**Cài đặt lương:**
1. Vào **Nhân sự** > **Cài đặt lương**
2. Cấu hình:
```
┌─────────────────────────────────────┐
│  💰 CÀI ĐẶT LƯƠNG                  │
├─────────────────────────────────────┤
│  Lương cơ bản:   [5,000,000___] đ  │
│  Phụ cấp cơm:    [500,000_____] đ  │
│  Phụ cấp xăng:   [300,000_____] đ  │
│  Phụ cấp ĐT:     [200,000_____] đ  │
├─────────────────────────────────────┤
│  % Hoa hồng bán: [5__]%            │
│  % Hoa hồng sửa: [10_]%            │
├─────────────────────────────────────┤
│  Khấu trừ:                         │
│  ☑ BHXH: 8%                        │
│  ☑ BHYT: 1.5%                      │
│  ☐ Thuế TNCN                       │
└─────────────────────────────────────┘
```

**Xem bảng lương:**
1. Vào **Nhân sự** > **Bảng lương**
2. Chọn tháng
3. Xem chi tiết từng nhân viên:
```
┌─────────────────────────────────────┐
│  💵 BẢNG LƯƠNG THÁNG 01/2026       │
├─────────────────────────────────────┤
│  👤 Nguyễn Văn A                   │
│  ─────────────────────────────────  │
│  Lương cơ bản:        5,000,000 đ  │
│  Ngày công: 22/22           100%   │
│  Phụ cấp:             1,000,000 đ  │
│  Hoa hồng bán:          500,000 đ  │
│  Hoa hồng sửa:          300,000 đ  │
│  Làm thêm:              200,000 đ  │
│  ─────────────────────────────────  │
│  TỔNG THU:            7,000,000 đ  │
│  ─────────────────────────────────  │
│  BHXH (8%):             400,000 đ  │
│  BHYT (1.5%):            75,000 đ  │
│  Tạm ứng:               500,000 đ  │
│  ─────────────────────────────────  │
│  THỰC LÃNH:           6,025,000 đ  │
└─────────────────────────────────────┘
```

### 10.6 Đánh giá hiệu suất

**Xem hiệu suất nhân viên:**
1. Vào **Nhân sự** > **Hiệu suất**

**Chỉ số hiệu suất:**
- Số đơn sửa hoàn thành
- Số đơn bán
- Doanh thu tạo ra
- Đánh giá khách hàng
- Ngày công

**Biểu đồ so sánh:**
- So sánh hiệu suất giữa các NV
- Xu hướng theo thời gian
- Top nhân viên xuất sắc

---

## 11. MODULE CÀI ĐẶT

### 11.1 Cài đặt cửa hàng

1. Vào **Cài đặt** > **Thông tin cửa hàng**
2. Chỉnh sửa:
```
┌─────────────────────────────────────┐
│  🏪 THÔNG TIN CỬA HÀNG             │
├─────────────────────────────────────┤
│  Tên shop:    [Huluca Mobile______]│
│  Địa chỉ:     [123 Nguyễn Trãi, Q1]│
│  SĐT:         [0909123456_________]│
│  Email:       [info@huluca.vn_____]│
│  Website:     [www.huluca.vn______]│
│                                     │
│  [📷 Logo cửa hàng]                │
└─────────────────────────────────────┘
```
3. Nhấn **"LƯU"**

### 11.2 Cài đặt máy in

**Kết nối máy in Bluetooth:**
1. Vào **Cài đặt** > **Máy in**
2. Bật Bluetooth trên thiết bị
3. Nhấn **"TÌM MÁY IN BLUETOOTH"**
4. Chọn máy in từ danh sách
5. Nhấn **"KẾT NỐI"**
6. Nhấn **"IN THỬ"** để kiểm tra

**Kết nối máy in WiFi:**
1. Nhập địa chỉ IP máy in (ví dụ: 192.168.1.100)
2. Nhập Port (thường là 9100)
3. Nhấn **"KẾT NỐI"**
4. Nhấn **"IN THỬ"**

### 11.3 Thiết kế hóa đơn

1. Vào **Cài đặt** > **Thiết kế hóa đơn**
2. Tùy chỉnh mẫu in:
```
┌─────────────────────────────────────┐
│  🖨️ THIẾT KẾ HÓA ĐƠN              │
├─────────────────────────────────────┤
│  HEADER                            │
│  ☑ Hiển thị logo                   │
│  ☑ Hiển thị tên shop               │
│  ☑ Hiển thị địa chỉ                │
│  ☑ Hiển thị SĐT                    │
├─────────────────────────────────────┤
│  NỘI DUNG                          │
│  ☑ Hiển thị IMEI                   │
│  ☑ Hiển thị giá vốn (chỉ admin)    │
│  ☑ Hiển thị chiết khấu             │
│  ☑ Hiển thị PTTT                   │
├─────────────────────────────────────┤
│  FOOTER                            │
│  Nội dung: [Cảm ơn quý khách!     │
│  Hotline: 0909 123 456____________]│
│  ☑ Hiển thị QR thanh toán          │
└─────────────────────────────────────┘
```
3. Nhấn **"XEM TRƯỚC"** để preview
4. Nhấn **"LƯU"**

### 11.4 Cài đặt thông báo

1. Vào **Cài đặt** > **Thông báo**
2. Bật/tắt các loại thông báo:
```
┌─────────────────────────────────────┐
│  🔔 CÀI ĐẶT THÔNG BÁO              │
├─────────────────────────────────────┤
│  ☑ Đơn sửa mới                     │
│  ☑ Đơn sửa hoàn thành              │
│  ☑ Đơn bán mới                     │
│  ☑ Thanh toán công nợ              │
│  ☑ Nhắc bảo hành sắp hết           │
│  ☑ Chốt quỹ cuối ngày              │
│  ☐ Chat nội bộ                     │
├─────────────────────────────────────┤
│  Âm thanh thông báo: ☑ Bật         │
│  Rung: ☑ Bật                       │
└─────────────────────────────────────┘
```

### 11.5 Cài đặt ngôn ngữ

1. Vào **Cài đặt** > **Ngôn ngữ**
2. Chọn:
   - 🇻🇳 Tiếng Việt
   - 🇬🇧 English
3. App tự động restart

### 11.6 Quản lý dữ liệu

**Đồng bộ dữ liệu:**
- Xem trạng thái đồng bộ
- Đồng bộ thủ công
- Xem log đồng bộ

**Sao lưu (Backup):**
1. Vào **Cài đặt** > **Sao lưu**
2. Nhấn **"SAO LƯU NGAY"**
3. Chờ quá trình hoàn tất
4. File backup lưu trên Firebase Storage

**Khôi phục (Restore):**
1. Chọn bản backup từ danh sách
2. Nhấn **"KHÔI PHỤC"**
3. Xác nhận (dữ liệu hiện tại sẽ bị ghi đè)

### 11.7 Thông tin tài khoản

1. Vào **Cài đặt** > **Tài khoản**
2. Các tùy chọn:
   - Đổi mật khẩu
   - Cập nhật thông tin cá nhân
   - Đăng xuất
   - Xóa tài khoản (cần xác nhận)

---

## 12. TÍNH NĂNG NÂNG CAO

### 12.1 Quét QR/Barcode

**Sử dụng:**
1. Nhấn icon **📷** hoặc **"QUÉT QR"**
2. Đưa camera vào mã QR/barcode
3. Hệ thống tự động nhận diện và xử lý

**Các loại mã hỗ trợ:**
- QR Code sản phẩm
- Barcode IMEI
- QR thanh toán ngân hàng
- Mã nhập nhanh tự tạo

### 12.2 Mã nhập nhanh

**Tạo mã nhập nhanh:**
1. Vào **Cài đặt** > **Mã nhập nhanh**
2. Nhấn **"+ TẠO MÃ"**
3. Nhập: Tên mã, nội dung tự động điền
4. Lưu và in QR

**Sử dụng:**
- Quét mã → Thông tin tự động điền vào form

### 12.3 Chat nội bộ

**Mở chat:**
1. Từ Home, nhấn icon **💬**
2. Hoặc vào **Cài đặt** > **Chat**

**Gửi tin nhắn:**
1. Nhập nội dung
2. Nhấn **"GỬI"**

**Tính năng:**
- Gửi text
- Đính kèm hình ảnh
- Liên kết đến đơn hàng/sản phẩm
- Thông báo tin nhắn mới

### 12.4 Tìm kiếm toàn cục

1. Nhấn icon **🔍** trên header
2. Nhập từ khóa
3. Kết quả phân theo:
   - Khách hàng
   - Đơn sửa chữa
   - Đơn bán hàng
   - Sản phẩm
4. Nhấn vào kết quả để xem chi tiết

### 12.5 Đối tác sửa chữa

**Quản lý đối tác bên ngoài** (tiệm khác gửi máy nhờ sửa):

1. Vào **Cài đặt** > **Đối tác sửa chữa**
2. Thêm đối tác mới
3. Tạo phiếu nhận máy từ đối tác
4. Theo dõi lịch sử
5. Thanh toán cho đối tác

---

## 13. XỬ LÝ SỰ CỐ

### 13.1 Không đăng nhập được

**Nguyên nhân có thể:**
- Sai email/mật khẩu
- Tài khoản bị khóa
- Không có kết nối mạng

**Giải pháp:**
1. Kiểm tra lại email/mật khẩu
2. Thử "Quên mật khẩu" để đặt lại
3. Kiểm tra kết nối Internet
4. Liên hệ admin nếu tài khoản bị khóa

### 13.2 Dữ liệu không đồng bộ

**Triệu chứng:**
- Dữ liệu trên các thiết bị không giống nhau
- Icon sync màu đỏ/vàng

**Giải pháp:**
1. Kiểm tra kết nối mạng
2. Nhấn giữ nút Sync để đồng bộ thủ công
3. Đợi 1-2 phút
4. Nếu vẫn lỗi, đăng xuất và đăng nhập lại

### 13.3 Máy in không hoạt động

**Với máy in Bluetooth:**
1. Kiểm tra máy in đã bật
2. Kiểm tra Bluetooth trên điện thoại
3. Thử ngắt kết nối và kết nối lại
4. Kiểm tra pin máy in

**Với máy in WiFi:**
1. Kiểm tra máy in và điện thoại cùng mạng WiFi
2. Kiểm tra địa chỉ IP đúng chưa
3. Thử restart máy in

### 13.4 App chạy chậm

**Giải pháp:**
1. Đóng các app khác
2. Xóa cache app (Cài đặt điện thoại > App > QuanLyShop > Xóa cache)
3. Restart điện thoại
4. Cập nhật app lên phiên bản mới nhất

### 13.5 Mất dữ liệu

**Phòng tránh:**
- Luôn đảm bảo đồng bộ thành công (icon xanh)
- Sao lưu định kỳ

**Khôi phục:**
1. Vào **Cài đặt** > **Sao lưu**
2. Chọn bản backup gần nhất
3. Nhấn **"KHÔI PHỤC"**

---

## 14. CÂU HỎI THƯỜNG GẶP (FAQ)

### Q1: Làm sao để thêm nhân viên mới?
**A:** Vào **Nhân sự** > **+ Thêm nhân viên** > Nhập thông tin > **Tạo tài khoản**. Sau đó phân quyền cho nhân viên.

### Q2: Tôi có thể sử dụng trên nhiều thiết bị không?
**A:** Có. Đăng nhập cùng tài khoản trên nhiều thiết bị, dữ liệu sẽ tự động đồng bộ.

### Q3: Làm sao để xuất báo cáo?
**A:** Vào **Tài chính** > **Báo cáo** > Chọn loại báo cáo > Nhấn icon **📤** > Chọn định dạng (Excel/PDF).

### Q4: Có thể hoàn tác khi xóa nhầm không?
**A:** Hệ thống sử dụng "xóa mềm", một số dữ liệu có thể khôi phục trong vòng 30 ngày. Liên hệ admin để được hỗ trợ.

### Q5: Tại sao tôi không xem được doanh thu?
**A:** Bạn cần được cấp quyền "Xem doanh thu". Liên hệ Chủ shop để được phân quyền.

### Q6: Làm sao để thay đổi giá sản phẩm?
**A:** Vào **Kho** > Chọn sản phẩm > **Sửa** > Thay đổi giá > **Lưu**. Cần quyền "Sửa sản phẩm".

### Q7: Có thể in hóa đơn từ điện thoại không?
**A:** Có. Kết nối máy in nhiệt Bluetooth, sau đó in trực tiếp từ chi tiết đơn hàng.

### Q8: Làm sao để tạo mã QR cho sản phẩm?
**A:** Vào chi tiết sản phẩm > Nhấn icon **QR** > Lưu/in mã QR.

### Q9: Dữ liệu có an toàn không?
**A:** Có. Dữ liệu được mã hóa và lưu trữ trên Firebase với bảo mật cao. Chỉ người dùng được phân quyền mới truy cập được.

### Q10: Làm sao để liên hệ hỗ trợ?
**A:** 
- Vào **Cài đặt** > **Giới thiệu** > **Liên hệ hỗ trợ**
- Hotline: 0909.xxx.xxx
- Email: support@huluca.com

---

## 📞 THÔNG TIN HỖ TRỢ

**Nhà phát triển:** Huluca Tech

**Liên hệ:**
- 📧 Email: support@huluca.com
- 📞 Hotline: 0909.xxx.xxx
- 🌐 Website: www.huluca.com
- 💬 Zalo: 0909.xxx.xxx

**Giờ hỗ trợ:**
- Thứ 2 - Thứ 7: 08:00 - 18:00
- Chủ nhật: 09:00 - 12:00

---

## 📝 LỊCH SỬ CẬP NHẬT TÀI LIỆU

| Phiên bản | Ngày | Nội dung |
|-----------|------|----------|
| 3.4.0 | 01/2026 | Tài liệu hoàn chỉnh lần đầu |

---

*Tài liệu được cập nhật: Tháng 1/2026*  
*Phiên bản app: 3.4.0+10*

---

**🎉 Chúc bạn sử dụng QuanLyShop hiệu quả!**

*Cảm ơn bạn đã tin tưởng và đồng hành cùng chúng tôi.*
