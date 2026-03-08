# Changelog

Tất cả thay đổi đáng chú ý của dự án sẽ được ghi lại trong file này.

---

## [11.0.9] - 2026-03-08

### Cải thiện giao diện
- **Tăng cỡ chữ toàn app**: Đồng bộ font size theo chuẩn app phổ biến (Zalo) — body: 12→14, caption: 11→12, heading tăng 1-2px. Thay thế hơn 65 file, không còn chữ quá nhỏ
- **Biểu đồ fl_chart trên Trang chủ**: Dashboard donut chart + bar chart thay thế biểu đồ cũ — hiện đại, mượt, có animation
- **Redesign Doanh thu & Chi phí**: Giao diện compact chuyên nghiệp với fl_chart (pie chart, bar chart)

### Tính năng mới
- **Thông tin hàng trả trên danh sách bán**: Hiển thị chip số lượng trả, số tiền hoàn trả ngay trên mỗi đơn. Đơn đã trả hết hiện màu xám và không cho trả thêm
- **Bảo vệ quyền truy cập tài chính**: Thêm permission guard cho tất cả view tài chính (Sổ quỹ, Báo cáo, Nhật ký)

### Sửa lỗi
- **Fix lỗi SQL cập nhật công nợ**: Sửa "no such column: paid" — thay double-quoted string bằng parameterized query trong updateDebtPaid
- **Fix tràn biểu đồ tháng**: Di chuyển label ra ngoài SizedBox, clamp chiều cao bar
- **Fix variant import**: Sửa literal \\n trong variant_management_view

### Kỹ thuật
- **Đổi tên**: 'Nhật ký tài chính' → 'Nhật ký hệ thống'
- **UI polish**: Compact activity grid, gộp section tài chính trùng, sửa loading Sổ quỹ
- **DB v89**: Thêm cột debt_payments, seed test data, dọn 8 file không dùng

---

## [11.0.1] - 2026-03-06

### Cải thiện giao diện
- **Giao diện web chuyên nghiệp**: Tab Nhân viên & Tài chính chuyển từ card dọc (icon trên, text dưới) sang dạng ngang compact (icon + text + chevron) — gọn đẹp hơn trên tablet/desktop
- **Grid layout tối ưu**: 3 cột trên tablet/desktop thay vì 2 cột, aspect ratio cao hơn (3.0/2.8) — card nhỏ gọn, không chiếm quá nhiều không gian
- **App icon mới**: Icon app tùy chỉnh cho Android (adaptive), iOS, và Web (favicon + PWA icons)

### Bảo mật
- **Xóa API keys khỏi git**: Loại bỏ google-services.json, GoogleService-Info.plist, firebase_options.dart khỏi version control
- **Cập nhật .gitignore**: Bảo vệ thông tin nhạy cảm

### Kỹ thuật
- **Web data loading**: Await downloadAllFromCloud() trên web thay vì fire-and-forget — dữ liệu hiển thị chính xác khi đăng nhập
- **Cache busting**: APP_VERSION tự động xóa cache khi cập nhật phiên bản web
- **Responsive UI**: 45+ cải thiện responsive cho wide screens (NavigationRail, dashboard, bar chart, grids)

---

## [10.2.0] - 2025-06-03

### Tính năng mới
- **Nhập kho nhanh từ danh sách kho**: Phụ kiện và linh kiện có nút "NHẬP THÊM" khi bấm vào chi tiết sản phẩm — nhập số lượng, giá nhập, phương thức thanh toán → tự động cộng tồn kho và ghi sổ tài chính
- **Mã nhập nhanh cho trang Nhập kho**: Thêm tính năng chọn mã nhập nhanh (Quick Input Code) trên trang Nhập kho thông minh (SmartStockInView) — giống trang Nhập nhanh
- **Tinh gọn thanh công cụ Quản lý kho**: Gom toàn bộ nút chức năng (Nhập kho, Nhanh, Linh kiện, Bán hàng, NCC, In tem, Excel) xuống thanh bottom bar có icon + label

### Cải thiện giao diện
- **Icon web app**: Tạo icon PWA từ logo app (favicon 32x32, Icon 192/512, maskable)
- **Sửa màn hình trắng iOS**: Thêm flutter_native_splash với nền xanh + logo — không còn màn hình trắng khi cài app lần đầu trên iOS

### Kỹ thuật
- **Nâng cấp Gradle/AGP**: Tương thích AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20
- **Build thành công**: Web release + AAB release

---

## [10.1.3] - 2025-06-30

### Tính năng mới
- **Chính sách BH & đổi trả in trên hóa đơn**: Thêm 2 trường "Chính sách bảo hành" và "Chính sách đổi trả" trong Cài đặt máy in. Dùng placeholder `{warrantyPolicy}` và `{returnPolicy}` trong mẫu hóa đơn bán/sửa để in lên phiếu.
- **Giá vốn linh kiện sửa chữa**: Ghi nhận chi phí linh kiện vào Sổ quỹ, hiển thị trong Sổ quỹ, Trang chủ, Nhật ký tài chính

### Sửa lỗi
- **Fix hiển thị tiền mặt = 0**: Sổ quỹ hiện đúng "0" thay vì để trống khi số dư tiền mặt bằng 0
- **Fix lịch làm việc hiển thị T7 = null**: Sửa thiếu key ngày Chủ nhật trong danh sách nhân viên

---

## [10.1.0] - 2025-06-14

### Tính năng mới
- **Thanh toán kết hợp**: Hỗ trợ thanh toán Tiền mặt + Chuyển khoản trong cùng 1 đơn
- **Thu phát sinh**: Thêm tính năng thu nhập ngoài bán hàng (Thu phát sinh) + nhấn giữ để xóa đơn sửa chữa
- **Đơn vị tùy chỉnh**: Cho phép cài đặt đơn vị đo lường riêng cho sản phẩm
- **Lối tắt trả góp NH**: Thêm shortcut trả góp ngân hàng từ màn hình chi tiết
- **Thanh toán trực tiếp**: Loại bỏ luồng "chờ xử lý", thanh toán tức thì khi xác nhận
- **Thiết kế lại Sổ Quỹ**: Danh sách Thu/Chi dạng card đẹp hơn, nhấn để xem chi tiết
- **Thưởng/Trừ nhanh**: Thêm nút lối tắt Thưởng/Trừ lương từ màn hình bảng lương

### Cải thiện giao diện
- **Theme Zalo Blue**: Giao diện chủ đạo xanh Zalo, màn hình giới thiệu redesign
- **Màn hình giới thiệu mới**: Redesign intro screen với hình minh họa đẹp hơn
- **Danh sách thanh toán gọn**: Gộp thông tin thanh toán, bỏ trang UnifiedPaymentPage thừa
- **Tối ưu UI shop thời trang**: Ẩn tính năng sửa chữa (Sổ Quỹ, Nhật ký, Báo cáo) cho shop thời trang/thực phẩm
- **Tab icon rõ ràng hơn**: Sửa icon tab khấu trừ/bảo hiểm/thuế bị trùng màu nền, tăng độ tương phản
- **Sửa tràn giao diện**: Sửa overflow nút Thưởng/Trừ trong danh sách nhân viên

### Sửa lỗi quan trọng
- **Fix quyền lưu khấu trừ**: Sửa lỗi permission-denied khi lưu cài đặt khấu trừ/bảo hiểm/thuế
- **Fix dữ liệu Giao dịch trống**: Tab Giao dịch trong Sổ Quỹ giờ hiển thị đầy đủ dữ liệu thực (bán hàng, chi phí, thu nợ, nhập hàng...)
- **Fix Nhật ký tài chính trống**: Tab Tài chính trong Nhật ký giờ lấy dữ liệu trực tiếp từ Firestore thay vì bảng log rỗng
- **Fix sync trạng thái sửa chữa**: 3 lỗi quan trọng trong syncAllToCloud được sửa
- **Fix đồng bộ thanh toán real-time**: Thanh toán hiện đồng bộ ngay lập tức giữa các thiết bị
- **Fix dữ liệu không nhất quán giữa 2 thiết bị**: Thêm shopId filter cho tất cả truy vấn DB tài chính
- **Fix tên người dùng hiển thị sai**: Sửa lời chào hiển thị 'Người Dùng' thay vì tên thật
- **Fix lưu + điều hướng**: Lưu đơn không tự thoát, chỉ pop khi giao máy/duyệt
- **Fix Firestore rules**: Cập nhật bảo mật cho bảng lương, khấu trừ, cài đặt shop
- **Fix lỗi assertion _dependents**: Gộp gift/discount vào single field tránh crash

### Tái cấu trúc
- Luồng tài chính gọn hơn: Gộp menu tài chính 10 mục → 6 mục
- Xóa 2 view thừa (transaction_detail, financial_reconciliation)
- Cải thiện log nhật ký: Mở rộng bộ lọc, mặc định 30 ngày, tìm kiếm audit log

---

## [10.0.11] - 2026-02-11

### Sửa lỗi & Tối ưu
- Sửa tràn bottom overflow tab Nhật ký tài chính (embedded mode)
- Giới hạn loại hình kinh doanh tạo chi nhánh: chỉ Điện tử & Thời trang
- Đổi mặc định khoảng thời gian từ 30 ngày sang hôm nay (Báo cáo, Nhật ký, Trả góp)
- Sửa 30+ lỗi biên dịch: thiếu khóa đa ngữ, validatePhone, biến sai phạm vi
- Dọn code thừa, xóa import không dùng

### Tối ưu giao diện Tài chính
- Tạo FinancialHubView gộp 4 tab: Báo cáo, Chi phí, Trả góp, Nhật ký
- Thêm chế độ embedded cho 4 view tài chính
- Gộp menu tài chính trang chủ: 10 mục giảm còn 6
- Xóa 2 view mồ côi (transaction_detail, financial_reconciliation)

---

## [10.0.7] - 2026-02-08

### Tính năng mới
- Hoa hồng theo bậc (3 bậc dựa trên giá trị đơn hàng)
- Đơn sửa chữa không cần SĐT khách ngay (nhắc khi giao máy)
- Sửa lỗi tab trang chủ không chuyển ngôn ngữ VI/EN

### Sửa lỗi
- Sửa tính hoa hồng theo bậc, ngày nghỉ âm, ngày làm việc theo cấu hình
- Sửa tab Lịch làm việc trắng (BoxConstraints infinite width)
- Thêm sync work_schedules và employee_salary_settings
- Thêm 28 unit tests cho salary và financial logic

---

## [10.0.5] - 2026-02-05

### Sửa lỗi
- Fix thanh toán trực tiếp
- Sửa đơn bán
- Cải thiện nhập kho

---

## [10.0.4] và trước đó

Xem git log để biết chi tiết các phiên bản trước.

---

*Ghi chú: Phiên bản theo format `major.minor.patch+build`*
