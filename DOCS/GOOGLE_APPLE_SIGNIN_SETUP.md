# Hướng dẫn cấu hình Google & Apple Sign-In cho HuLuCa Shop

> **⚠️ CẢNH BÁO**: App đang có user thật. Tất cả bước dưới đây **CHỈ THÊM** tính năng mới, **KHÔNG ảnh hưởng** đến tài khoản Email/Password hiện tại.

---

## Mục lục
1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Bước 1: Thêm SHA fingerprint vào Firebase](#2-bước-1-thêm-sha-fingerprint)
3. [Bước 2: Bật Google Sign-In trong Firebase](#3-bước-2-bật-google-sign-in)
4. [Bước 3: Cập nhật file cấu hình Android](#4-bước-3-cập-nhật-android)
5. [Bước 4: Cập nhật file cấu hình iOS](#5-bước-4-cập-nhật-ios)
6. [Bước 5: Cập nhật firebase_options.dart](#6-bước-5-cập-nhật-firebase_optionsdart)
7. [Bước 6: Bật Apple Sign-In trong Firebase](#7-bước-6-bật-apple-sign-in)
8. [Bước 7: Cấu hình Apple Developer Console](#8-bước-7-apple-developer-console)
9. [Bước 8: Cấu hình Xcode](#9-bước-8-cấu-hình-xcode)
10. [Kiểm tra & xác nhận](#10-kiểm-tra--xác-nhận)
11. [Cách sử dụng (cho người dùng)](#11-cách-sử-dụng)
12. [Xử lý sự cố](#12-xử-lý-sự-cố)

---

## 1. Tổng quan kiến trúc

```
User hiện tại (Email/Password)
    │
    ├─ Đăng nhập bằng Google → Nếu cùng email → TỰ ĐỘNG link vào tài khoản cũ (giữ nguyên UID)
    │                        → Nếu email mới  → Tạo tài khoản mới
    │
    ├─ Đăng nhập bằng Apple  → Tương tự
    │
    └─ Liên kết trong Cài đặt → Thêm Google/Apple vào tài khoản đã có
```

**An toàn dữ liệu**: Code sử dụng `linkWithCredential()` — giữ nguyên UID hiện tại, không mất data.

---

## 2. Bước 1: Thêm SHA fingerprint

### Vào Firebase Console:
1. Mở https://console.firebase.google.com/project/huyaka-1809/settings/general
2. Kéo xuống phần **"Your apps"** → chọn app **Android** (`com.huluca.shop`)
3. Click **"Add fingerprint"**

### Thêm lần lượt 2 SHA-1 và 2 SHA-256:

| Loại | Giá trị |
|------|---------|
| **Release SHA-1** | `A4:64:62:B2:E3:02:05:E8:25:F9:FA:6E:2E:43:0F:65:CF:D7:04:03` |
| **Release SHA-256** | `FC:91:AF:51:66:33:FC:9D:F3:26:8A:0D:13:C2:19:83:6A:77:99:23:85:D5:F6:5D:54:D6:C6:57:05:3C:E8:9E` |
| **Debug SHA-1** | `28:BE:D0:A3:A9:6E:0C:1C:E3:D4:66:ED:E1:B7:FE:45:72:C8:07:0B` |
| **Debug SHA-256** | `A0:2E:C4:37:13:1F:3F:50:75:EA:1F:83:6C:83:1F:27:F2:A5:7D:33:52:54:96:34:2F:47:1D:50:1B:A7:99:2D` |

4. Click **"Save"** sau khi thêm xong tất cả.

---

## 3. Bước 2: Bật Google Sign-In

1. Mở https://console.firebase.google.com/project/huyaka-1809/authentication/providers
2. Click **"Google"** trong danh sách providers
3. Toggle **"Enable"** = ON
4. **Project public-facing name**: `HuLuCa Shop` (tên hiện cho user khi đăng nhập)
5. **Project support email**: Chọn email admin của bạn
6. Click **"Save"**

> ✅ Sau bước này, Firebase tự động tạo OAuth client ID cho Android, iOS, và Web.

---

## 4. Bước 3: Cập nhật Android

### Tải lại google-services.json:
1. Ở trang Firebase Console → Project Settings → Your Apps → Android app
2. Click **"Download google-services.json"**
3. **Thay thế** file cũ tại: `android/app/google-services.json`

> File mới sẽ có `oauth_client` không còn rỗng — chứa client ID cần thiết cho Google Sign-In.

### Xác nhận file mới đúng:
Mở file và kiểm tra phần `oauth_client` phải có ít nhất 1 entry với `client_type: 1` hoặc `client_type: 3`:
```json
"oauth_client": [
  {
    "client_id": "51200928212-xxxxxxx.apps.googleusercontent.com",
    "client_type": 3
  }
]
```

---

## 5. Bước 4: Cập nhật iOS

### Tải lại GoogleService-Info.plist:
1. Firebase Console → Project Settings → Your Apps → iOS app (`com.huluca.shop`)
2. Click **"Download GoogleService-Info.plist"**
3. **Thay thế** file tại: `ios/Runner/GoogleService-Info.plist`
4. **Cũng copy** vào: `ios/GoogleService-Info.plist` (root iOS folder nếu có)

### Cập nhật Info.plist (URL Scheme):
1. Mở file `GoogleService-Info.plist` mới
2. Tìm giá trị **`REVERSED_CLIENT_ID`** (dạng `com.googleusercontent.apps.51200928212-xxxxxxx`)
3. Mở `ios/Runner/Info.plist`
4. Tìm và thay thế:
```xml
<!-- TÌM (PLACEHOLDER cũ): -->
<string>com.googleusercontent.apps.PLACEHOLDER</string>

<!-- THAY BẰNG (giá trị thật từ GoogleService-Info.plist): -->
<string>com.googleusercontent.apps.51200928212-xxxxxxx</string>
```

---

## 6. Bước 5: Cập nhật firebase_options.dart

### Lấy iOS Client ID:
1. Mở `GoogleService-Info.plist` mới (đã tải ở bước 4)
2. Tìm giá trị **`CLIENT_ID`** (dạng `51200928212-xxxxxxx.apps.googleusercontent.com`)

### Cập nhật code:
Mở `lib/firebase_options.dart`, tìm phần iOS options:

```dart
// TÌM (khoảng dòng 55-65):
static const FirebaseOptions ios = FirebaseOptions(
  apiKey: 'AIzaSyAS_5VLVEO1GdjrK9XbnqlrHLegMmEGHW4',
  appId: '1:51200928212:ios:04c10eca3b61a3be910e41',
  messagingSenderId: '51200928212',
  projectId: 'huyaka-1809',
  storageBucket: 'huyaka-1809.firebasestorage.app',
  iosBundleId: 'com.huluca.shop',
);

// THÊM dòng iosClientId:
static const FirebaseOptions ios = FirebaseOptions(
  apiKey: 'AIzaSyAS_5VLVEO1GdjrK9XbnqlrHLegMmEGHW4',
  appId: '1:51200928212:ios:04c10eca3b61a3be910e41',
  messagingSenderId: '51200928212',
  projectId: 'huyaka-1809',
  storageBucket: 'huyaka-1809.firebasestorage.app',
  iosClientId: '51200928212-xxxxxxx.apps.googleusercontent.com',  // ← THÊM
  iosBundleId: 'com.huluca.shop',
);
```

Làm tương tự cho phần **macOS** nếu có (cùng `iosClientId`).

---

## 7. Bước 6: Bật Apple Sign-In

1. Mở https://console.firebase.google.com/project/huyaka-1809/authentication/providers
2. Click **"Apple"** trong danh sách
3. Toggle **"Enable"** = ON
4. Các field:
   - **Service ID**: Để trống trước (cần cho web — xem note bên dưới)
   - **Apple Team ID**: Lấy từ https://developer.apple.com/account → Membership → Team ID
   - **Key ID** và **Private Key**: Xem bước 7 bên dưới
5. Click **"Save"**

### Cho Web (tùy chọn — nếu muốn Apple Sign-In trên web):
Cần tạo **Services ID** trong Apple Developer Console:
1. Tạo Services ID tại https://developer.apple.com/account/resources/identifiers/list/serviceId
2. Identifier: `com.huluca.shop.web`
3. Enable "Sign In with Apple" → Configure:
   - Primary App ID: `com.huluca.shop`
   - Domains: `huyaka-1809.firebaseapp.com`
   - Return URLs: `https://huyaka-1809.firebaseapp.com/__/auth/handler`
4. Save, rồi quay lại Firebase Console nhập Services ID vào.

---

## 8. Bước 7: Apple Developer Console

### A. Bật Sign In with Apple cho App ID:
1. Mở https://developer.apple.com/account/resources/identifiers/list
2. Chọn App ID: `com.huluca.shop`
3. Scroll xuống **Capabilities** → Check ✅ **"Sign In with Apple"**
4. Click **"Save"**

### B. Tạo Key cho Apple Sign-In:
1. Mở https://developer.apple.com/account/resources/authkeys/list
2. Click **"+"** → Name: `HuLuCa Shop Apple SignIn`
3. Check ✅ **"Sign In with Apple"** → Configure → Primary App ID: `com.huluca.shop`
4. Click **"Continue"** → **"Register"**
5. **Download** file `.p8` (CHỈ TẢI ĐƯỢC 1 LẦN!)
6. Ghi nhớ **Key ID** (10 ký tự)

### C. Quay lại Firebase Console nhập key:
1. Mở lại Apple provider settings trong Firebase
2. Nhập **Key ID** và paste nội dung file `.p8` vào **Private Key**
3. Nhập **Team ID** từ Apple Developer
4. Click **"Save"**

---

## 9. Bước 8: Cấu hình Xcode

1. Mở project trong Xcode: `ios/Runner.xcworkspace`
2. Chọn target **"Runner"** → tab **"Signing & Capabilities"**
3. Click **"+ Capability"** → tìm **"Sign In with Apple"** → thêm vào
4. Đảm bảo **Team** đúng (cùng team với Apple Developer account)

> ⚠️ Bước này BẮT BUỘC cho iOS/macOS. Không có capability này, Apple Sign-In sẽ crash.

---

## 10. Kiểm tra & xác nhận

### Checklist:

| # | Hạng mục | Trạng thái |
|---|----------|------------|
| 1 | SHA fingerprints added in Firebase Console | ⬜ |
| 2 | Google provider enabled in Firebase Auth | ⬜ |
| 3 | google-services.json re-downloaded (Android) | ⬜ |
| 4 | GoogleService-Info.plist re-downloaded (iOS) | ⬜ |
| 5 | Info.plist REVERSED_CLIENT_ID updated | ⬜ |
| 6 | firebase_options.dart iosClientId added | ⬜ |
| 7 | Apple provider enabled in Firebase Auth | ⬜ |
| 8 | Apple Developer: Sign In with Apple capability | ⬜ |
| 9 | Apple Developer: Key created, .p8 downloaded | ⬜ |
| 10 | Firebase: Apple Key ID + Private Key saved | ⬜ |
| 11 | Xcode: Sign In with Apple capability added | ⬜ |

### Test thứ tự:
1. **Web** (dễ nhất): `flutter run -d chrome` → test Google Sign-In
2. **Android**: Build debug → test Google Sign-In
3. **iOS**: Build → test cả Google và Apple Sign-In

---

## 11. Cách sử dụng

### Người dùng MỚI:
1. Mở app → Màn hình đăng nhập
2. Nhấn nút **"Đăng nhập bằng Google"** (hoặc Apple trên iOS)
3. Chọn tài khoản Google → Đăng nhập thành công
4. App tự tạo tài khoản + shop mới

### Người dùng CŨ (đã có tài khoản Email/Password):
**Cách 1 — Liên kết trong Cài đặt (KHUYẾN NGHỊ):**
1. Đăng nhập bằng Email/Password như bình thường
2. Vào **Cài đặt** → kéo xuống card **"Tài khoản liên kết"**
3. Nhấn **"Liên kết"** bên cạnh Google hoặc Apple
4. Chọn tài khoản Google (phải cùng email hoặc email khác)
5. Từ lần sau, có thể đăng nhập bằng cả 2 cách

**Cách 2 — Đăng nhập trực tiếp bằng Google:**
1. Nếu email Google **trùng** với email đã đăng ký → App tự link, giữ nguyên dữ liệu
2. Nếu email Google **khác** → App thông báo cần đăng nhập bằng Email trước, rồi liên kết

### Hủy liên kết:
1. Cài đặt → Tài khoản liên kết
2. Nhấn **"Hủy liên kết"** bên cạnh Google/Apple
3. ⚠️ Phải còn ít nhất 1 phương thức đăng nhập (email hoặc social)

---

## 12. Xử lý sự cố

### "account-exists-with-different-credential"
- **Nguyên nhân**: User đã có tài khoản email/password, đang thử đăng nhập bằng Google/Apple cùng email
- **Giải pháp**: Đăng nhập bằng email/password trước → Cài đặt → Liên kết Google/Apple

### Google Sign-In không hiện popup (Web)
- Kiểm tra Google provider đã enable trong Firebase Console
- Kiểm tra domain `huyaka-1809.firebaseapp.com` trong Authorized domains

### Google Sign-In lỗi trên Android
- Kiểm tra SHA fingerprint đúng chưa (cả release và debug)
- Kiểm tra đã download lại google-services.json sau khi thêm SHA
- Chạy `flutter clean && flutter pub get && flutter run`

### Apple Sign-In crash trên iOS
- Kiểm tra Xcode đã thêm "Sign In with Apple" capability
- Kiểm tra Bundle ID match: `com.huluca.shop`
- Kiểm tra Apple Developer đã enable Sign In with Apple cho App ID

### "PlatformException(sign_in_failed, ...)"
- Android: SHA mismatch → kiểm tra lại fingerprint
- iOS: Missing iosClientId trong firebase_options.dart

---

## Thông tin kỹ thuật

| Thông số | Giá trị |
|----------|---------|
| Firebase Project | `huyaka-1809` |
| Android Package | `com.huluca.shop` |
| iOS Bundle ID | `com.huluca.shop` |
| Web Auth Domain | `huyaka-1809.firebaseapp.com` |
| Firebase Project Number | `51200928212` |
| Keystore | `D:\android-keys\upload-keystore.jks` |
| Key Alias | `upload` |

