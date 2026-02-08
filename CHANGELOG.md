# Changelog

Tất cả thay đổi đáng chú ý của dự án sẽ được ghi lại trong file này.

---

## [10.0.6] - 2026-02-08

### ✨ Tính năng mới

#### 1. Hoa hồng theo bậc (Tiered Commission)
- Thêm loại hoa hồng mới "Theo bậc" cho nhân viên bán hàng
- Cấu hình 3 bậc dựa trên giá trị đơn hàng:
  - Bậc 1: Đơn hàng dưới 10 triệu → 20,000đ/đơn
  - Bậc 2: Đơn hàng 10-50 triệu → 50,000đ/đơn
  - Bậc 3: Đơn hàng trên 50 triệu → 100,000đ/đơn
- Hỗ trợ cài đặt riêng cho từng nhân viên hoặc mặc định toàn shop

#### 2. Đơn sửa chữa linh hoạt
- Cho phép tạo đơn sửa chữa mà không cần nhập SĐT khách ngay
- Yêu cầu cập nhật thông tin khách hàng trước khi giao máy
- Hiển thị dialog nhắc nhở khi chốt đơn chưa có thông tin khách

#### 3. Đa ngữ cải tiến
- Sửa lỗi các tab trang chủ không chuyển ngôn ngữ khi đổi VI↔EN
- Tab "TRANG CHỦ", "BÁN", "KHO"... giờ hiển thị đúng ngôn ngữ đã chọn

### 🐛 Sửa lỗi

#### Tính lương & Hoa hồng
- Sửa lỗi tính hoa hồng theo bậc với giá trị đơn hàng thực tế
- Sửa lỗi số ngày nghỉ (absentDays) âm khi NV làm nhiều hơn ngày chuẩn
- Tính ngày làm việc theo cấu hình workDays của nhân viên (T2-CN tùy chọn)

#### Tab Lịch làm việc (Trung tâm hoạt động)
- Sửa lỗi tab "LỊCH LÀM VIỆC" hiển thị trắng (BoxConstraints infinite width)
- Đơn giản hóa layout để tương thích tốt hơn

#### Real-time Sync
- Thêm sync cho `work_schedules` và `employee_salary_settings`
- Cập nhật cài đặt lương đồng bộ giữa các thiết bị

### 📚 Tài liệu
- Thêm `MULTI_INDUSTRY_EXPANSION_GUIDE.md` - Hướng dẫn mở rộng đa ngành
- Cập nhật `DEVELOPER_ONBOARDING.md` với link tài liệu mới
- Cập nhật `copilot-instructions.md` với hướng dẫn mở rộng

### 🧪 Tests
- Thêm 28 unit tests cho salary và financial logic
- Test coverage cho tiered commission, attendance, deductions

---

## [10.0.5] - 2026-02-05

### Sửa lỗi
- Fix thanh toán trực tiếp
- Sửa đơn bán
- Cải thiện nhập kho

---

## [10.0.4] và trước đó

Xem git log để biết chi tiết các phiên bản trước.

---

*Ghi chú: Phiên bản theo format `major.minor.patch+build`*
