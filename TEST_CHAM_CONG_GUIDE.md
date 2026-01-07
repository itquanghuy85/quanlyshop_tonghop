# 🧪 HƯỚNG DẪN TEST CHẤM CÔNG & CÀI ĐẶT LƯƠNG
**Ngày cập nhật:** 26/12/2025

## 🎯 MỤC TIÊU TEST
- Kiểm tra tính năng chấm công hoạt động đúng
- Test cài đặt thời gian làm việc
- Test cài đặt lương nhân viên
- Xác minh tính lương tự động

---

## 📋 CHECKLIST TEST CHẤM CÔNG

### ✅ TEST 1: CÀI ĐẶT THỜI GIAN LÀM VIỆC
1. **Đăng nhập với tài khoản chủ shop**
2. **Vào Cài đặt → Lịch làm việc**
3. **Tab "Thời gian làm việc"**
   - ✅ Thay đổi giờ bắt đầu: 08:30
   - ✅ Thay đổi giờ kết thúc: 17:30
   - ✅ Thay đổi giờ nghỉ: 1.5 giờ
   - ✅ Thay đổi max OT: 3 giờ
   - ✅ Nhấn "Lưu cài đặt"

4. **Tab "Ngày làm việc"**
   - ✅ Bỏ tick Thứ 7 (nghỉ thứ 7)
   - ✅ Thêm ngày nghỉ lễ: 2025-12-25
   - ✅ Nhấn "Lưu cài đặt"

5. **Tab "Tăng ca"**
   - ✅ Thay đổi OT ngày thường: 160%
   - ✅ Thay đổi OT cuối tuần: 220%
   - ✅ Thay đổi OT lễ: 350%
   - ✅ Nhấn "Lưu cài đặt"

### ✅ TEST 2: CÀI ĐẶT LƯƠNG NHÂN VIÊN
1. **Tab "Lương nhân viên"**
2. **Chọn nhân viên từ dropdown**
3. **Nhập lương cơ bản:**
   - Nguyễn Văn A: 8,500,000 đ
   - Trần Thị B: 7,800,000 đ
4. **Nhấn "Lưu lương"**
5. **Kiểm tra danh sách đã cập nhật**

### ✅ TEST 3: CÀI ĐẶT CÔNG THỨC LƯƠNG CHUNG
1. **Vào Cài đặt → Công thức lương**
2. **Thay đổi:**
   - Lương cơ bản: 8,000,000 đ
   - Hoa hồng bán máy: 1.5%
   - Thưởng sửa chữa: 12%
3. **Nhấn "ÁP DỤNG CÔNG THỨC"**

### ✅ TEST 4: CHẤM CÔNG THỰC TẾ
1. **Đăng nhập với tài khoản nhân viên**
2. **Vào màn hình Chấm công**
3. **Test CHECK-IN:**
   - ✅ Nhấn "CHECK-IN"
   - ✅ Cho phép camera
   - ✅ Chụp ảnh selfie
   - ✅ Nhận thông báo "CHÀO BUỔI SÁNG! ĐÃ CHECK-IN"
   - ✅ Kiểm tra vị trí GPS được ghi nhận

4. **Test CHECK-OUT (sau 1-2 giờ):**
   - ✅ Nhấn "CHECK-OUT"
   - ✅ Chụp ảnh selfie lần 2
   - ✅ Nhận thông báo thành công
   - ✅ Kiểm tra giờ làm việc được tính

### ✅ TEST 5: XEM BÁO CÁO LƯƠNG
1. **Đăng nhập lại với tài khoản chủ shop**
2. **Vào Chấm công → Báo cáo**
3. **Chọn tháng hiện tại**
4. **Kiểm tra:**
   - ✅ Danh sách nhân viên
   - ✅ Số ngày công
   - ✅ Giờ làm việc
   - ✅ Lương được tính đúng công thức
   - ✅ Có thể xuất CSV

### ✅ TEST 6: TEST CÁC TRƯỜNG HỢP ĐẶC BIỆT
1. **Test đi muộn:**
   - Check-in sau giờ quy định
   - Xem có cảnh báo "Đi muộn"

2. **Test về sớm:**
   - Check-out trước giờ quy định
   - Xem có cảnh báo "Về sớm"

3. **Test OT:**
   - Làm việc quá giờ quy định
   - Kiểm tra giờ OT được tính

4. **Test ngày nghỉ:**
   - Check-in ngày nghỉ lễ
   - Xem có cảnh báo phù hợp

---

## 🔧 TROUBLESHOOTING

### ❌ Lỗi: Không thể upload ảnh
**Nguyên nhân:** Thiếu quyền camera hoặc network
**Giải pháp:**
1. Kiểm tra quyền camera trong Settings
2. Kiểm tra kết nối internet
3. Restart app

### ❌ Lỗi: Không ghi nhận vị trí
**Nguyên nhân:** GPS bị tắt hoặc thiếu quyền
**Giải pháp:**
1. Bật GPS trên thiết bị
2. Cho phép quyền vị trí trong app
3. Restart app

### ❌ Lỗi: Lương tính sai
**Nguyên nhân:** Cài đặt chưa lưu hoặc công thức lỗi
**Giải pháp:**
1. Kiểm tra lại cài đặt thời gian làm việc
2. Kiểm tra cài đặt lương nhân viên
3. Kiểm tra công thức lương chung
4. Restart app và test lại

### ❌ Lỗi: Không thể check-in/out
**Nguyên nhân:** Vị trí không hợp lệ hoặc network lỗi
**Giải pháp:**
1. Kiểm tra cài đặt bán kính cho phép (Settings)
2. Đảm bảo ở trong khu vực làm việc
3. Kiểm tra kết nối mạng

---

## 📞 HỖ TRỢ
Nếu gặp vấn đề trong quá trình test, hãy:
1. 📸 Chụp ảnh màn hình lỗi
2. 📝 Ghi lại các bước thực hiện
3. 📱 Gửi Zalo: **0964.09.59.79**
4. 📧 Email: support@quanghuysoftware.com

---
**✅ TEST HOÀN THÀNH KHI:** Tất cả checklist đều pass và không có lỗi critical.