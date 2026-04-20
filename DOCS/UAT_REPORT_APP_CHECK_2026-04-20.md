# Biên bản UAT 2 máy - App Check và đồng bộ

## 1) Thông tin chung
- Dự án: quanlyshop
- Ngày kiểm thử: 2026-04-20
- Mục tiêu: tích hợp Firebase App Check (Android + iOS) để xử lý dứt điểm lỗi upload ảnh, sau đó chạy checklist UAT 14 mục
- Môi trường thực thi hiện tại: Windows

## 2) Thiết bị kiểm thử
- Máy A (đã chạy): Android CPH1989, deviceId HE5TAAIJAADIZ9JV
- Máy B (yêu cầu): iPhone 17 Pro Max
- Trạng thái máy B trong phiên này: BLOCKED (không có môi trường build/chạy iOS trên Windows và không có luồng log iOS trực tiếp trong phiên)

## 3) Kết quả tích hợp App Check
### 3.1. Kết quả kỹ thuật
- Đã tích hợp Firebase App Check trong startup app tại main app bootstrap.
- Đã tạo và allowlist debug token Android cho appId 1:51200928212:android:fdd5862b241eb527910e41.
- Đã chạy lại app sau khi allowlist token.

### 3.2. Kiểm tra log sạch (Android)
- appcheck_errors = 0
- storage_unauthorized = 0
- Không còn các chuỗi lỗi:
  - Error getting App Check token
  - No AppCheckProvider installed
  - App attestation failed
  - Too many attempts
  - firebase_storage/unauthorized
  - StorageException

## 4) Checklist UAT 14 mục (Pass/Fail)
Ghi chú trạng thái:
- PASS: đã kiểm thử và đạt
- FAIL: đã kiểm thử và lỗi
- PARTIAL: mới xác nhận một phần, cần chạy lại đầy đủ
- BLOCKED: không thể chạy trong phiên hiện tại

| STT | Hạng mục | Bước kiểm thử | Android (Máy A) | iOS (Máy B) | Ghi chú bằng chứng |
|---|---|---|---|---|---|
| 1 | Đăng nhập và vào Home | Đăng nhập tài khoản chủ shop, vào màn Home | PASS | BLOCKED | App chạy ổn định, có log tải Home và thống kê |
| 2 | Kích hoạt App Check | Khởi động app và xác nhận không còn lỗi token/attestation | PASS | BLOCKED | Bộ lọc log App Check = 0 lỗi |
| 3 | Upload ảnh phiếu sửa | Tạo/sync phiếu sửa có ảnh | PASS | BLOCKED | Không còn StorageException hoặc unauthorized |
| 4 | Sync phiếu sửa lên cloud | Kiểm tra sync repairs sau upload | PASS | BLOCKED | Có log "Synced 1 repairs to cloud" |
| 5 | Sync health tổng thể | Chạy kiểm tra local/cloud mismatch | PASS | BLOCKED | Có log Sync Health: Mismatches = 0 |
| 6 | Sửa thông tin nhân viên | Đổi tên/quyền và bấm Lưu | PARTIAL | BLOCKED | Đã có fallback callable phía backend, chưa chạy lại full flow 2 máy trong phiên này |
| 7 | Đăng ký tài khoản mới | Đăng ký xong phải tự điều hướng vào Home | FAIL | BLOCKED | Người dùng báo còn ở trang đăng ký ([eror list.txt](eror%20list.txt#L4)) |
| 8 | Thiết lập loại hình kinh doanh | Nhân viên đăng nhập lần đầu không bị bật popup sai ngữ cảnh | FAIL | BLOCKED | Người dùng báo vẫn hiện popup ([eror list.txt](eror%20list.txt#L6)) |
| 9 | Nhập kho và cập nhật danh sách kho | Xác nhận nhập kho xong phải thấy hàng ngay | FAIL | BLOCKED | Người dùng báo chưa thấy hàng sau nhập kho ([eror list.txt](eror%20list.txt#L11)) |
| 10 | Đồng bộ khách hàng chéo máy | Thêm khách trên máy A, máy B nhận realtime | FAIL | BLOCKED | Người dùng báo phải đăng xuất/đăng nhập lại ([eror list.txt](eror%20list.txt#L8)) |
| 11 | Chấm công + tính lương | Mở màn lương/chấm công theo tháng | FAIL | BLOCKED | Có lỗi Firestore requires index và permission-denied trong luồng lương/chấm công |
| 12 | Cash closing notifier | Poll dữ liệu chốt quỹ theo shop | FAIL | BLOCKED | Có lỗi requires index cho cash_closings |
| 13 | Push/chat thông báo chéo máy | Tạo đơn sửa có ảnh và kiểm tra thông báo/chat máy còn lại | FAIL | BLOCKED | Người dùng báo push/chat không tới máy còn lại ([eror list.txt](eror%20list.txt#L9), [eror list.txt](eror%20list.txt#L10)) |
| 14 | Độ sạch log runtime | Không còn error gây chặn nghiệp vụ chính | PARTIAL | BLOCKED | App Check + Storage sạch; vẫn còn lỗi nghiệp vụ khác theo UAT mục 7-13 |

## 5) Danh sách bug theo mức độ và gợi ý fix

### Critical
1. Đăng ký xong không tự vào Home.
- Ảnh hưởng: chặn onboarding người dùng mới.
- Bằng chứng: [eror list.txt](eror%20list.txt#L4)
- Gợi ý fix: sau register thành công, gọi đồng bộ user/shop xong rồi điều hướng thẳng Home; tránh chặn bởi điều kiện role/shop chưa refresh.

2. Popup thiết lập loại hình kinh doanh bật sai cho nhân viên.
- Ảnh hưởng: sai luồng phân quyền, gây nhầm cấu hình shop.
- Bằng chứng: [eror list.txt](eror%20list.txt#L6)
- Gợi ý fix: chỉ cho owner/super admin chạy flow setup business type; employee luôn skip.

3. Khách hàng thêm mới không sync realtime sang máy còn lại.
- Ảnh hưởng: dữ liệu bán hàng/chăm sóc khách bị trễ.
- Bằng chứng: [eror list.txt](eror%20list.txt#L8)
- Gợi ý fix: kiểm tra EventBus emit sau upsert customer + subscription customers trong SyncService; xác nhận không bị role-gate nhầm.

4. Tính lương/chấm công lỗi index/permission.
- Ảnh hưởng: module nhân sự không dùng được ổn định.
- Bằng chứng: log runtime có requires index cho attendance theo shopId + userId + dateKey.
- Gợi ý fix: tạo composite index bắt buộc và rà lại rule read cho dữ liệu setting lương.

5. Cash closing lỗi requires index.
- Ảnh hưởng: polling chốt quỹ fail, gây mất cảnh báo tài chính.
- Bằng chứng: log runtime có requires index cho cash_closings theo shopId + createdAt.
- Gợi ý fix: thêm index tương ứng vào Firestore, deploy index, giữ retry/backoff nhẹ ở client.

6. Push/chat liên máy lỗi sau tạo phiếu sửa có ảnh.
- Ảnh hưởng: mất thông báo realtime giữa chủ shop và nhân viên.
- Bằng chứng: [eror list.txt](eror%20list.txt#L9), [eror list.txt](eror%20list.txt#L10)
- Gợi ý fix: kiểm tra pipeline gửi push khi tạo/sync repair (FCM token hợp lệ, ownership token, quyền gửi).

### Medium
1. Nhập kho xong chưa thấy hàng ngay.
- Ảnh hưởng: UX kho chậm cập nhật, dễ hiểu nhầm mất dữ liệu.
- Bằng chứng: [eror list.txt](eror%20list.txt#L11)
- Gợi ý fix: đảm bảo emit đúng event sau xác nhận nhập kho và refresh list từ local DB theo debounce ngắn.

2. Luồng sửa nhân viên mới xác nhận PARTIAL trong phiên này.
- Ảnh hưởng: chưa có bằng chứng full UAT 2 máy sau bản fix mới.
- Gợi ý fix: chạy lại test case owner sửa nhân viên trên máy A, kiểm tra máy B nhận thay đổi realtime.

### Minor
1. Mật độ hiển thị list kho còn thấp, icon dư thừa.
- Ảnh hưởng: tốn không gian, giảm hiệu suất thao tác.
- Bằng chứng: [eror list.txt](eror%20list.txt#L7), [eror list.txt](eror%20list.txt#L12), [eror list.txt](eror%20list.txt#L13)
- Gợi ý fix: tối ưu row height, gom icon hành động vào menu overflow, ưu tiên thông tin chính trên 1-2 dòng.

## 6) Kết luận
- Mục tiêu chính App Check cho Android đã đạt: không còn lỗi token/attestation và không còn lỗi upload ảnh Storage trong log hiện tại.
- Biên bản UAT 14 mục đã lập đủ trạng thái Pass/Fail; nhiều hạng mục còn FAIL/BLOCKED do cần kiểm thử trực tiếp máy iOS và xử lý thêm index/rule.
- Cần một vòng xác nhận bổ sung trên iPhone để chốt đầy đủ tiêu chí "2 máy" trước khi đóng release.
