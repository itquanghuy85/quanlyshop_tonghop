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

## Ưu tiên 2 - Module đổi ca (Shift Swap) (HOÀN TẤT)

Phạm vi dự kiến:
- Danh sách yêu cầu đổi ca.
- Luồng tạo yêu cầu + duyệt/từ chối.
- Audit log và trạng thái realtime.
- Chặn trùng lịch và quyền theo vai trò.

Kết quả đã hoàn tất:
- Đã có màn hình `ShiftSwapView` cho nhân viên tạo yêu cầu và quản lý duyệt/từ chối.
- Đã có service shop-scoped `ShiftSwapService` (create/list/approve/reject/cancel).
- Đã tích hợp điểm mở từ màn hình chấm công cá nhân và quản lý chấm công.
- Đã chạy test + build debug thành công trước khi phát hành.

## Ưu tiên 3 - Màn hình Recent Activity độc lập (HOÀN TẤT)

Phạm vi dự kiến:
- Tách khỏi card feed hiện tại thành trang riêng.
- Filter theo nghiệp vụ, người thực hiện, mốc thời gian.
- Truy cập nhanh từ Home shortcut/tab tài chính.

Kết quả đã hoàn tất:
- Đã có màn hình `RecentActivityView` độc lập, lọc theo nguồn và mốc thời gian.
- Đã tổng hợp dữ liệu từ financial activity log + sync audit + audit logs.
- Đã tích hợp điểm mở từ shortcut hoạt động và thẻ Activity Feed trên Home.
- Đã chạy test + build debug thành công trước khi phát hành.

## Ưu tiên 4 - Màn hình test kết nối Firestore độc lập (HOÀN TẤT)

Phạm vi dự kiến:
- Reuse dữ liệu từ diagnostics hiện có.
- Thêm step-by-step UI để vận hành tự kiểm tra.
- Nút xuất kết quả chẩn đoán để gửi hỗ trợ.

Kết quả đã hoàn tất:
- Đã có màn hình `FirestoreConnectivityTestView` độc lập, hiển thị step-by-step checklist.
- Đã có phần tổng quan, cảnh báo/lỗi/khuyến nghị và copy báo cáo để hỗ trợ vận hành.
- Đã tích hợp điểm mở từ Trung tâm đồng bộ.
- Đã chạy test + build debug thành công trước khi phát hành.

## Nguyên tắc triển khai

- Không sửa `PaymentIntentService` và `SalaryCalculationService` trong chuỗi mở rộng.
- Giữ tương thích ngược với shop cũ.
- Mọi query cloud bắt buộc theo `shopId` (trừ super-admin có context shop rõ ràng).
- Mỗi bước đều chạy test và build debug trước khi phát hành.