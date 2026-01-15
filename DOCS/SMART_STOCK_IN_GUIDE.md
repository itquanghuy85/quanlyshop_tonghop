# Hướng Dẫn Sử Dụng - Hệ Thống Nhập Kho Thông Minh (Kho Tạm)

## 📋 Tổng Quan

Hệ thống **Nhập Kho Thông Minh** cho phép nhập hàng vào kho với 2 chế độ:
- **Nhập nhanh (Quick)**: Nhập đầy đủ thông tin và xác nhận ngay
- **Nhập tạm (Staging)**: Nhập tạm khi chưa có đầy đủ thông tin, xác nhận sau

## 🎯 Lợi Ích

1. **Tránh thiếu sót dữ liệu** - Có thể nhập tạm khi bận, bổ sung sau
2. **Theo dõi hàng chờ** - Dashboard hiển thị badge cảnh báo hàng chờ xác nhận
3. **Atomic transaction** - Khi xác nhận, tất cả dữ liệu được ghi đồng thời
4. **Đa loại sản phẩm** - Hỗ trợ Điện thoại, Phụ kiện, Linh kiện

## 🚀 Cách Sử Dụng

### 1. Mở Form Nhập Kho

Từ **Tab Kho** → Nhấn nút **NHẬP MỚI** (màu xanh lá)

### 2. Chọn Loại Sản Phẩm

- 📱 **Điện thoại** - Hiển thị fields: IMEI, Hãng, Model, Dung lượng, Màu sắc, Tình trạng
- 🎧 **Phụ kiện** - Hiển thị fields: SKU, Đơn vị, Số lượng
- 🔧 **Linh kiện** - Tương tự Phụ kiện

### 3. Nhập Thông Tin

#### Thông tin bắt buộc để XÁC NHẬN:
- ✅ Tên sản phẩm
- ✅ Giá vốn
- ✅ Nhà cung cấp
- ✅ Phương thức thanh toán

#### Thông tin bắt buộc để LƯU TẠM:
- ✅ Chỉ cần Tên sản phẩm

### 4. Hai Tùy Chọn Lưu

| Nút | Mô tả | Khi nào dùng |
|-----|-------|--------------|
| **LƯU TẠM** | Lưu dạng DRAFT, chưa vào kho | Khi chưa có đầy đủ thông tin |
| **LƯU & XÁC NHẬN** | Xác nhận ngay, hàng vào kho | Khi đã có đầy đủ thông tin |

### 5. Quản Lý Hàng Chờ

Từ **Tab Kho** → **Hàng chờ xác nhận** hoặc nhấn vào widget cam trên đầu tab

- 👁️ **Xem danh sách** phiếu DRAFT
- ✏️ **Chỉnh sửa** để bổ sung thông tin
- ✅ **Xác nhận** khi đã đủ thông tin
- ❌ **Hủy** nếu không cần nữa

## ⚙️ Quy Trình Xác Nhận (Atomic)

Khi nhấn **XÁC NHẬN**, hệ thống sẽ:

1. ✅ Tạo sản phẩm trong collection `products`
2. ✅ Ghi log tài chính vào `financial_activities`
3. ✅ Tạo công nợ NCC (nếu chọn CÔNG NỢ)
4. ✅ Cập nhật trạng thái phiếu = CONFIRMED
5. ✅ Khóa phiếu (locked = true)

> **Quan trọng**: Tất cả bước trên xảy ra trong 1 transaction - nếu bất kỳ bước nào fail, toàn bộ sẽ rollback.

## 📱 Widget Dashboard

Widget **"Hàng chờ xác nhận"** sẽ tự động hiển thị khi có phiếu DRAFT:

- 🔴 Badge số lượng phiếu chờ
- 📊 Thống kê theo loại (📱ĐT, 🎧PK, 🔧LK)
- ⚠️ Cảnh báo phiếu quá hạn (>3 ngày)

## 🎨 Phân Biệt Màu Sắc

| Màu | Ý nghĩa |
|-----|---------|
| 🟢 Xanh lá | Đã đủ thông tin, có thể xác nhận |
| 🟠 Cam | Chưa đủ thông tin |
| 🔴 Đỏ | Phiếu quá 7 ngày chưa xác nhận |

## ⚠️ Lưu Ý Quan Trọng

1. **IMEI không unique** - Hệ thống CHO PHÉP nhập trùng IMEI
2. **Không thể sửa sau xác nhận** - Phiếu CONFIRMED sẽ bị khóa
3. **Không thể xóa** - Chỉ có thể HỦY phiếu DRAFT
4. **Financial tracking** - Mọi nhập kho đều được ghi log tài chính

## 🔧 Firestore Collections

| Collection | Mô tả |
|------------|-------|
| `stock_entries` | Phiếu nhập kho (DRAFT/CONFIRMED/CANCELLED) |
| `products` | Sản phẩm đã xác nhận |
| `financial_activities` | Log tài chính |
| `supplier_debts` | Công nợ NCC |

## 📝 Ví Dụ Thực Tế

### Scenario 1: Nhập điện thoại đầy đủ thông tin
1. Chọn 📱 Điện thoại
2. Nhập: IPHONE 15 PRO MAX, IMEI, Hãng, Model, Dung lượng, Màu, Tình trạng
3. Nhập: Giá vốn 25000k, Giá bán 28000k
4. Chọn NCC, Phương thức thanh toán
5. Nhấn **LƯU & XÁC NHẬN** → Hàng vào kho ngay

### Scenario 2: Nhập hàng lúc bận, bổ sung sau
1. Chọn 📱 Điện thoại
2. Nhập nhanh: IPHONE 15 PRO MAX
3. Nhấn **LƯU TẠM** → Phiếu DRAFT được tạo
4. Sau đó vào **Hàng chờ xác nhận**
5. Chỉnh sửa bổ sung: IMEI, giá, NCC...
6. Nhấn **XÁC NHẬN** → Hàng vào kho

---

*Hệ thống được thiết kế bởi Huluca Tech - © 2025*
