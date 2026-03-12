# Hướng Dẫn Đưa Ứng Dụng Lên App Store

Tài liệu này là bản hướng dẫn từng bước bằng tiếng Việt có dấu, theo thứ tự thực hiện thực tế để đưa ứng dụng iOS lên TestFlight và App Store.

## A. Chuẩn Bị Trước Khi Làm

Bạn cần chuẩn bị đủ các mục sau:

1. Tài khoản Apple Developer đang hoạt động.
2. Ứng dụng đã có Bundle ID đúng: `com.huluca.shop`.
3. Có máy Mac cài Xcode.
4. Có quyền truy cập Firebase project của ứng dụng.
5. Có file APNs Auth Key `.p8` nếu muốn dùng thông báo đẩy trên iOS.
6. Có tài khoản đăng nhập dành cho reviewer.
7. Có ảnh chụp màn hình App Store.
8. Có đường dẫn Privacy Policy URL và Support URL.

## B. Bước 1: Kiểm Tra Cấu Hình Apple Developer

1. Mở Apple Developer.
2. Vào Certificates, Identifiers & Profiles.
3. Mở Identifiers.
4. Tìm App ID có bundle id `com.huluca.shop`.
5. Kiểm tra các mục sau đã bật:
   - Push Notifications
   - Associated capability cần thiết nếu có
6. Nếu chưa có APNs key:
   - Vào mục Keys
   - Tạo key mới
   - Bật Apple Push Notifications service (APNs)
   - Tải file `.p8` về máy
   - Ghi lại `Key ID`
   - Ghi lại `Team ID`

## C. Bước 2: Cấu Hình APNs Trong Firebase

1. Mở Firebase Console.
2. Chọn đúng project mà app đang dùng.
3. Vào Project Settings.
4. Mở tab Cloud Messaging.
5. Tìm cấu hình ứng dụng Apple.
6. Upload file `.p8`.
7. Nhập `Key ID`.
8. Nhập `Team ID`.
9. Kiểm tra lại bundle id iOS là `com.huluca.shop`.

Lưu ý quan trọng:

- Không chép file `.p8` vào thư mục `ios/`.
- Không commit file `.p8` lên GitHub.
- File `.p8` chỉ dùng ở Apple Developer và Firebase Console.

## D. Bước 3: Kiểm Tra Repo Trước Khi Build Trên Mac

1. Kéo mã nguồn mới nhất từ GitHub.
2. Mở thư mục dự án.
3. Chạy:

```bash
flutter pub get
```

4. Kiểm tra các file sau đã đúng:
   - `ios/Runner/Info.plist`
   - `ios/Runner/RunnerRelease.entitlements`
   - `ios/GoogleService-Info.plist`
5. Kiểm tra `pubspec.yaml` và tăng build number nếu chuẩn bị gửi build mới.

## E. Bước 4: Mở Xcode Và Kiểm Tra Signing

1. Mở file `ios/Runner.xcworkspace` bằng Xcode.
2. Chọn target `Runner`.
3. Mở tab Signing & Capabilities.
4. Kiểm tra:
   - Team: `F7B6X2BZ6A`
   - Bundle Identifier: `com.huluca.shop`
   - Push Notifications: bật
   - Background Modes: bật `Background fetch` và `Remote notifications`
5. Để Signing ở chế độ Automatic nếu không có lý do đặc biệt.
6. Chọn thiết bị `Any iOS Device (arm64)`.

## F. Bước 5: Build Và Archive

Bạn có thể dùng một trong hai cách sau.

### Cách 1: Dùng Xcode

1. Trong Xcode chọn `Product`.
2. Chọn `Archive`.
3. Chờ Xcode build xong.
4. Khi cửa sổ Organizer mở ra, chọn bản archive mới nhất.

### Cách 2: Dùng Flutter trước rồi upload bằng Xcode nếu cần

```bash
flutter clean
flutter pub get
flutter build ipa --release
```

Nếu build bằng Flutter nhưng cần xử lý signing thủ công, bạn vẫn nên xác nhận lại archive trong Xcode.

## G. Bước 6: Upload Lên App Store Connect

1. Trong Organizer, chọn `Distribute App`.
2. Chọn `App Store Connect`.
3. Chọn `Upload`.
4. Tiếp tục theo hướng dẫn mặc định của Xcode.
5. Nếu Apple hỏi về Export Compliance, trả lời theo tình hình thực tế của ứng dụng.
6. Chờ quá trình upload hoàn tất.

## H. Bước 7: Kiểm Tra Build Trên TestFlight

1. Mở App Store Connect.
2. Vào ứng dụng của bạn.
3. Mở tab TestFlight.
4. Chờ build processing hoàn tất.
5. Thêm người thử nghiệm nội bộ.
6. Cài build TestFlight lên iPhone thật.
7. Kiểm tra tối thiểu các luồng sau:
   - Đăng nhập
   - Màn hình chính
   - Đơn sửa
   - Bán hàng
   - Tồn kho
   - Chấm công
   - Thông báo đẩy
   - In Bluetooth nếu có thiết bị

## I. Bước 8: Điền Nội Dung App Store Connect

1. Mở App Store Connect.
2. Vào trang App Information.
3. Điền tên ứng dụng, phụ đề, danh mục.
4. Vào mục bản tiếng Việt hoặc ngôn ngữ chính.
5. Sao chép nội dung từ tài liệu:

[DOCS/APPSTORE_METADATA_COPY_PASTE_VI.md](DOCS/APPSTORE_METADATA_COPY_PASTE_VI.md)

6. Dán lần lượt vào các ô:
   - Promotional Text
   - Description
   - Keywords
   - Support URL
   - Privacy Policy URL
   - Notes for Review

## J. Bước 9: Điền App Privacy

Bạn cần khai báo trung thực theo đúng dữ liệu ứng dụng xử lý. Với ứng dụng này, bạn nên rà kỹ các nhóm sau:

1. Thông tin liên hệ người dùng nếu có lưu tài khoản.
2. Ảnh hoặc tệp do người dùng tải lên.
3. Vị trí dùng cho chấm công.
4. Chẩn đoán hoặc log nếu có gửi về dịch vụ bên thứ ba.

Lưu ý:

- Phần này không nên đoán mò.
- Nếu chưa chắc, hãy kiểm tra lại chính sách thu thập dữ liệu thực tế trước khi gửi review.

## K. Bước 10: Chuẩn Bị Tài Khoản Cho Reviewer

1. Tạo hoặc chọn một tài khoản owner hoặc manager.
2. Đảm bảo tài khoản này đăng nhập được ổn định.
3. Có sẵn dữ liệu mẫu để reviewer nhìn thấy tính năng chính.
4. Dán thông tin tài khoản vào mục App Review Information.

Bạn có thể dùng mẫu trong:

[DOCS/APPSTORE_METADATA_COPY_PASTE_VI.md](DOCS/APPSTORE_METADATA_COPY_PASTE_VI.md)

## L. Bước 11: Gửi Review

1. Kiểm tra lại toàn bộ metadata.
2. Kiểm tra lại ảnh chụp màn hình.
3. Kiểm tra lại URL hỗ trợ và chính sách bảo mật.
4. Kiểm tra lại tài khoản reviewer.
5. Chọn phiên bản build đúng.
6. Bấm `Submit for Review`.

## M. Các Lỗi Thường Gặp

### 1. Build lên TestFlight nhưng không nhận được push iOS

Kiểm tra lại:

1. APNs key đã upload đúng Firebase chưa.
2. Bundle ID có khớp hoàn toàn không.
3. Release entitlement có là `production` không.
4. Thiết bị đã cho phép Notifications chưa.

### 2. Apple hỏi vì sao cần quyền vị trí

Trả lời:

Ứng dụng dùng vị trí khi đang sử dụng để phục vụ chấm công và xác định địa điểm làm việc.

### 3. Apple hỏi vì sao cần Bluetooth

Trả lời:

Ứng dụng dùng Bluetooth để kết nối máy in nhiệt, phục vụ in hóa đơn và chứng từ liên quan.

### 4. Apple hỏi vì sao cần camera

Trả lời:

Ứng dụng dùng camera để chụp ảnh máy, chụp minh chứng công việc và quét mã vạch hoặc IMEI.

## N. Những Gì Bạn Chỉ Cần Thay Trước Khi Dùng

1. Tên ứng dụng nếu đổi thương hiệu.
2. URL hỗ trợ.
3. URL chính sách bảo mật.
4. Tài khoản reviewer.
5. Ảnh chụp màn hình.
6. Build number mới.