# TÀI LIỆU NGHIỆP VỤ TỔNG QUAN DỰ ÁN QUẢN LÝ SHOP

Cập nhật: 2026-05-01
Phiên bản tham chiếu: 1.0.5+523

## 1) Mục tiêu hệ thống

Ứng dụng hỗ trợ vận hành cửa hàng theo mô hình local-first + cloud-sync:
- Quản lý sửa chữa, bán hàng, kho, công nợ, tài chính, nhân sự.
- Làm việc ổn khi mất mạng (ghi local), tự đồng bộ lại khi có mạng.
- Hỗ trợ đa thiết bị, đa vai trò, đa ngành hàng.

## 2) Bức tranh tổng thể kiến trúc

- Frontend: Flutter (Android/iOS/Web/Desktop).
- Xác thực: Firebase Auth.
- Cloud data: Firestore + Storage + Functions.
- Local data: SQLite qua DBHelper.
- Đồng bộ:
  - SyncOrchestrator: local -> cloud (hàng đợi, retry).
  - SyncService: cloud -> local (real-time listeners).

## 3) Module nghiệp vụ chính

### 3.1 Sửa chữa
- Tạo đơn sửa, cập nhật trạng thái, giao máy.
- Theo dõi chi phí linh kiện, doanh thu sửa chữa.

### 3.2 Bán hàng
- Bán lẻ, hỗ trợ nhiều phương thức thanh toán.
- Ghi nhận doanh thu và ảnh hưởng tồn kho.

### 3.3 Kho hàng
- Quản lý sản phẩm/kho linh kiện.
- Nhập thêm nhanh ngay từ danh sách kho.
- Gắn nhà cung cấp, giá vốn, số lượng.

### 3.4 Công nợ
- Khách nợ, shop nợ NCC/đối tác.
- Theo dõi số tiền tổng, đã trả, còn lại.

### 3.5 Tài chính
- Trọng tâm hiển thị: Finance V2.
- Theo dõi dòng tiền, báo cáo theo kỳ, nhật ký tài chính.

### 3.6 Nhân sự
- Chấm công, lịch làm việc, phê duyệt, cấu hình lương.

## 4) Luồng dữ liệu chuẩn

### 4.1 Ghi dữ liệu
- View gọi Service.
- Service ghi local DB trước.
- Enqueue vào sync queue.
- Khi có mạng: đẩy lên Firestore/Storage.

### 4.2 Đọc dữ liệu
- View đọc từ local DB làm nguồn chính.
- SyncService đổ dữ liệu cloud về local theo shopId.

## 5) Quy tắc nghiệp vụ quan trọng

### 5.1 Cô lập dữ liệu theo cửa hàng
- Mọi nghiệp vụ phải có shopId.
- Không truy vấn chéo shop.

### 5.2 Tài chính nhập kho linh kiện
- Nếu TIỀN MẶT/CHUYỂN KHOẢN:
  - Phải ghi expense.
  - Phải ghi financial activity.
- Nếu CÔNG NỢ:
  - Bắt buộc có nhà cung cấp.
  - Phải ghi debt type SHOP_OWES.
  - Phải phát sự kiện cập nhật công nợ.

### 5.3 Đồng bộ và sự kiện
- EventBus dùng để refresh các màn liên quan (parts_changed, expenses_changed, debts_changed, financialChanged).

## 6) Phân quyền

- Quyền lấy từ UserService.
- Vai trò đặc biệt super admin qua tài khoản quản trị.
- Mỗi màn nghiệp vụ phải tự chặn nếu thiếu quyền.

## 7) Chuẩn phát hành (release process)

1. Hoàn tất code + migrate (nếu có).
2. Chạy analyze các file thay đổi.
3. Chạy thử trên thiết bị thực.
4. Build web release.
5. Deploy hosting.
6. Build Android App Bundle (AAB) release.
7. Cập nhật changelog + release note.
8. Commit theo nhóm thay đổi nghiệp vụ.

## 8) Cấu trúc thư mục quan trọng

- lib/views: màn hình giao diện.
- lib/services: nghiệp vụ + tích hợp.
- lib/data/db_helper.dart: schema và truy cập SQLite.
- lib/finance_v2: module tài chính chính.
- functions: Cloud Functions.
- DOCS: tài liệu vận hành/phát hành.

## 9) Hướng dẫn cho người mới vào dự án

Nên đọc theo thứ tự:
1. lib/main.dart
2. lib/views/home_view.dart
3. lib/services/user_service.dart
4. lib/services/sync_orchestrator.dart
5. lib/services/sync_service.dart
6. lib/data/db_helper.dart
7. lib/finance_v2/*
8. Tài liệu này

## 10) Trạng thái hiện tại

- Finance V2 đang là luồng chính cho tài chính.
- Nút tạo data demo trong khu Cài đặt/Home đã được loại bỏ khỏi giao diện vận hành.
- Luồng nhập thêm linh kiện đã chuẩn hóa ghi nhận tài chính/công nợ theo phương thức thanh toán.
