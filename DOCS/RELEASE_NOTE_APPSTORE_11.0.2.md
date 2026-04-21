# Phát hành 11.0.2 - Android, iOS, Web

Ngày phát hành: 2026-04-21
Phiên bản: 11.0.2

## 1) Release Note (chi tiết nội bộ)

### Mục tiêu bản 11.0.2
- Đồng bộ định danh ứng dụng về `com.huluca.shop`.
- Sửa luồng đăng ký: cho phép người dùng tự nhập email đăng nhập (bỏ cơ chế email tự động).
- Sửa lỗi tràn giao diện trong bộ chuyển shop ở màn hình Cài đặt.
- Dọn dẹp và đồng bộ build cho Android + Web; cập nhật cấu hình iOS để sẵn sàng phát hành.

### Thay đổi chính
- Chuyển các tham chiếu package cũ sang `com.huluca.shop` trong mã nguồn/cấu hình/tài liệu và file dump liên quan.
- Đăng ký tài khoản:
  - Bỏ logic tự sinh email từ tên + tên shop.
  - Trường email cho phép người dùng nhập thủ công.
- Shop switcher:
  - Bổ sung xử lý tránh overflow cho dropdown (`isExpanded` + `ellipsis` cho selected item và menu item).
- iOS:
  - Đồng bộ bundle id cho RunnerTests sang `com.huluca.shop.RunnerTests`.

### Kiểm tra đã thực hiện
- `flutter test`: PASS (toàn bộ test).
- `flutter build apk --release`: PASS.
- `flutter build web --release`: PASS.
- Lưu ý WebAssembly dry-run warning: chưa chặn build web hiện tại.

## 2) Nội dung "Có gì mới" để dán lên Google Play

### Bản tiếng Việt (đề xuất)
- Sửa đăng ký: bạn đã có thể tự nhập email đăng nhập.
- Cải thiện màn hình Cài đặt: sửa lỗi tràn ở bộ chuyển cửa hàng.
- Đồng bộ và tối ưu hệ thống để tăng độ ổn định trên Android, iOS và Web.

### Bản tiếng Anh (dự phòng)
- Improved sign-up flow: login email can now be entered manually.
- Fixed settings UI overflow in the shop switcher.
- Stability and compatibility improvements across Android, iOS, and Web.

## 3) Nội dung "What’s New" để dán lên App Store

### Bản tiếng Việt (đề xuất)
Bản cập nhật 11.0.2 tập trung vào độ ổn định và trải nghiệm người dùng:
- Cho phép nhập email đăng nhập thủ công khi đăng ký.
- Khắc phục lỗi tràn giao diện bộ chuyển cửa hàng trong Cài đặt.
- Đồng bộ cấu hình ứng dụng và tối ưu vận hành trên nhiều nền tảng.

### Bản tiếng Anh (dự phòng)
Version 11.0.2 focuses on stability and usability:
- Manual login email entry is now supported during registration.
- Fixed UI overflow in the shop switcher on Settings.
- Configuration and runtime stability improvements across platforms.

## 4) App Review Notes (mẫu gửi duyệt - iOS/Android)

Dùng mẫu dưới đây khi nộp bản build:

- App purpose:
  - HULUCA Shop giúp cửa hàng quản lý sửa chữa, bán hàng, nhân viên và đồng bộ dữ liệu đa nền tảng.

- Account requirement:
  - Ứng dụng yêu cầu đăng nhập để truy cập dữ liệu của cửa hàng.
  - Nếu cần tài khoản test cho reviewer, vui lòng cung cấp:
    - Email test: [ĐIỀN_EMAIL_TEST]
    - Mật khẩu test: [ĐIỀN_MẬT_KHẨU_TEST]

- Test path để reviewer kiểm tra nhanh:
  1. Đăng nhập tài khoản test.
  2. Vào Cài đặt -> Chuyển cửa hàng (kiểm tra không còn tràn giao diện).
  3. Đăng ký tài khoản mới (kiểm tra có thể nhập email thủ công).

- Data and privacy:
  - Dữ liệu được lưu trên Firebase và đồng bộ theo shop.
  - Không thu thập dữ liệu ngoài phạm vi vận hành của tính năng quản lý cửa hàng.

- Permissions:
  - Chỉ sử dụng quyền hệ thống phục vụ tính năng nghiệp vụ (thông báo, camera/ảnh nếu người dùng thao tác).

## 5) Checklist trước khi bấm Submit

- Tăng version trong `pubspec.yaml` lên `11.0.2+<build_number_mới>`.
- Android:
  - Xác nhận `applicationId` = `com.huluca.shop`.
  - Build AAB release: `flutter build appbundle --release`.
- iOS (thực hiện trên macOS):
  - Xác nhận Bundle Identifier = `com.huluca.shop` cho Runner.
  - Archive bằng Xcode và upload qua Organizer.
- Web:
  - Build release thành công và deploy theo quy trình môi trường.
- Kiểm tra đăng ký, chuyển shop, tạo đơn, xem báo cáo ở tài khoản test.
