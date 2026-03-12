# App Store Release Checklist

Tai lieu nay tong hop cac buoc can lam de dua ung dung iOS len TestFlight va App Store cho du an nay.

## Cau hinh hien tai

- App name: Quan Ly Shop
- Bundle ID: com.huluca.shop
- Apple Developer Team ID: F7B6X2BZ6A
- Flutter version: 11.1.45+246
- iOS minimum version: 14.0
- Release APNs entitlement: production

## Viec can chot truoc khi archive

1. Xac nhan ten hien thi trong iOS la dung va khong loi dau.
2. Xac nhan icon app 1024x1024 da dep va khong chua alpha.
3. Chot version va build number moi trong pubspec.yaml truoc moi lan gui build.
4. Kiem tra Firebase production dang dung dung project cho iOS.
5. Upload APNs Auth Key (.p8) vao Firebase Console cho app iOS bundle id com.huluca.shop.
6. Kiem tra push notification tren build Release/TestFlight, khong chi Debug.
6. Chuan bi tai khoan demo cho App Review neu app can dang nhap.
7. Chuan bi privacy policy URL va support URL.

## Luu y quan trong ve APNs key

- APNs Auth Key (.p8) KHONG duoc nhung vao app iOS va KHONG commit vao Git.
- Key nay phai duoc upload tren Firebase Console hoac he thong server gui push.
- Repo nay chi can dung bundle id, entitlements va code FCM dung. Cac muc nay da duoc cau hinh san cho iOS Release.

## Viec can tao tren App Store Connect

1. Tao app moi voi bundle id com.huluca.shop neu chua tao.
2. Dien cac thong tin co ban:
   - App Name
   - Subtitle
   - Primary Language
   - Category
   - Content Rights
   - Age Rating
3. Dien cac URL bat buoc:
   - Privacy Policy URL
   - Support URL
   - Marketing URL neu co
4. Dien phan App Privacy theo dung cac quyen dang su dung trong app:
   - Camera
   - Photo Library
   - Bluetooth
   - Location
   - Notifications
5. Dien mo ta va metadata:
   - Promotional Text
   - Description
   - Keywords
   - Copyright
6. Chuan bi screenshot dung kich thuoc cho:
   - iPhone 6.7 inch
   - iPhone 6.5 inch hoac 6.9 inch tuy thiet bi chup
   - iPad neu muon phat hanh iPad day du

## Viec can kiem tra trong Xcode

1. Mo ios/Runner.xcworkspace trong Xcode.
2. Chon target Runner -> Signing & Capabilities:
   - Team: F7B6X2BZ6A
   - Bundle Identifier: com.huluca.shop
   - Push Notifications: bat
   - Background Modes: fetch, remote notifications
3. Xac nhan Signing la Automatic hoac provisioning profile dung voi bundle id com.huluca.shop.
4. Chon Product -> Scheme -> Edit Scheme va dam bao build theo Release khi archive.
5. Chay tren iPhone that mot lan bang Release neu co the.

## Len build TestFlight

1. Tang version neu can trong pubspec.yaml.
2. Chay lenh:

```powershell
flutter pub get
flutter build ipa --release
```

3. Cach khuyen nghi bang Xcode:
   - Open ios/Runner.xcworkspace
   - Product -> Archive
   - Organizer -> Distribute App
   - App Store Connect -> Upload
4. Sau khi upload, vao App Store Connect -> TestFlight doi build processing.
5. Dien Export Compliance neu Apple hoi.
6. Moi internal testers test cac luong quan trong:
   - Dang nhap
   - Don sua
   - Ban hang
   - Chup anh
   - In Bluetooth
   - Thong bao push
   - Cham cong va xin nghi

## Checklist truoc khi gui review App Store

1. Build TestFlight da duoc test xong.
2. Khong crash khi mo lan dau.
3. Thong tin login review da san sang:
   - So dien thoai/email
   - Mat khau
   - Huong dan buoc vao man hinh chinh
4. Co ghi chu ro cho reviewer neu can:
   - App dung Firebase
   - Can cho phep camera, vi tri, thong bao, bluetooth de dung day du tinh nang
   - Neu co chuc nang can thiet bi ngoai vi du may in Bluetooth, can mo ta cach test thay the
5. App Privacy da khai bao dung.
6. Tu khoa, mo ta, screenshot da final.
7. Chon manual release neu muon tu bam phat hanh sau khi duoc duyet.

## Cac muc de Apple hay hoi voi app nay

- Tai sao can vi tri: cham cong va xac dinh dia diem lam viec.
- Tai sao can camera: chup anh may, quet ma vach/IMEI.
- Tai sao can bluetooth: ket noi may in nhiet.
- Tai sao can notifications: thong bao don hang, cham cong, don sua.
- Neu co tai khoan phan quyen: cung cap tai khoan owner hoac manager cho review.

## Nhung thu con thieu can ban cung cap

1. Ten app chinh thuc muon hien tren App Store.
2. Subtitle ngan 30 ky tu.
3. Mo ta day du 1-2 doan.
4. 10-20 keywords.
5. Privacy Policy URL.
6. Support URL.
7. Copyright text.
8. Tai khoan demo cho reviewer.
9. Bo screenshot App Store.
10. Bieu tuong 1024x1024 neu icon hien tai chua dat.

## Goi y quy trinh toi uu

1. Day code len remote truoc.
2. Tang version/build number cho ban iOS du dinh gui.
3. Archive va upload len TestFlight.
4. Test 1 vong noi bo tren TestFlight.
5. Hoan tat metadata App Store Connect.
6. Gui review.
