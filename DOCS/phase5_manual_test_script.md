# Script kiểm thử nhanh Phase 5 – Multi-Branch (bước 5.5 → 5.12)

> Chuẩn bị: App đang chạy (hot-reload OK). Đang đăng nhập tài khoản test. Flag Multi-Branch đã bật.

---

## BƯỚC 5.5 – Thêm chi nhánh "HCM"

1. Từ Home → bấm nút **"Quản lý chi nhánh"** (nút thứ 2 ngay dưới nút chi nhánh hiện tại).
2. Màn "Quản lý chi nhánh" mở ra → thấy FAB **"Thêm chi nhánh"** ở góc dưới phải.
3. Bấm FAB → dialog "Thêm chi nhánh" xuất hiện.
4. Gõ tên: **HCM** → bấm **Thêm**.
5. ✅ Kết quả mong đợi: "HCM" xuất hiện trong danh sách.
✅
---

## BƯỚC 5.6 – Thêm chi nhánh "Hà Nội"

1. Vẫn ở màn Quản lý chi nhánh → bấm FAB lần 2 (hoặc icon + góc phải AppBar).
2. Gõ tên: **Hà Nội** → bấm **Thêm**.
3. ✅ Kết quả mong đợi: Danh sách có 2 dòng: HCM và Hà Nội.

---

## BƯỚC 5.7 – Quay về Home và mở selector

1. Bấm nút **Back** (← trên AppBar) để trở về Home.
2. Thấy nút **"Chi nhánh hiện tại: Chưa chọn"** → bấm vào.
3. ✅ Kết quả mong đợi: Màn "Chọn chi nhánh" mở ra, thấy 2 chi nhánh HCM và Hà Nội trong danh sách.

---

## BƯỚC 5.8 – Chọn HCM và xác nhận

1. Tap vào dòng **HCM** (radio tick vào HCM).
2. Bấm nút **"Xác nhận"** ở cuối màn.
3. ✅ Kết quả mong đợi:
   - Snackbar xanh: *"Đã chuyển sang chi nhánh "HCM""*
   - Màn tự đóng, trở về Home.

---

## BƯỚC 5.9 – Kiểm tra nhãn trên Home

1. Nhìn lên đầu trang Home tab.
2. ✅ Kết quả mong đợi: Nút đổi thành **"Chi nhánh hiện tại: HCM"**.
❌: vẫn hiện chi nhánh hiện tại : Chưa chọn.
---

## BƯỚC 5.10 – Chuyển sang Hà Nội

1. Bấm nút **"Chi nhánh hiện tại: HCM"** trên Home.
2. Màn selector mở ra → tap dòng **Hà Nội**.
3. Bấm **"Xác nhận"**.
4. ✅ Kết quả mong đợi:
   - Snackbar xanh: *"Đã chuyển sang chi nhánh "Hà Nội""*
   - Nút trên Home đổi thành **"Chi nhánh hiện tại: Hà Nội"**.
❌ vẫn hiện chi nhánh hiện tại :chưa chọn.
---

## BƯỚC 5.11 – Tạo đơn bán không bị ảnh hưởng

1. Bấm tab **Bán hàng** (icon giỏ hàng dưới cùng).
2. Tạo 1 đơn bán bình thường: thêm 1 sản phẩm → bấm **Lưu/Thanh toán**.
3. ✅ Kết quả mong đợi: Đơn bán lưu thành công, không có thông báo lỗi nào liên quan đến chi nhánh.

---

## BƯỚC 5.12 – Thoát app và mở lại

1. Thoát app hoàn toàn (swipe away trong recent apps, hoặc bấm nút back phần cứng đến khi thoát hẳn).
2. Mở lại app.
3. ✅ Kết quả mong đợi:
   - App khởi động bình thường, không crash.
   - Đăng nhập vẫn còn (hoặc vào lại nhanh).
   - Home hiển thị bình thường.

---

## Báo lại kết quả

Sau khi bấm xong từng bước, báo lại theo mẫu:

```
5.5  ✅ / ❌ (ghi mô tả nếu lỗi)
5.6  ✅ / ❌
5.7  ✅ / ❌
5.8  ✅ / ❌
5.9  ✅ / ❌
5.10 ✅ / ❌
5.11 ✅ / ❌
5.12 ✅ / ❌
```

Nếu bước nào ❌ → ghi thêm: màn hình đang ở đâu, thấy thông báo gì, app có crash không.
