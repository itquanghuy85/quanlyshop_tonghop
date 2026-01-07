# Hướng Dẫn Quản Lý Nhân Viên - Tính Năng Mới

## 🚀 Các Phương Pháp Tối Ưu Hóa Việc Thêm Nhân Viên

### 1. **Thêm Nhân Viên Đơn Lẻ (Cải Tiến)**
- **Tự động tạo mật khẩu mạnh**: Không cần nhập mật khẩu thủ công
- **Mặc định quyền "Nhân viên"**: Giảm lỗi chọn quyền
- **Hiển thị mật khẩu tạm thời**: Dễ dàng chia sẻ với nhân viên

### 2. **Mời Nhân Viên Hàng Loạt**
- **Nhập nhiều email cùng lúc**: Mỗi email một dòng
- **Tự động tạo tài khoản**: Với mật khẩu ngẫu nhiên
- **Gửi lời mời nhanh chóng**: Tiết kiệm thời gian

### 3. **Import Từ File CSV**
- **Hỗ trợ định dạng CSV chuẩn**
- **Import hàng loạt**: Hàng chục đến hàng trăm nhân viên
- **Tự động mapping dữ liệu**: Email, tên, SĐT, địa chỉ, quyền

## 📋 Định Dạng File CSV

File CSV cần có các cột theo thứ tự:
```
Email,Họ tên,Số điện thoại,Địa chỉ,Quyền
```

**Ví dụ:**
```csv
Email,Họ tên,Số điện thoại,Địa chỉ,Quyền
nguyenvana@example.com,Nguyễn Văn A,0987654321,Hà Nội,employee
tranthib@example.com,Trần Thị B,0987654322,Hồ Chí Minh,technician
```

**Các quyền hợp lệ:**
- `employee` - Nhân viên
- `technician` - Kỹ thuật
- `manager` - Quản lý

## 🔧 Cách Sử Dung

1. **Thêm đơn lẻ**: Nhấn nút "Thêm nhân viên" → Điền thông tin → Chọn "Tự động tạo mật khẩu mạnh"
2. **Mời hàng loạt**: Nhấn nút "Mời hàng loạt" → Nhập emails → Chọn quyền mặc định → Gửi
3. **Import CSV**: Nhấn nút "Import CSV" → Chọn file → Xem preview → Import

## 📊 Ưu Điểm So Với Cách Cũ

| Phương Pháp Cũ | Phương Pháp Mới |
|---|---|
| Nhập từng người một | Thêm hàng loạt |
| Tự nghĩ mật khẩu | Tự động tạo mạnh |
| Dễ quên/chia sẻ mật khẩu | Hiển thị ngay mật khẩu tạm thời |
| Chỉ thêm thủ công | Hỗ trợ import từ file |

## ⚠️ Lưu Ý Quan Trọng

- **Mật khẩu tạm thời**: Nhân viên cần đổi mật khẩu sau lần đầu đăng nhập
- **Email hợp lệ**: Đảm bảo email đúng định dạng
- **Quyền mặc định**: Có thể thay đổi sau khi tạo tài khoản
- **File CSV**: Đảm bảo encoding UTF-8 để hỗ trợ tiếng Việt

## 🎯 Khuyến Nghị

1. **Dùng import CSV** cho số lượng lớn (>10 nhân viên)
2. **Dùng mời hàng loạt** cho số lượng trung bình (2-10 nhân viên)
3. **Dùng thêm đơn lẻ** khi cần tùy chỉnh chi tiết

File mẫu: `sample_staff_import.csv`