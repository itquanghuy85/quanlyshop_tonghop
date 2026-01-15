# 📋 KỊCH BẢN TEST TOÀN DIỆN - QUẢN LÝ SHOP

## 📌 MỤC LỤC
1. [Thiết lập ban đầu](#1-thiết-lập-ban-đầu)
2. [Quản lý Kho & Sản phẩm](#2-quản-lý-kho--sản-phẩm)
3. [Quản lý Nhà cung cấp](#3-quản-lý-nhà-cung-cấp)
4. [Nhập hàng & Linh kiện](#4-nhập-hàng--linh-kiện)
5. [Bán hàng](#5-bán-hàng)
6. [Sửa chữa](#6-sửa-chữa)
7. [Công nợ](#7-công-nợ)
8. [Chi phí](#8-chi-phí)
9. [Chốt quỹ cuối ngày](#9-chốt-quỹ-cuối-ngày)
10. [Báo cáo tài chính](#10-báo-cáo-tài-chính)
11. [Quản lý nhân sự](#11-quản-lý-nhân-sự)
12. [Chat & Thông báo](#12-chat--thông-báo)
13. [Kiểm tra số liệu tổng hợp](#13-kiểm-tra-số-liệu-tổng-hợp)

---

## 1. THIẾT LẬP BAN ĐẦU

### 1.1 Đăng nhập & Tạo Shop
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 1.1.1 | Mở app, đăng nhập bằng email/password | Vào được màn hình Home |
| 1.1.2 | Kiểm tra tên shop hiển thị | Tên shop đúng với thông tin đã tạo |
| 1.1.3 | Kiểm tra role người dùng (Admin/Owner/Employee) | Hiển thị đúng quyền |

### 1.2 Cấu hình ban đầu
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 1.2.1 | Vào Cài đặt > Thông tin shop | Có thể sửa tên, địa chỉ, SĐT |
| 1.2.2 | Cài đặt máy in | Kết nối thành công với máy in Bluetooth |
| 1.2.3 | Kiểm tra quyền thông báo | Thông báo hoạt động |

---

## 2. QUẢN LÝ KHO & SẢN PHẨM

### 2.1 Thêm sản phẩm mới
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 2.1.1 | Vào Kho > Thêm sản phẩm | Loại: ĐIỆN THOẠI | Form hiển thị đầy đủ |
| 2.1.2 | Nhập thông tin | Tên: iPhone 15 Pro Max 256GB, Giá vốn: 28,000,000đ, Giá bán: 32,000,000đ | Lưu thành công |
| 2.1.3 | Thêm IMEI | IMEI: 123456789012345 | IMEI được ghi nhận |
| 2.1.4 | Kiểm tra số lượng tồn | - | Tồn kho = 1 |

### 2.2 Thêm phụ kiện
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 2.2.1 | Thêm sản phẩm | Loại: PHỤ KIỆN | - |
| 2.2.2 | Nhập thông tin | Tên: Ốp lưng iPhone 15, Giá vốn: 50,000đ, Giá bán: 150,000đ, SL: 20 | Lưu thành công |
| 2.2.3 | Thêm sản phẩm | Tên: Cáp sạc Type-C, Giá vốn: 30,000đ, Giá bán: 100,000đ, SL: 30 | Lưu thành công |

### 2.3 Thêm linh kiện sửa chữa
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 2.3.1 | Thêm sản phẩm | Loại: LINH KIỆN | - |
| 2.3.2 | Nhập màn hình | Tên: Màn hình iPhone 15 Pro Max, Giá vốn: 3,500,000đ, Giá bán: 5,000,000đ, SL: 5 | Lưu thành công |
| 2.3.3 | Nhập pin | Tên: Pin iPhone 15 Pro Max, Giá vốn: 400,000đ, Giá bán: 800,000đ, SL: 10 | Lưu thành công |
| 2.3.4 | Nhập IC | Tên: IC Wifi iPhone, Giá vốn: 200,000đ, Giá bán: 500,000đ, SL: 5 | Lưu thành công |

---

## 3. QUẢN LÝ NHÀ CUNG CẤP

### 3.1 Thêm nhà cung cấp
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 3.1.1 | Vào Kho > Nhà cung cấp > Thêm mới | - | Form hiển thị |
| 3.1.2 | Nhập NCC 1 | Tên: Công ty TNHH Phụ kiện ABC, SĐT: 0901234567, Địa chỉ: 123 Nguyễn Trãi, Q1, TPHCM | Lưu thành công |
| 3.1.3 | Nhập NCC 2 | Tên: Linh kiện Minh Châu, SĐT: 0912345678, Địa chỉ: 456 Lê Văn Sỹ, Q3, TPHCM | Lưu thành công |
| 3.1.4 | Nhập NCC 3 | Tên: Kho sỉ Điện thoại Sài Gòn, SĐT: 0923456789 | Lưu thành công |

---

## 4. NHẬP HÀNG & LINH KIỆN

### 4.1 Nhập hàng từ NCC (Trả ngay)
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 4.1.1 | Vào Kho > Nhập hàng | Chọn NCC: Công ty ABC | - |
| 4.1.2 | Thêm sản phẩm | Ốp lưng iPhone 15 x 10, Giá nhập: 50,000đ | Tổng: 500,000đ |
| 4.1.3 | Chọn thanh toán | TIỀN MẶT - Trả đủ | Quỹ tiền mặt giảm 500,000đ |
| 4.1.4 | Xác nhận | - | Tồn kho tăng 10 |

### 4.2 Nhập hàng từ NCC (Công nợ)
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 4.2.1 | Nhập hàng | Chọn NCC: Linh kiện Minh Châu | - |
| 4.2.2 | Thêm linh kiện | Màn hình iPhone 15 PM x 3, Giá nhập: 3,500,000đ | Tổng: 10,500,000đ |
| 4.2.3 | Chọn thanh toán | CÔNG NỢ - Trả sau | Tạo công nợ Shop nợ NCC |
| 4.2.4 | Xác nhận | - | Công nợ = 10,500,000đ |

### 4.3 Kiểm tra số liệu sau nhập
| Kiểm tra | Giá trị mong đợi |
|----------|------------------|
| Tổng chi tiền mặt | 500,000đ |
| Công nợ Shop nợ NCC | 10,500,000đ |
| Tồn kho Ốp lưng | 30 (20 + 10) |
| Tồn kho Màn hình | 8 (5 + 3) |

---

## 5. BÁN HÀNG

### 5.1 Bán điện thoại (Trả đủ tiền mặt)
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 5.1.1 | Vào Bán hàng > Tạo đơn | - | Form hiển thị |
| 5.1.2 | Nhập khách hàng | Tên: Nguyễn Văn A, SĐT: 0987654321 | - |
| 5.1.3 | Chọn sản phẩm | iPhone 15 Pro Max 256GB, IMEI: 123456789012345 | Giá: 32,000,000đ |
| 5.1.4 | Thêm phụ kiện | Ốp lưng iPhone 15 x 1, Cáp sạc x 1 | +250,000đ |
| 5.1.5 | Tổng đơn | - | 32,250,000đ |
| 5.1.6 | Thanh toán | TIỀN MẶT - Trả đủ | ✓ |
| 5.1.7 | Hoàn tất | - | In hóa đơn |

**Kiểm tra sau bán:**
| Mục | Giá trị |
|-----|---------|
| Doanh thu hôm nay | +32,250,000đ |
| Giá vốn | 28,080,000đ (28M + 50k + 30k) |
| Lợi nhuận gộp | 4,170,000đ |
| Tồn kho iPhone | 0 |
| Tồn kho Ốp lưng | 29 |
| Tồn kho Cáp sạc | 29 |

### 5.2 Bán hàng (Công nợ khách)
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 5.2.1 | Tạo đơn bán | Khách: Trần Văn B, SĐT: 0976543210 | - |
| 5.2.2 | Chọn sản phẩm | Ốp lưng x 5, Cáp sạc x 3 | Tổng: 1,050,000đ |
| 5.2.3 | Thanh toán | CÔNG NỢ - Đặt cọc 500,000đ | Còn nợ: 550,000đ |
| 5.2.4 | Hoàn tất | - | Tạo công nợ Khách nợ Shop |

**Kiểm tra:**
| Mục | Giá trị |
|-----|---------|
| Tiền mặt thu | +500,000đ |
| Công nợ Khách nợ | 550,000đ |
| Doanh thu | +1,050,000đ |

### 5.3 Bán hàng (Trả góp ngân hàng)
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 5.3.1 | Tạo đơn bán | Khách: Lê Thị C, SĐT: 0965432109 | - |
| 5.3.2 | Thêm điện thoại mới | Samsung Galaxy S24 Ultra, Giá: 28,000,000đ | - |
| 5.3.3 | Thanh toán | TRẢ GÓP, Ngân hàng: HD Saison, Đặt cọc: 5,000,000đ | - |
| 5.3.4 | Hoàn tất | - | Ghi nhận trả góp |

---

## 6. SỬA CHỮA

### 6.1 Tiếp nhận đơn sửa chữa
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 6.1.1 | Vào Sửa chữa > Tạo đơn | - | Form tiếp nhận |
| 6.1.2 | Nhập thông tin khách | Tên: Phạm Văn D, SĐT: 0954321098 | - |
| 6.1.3 | Nhập thông tin máy | Model: iPhone 15 Pro Max, IMEI: 999888777666555 | - |
| 6.1.4 | Mô tả lỗi | Vỡ màn hình, cần thay màn | - |
| 6.1.5 | Báo giá | Công thay: 200,000đ, Linh kiện: 5,000,000đ | Tổng: 5,200,000đ |
| 6.1.6 | Đặt cọc | 2,000,000đ (tiền mặt) | Trạng thái: Đang chờ |
| 6.1.7 | Lưu đơn | - | Đơn #R001 tạo thành công |

### 6.2 Cập nhật trạng thái sửa chữa
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 6.2.1 | Chuyển trạng thái: Đang sửa | Badge "Đang sửa" hiển thị |
| 6.2.2 | Chọn linh kiện sử dụng | Màn hình iPhone 15 PM x 1 |
| 6.2.3 | Hoàn thành sửa | Trạng thái: Đã sửa xong |

### 6.3 Giao máy & Thu tiền
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 6.3.1 | Giao máy cho khách | - | - |
| 6.3.2 | Thu tiền còn lại | 3,200,000đ (5,200,000 - 2,000,000 cọc) | TIỀN MẶT |
| 6.3.3 | Xác nhận hoàn tất | - | Trạng thái: Đã giao |

**Kiểm tra sau sửa chữa:**
| Mục | Giá trị |
|-----|---------|
| Doanh thu sửa chữa | +5,200,000đ |
| Giá vốn linh kiện | 3,500,000đ |
| Lợi nhuận | 1,700,000đ |
| Tồn kho Màn hình | 7 (8 - 1) |
| Thu tiền mặt | 5,200,000đ (2M cọc + 3.2M còn lại) |

### 6.4 Sửa chữa - Công nợ
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 6.4.1 | Tạo đơn sửa chữa | Khách: Hoàng Văn E, Lỗi: Thay pin | - |
| 6.4.2 | Báo giá | Công: 100,000đ, Pin: 800,000đ = 900,000đ | - |
| 6.4.3 | Thanh toán | CÔNG NỢ - Không cọc | Công nợ: 900,000đ |
| 6.4.4 | Sửa & giao | - | Khách nợ Shop |

---

## 7. CÔNG NỢ

### 7.1 Kiểm tra danh sách công nợ
| Tab | Số lượng | Tổng tiền |
|-----|----------|-----------|
| Khách nợ Shop | 2 khoản | 1,450,000đ (550k + 900k) |
| Shop nợ NCC | 1 khoản | 10,500,000đ |

### 7.2 Thu nợ khách hàng
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 7.2.1 | Vào Công nợ > Khách nợ | Chọn: Trần Văn B | Nợ: 550,000đ |
| 7.2.2 | Thu nợ | Thu: 300,000đ, TIỀN MẶT | Còn nợ: 250,000đ |
| 7.2.3 | Kiểm tra | - | Tiền mặt +300,000đ |

### 7.3 Trả nợ NCC
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 7.3.1 | Vào Công nợ > Shop nợ NCC | Chọn: Linh kiện Minh Châu | Nợ: 10,500,000đ |
| 7.3.2 | Trả nợ | Trả: 5,000,000đ, CHUYỂN KHOẢN | Còn nợ: 5,500,000đ |
| 7.3.3 | Kiểm tra | - | Tiền NH -5,000,000đ |

---

## 8. CHI PHÍ

### 8.1 Thêm chi phí
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 8.1.1 | Vào Tài chính > Chi phí > Thêm | - | Form chi phí |
| 8.1.2 | Chi tiền điện | Mô tả: Tiền điện tháng 1, Số tiền: 2,000,000đ, TIỀN MẶT | ✓ |
| 8.1.3 | Chi tiền thuê mặt bằng | Mô tả: Thuê mặt bằng T1, Số tiền: 15,000,000đ, CHUYỂN KHOẢN | ✓ |
| 8.1.4 | Chi tạp phí | Mô tả: Mua đồ văn phòng, Số tiền: 500,000đ, TIỀN MẶT | ✓ |

**Tổng chi phí hôm nay:**
| Loại | Số tiền |
|------|---------|
| Tiền mặt | 2,500,000đ |
| Chuyển khoản | 15,000,000đ |
| **Tổng** | **17,500,000đ** |

---

## 9. CHỐT QUỸ CUỐI NGÀY

### 9.1 Chuẩn bị dữ liệu test (Tổng hợp từ các bước trên)

**THU (Tiền mặt):**
| Nguồn | Số tiền |
|-------|---------|
| Bán iPhone + phụ kiện | 32,250,000đ |
| Bán hàng - đặt cọc | 500,000đ |
| Sửa chữa - đặt cọc | 2,000,000đ |
| Sửa chữa - thu còn lại | 3,200,000đ |
| Thu nợ Trần Văn B | 300,000đ |
| **Tổng THU tiền mặt** | **38,250,000đ** |

**CHI (Tiền mặt):**
| Mục | Số tiền |
|-----|---------|
| Nhập hàng từ NCC | 500,000đ |
| Chi phí tiền điện | 2,000,000đ |
| Chi phí tạp phí | 500,000đ |
| **Tổng CHI tiền mặt** | **3,000,000đ** |

**Quỹ tiền mặt cuối ngày:** 38,250,000 - 3,000,000 = **35,250,000đ**

### 9.2 Thực hiện chốt quỹ
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 9.2.1 | Vào Tài chính > Chốt quỹ | Hiển thị tổng quan |
| 9.2.2 | Kiểm tra Quỹ đầu ngày | 0đ (ngày đầu tiên) |
| 9.2.3 | Kiểm tra Tổng thu tiền mặt | 38,250,000đ |
| 9.2.4 | Kiểm tra Tổng chi tiền mặt | 3,000,000đ |
| 9.2.5 | Kiểm tra Quỹ cuối ngày (tính) | 35,250,000đ |
| 9.2.6 | Nhập Tiền thực đếm | 35,250,000đ |
| 9.2.7 | Kiểm tra Chênh lệch | 0đ |
| 9.2.8 | Xác nhận chốt quỹ | ✓ Chốt thành công |

### 9.3 Kiểm tra sau chốt quỹ
| Mục | Giá trị mong đợi |
|-----|------------------|
| Lịch sử chốt quỹ | Có 1 bản ghi |
| Quỹ đầu ngày (ngày mai) | 35,250,000đ |

---

## 10. BÁO CÁO TÀI CHÍNH

### 10.1 Báo cáo doanh thu
| Mục | Giá trị |
|-----|---------|
| Doanh thu bán hàng | 33,300,000đ (32,250k + 1,050k) |
| Doanh thu sửa chữa | 6,100,000đ (5,200k + 900k) |
| **Tổng doanh thu** | **39,400,000đ** |

### 10.2 Báo cáo lợi nhuận
| Mục | Giá trị |
|-----|---------|
| Tổng doanh thu | 39,400,000đ |
| Giá vốn hàng bán | 28,330,000đ |
| Giá vốn linh kiện sửa chữa | 3,900,000đ (3,500k + 400k) |
| Chi phí | 17,500,000đ |
| **Lợi nhuận ròng** | **-10,330,000đ** |

### 10.3 Báo cáo công nợ
| Loại | Số tiền |
|------|---------|
| Khách nợ Shop | 1,150,000đ (250k + 900k) |
| Shop nợ NCC | 5,500,000đ |
| **Chênh lệch (Shop phải trả)** | **4,350,000đ** |

---

## 11. QUẢN LÝ NHÂN SỰ

### 11.1 Thêm nhân viên
| Bước | Hành động | Dữ liệu test | Kết quả mong đợi |
|------|-----------|--------------|------------------|
| 11.1.1 | Vào Nhân sự > Mời nhân viên | - | Form mời |
| 11.1.2 | Nhập email | nhanvien1@test.com | - |
| 11.1.3 | Chọn vai trò | Nhân viên (employee) | - |
| 11.1.4 | Gửi lời mời | - | Gửi thành công |

### 11.2 Phân quyền
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 11.2.1 | Chọn nhân viên > Phân quyền | Hiển thị danh sách quyền |
| 11.2.2 | Bật: Xem bán hàng | ✓ |
| 11.2.3 | Bật: Xem sửa chữa | ✓ |
| 11.2.4 | Tắt: Xem tài chính | ✗ |
| 11.2.5 | Lưu | Quyền được cập nhật |

### 11.3 Chấm công
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 11.3.1 | Nhân viên check-in | Ghi nhận giờ vào |
| 11.3.2 | Nhân viên check-out | Ghi nhận giờ ra |
| 11.3.3 | Xem lịch sử chấm công | Hiển thị đầy đủ |

---

## 12. CHAT & THÔNG BÁO

### 12.1 Gửi tin nhắn
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 12.1.1 | Vào Chat | Hiển thị danh sách chat |
| 12.1.2 | Chọn nhân viên | Mở cửa sổ chat |
| 12.1.3 | Gửi tin nhắn văn bản | Tin nhắn gửi thành công |
| 12.1.4 | Gửi hình ảnh | Ảnh tải lên thành công |
| 12.1.5 | React tin nhắn | Reaction hiển thị |
| 12.1.6 | Reply tin nhắn | Reply hiển thị đúng |

### 12.2 Thông báo
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 12.2.1 | Tạo đơn sửa chữa mới | Thông báo đến Admin |
| 12.2.2 | Hoàn thành sửa chữa | Thông báo đến khách (nếu có) |
| 12.2.3 | Kiểm tra badge thông báo | Số đúng với thông báo chưa đọc |

---

## 13. KIỂM TRA SỐ LIỆU TỔNG HỢP

### 13.1 Dashboard Home
| Mục | Giá trị mong đợi |
|-----|------------------|
| Đơn sửa chữa đang chờ | 0 |
| Đơn bán hàng hôm nay | 3 |
| Doanh thu hôm nay | 39,400,000đ |
| Chi phí hôm nay | 17,500,000đ |
| Công nợ còn | 1,150,000đ |

### 13.2 Kiểm tra tồn kho cuối ngày
| Sản phẩm | Tồn đầu | Nhập | Bán/Dùng | Tồn cuối |
|----------|---------|------|----------|----------|
| iPhone 15 Pro Max | 1 | 0 | 1 | 0 |
| Ốp lưng iPhone 15 | 20 | 10 | 6 | 24 |
| Cáp sạc Type-C | 30 | 0 | 4 | 26 |
| Màn hình iPhone 15 PM | 5 | 3 | 1 | 7 |
| Pin iPhone 15 PM | 10 | 0 | 1 | 9 |
| IC Wifi iPhone | 5 | 0 | 0 | 5 |

### 13.3 Kiểm tra đồng bộ dữ liệu
| Bước | Hành động | Kết quả mong đợi |
|------|-----------|------------------|
| 13.3.1 | Đăng xuất & đăng nhập lại | Dữ liệu giữ nguyên |
| 13.3.2 | Kiểm tra Firestore | Dữ liệu đồng bộ đúng |
| 13.3.3 | Offline mode | App hoạt động bình thường |
| 13.3.4 | Online lại | Sync dữ liệu thành công |

---

## 📊 BẢNG TỔNG HỢP KẾT QUẢ TEST

### Checklist hoàn thành
- [ ] 1. Thiết lập ban đầu (3 test cases)
- [ ] 2. Quản lý Kho & Sản phẩm (7 test cases)
- [ ] 3. Quản lý Nhà cung cấp (4 test cases)
- [ ] 4. Nhập hàng & Linh kiện (8 test cases)
- [ ] 5. Bán hàng (12 test cases)
- [ ] 6. Sửa chữa (10 test cases)
- [ ] 7. Công nợ (6 test cases)
- [ ] 8. Chi phí (4 test cases)
- [ ] 9. Chốt quỹ cuối ngày (8 test cases)
- [ ] 10. Báo cáo tài chính (3 test cases)
- [ ] 11. Quản lý nhân sự (8 test cases)
- [ ] 12. Chat & Thông báo (6 test cases)
- [ ] 13. Kiểm tra số liệu tổng hợp (6 test cases)

**Tổng: 85 test cases**

---

## 🔄 KỊCH BẢN TEST NGÀY 2

Để test chức năng liên tục qua nhiều ngày:

### Ngày 2 - Kiểm tra
| Mục | Kiểm tra |
|-----|----------|
| Quỹ đầu ngày | = Quỹ cuối ngày 1 (35,250,000đ) |
| Doanh thu ngày 1 | Vẫn hiển thị đúng trong báo cáo |
| Công nợ | Vẫn còn đúng số |
| Filter theo ngày | Hoạt động đúng |

---

## 📝 GHI CHÚ

1. **Thứ tự test**: Nên test theo thứ tự từ 1-13 để đảm bảo dữ liệu liên kết đúng
2. **Reset data**: Có thể xóa app và cài lại để test từ đầu
3. **Multi-user test**: Test với 2 thiết bị cùng lúc để kiểm tra sync
4. **Edge cases**: Test với số tiền 0, số âm, text dài, ký tự đặc biệt

---

*Tạo bởi AI Assistant - Cập nhật: 15/01/2026*
