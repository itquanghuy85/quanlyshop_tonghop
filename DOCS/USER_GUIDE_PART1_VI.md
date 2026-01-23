# 📱 HƯỚNG DẪN SỬ DỤNG QUANLYSHOP - PHẦN 1

> **Phần mềm Quản lý Tiệm Sửa chữa & Mua bán Điện thoại**  
> Tài liệu training cho người dùng mới

---

## 📋 MỤC LỤC PHẦN 1

1. [Giới thiệu chung](#1-giới-thiệu-chung)
2. [Đăng ký & Đăng nhập](#2-đăng-ký--đăng-nhập)
3. [Màn hình chính (Home)](#3-màn-hình-chính-home)
4. [Module Bán hàng](#4-module-bán-hàng)
5. [Module Sửa chữa](#5-module-sửa-chữa)
6. [Module Khách hàng](#6-module-khách-hàng)

---

## 1. GIỚI THIỆU CHUNG

### 1.1 Ứng dụng QuanLyShop là gì?

**QuanLyShop** là phần mềm quản lý toàn diện dành cho các cửa hàng sửa chữa và mua bán điện thoại. Ứng dụng giúp bạn:

- 📱 **Quản lý bán hàng**: Tạo hóa đơn, theo dõi doanh thu, quản lý trả góp
- 🔧 **Quản lý sửa chữa**: Tiếp nhận máy, theo dõi tiến độ, quản lý bảo hành
- 📦 **Quản lý kho**: Nhập/xuất hàng, kiểm kê, theo dõi tồn kho
- 💰 **Quản lý tài chính**: Doanh thu, chi phí, công nợ, báo cáo
- 👥 **Quản lý nhân sự**: Nhân viên, chấm công, tính lương
- 🖨️ **In hóa đơn**: Hỗ trợ máy in nhiệt Bluetooth/WiFi

### 1.2 Yêu cầu thiết bị

| Nền tảng | Yêu cầu tối thiểu |
|----------|-------------------|
| Android | Android 6.0 trở lên |
| iOS | iOS 12.0 trở lên |
| Web | Chrome, Firefox, Safari mới nhất |

### 1.3 Cài đặt ứng dụng

**Trên Android:**
1. Tải file APK từ link được cung cấp
2. Cho phép "Cài đặt từ nguồn không xác định" trong Cài đặt
3. Mở file APK và nhấn "Cài đặt"

**Trên iOS:**
1. Liên hệ quản trị viên để được cấp quyền TestFlight
2. Mở TestFlight và cài đặt ứng dụng

**Trên Web:**
1. Truy cập địa chỉ web được cung cấp
2. Đăng nhập và sử dụng ngay

---

## 2. ĐĂNG KÝ & ĐĂNG NHẬP

### 2.1 Đăng ký tài khoản mới

> **Lưu ý:** Chỉ chủ cửa hàng mới cần đăng ký. Nhân viên sẽ được chủ shop tạo tài khoản.

**Các bước đăng ký:**

1. Mở ứng dụng, nhấn **"ĐĂNG KÝ"**
2. Điền thông tin:
   - **Email**: Địa chỉ email hợp lệ (sẽ dùng để đăng nhập)
   - **Mật khẩu**: Tối thiểu 6 ký tự
   - **Xác nhận mật khẩu**: Nhập lại mật khẩu
   - **Tên cửa hàng**: Tên shop của bạn
   - **Số điện thoại**: Số liên hệ
3. Nhấn **"ĐĂNG KÝ"**
4. Kiểm tra email và xác nhận (nếu được yêu cầu)
5. Đăng nhập với email và mật khẩu đã tạo

### 2.2 Đăng nhập

1. Mở ứng dụng
2. Nhập **Email** và **Mật khẩu**
3. Nhấn **"ĐĂNG NHẬP"**

**Quên mật khẩu?**
1. Nhấn **"Quên mật khẩu?"** trên màn hình đăng nhập
2. Nhập email đã đăng ký
3. Kiểm tra email và làm theo hướng dẫn đặt lại mật khẩu

### 2.3 Màn hình giới thiệu (Intro)

Lần đầu đăng nhập, bạn sẽ thấy màn hình giới thiệu các tính năng:
- Vuốt sang trái để xem tiếp
- Nhấn **"Bỏ qua"** để vào app ngay
- Nhấn **"Bắt đầu"** ở slide cuối

---

## 3. MÀN HÌNH CHÍNH (HOME)

### 3.1 Tổng quan giao diện

Màn hình Home gồm các phần:

```
┌─────────────────────────────────────┐
│  🔔 Thông báo     🔍 Tìm kiếm      │  ← Header
├─────────────────────────────────────┤
│                                     │
│     📊 THỐNG KÊ NHANH               │  ← Dashboard
│     • Doanh thu hôm nay            │
│     • Đơn sửa chưa xong            │
│     • Đơn bán hôm nay              │
│     • Bảo hành sắp hết hạn         │
│                                     │
├─────────────────────────────────────┤
│                                     │
│     📱 SHORTCUTS                    │  ← Phím tắt
│     • Tạo đơn sửa nhanh            │
│     • Bán hàng nhanh               │
│     • Quét QR                       │
│                                     │
├─────────────────────────────────────┤
│  🏠   🛒   🔧   📦   👥   💰   ⚙️  │  ← Bottom Navigation
│ Home Bán  Sửa  Kho  HR  TC  Cài   │
└─────────────────────────────────────┘
```

### 3.2 Thanh điều hướng (Bottom Navigation)

| Icon | Tab | Chức năng |
|------|-----|-----------|
| 🏠 | **Home** | Trang chủ, thống kê tổng quan |
| 🛒 | **Bán hàng** | Quản lý bán hàng, đơn bán |
| 🔧 | **Sửa chữa** | Quản lý đơn sửa chữa |
| 📦 | **Kho** | Quản lý kho hàng, sản phẩm |
| 👥 | **Nhân sự** | Quản lý nhân viên, chấm công |
| 💰 | **Tài chính** | Doanh thu, chi phí, công nợ |
| ⚙️ | **Cài đặt** | Cài đặt shop, hệ thống |

### 3.3 Thống kê Dashboard

**Các chỉ số hiển thị:**
- **Doanh thu hôm nay**: Tổng tiền từ bán hàng + sửa chữa
- **Đơn sửa đang chờ**: Số phiếu sửa chưa hoàn thành
- **Máy bán hôm nay**: Số máy đã bán trong ngày
- **Chi phí hôm nay**: Tổng chi phí phát sinh
- **Công nợ còn lại**: Tổng nợ chưa thu
- **Bảo hành sắp hết**: Số máy bảo hành < 30 ngày

**Nhấn vào mỗi thống kê để xem chi tiết.**

### 3.4 Phím tắt (Shortcuts)

Các phím tắt giúp thao tác nhanh:

| Phím tắt | Chức năng |
|----------|-----------|
| ➕ **Tạo đơn sửa** | Mở form tiếp nhận máy sửa |
| 🛒 **Bán hàng** | Mở form tạo hóa đơn bán |
| 📷 **Quét QR** | Quét mã QR/barcode sản phẩm |
| 📊 **Báo cáo** | Xem báo cáo tài chính |
| 🔔 **Thông báo** | Xem danh sách thông báo |
| 💬 **Chat** | Trò chuyện nội bộ |

### 3.5 Tìm kiếm toàn cục

1. Nhấn icon **🔍** trên header
2. Nhập từ khóa tìm kiếm:
   - Tên khách hàng
   - Số điện thoại
   - Mã IMEI
   - Tên sản phẩm
   - Mã đơn hàng
3. Kết quả hiển thị theo danh mục (Khách hàng, Đơn sửa, Đơn bán, Sản phẩm)
4. Nhấn vào kết quả để xem chi tiết

### 3.6 Thông báo

1. Nhấn icon **🔔** để xem thông báo
2. Các loại thông báo:
   - 📝 Đơn sửa mới
   - ✅ Đơn sửa hoàn thành
   - 🛒 Đơn bán mới
   - 💰 Thanh toán công nợ
   - ⚠️ Cảnh báo hệ thống
3. Nhấn vào thông báo để xem chi tiết
4. Vuốt để xóa thông báo

### 3.7 Đồng bộ dữ liệu

**Nút đồng bộ (Sync):**
- Vị trí: Góc phải header hoặc floating button
- Màu xanh: Đã đồng bộ
- Màu vàng: Đang đồng bộ
- Màu đỏ: Có lỗi đồng bộ

**Cách đồng bộ thủ công:**
1. Nhấn giữ nút Sync
2. Chờ quá trình hoàn tất
3. Kiểm tra trạng thái

> **Tip:** Ứng dụng tự động đồng bộ khi có kết nối mạng. Chỉ cần đồng bộ thủ công khi gặp lỗi.

---

## 4. MODULE BÁN HÀNG

### 4.1 Tổng quan

Module Bán hàng giúp bạn:
- Tạo hóa đơn bán hàng nhanh chóng
- Quản lý danh sách đơn bán
- Theo dõi trả góp ngân hàng
- In hóa đơn nhiệt
- Quản lý bảo hành máy bán

### 4.2 Xem danh sách đơn bán

1. Nhấn tab **🛒 Bán hàng** trên thanh điều hướng
2. Danh sách đơn bán hiển thị theo thời gian (mới nhất trên cùng)

**Bộ lọc danh sách:**
- **Tất cả**: Hiển thị tất cả đơn
- **Hôm nay**: Chỉ đơn trong ngày
- **Tuần này**: Đơn trong 7 ngày qua
- **Tháng này**: Đơn trong tháng

**Tìm kiếm:**
- Nhập tên khách, SĐT, hoặc tên sản phẩm vào ô tìm kiếm

**Thông tin mỗi đơn:**
- Tên khách hàng
- Sản phẩm đã mua
- Tổng tiền
- Ngày bán
- Trạng thái thanh toán

### 4.3 Tạo đơn bán hàng mới

**Bước 1: Mở form tạo đơn**
- Nhấn nút **➕** hoặc **"TẠO ĐƠN BÁN"**

**Bước 2: Nhập thông tin khách hàng**
```
┌─────────────────────────────────────┐
│  👤 THÔNG TIN KHÁCH HÀNG           │
├─────────────────────────────────────┤
│  Tên khách hàng: [________________] │
│  Số điện thoại:  [________________] │
│  Địa chỉ:        [________________] │
└─────────────────────────────────────┘
```
- **Tên khách hàng**: Bắt buộc
- **Số điện thoại**: Bắt buộc (9-12 số)
- **Địa chỉ**: Tùy chọn

> **Tip:** Nếu khách cũ, nhập SĐT sẽ tự động điền thông tin.

**Bước 3: Chọn sản phẩm**

Có 3 cách chọn sản phẩm:

1. **Từ danh sách kho:**
   - Nhấn **"CHỌN SẢN PHẨM"**
   - Tìm kiếm hoặc cuộn danh sách
   - Nhấn vào sản phẩm để chọn

2. **Quét QR/Barcode:**
   - Nhấn icon **📷** quét mã
   - Đưa camera vào mã QR/barcode
   - Sản phẩm tự động được thêm

3. **Nhập IMEI thủ công:**
   - Nhấn **"NHẬP IMEI"**
   - Nhập 5 số cuối IMEI
   - Nhấn **"TÌM"**

**Bước 4: Xác nhận giá bán**
```
┌─────────────────────────────────────┐
│  📱 SẢN PHẨM ĐÃ CHỌN               │
├─────────────────────────────────────┤
│  iPhone 14 Pro Max 256GB Đen       │
│  IMEI: ...12345                    │
│  Giá niêm yết: 25,000,000 đ        │
│  Giá bán:      [24,500,000_____] đ │
│                              [Xóa] │
├─────────────────────────────────────┤
│  [+ THÊM SẢN PHẨM]                 │
└─────────────────────────────────────┘
```
- Có thể điều chỉnh giá bán cho từng sản phẩm
- Nhấn **"Xóa"** để bỏ sản phẩm
- Nhấn **"+ THÊM SẢN PHẨM"** để thêm nhiều sản phẩm

**Bước 5: Nhập chiết khấu và quà tặng (tùy chọn)**
```
┌─────────────────────────────────────┐
│  🎁 KHUYẾN MÃI                     │
├─────────────────────────────────────┤
│  Chiết khấu:  [500,000_________] đ │
│  Quà tặng:    [Ốp lưng, cường lực] │
└─────────────────────────────────────┘
```

**Bước 6: Chọn phương thức thanh toán**
```
┌─────────────────────────────────────┐
│  💳 THANH TOÁN                     │
├─────────────────────────────────────┤
│  ○ Tiền mặt                        │
│  ○ Chuyển khoản                    │
│  ○ Tiền mặt + Chuyển khoản         │
│  ○ Trả góp ngân hàng               │
└─────────────────────────────────────┘
```

**Nếu chọn Trả góp ngân hàng:**
```
┌─────────────────────────────────────┐
│  🏦 THÔNG TIN TRẢ GÓP              │
├─────────────────────────────────────┤
│  Trả trước:    [5,000,000______] đ │
│  PTTT trả trước: [Tiền mặt____▼]   │
│  Ngân hàng 1:  [Home Credit___▼]   │
│  Số tiền vay:  [19,000,000_____] đ │
│  Kỳ hạn:       [12 tháng______▼]   │
│                                     │
│  [+ Thêm ngân hàng thứ 2]          │
└─────────────────────────────────────┘
```

**Bước 7: Nhập bảo hành**
```
┌─────────────────────────────────────┐
│  🛡️ BẢO HÀNH                       │
├─────────────────────────────────────┤
│  Thời gian BH: [12 tháng______▼]   │
│  ○ Không bảo hành                  │
│  ○ 3 tháng                         │
│  ○ 6 tháng                         │
│  ● 12 tháng                        │
│  ○ 24 tháng                        │
└─────────────────────────────────────┘
```

**Bước 8: Ghi chú (tùy chọn)**
- Nhập ghi chú nếu cần: điều kiện bảo hành đặc biệt, yêu cầu của khách...

**Bước 9: Xác nhận và tạo đơn**
```
┌─────────────────────────────────────┐
│  📋 TÓM TẮT ĐƠN HÀNG               │
├─────────────────────────────────────┤
│  Khách hàng: Nguyễn Văn A          │
│  SĐT: 0909123456                   │
│  Sản phẩm: iPhone 14 Pro Max       │
│  Tổng tiền:       24,500,000 đ     │
│  Chiết khấu:         500,000 đ     │
│  ─────────────────────────────     │
│  THANH TOÁN:      24,000,000 đ     │
│  Phương thức: Trả góp              │
│                                     │
│       [HỦY]      [TẠO ĐƠN BÁN]     │
└─────────────────────────────────────┘
```

**Bước 10: In hóa đơn**
- Sau khi tạo đơn, hệ thống hỏi **"In hóa đơn?"**
- Chọn **"In"** để in qua máy in nhiệt
- Chọn **"Bỏ qua"** nếu không cần in

### 4.4 Xem chi tiết đơn bán

1. Trong danh sách đơn bán, nhấn vào đơn cần xem
2. Màn hình chi tiết hiển thị:
   - Thông tin khách hàng
   - Danh sách sản phẩm
   - Tổng tiền, chiết khấu
   - Phương thức thanh toán
   - Thông tin trả góp (nếu có)
   - Thời gian bảo hành

**Các thao tác:**
- **In lại hóa đơn**: Nhấn icon 🖨️
- **Chia sẻ**: Nhấn icon 📤
- **Chỉnh sửa**: Nhấn icon ✏️ (chỉ admin/owner)
- **Xóa**: Nhấn icon 🗑️ (yêu cầu xác nhận mật khẩu)

### 4.5 Quản lý trả góp ngân hàng

**Xem danh sách trả góp:**
1. Vào **Bán hàng** > **Báo cáo trả góp**
2. Hoặc: **Tài chính** > **Trả góp ngân hàng**

**Thông tin hiển thị:**
- Tên khách hàng
- Sản phẩm
- Ngân hàng
- Số tiền vay
- Ngày dự kiến tất toán
- Trạng thái: Chờ tất toán / Đã tất toán

**Cập nhật tất toán:**
1. Nhấn vào đơn trả góp
2. Nhấn **"CẬP NHẬT TẤT TOÁN"**
3. Nhập:
   - Ngày nhận tiền
   - Số tiền thực nhận
   - Phí tất toán (nếu có)
   - Mã giao dịch
4. Nhấn **"XÁC NHẬN"**

### 4.6 In hóa đơn

**Cài đặt máy in:**
1. Vào **Cài đặt** > **Máy in**
2. Chọn loại máy in:
   - **Bluetooth**: Ghép nối máy in Bluetooth
   - **WiFi**: Nhập IP máy in mạng
3. Nhấn **"KIỂM TRA"** để in thử
4. Nhấn **"LƯU"**

**In hóa đơn:**
1. Trong chi tiết đơn bán, nhấn icon 🖨️
2. Hoặc khi tạo đơn xong, chọn **"In"**
3. Chờ máy in xuất hóa đơn

**Tùy chỉnh mẫu hóa đơn:**
1. Vào **Cài đặt** > **Thiết kế hóa đơn**
2. Chỉnh sửa:
   - Logo cửa hàng
   - Thông tin header
   - Nội dung footer
   - Hiển thị/ẩn các trường
3. Nhấn **"LƯU"**

---

## 5. MODULE SỬA CHỮA

### 5.1 Tổng quan

Module Sửa chữa giúp bạn:
- Tiếp nhận máy khách đem sửa
- Theo dõi tiến độ sửa chữa
- Ghi nhận linh kiện sử dụng
- Quản lý trả máy
- Theo dõi bảo hành

### 5.2 Các trạng thái đơn sửa

| Trạng thái | Màu | Mô tả |
|------------|-----|-------|
| 🟠 **Đang sửa** | Cam | Đang trong quá trình sửa |
| 🔵 **Chờ linh kiện** | Xanh dương | Chờ linh kiện/phụ tùng |
| 🟢 **Hoàn thành** | Xanh lá | Sửa xong, chờ khách lấy |
| 🔴 **Đã trả máy** | Đỏ | Đã giao máy cho khách |

### 5.3 Xem danh sách đơn sửa

1. Nhấn tab **🔧 Sửa chữa** trên thanh điều hướng
2. Danh sách hiển thị theo trạng thái

**Bộ lọc:**
- **Tất cả**: Hiển thị tất cả đơn
- **Đang sửa**: Chỉ đơn đang sửa
- **Chờ LK**: Đơn chờ linh kiện
- **Hoàn thành**: Đơn sửa xong
- **Đã trả**: Đơn đã trả máy

**Thông tin mỗi đơn:**
- Tên khách + SĐT
- Model máy + IMEI
- Lỗi máy
- Trạng thái
- Thời gian tiếp nhận

### 5.4 Tiếp nhận máy sửa (Tạo đơn mới)

**Bước 1: Mở form tiếp nhận**
- Nhấn nút **➕** hoặc **"TIẾP NHẬN MÁY"**

**Bước 2: Nhập thông tin khách hàng**
```
┌─────────────────────────────────────┐
│  👤 THÔNG TIN KHÁCH HÀNG           │
├─────────────────────────────────────┤
│  Tên khách hàng*: [_______________] │
│  Số điện thoại*:  [_______________] │
│  Địa chỉ:         [_______________] │
└─────────────────────────────────────┘
```

**Bước 3: Nhập thông tin máy**
```
┌─────────────────────────────────────┐
│  📱 THÔNG TIN MÁY                  │
├─────────────────────────────────────┤
│  Model máy*:  [iPhone 14 Pro Max__] │
│  IMEI (5 số): [12345______________] │
│  Màu sắc:     [Đen_______________▼] │
│  Tình trạng:  [Trầy xước nhẹ______] │
└─────────────────────────────────────┘
```

**Bước 4: Mô tả lỗi máy**
```
┌─────────────────────────────────────┐
│  ❌ MÔ TẢ LỖI                      │
├─────────────────────────────────────┤
│  Lỗi máy*:                         │
│  [Không lên nguồn, có tiếng rơ     │
│   rơ bên trong khi lắc máy         │
│  _________________________________] │
│                                     │
│  💡 Gợi ý: Thay pin, Thay màn,     │
│     Sửa main, Thay IC...           │
└─────────────────────────────────────┘
```

**Bước 5: Liệt kê phụ kiện kèm theo**
```
┌─────────────────────────────────────┐
│  📎 PHỤ KIỆN KÈM THEO              │
├─────────────────────────────────────┤
│  ☑ Sạc                             │
│  ☐ Cáp                             │
│  ☑ Ốp lưng                         │
│  ☐ Tai nghe                        │
│  ☐ Hộp                             │
│  Khác: [SIM Viettel______________] │
└─────────────────────────────────────┘
```

**Bước 6: Chụp ảnh máy (quan trọng!)**
```
┌─────────────────────────────────────┐
│  📷 ẢNH MÁY KHI NHẬN               │
├─────────────────────────────────────┤
│  [Ảnh 1]  [Ảnh 2]  [Ảnh 3]  [+]   │
│                                     │
│  💡 Chụp rõ: mặt trước, sau, các   │
│     vết trầy xước, lỗi hiện tại    │
└─────────────────────────────────────┘
```

> **Quan trọng:** Luôn chụp ảnh máy khi nhận để tránh tranh chấp sau này!

**Bước 7: Ước tính giá (tùy chọn)**
```
┌─────────────────────────────────────┐
│  💰 ƯỚC TÍNH                       │
├─────────────────────────────────────┤
│  Giá dự kiến: [500,000________] đ  │
│  Bảo hành:    [3 tháng________▼]   │
└─────────────────────────────────────┘
```

**Bước 8: Xác nhận và tạo phiếu**
- Nhấn **"TẠO PHIẾU SỬA"**
- In phiếu biên nhận cho khách (nếu cần)

### 5.5 Cập nhật tiến độ sửa chữa

**Mở chi tiết đơn sửa:**
1. Nhấn vào đơn sửa trong danh sách
2. Màn hình chi tiết hiển thị

**Cập nhật trạng thái:**
```
┌─────────────────────────────────────┐
│  📊 TRẠNG THÁI                     │
├─────────────────────────────────────┤
│  Hiện tại: 🟠 Đang sửa             │
│                                     │
│  Chuyển sang:                      │
│  [🔵 Chờ linh kiện]                │
│  [🟢 Hoàn thành    ]               │
└─────────────────────────────────────┘
```

**Ghi nhận linh kiện đã dùng:**
```
┌─────────────────────────────────────┐
│  🔧 LINH KIỆN SỬ DỤNG              │
├─────────────────────────────────────┤
│  [+ THÊM LINH KIỆN]                │
│                                     │
│  • Pin iPhone 14 Pro    x1  150,000│
│  • Keo chống nước       x1   20,000│
│                       ─────────────│
│                   Tổng:    170,000đ│
└─────────────────────────────────────┘
```

Cách thêm linh kiện:
1. Nhấn **"+ THÊM LINH KIỆN"**
2. Chọn từ danh sách linh kiện trong kho
3. Hoặc nhập thủ công: Tên + Giá

**Cập nhật giá dịch vụ:**
```
┌─────────────────────────────────────┐
│  💰 GIÁ DỊCH VỤ                    │
├─────────────────────────────────────┤
│  Công sửa:      [200,000______] đ  │
│  Linh kiện:              170,000 đ │
│                 ───────────────────│
│  TỔNG CỘNG:              370,000 đ │
└─────────────────────────────────────┘
```

**Phân công thợ sửa:**
- Chọn nhân viên phụ trách từ dropdown
- Lưu lại để thống kê hiệu suất

### 5.6 Trả máy cho khách

**Khi máy sửa xong:**

1. Chuyển trạng thái sang **"Hoàn thành"**
2. Liên hệ khách đến lấy máy

**Quy trình trả máy:**

1. **Kiểm tra lại máy** trước mặt khách
2. **Xác nhận thanh toán:**
```
┌─────────────────────────────────────┐
│  💳 THANH TOÁN                     │
├─────────────────────────────────────┤
│  Tổng tiền:           370,000 đ    │
│  Phương thức:                      │
│  ○ Tiền mặt                        │
│  ○ Chuyển khoản                    │
│  ○ Tiền mặt + CK                   │
└─────────────────────────────────────┘
```

3. **Chụp ảnh trả máy:**
```
┌─────────────────────────────────────┐
│  📷 ẢNH MÁY KHI TRẢ                │
├─────────────────────────────────────┤
│  [Ảnh 1]  [Ảnh 2]  [+]             │
│                                     │
│  💡 Chụp ảnh xác nhận tình trạng   │
│     máy khi trả cho khách          │
└─────────────────────────────────────┘
```

4. **Nhấn "TRẢ MÁY"**

5. **In phiếu trả máy** (tùy chọn)

> **Lưu ý:** Một số shop yêu cầu admin duyệt trước khi trả máy. Kiểm tra cài đặt quyền.

### 5.7 Quản lý bảo hành

**Xem danh sách bảo hành:**
1. Từ Home, nhấn **"Siêu trung tâm bảo hành"**
2. Hoặc vào **Sửa chữa** > **Bảo hành**

**Danh sách hiển thị:**
- Tất cả máy còn trong thời hạn bảo hành (từ bán + sửa)
- Sắp xếp theo ngày hết hạn (sắp hết trước)
- Hiển thị số ngày còn lại

**Thông tin mỗi item:**
- Model máy
- Tên khách hàng
- IMEI
- Ngày bắt đầu BH
- Ngày hết hạn
- Thanh progress hiển thị % thời gian còn lại

**Màu sắc cảnh báo:**
- 🟢 Xanh: Còn > 30 ngày
- 🟠 Cam: Còn 10-30 ngày
- 🔴 Đỏ: Còn < 10 ngày

### 5.8 In phiếu biên nhận

**Khi nào in:**
- Khi tiếp nhận máy: In phiếu biên nhận cho khách giữ
- Khi trả máy: In phiếu trả máy (nếu cần)

**Nội dung phiếu biên nhận:**
- Thông tin cửa hàng
- Thông tin khách hàng
- Thông tin máy (model, IMEI, tình trạng)
- Mô tả lỗi
- Phụ kiện kèm theo
- Ngày nhận
- Giá dự kiến (nếu có)
- Chữ ký xác nhận

---

## 6. MODULE KHÁCH HÀNG

### 6.1 Tổng quan

Module Khách hàng giúp bạn:
- Quản lý danh sách khách hàng
- Xem lịch sử giao dịch của khách
- Phân tích khách hàng tiềm năng
- Chăm sóc khách hàng

### 6.2 Xem danh sách khách hàng

1. Từ Home, nhấn **"Khách hàng"**
2. Hoặc vào **Cài đặt** > **Quản lý khách hàng**

**Thông tin hiển thị:**
- Tên khách hàng
- Số điện thoại
- Địa chỉ
- Tổng chi tiêu
- Số lần sửa chữa
- Số lần mua hàng

**Bộ lọc:**
- Tìm theo tên/SĐT
- Lọc khách VIP (chi tiêu cao)
- Lọc khách mới

### 6.3 Xem chi tiết khách hàng

1. Nhấn vào khách hàng trong danh sách
2. Modal hiển thị:

**Tab "Lịch sử sửa chữa":**
- Danh sách các lần đem máy sửa
- Model, lỗi, giá tiền
- Trạng thái

**Tab "Lịch sử mua hàng":**
- Danh sách các lần mua máy
- Sản phẩm, giá tiền
- Phương thức thanh toán

**Thống kê:**
- Tổng chi tiêu
- Số lần sửa chữa
- Số lần mua hàng

### 6.4 Tạo khách hàng mới

Khách hàng được tự động tạo khi:
- Tạo đơn sửa chữa mới
- Tạo đơn bán hàng mới

Hoặc tạo thủ công:
1. Nhấn **"+ THÊM KHÁCH"**
2. Nhập thông tin:
   - Tên khách hàng (bắt buộc)
   - Số điện thoại (bắt buộc)
   - Email (tùy chọn)
   - Địa chỉ (tùy chọn)
   - Ghi chú (tùy chọn)
3. Nhấn **"LƯU"**

### 6.5 Xóa khách hàng

> **Lưu ý:** Chỉ có thể xóa khách hàng KHÔNG có lịch sử giao dịch.

1. Giữ lâu vào khách hàng cần xóa
2. Chọn **"Xóa"**
3. Xác nhận xóa

Nếu khách có lịch sử:
- Hệ thống từ chối xóa
- Hiển thị thông báo: "Không thể xóa khách đã có lịch sử sửa/bán"

---

## 📌 TÓM TẮT PHẦN 1

Trong phần 1, bạn đã học:

✅ **Giới thiệu chung** về ứng dụng QuanLyShop  
✅ **Đăng ký & Đăng nhập** tài khoản  
✅ **Màn hình chính** và cách điều hướng  
✅ **Module Bán hàng**: Tạo đơn, in hóa đơn, quản lý trả góp  
✅ **Module Sửa chữa**: Tiếp nhận máy, cập nhật tiến độ, trả máy  
✅ **Module Khách hàng**: Quản lý và xem lịch sử khách

---

**👉 Tiếp tục đọc [PHẦN 2](USER_GUIDE_PART2_VI.md) để học về:**
- Module Kho hàng
- Module Nhà cung cấp
- Module Tài chính
- Module Nhân sự
- Cài đặt hệ thống

---

*Tài liệu được cập nhật: Tháng 1/2026*  
*Phiên bản app: 3.4.0+10*
