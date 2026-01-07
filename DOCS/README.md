# QuanLyShop - Phần Mềm Quản Lý Tiệm Sửa Chữa Điện Thoại

## 📱 Giới Thiệu Ứng Dụng

**QuanLyShop** là phần mềm quản lý tiệm sửa chữa điện thoại chuyên nghiệp, được thiết kế để tối ưu hóa quy trình kinh doanh cho các cửa hàng sửa chữa điện thoại. Ứng dụng cung cấp giải pháp toàn diện cho việc quản lý khách hàng, đơn hàng, kho hàng, và báo cáo tài chính.

### ✨ Tính Năng Chính

- **👥 Quản Lý Khách Hàng**: Lưu trữ thông tin khách hàng, lịch sử sửa chữa
- **📋 Quản Lý Đơn Hàng**: Theo dõi tiến độ sửa chữa, quản lý linh kiện
- **📊 Báo Cáo Tài Chính**: Thống kê doanh thu, chi phí, lợi nhuận chi tiết
- **📱 Đồng Bộ Đám Mây**: Sao lưu dữ liệu tự động lên Firebase
- **🖨️ In Hóa Đơn**: Hỗ trợ in hóa đơn qua Bluetooth và WiFi
- **📷 Quét QR Code**: Quét mã QR để tra cứu thông tin sản phẩm
- **📸 Chụp Ảnh**: Ghi nhận hình ảnh trước và sau khi sửa chữa
- **🔔 Thông Báo**: Nhắc nhở lịch hẹn và cập nhật đơn hàng

### 🛠️ Công Nghệ Sử Dụng

- **Framework**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Auth, Storage, Functions)
- **Database**: SQLite (offline) + Firestore (online)
- **UI/UX**: Material Design
- **Platform**: Android, iOS, Web, Windows, Linux, macOS

## 👨‍💻 Thông Tin Nhà Phát Triển

### Quang Huy
**Chuyên Gia Phát Triển Ứng Dụng Mobile**

Tôi là nhà phát triển phần mềm với hơn 5 năm kinh nghiệm trong lĩnh vực phát triển ứng dụng di động, đặc biệt là các giải pháp quản lý kinh doanh cho doanh nghiệp nhỏ và vừa.

### 📞 Liên Hệ

- **📱 Số Điện Thoại**: 0964 095 979
- **💬 Zalo**: 0964 095 979
- **📧 Email**: [Chưa cập nhật]

### 🚀 Dịch Vụ Phát Triển

Tôi chuyên cung cấp các dịch vụ phát triển ứng dụng di động cho doanh nghiệp:

- Phát triển ứng dụng Android/iOS
- Tích hợp Firebase và các dịch vụ đám mây
- Tư vấn giải pháp quản lý kinh doanh
- Bảo trì và nâng cấp ứng dụng
- Phát triển phần mềm theo yêu cầu

## 📋 Yêu Cầu Hệ Thống

- **Flutter SDK**: >= 3.10.0
- **Dart SDK**: >= 3.10.0
- **Android**: API 21+ (Android 5.0+)
- **iOS**: 11.0+

## 🚀 Cài Đặt và Chạy

### 1. Cài Đặt Dependencies
```bash
flutter pub get
```

### 2. Cấu Hình Firebase
- Tạo project trên Firebase Console
- Thêm file `google-services.json` vào `android/app/`
- Cập nhật cấu hình trong `lib/firebase_options.dart`

### 3. Chạy Ứng Dụng
```bash
flutter run
```

### 4. Build APK
```bash
flutter build apk --release
```

## 📁 Cấu Trúc Dự Án

```
lib/
├── main.dart                 # Điểm khởi đầu ứng dụng
├── firebase_options.dart     # Cấu hình Firebase
├── models/                   # Định nghĩa dữ liệu
├── services/                 # Logic nghiệp vụ và API
├── views/                    # Giao diện người dùng
├── widgets/                  # Component tái sử dụng
├── data/                     # Database và storage
└── utils/                    # Utility functions
```

## 📄 Giấy Phép

Ứng dụng này được phát triển cho mục đích thương mại. Vui lòng liên hệ nhà phát triển để được tư vấn về việc sử dụng.

## 🤝 Hỗ Trợ

Nếu bạn cần hỗ trợ kỹ thuật hoặc có ý kiến đóng góp, vui lòng liên hệ:

**Quang Huy**  
📱 **0964 095 979**  
💬 **Zalo: 0964 095 979**

---

*Phát triển bởi Quang Huy - Chuyên gia giải pháp phần mềm cho doanh nghiệp*
