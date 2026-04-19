# Kế hoạch triển khai tính năng mở rộng (v279)

Ngày cập nhật: 2026-04-19
Mục tiêu: triển khai theo thứ tự ưu tiên 1 -> 4, giảm rủi ro hồi quy và giữ tương thích shop cũ.

## Ưu tiên 1 - Dashboard thống kê Firebase Read/Write chi tiết (HOÀN TẤT)

Phạm vi:
- Tạo service tổng hợp số liệu cloud theo collection.
- Tổng hợp write 24h từ `sync_audit_log`.
- Tổng hợp read realtime 24h từ listener (ghi nhận vào local metrics).
- Hiển thị dashboard có thể refresh thủ công.
- Gắn điểm mở từ Trung tâm đồng bộ.

Checklist:
- [x] Thiết kế data model thống kê
- [x] Tạo service thống kê tổng hợp
- [x] Tạo màn hình dashboard Read/Write
- [x] Tích hợp điều hướng từ Sync Center
- [x] Chạy test + build

## Ưu tiên 2 - Module đổi ca (Shift Swap)

Phạm vi dự kiến:
- Danh sách yêu cầu đổi ca.
- Luồng tạo yêu cầu + duyệt/từ chối.
- Audit log và trạng thái realtime.
- Chặn trùng lịch và quyền theo vai trò.

Điều kiện bắt đầu:
- Hoàn tất ưu tiên 1 và xác nhận ổn định build/test.

## Ưu tiên 3 - Màn hình Recent Activity độc lập

Phạm vi dự kiến:
- Tách khỏi card feed hiện tại thành trang riêng.
- Filter theo nghiệp vụ, người thực hiện, mốc thời gian.
- Truy cập nhanh từ Home shortcut/tab tài chính.

Điều kiện bắt đầu:
- Hoàn tất ưu tiên 2.

## Ưu tiên 4 - Màn hình test kết nối Firestore độc lập

Phạm vi dự kiến:
- Reuse dữ liệu từ diagnostics hiện có.
- Thêm step-by-step UI để vận hành tự kiểm tra.
- Nút xuất kết quả chẩn đoán để gửi hỗ trợ.

Điều kiện bắt đầu:
- Hoàn tất ưu tiên 3.

## Nguyên tắc triển khai

- Không sửa `PaymentIntentService` và `SalaryCalculationService` trong chuỗi mở rộng.
- Giữ tương thích ngược với shop cũ.
- Mọi query cloud bắt buộc theo `shopId` (trừ super-admin có context shop rõ ràng).
- Mỗi bước đều chạy test và build debug trước khi phát hành.