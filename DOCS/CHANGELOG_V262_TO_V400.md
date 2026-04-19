# Changelog v262 den v400

Generated: 2026-04-19
Source: git log --all (version-tagged commits only)
Filter: versions v262..v400

Tong so dong release tim thay: 62

Luu y: Khong tim thay commit gan tag version tu v367 den v400 trong lich su git hien tai.

| Version | Date | Commit | Noi dung |
| --- | --- | --- | --- |
| v262 | 2026-04-18 | bc6cd07e | rollback toàn bộ về bản ổn định 11.3.4+262 |
| v263 | 2026-04-17 | ff2160ed | Lưu tạm đơn bán/sửa + giá vốn từng món + lợi nhuận đơn sửa + bàn phím IP máy in + xóa nợ gọn + tắt bàn phím login Google/Apple |
| v263 | 2026-04-18 | 5a31573f | vá ổn định crash iOS, splash lifecycle và migration DB idempotent |
| v264 | 2026-04-17 | 2846e042 | Sửa bàn phím IP máy in iOS (TextInputType.text + inputFormatters dấu chấm) + fix hủy Apple không báo lỗi |
| v264 | 2026-04-18 | 6a66582b | chuẩn hóa PRAGMA DBHelper sang rawQuery để ổn định startup |
| v265 | 2026-04-18 | 64e6cab9 | Chan stale iOS Podfile.lock va them script reset pods macOS |
| v265 | 2026-04-18 | 74ab33c9 | Khôi phục nhánh v262 theo Firebase, bỏ Mongo và thêm hardening iOS Pods |
| v266 | 2026-04-18 | 2553eb48 | Audit git log tu thang 3 va lap ke hoach khoi phuc tinh nang da mat |
| v267 | 2026-04-18 | c180d2e1 | Chan double sync iOS khi vao Home de tranh crash native Firebase |
| v268 | 2026-04-19 | b4732be2 | bổ sung scope chi phí và deep-link thông báo vào chi tiết đơn |
| v269 | 2026-04-19 | 0cb38d57 | bổ sung lối tắt nhập kho mới và hàng chờ sang kho |
| v270 | 2026-04-19 | a77d020c | bổ sung kiểm tra kết nối Firestore trong trung tâm đồng bộ |
| v271 | 2026-04-19 | 0b37d4f1 | Sửa triệt để đồng bộ trạng thái đơn sửa và chống ghi đè sai trạng thái |
| v272 | 2026-04-19 | 8d85f6f5 | them bao cao trang thai sync theo nghiep vu trong trung tam dong bo |
| v273 | 2026-04-19 | e3e6f599 | Hoàn thành Phase 2: ghi lịch sử sync bền vững và thống kê 24h theo nghiệp vụ |
| v274 | 2026-04-17 | 205106a2 | sua 6 loi compile tu cherry-pick: RepairService.serviceName, stock_entry .get(), attendance firestoreQueryWithTimeout, ActivityFeedCard params, inventory duplicate bottom bar, recent_activity import |
| v274 | 2026-04-19 | 5211a9f5 | Hoàn thiện Phase 3: cảnh báo kẹt sync chủ động và xuất báo cáo vận hành |
| v275 | 2026-04-18 | 4de8e63b | sua NPE crash: email! -> email??, them stack trace vao GLOBAL ERROR, boc ngoai try/catch cho initRealTimeSync, sua catchError void return |
| v275 | 2026-04-19 | e1c45b34 | Chốt checklist Phase 3 và xác nhận hoàn tất triển khai Sync Observability |
| v276 | 2026-04-18 | f13eb9a4 | Fix crash iOS 'freed pointer was not the last allocation': them WAL mode + singleInstance cho SQLite, xoa double getIdToken(true), doi Future.microtask sang Future.delayed(2s) tranh race condition voi Firestore/SQLite |
| v276 | 2026-04-19 | 949886d1 | Chuyển hệ thống về Firebase-only, loại bỏ MongoDB local mode |
| v277 | 2026-04-18 | 711f4fb5 | fix triệt để crash iOS: chặn race AnimationController ở Splash, bật WAL đúng chuẩn onConfigure, thay file_picker bằng file_selector để loại xung đột FileUtils và ổn định native |
| v277 | 2026-04-19 | aaad7ae4 | Hardening Firebase-only và dọn sạch artifacts local |
| v278 | 2026-04-18 | cdb07d53 | tạo mới trang thống kê Firebase Read/Write chi tiết, đọc trực tiếp số liệu cloud theo collection, track realtime listeners và read/write thực tế từ app |
| v278 | 2026-04-19 | d5a6c39a | Chốt checklist hardening Firebase-only và cập nhật build |
| v279 | 2026-04-18 | 35c289c1 | ổn định crash splash sync và thêm mục thống kê Firebase |
| v280 | 2026-04-18 | 0f624566 | chặn crash splash iOS và khóa download startup tránh chồng sync |
| v281 | 2026-04-18 | ccf1f740 | khóa race mở DB và bật iOS stable mode startup |
| v295 | 2026-04-01 | 73798a3b | Sửa lỗi hệ thống ổn định - timeout+cache fallback cho Firestore reads |
| v296 | 2026-04-01 | 4b7abea7 | Sửa lỗi kho máy xác không hiển thị dữ liệu |
| v297 | 2026-04-01 | c5d6ca74 | Sửa timeout Firestore toàn bộ màn hình + fix lỗi mất shopId trong expense model |
| v298 | 2026-04-01 | e7529f54 | Thêm timeout Firestore cho toàn bộ services + views còn lại |
| v299 | 2026-04-01 | 94bc4822 | FIX NGHIÊM TRỌNG sync - sửa mất dữ liệu shopId, timestamp, soft-delete |
| v300 | 2026-04-02 | 83d9cb55 | Sửa lỗi deadline-exceeded khi bán hàng - tự động verify + recovery |
| v301 | 2026-04-02 | 38600b8c | Sửa đồng bộ kho máy xác, sửa crash AppLocalizations, tính doanh thu ĐT riêng cho lương NV, thêm tính năng đổi ca |
| v301 | 2026-04-02 | 5ed0b7a7 | Sửa đồng bộ kho máy xác, sửa crash AppLocalizations, tính doanh thu ĐT riêng cho lương NV, thêm tính năng đổi ca |
| v302 | 2026-04-02 | 23a67d3b | Sửa đồng bộ kho máy xác + lưu lịch làm việc nhân viên |
| v303 | 2026-04-02 | 5e0d913c | Sửa liên kết/hủy Apple Google không cập nhật UI ngay trong tab cài đặt |
| v304 | 2026-04-02 | 72eb3d93 | Sửa xóa tài khoản xong spinner xoay mãi không cho đăng nhập lại |
| v305 | 2026-04-02 | 68caeb57 | Sửa bàn phím iOS không có dấu chấm khi nhập IP máy in + sửa QR tem kiểm kho không khớp |
| v306 | 2026-04-02 | a158d81d | Sửa bàn phím iOS nhập IP máy in - tự động chuyển dấu phẩy thành dấu chấm cho locale tiếng Việt |
| v306 | 2026-04-02 | e1bfa2d9 | Sửa bàn phím iOS nhập IP máy in - tự động chuyển dấu phẩy thành dấu chấm cho locale tiếng Việt |
| v307 | 2026-04-03 | cc2d2c0f | Sửa thông báo kho/NV bị block, hiện giá đơn sửa chưa nhập, tối ưu tốc độ nhập kho+chat, sửa sync đơn bán kẹt, thêm lối tắt chi phí tab tài chính, nâng cấp xuất Excel thu chi chuyên nghiệp 3 sheet |
| v307 | 2026-04-03 | e47bfa9d | Sửa thông báo kho/NV bị block, hiện giá đơn sửa chưa nhập, tối ưu tốc độ nhập kho+chat, sửa sync đơn bán kẹt, thêm lối tắt chi phí tab tài chính, nâng cấp xuất Excel thu chi chuyên nghiệp 3 sheet |
| v308 | 2026-04-04 | d19eabc4 | Thêm điều hướng khi bấm thông báo - vào thẳng đơn sửa/bán chi tiết |
| v308 | 2026-04-04 | f2b1431e | Thêm điều hướng khi bấm thông báo - vào thẳng đơn sửa/bán chi tiết |
| v309 | 2026-04-04 | d677d60e | Thêm bộ lọc danh mục chi phí + sửa chat hiện spinner/trống khi mở lại |
| v309 | 2026-04-04 | fba4b269 | Thêm bộ lọc danh mục chi phí + sửa chat hiện spinner/trống khi mở lại |
| v310 | 2026-04-04 | 0808d539 | Sửa crash setState sau dispose, sửa lọc chi phí, thêm ĐÓNG TIỀN loại trừ tài chính, sửa lợi nhuận sửa chữa trong báo cáo ngày |
| v311 | 2026-04-04 | 4b272faf | Tối ưu chấm công batch query, sửa chat cold-start, thêm tab CHI TIẾT chấm công, kế hoạch audit toàn app |
| v311 | 2026-04-04 | de43b60f | Tối ưu chấm công batch query, sửa chat cold-start, thêm tab CHI TIẾT chấm công, kế hoạch audit toàn app |
| v312 | 2026-04-04 | 66194861 | Sửa crash EXC_BAD_ACCESS - fix memory leak dialog controller, chặn orphan subscription sync, thêm idempotency key tự động, ngăn double-tap, cải thiện validation và error logging |
| v313 | 2026-04-05 | 12b09467 | Sửa nhập kho treo khi lưu (thêm timeout 30s), sửa bàn phím iOS không nhập được dấu chấm IP máy in, sửa web không đăng xuất được |
| v314 | 2026-04-05 | 339bf05f | Phân loại chi phí SHOP / CÁ NHÂN: thêm scope vào model, DB, dialog thu/chi, filter, badge, loại trừ CÁ NHÂN khỏi doanh thu, xuất Excel |
| v314 | 2026-04-05 | cb2a7d3f | Phân loại chi phí SHOP / CÁ NHÂN: thêm scope vào model, DB, dialog thu/chi, filter, badge, loại trừ CÁ NHÂN khỏi doanh thu, xuất Excel |
| v360 | 2026-04-07 | d52dd0ff | Sửa chẩn đoán app treo tab Nhân viên/Chat + đổi lối tắt thêm chi/thu về trang đầy đủ |
| v361 | 2026-04-07 | 26031c69 | Sửa Firestore gRPC nghẽn kênh — chẩn đoán + tab Nhân viên + Chat cùng treo |
| v362 | 2026-04-07 | 0a5946b6 | Lối tắt Thêm chi/thu mở thẳng dialog ghi chép + thu gọn danh sách chi phí |
| v363 | 2026-04-07 | 9dfa57bc | Thêm trang Test Kết Nối Firestore - kiểm tra từng bước Auth, ShopId, Firestore ping, cache, realtime listeners, chat stream, staff query, sync query với giao diện trực quan hiển thị tiến trình và lỗi chính xác |
| v364 | 2026-04-07 | 3bf83e80 | Sửa đúng shortcut thêm chi thêm thu sang trang Chi Phí và thu gọn danh sách giao dịch |
| v365 | 2026-04-07 | fb0c8651 | Chặn hẳn dialog nhanh cũ ở Home và ép thêm chi thêm thu mở sang trang Chi Phí |
| v366 | 2026-04-07 | 6887be7e | Giảm listener nền realtime và chuyển HR audit salvage sang on-demand |
