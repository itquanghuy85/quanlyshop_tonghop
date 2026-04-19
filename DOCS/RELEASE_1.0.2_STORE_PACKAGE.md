# GOI PHAT HANH 1.0.2 - IOS / ANDROID / WEB

Cap nhat ngay: 19/04/2026
Moc so sanh tinh nang: tu v262 den v291
Doi tuong: Nguoi su dung cua hang

## 1) Release Note dang ngan (dan vao store)

### App Store / Play Store (ban ngan)
- Ban 1.0.2 tap trung nang cap do on dinh va toc do dong bo tren nhieu thiet bi. Bo sung trung tam theo doi dong bo, man hinh hoat dong gan day, va hoan thien quy trinh doi ca nhan vien. Cai thien trai nghiem su dung tren Android, iOS, Web va giam chi phi doc du lieu nen de app muot hon.

### Ban rat ngan (du phong)
- Nang cap dong bo da thiet bi, bo sung theo doi trang thai he thong, toi uu toc do va do on dinh toan bo app.

## 2) Mo ta tinh nang moi cho nguoi dung (tu v262 den nay)

### A. Dong bo va do on dinh
- Dong bo giua cac thiet bi nhanh va on dinh hon.
- Giam tinh trang du lieu cap nhat cham khi mo lai app.
- Han che loi lech trang thai don va ghi de du lieu.

### B. Quan sat he thong ro rang hon
- Co trang thong ke Read/Write Firebase de theo doi suc khoe dong bo.
- Co trang hoat dong gan day (Recent Activity) de kiem tra thay doi nhanh.
- Co them loi vao/chuc nang tren Trang chu de thao tac nhanh hon.

### C. Quan tri nhan su
- Hoan thien module doi ca: tao yeu cau, duyet, tu choi, theo doi trang thai.
- Firestore Rules cho doi ca va quyen truy cap duoc cung co.

### D. Hieu nang va chi phi van hanh
- Giam manh doc du lieu nen (bat buoc fetch theo trigger/lifecycle thay vi poll lien tuc).
- App phan hoi muot hon khi su dung lau, giam tai cloud.

### E. Bao mat va tinh nhat quan
- Chuan hoa updatedAt va dong bo quyen/pham vi du lieu theo shop.
- Kien truc Firebase-only duoc hoan thien de tranh xung dot mode.

## 3) Mo ta app (Store Listing) de xuat

### Ten ung dung
- Quan Ly Shop

### Subtitle (iOS) / Short description (Android)
- Quan ly ban hang, sua chua, kho va tai chinh da thiet bi

### Full description (de xuat)
Quan Ly Shop la ung dung van hanh cua hang dien thoai/sua chua toan dien, giup chu shop va nhan vien quan ly ban hang, don sua, kho, cong no, chi phi va cham cong tren cung mot he thong.

Noi bat:
- Quan ly don sua chua, trang thai may, linh kien va giao may.
- Quan ly don ban hang, khach hang, kho san pham va lich su giao dich.
- Theo doi tai chinh cua shop: thu, chi, cong no, bao cao tong hop.
- Quan ly nhan su: phan quyen, cham cong, va doi ca.
- Dong bo du lieu da thiet bi theo shop, phuc hoi nhanh khi doi mang.
- Hoat dong tren Android, iOS va Web.

Ban 1.0.2 tap trung nang cap do on dinh he thong dong bo, giam tai nen, va bo sung cong cu theo doi trang thai he thong de nguoi dung van hanh cua hang an toan, minh bach va hieu qua hon.

## 4) Checklist de dua store han che bi tu choi

### iOS App Store Connect
1. Support URL hop le:
- De xuat: https://quanlyshop.web.app/support.html
2. Privacy Policy URL hop le:
- De xuat: https://quanlyshop.web.app/privacy.html
3. Age Rating:
- Bat cac muc phu hop voi tinh nang chat/messaging noi bo.
4. App Review Information:
- Cung cap tai khoan test (email, mat khau, role).
- Mo ta ro luong dang nhap/phan quyen cho reviewer.
5. Account deletion:
- Co huong dan xoa tai khoan trong app hoac URL support.
6. Permission usage:
- Camera, Photo, Bluetooth, Location phai dung dung voi tinh nang hien co.
7. Push notification:
- Xac nhan release entitlements co aps-environment=production.
8. Metadata khong qua huan:
- Khong dung tuyen bo khong co trong app; screenshot phai dung giao dien that.

### Google Play Console
1. Data Safety form:
- Khai bao dung du lieu thu thap, ma hoa va chia se du lieu.
2. App Access (neu can):
- Cung cap thong tin tai khoan demo cho reviewer.
3. Content rating:
- Dien day du theo tinh nang thong bao/chat noi bo.
4. Permissions declaration:
- Dong bo voi AndroidManifest va tinh nang dang su dung.
5. Deletion policy:
- Neu app cho tao tai khoan, cung cap cach xoa tai khoan/du lieu.

### Web release
1. Deploy hosting kem support/privacy URL.
2. Kiem tra cache busting version sau moi release.
3. Kiem tra dang nhap va dong bo tren trinh duyet mobile + desktop.

## 5) Build artifact cho ban 1.0.2

- Android AAB:
  build/app/outputs/bundle/release/app-release.aab
- Web build:
  build/web
- iOS:
  Build tren macOS (khong build duoc tren Windows)

Lenh de xuat tren macOS cho iOS release:
- flutter pub get
- flutter build ios --release
- xcodebuild archive (qua Xcode Organizer) de upload App Store Connect

## 6) Luu y van hanh truoc khi submit

1. Doi metadata version trong App Store Connect/Play:
- Version name: 1.0.2
- Build number: 292
2. Deploy web truoc khi submit de URL support/privacy co san.
3. Chay smoke test 4 flow bat buoc:
- Tao/Sua/Xoa don
- Dong bo 2 thiet bi
- Push notification
- Dang nhap + phan quyen nhan vien
