# Tiến Trình Sync Observability

Cập nhật: 2026-04-19

## Mục tiêu tổng thể
- Hoàn tất minh bạch trạng thái sync cho 4 nhóm: tài chính, đơn sửa, kho, bán hàng.
- Có lịch sử thành công/lỗi bền vững để truy vết sau khi queue đã xóa item completed.
- Có cảnh báo kẹt sync chủ động + xuất báo cáo để hỗ trợ vận hành production.

## Checklist phase
- [x] Phase 1: Báo cáo theo domain từ queue + local unsynced + mismatch + mốc sync cloud.
- [x] Phase 2: Ghi lịch sử sync bền vững (thành công/lỗi/retry) và hiển thị vào domain report.
- [x] Phase 3: Cảnh báo kẹt sync chủ động + xuất báo cáo vận hành.

## Nhật ký thực thi
### Bước 0 - Chuyển nhánh làm việc
- [x] Fast-forward từ test/v262-firebase-iphone sang master.
- [x] Push master lên origin.
- [x] Tiếp tục phát triển trực tiếp trên master.

### Bước 1 - Triển khai Phase 2
- [x] Tạo dịch vụ `sync_audit_log` lưu sự kiện success/retry/failed.
- [x] Tích hợp log success/failure từ SyncOrchestrator.
- [x] Nối dữ liệu audit vào Domain Sync Report (thống kê 24h + mốc gần nhất).
- [x] Hiển thị thống kê success/lỗi/retry trong Sync Center.
- [x] Build + test: `flutter test` (552 tests passed) + `flutter build apk --debug --no-pub` (thành công).
- [x] Commit + push bước Phase 2.

### Bước 2 - Triển khai Phase 3
- [x] Bổ sung cảnh báo kẹt sync chủ động theo domain (pending/processing quá 20 phút).
- [x] Hiển thị banner cảnh báo vận hành tổng hợp trong Sync Center.
- [x] Tạo chức năng xuất báo cáo sync Markdown + mở/chia sẻ trực tiếp.
- [x] Build + test: `flutter test` (552 tests passed) + `flutter build apk --debug --no-pub` (thành công).
- [x] Commit + push bước Phase 3.

### Bước 3 - Chốt Firebase-only (loại bỏ MongoDB)
- [x] Xóa thư mục local `backend/` khỏi workspace để tránh chạy nhầm luồng Mongo/API cũ.
- [x] Thêm guard runtime trong `main.dart` để cảnh báo và bỏ qua các `dart-define` cũ: `LOCAL_API_BASE_URL`, `MONGODB_URI`, `USE_MONGO`.
- [x] Dọn wording gây hiểu nhầm backend trong luồng cập nhật danh mục.
- [x] Build + test: `flutter test` (552 tests passed) + `flutter build apk --debug --no-pub` (thành công).
- [x] Commit + push bước Firebase-only.
