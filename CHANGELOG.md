# Changelog

Tất cả thay đổi đáng chú ý của dự án sẽ được ghi lại trong file này.

---

## [10.0.9] - 2026-02-11

### Sửa lỗi & Tối ưu
- Sửa tràn bottom overflow tab Nhật ký tài chính (embedded mode)
- Giới hạn loại hình kinh doanh tạo chi nhánh: chỉ Điện tử & Thời trang
- Đổi mặc định khoảng thời gian từ 30 ngày sang hôm nay (Báo cáo, Nhật ký, Trả góp)
- Sửa 30+ lỗi biên dịch: thiếu khóa đa ngữ, validatePhone, biến sai phạm vi
- Dọn code thừa, xóa import không dùng

### Tối ưu giao diện Tài chính
- Tạo FinancialHubView gộp 4 tab: Báo cáo, Chi phí, Trả góp, Nhật ký
- Thêm chế độ embedded cho 4 view tài chính
- Gộp menu tài chính trang chủ: 10 mục giảm còn 6
- Xóa 2 view mồ côi (transaction_detail, financial_reconciliation)

---

## [10.0.7] - 2026-02-08

### Tính năng mới
- Hoa hồng theo bậc (3 bậc dựa trên giá trị đơn hàng)
- Đơn sửa chữa không cần SĐT khách ngay (nhắc khi giao máy)
- Sửa lỗi tab trang chủ không chuyển ngôn ngữ VI/EN

### Sửa lỗi
- Sửa tính hoa hồng theo bậc, ngày nghỉ âm, ngày làm việc theo cấu hình
- Sửa tab Lịch làm việc trắng (BoxConstraints infinite width)
- Thêm sync work_schedules và employee_salary_settings
- Thêm 28 unit tests cho salary và financial logic

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
