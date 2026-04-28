🔲 PHASE 1: Module VAT
Bật flag
Trong file expansion_feature_flags.dart, dòng safeDefaults:

#	Thao tác	Kết quả mong đợi
1.1	Build lại app	Build thành công, không crash khi mở
1.2	Tạo 1 đơn bán → hoàn tất	Đơn bán lưu bình thường như cũ
1.3	Trong màn tạo đơn bán	Thấy xuất hiện nút/tùy chọn tạo hóa đơn VAT
1.4	Bấm tạo hóa đơn VAT	Mở màn nhập thông tin người mua
1.5	Nhập: tên công ty, MST, địa chỉ, email	Form nhận đủ thông tin, không báo lỗi lạ
1.6	Bấm Xác nhận tạo hóa đơn	Thông báo thành công
1.7	Kiểm tra số tiền + thuế	Thuế hiển thị đúng (ví dụ 10% × giá bán)
1.8	Tạo thêm 1 đơn bán không dùng VAT	Đơn bán vẫn lưu bình thường như cũ
Nếu lỗi → tắt flag
Xác nhận: đơn bán vẫn tạo được bình thường.

🔲 PHASE 2: Module CRM
Bật flag
#	Thao tác	Kết quả mong đợi
2.1	Build lại app	Build thành công
2.2	Vào Quản lý khách hàng	Danh sách khách vẫn hiển thị đầy đủ như cũ
2.3	Long-press hoặc tap 3 chấm 1 khách hàng	Xuất hiện menu có mục "Xem điểm"
2.4	Bấm "Xem điểm"	Mở màn hiển thị điểm khách hàng
2.5	Màn điểm	Thấy số điểm hiện tại, hạng thành viên (Thường/Bạc/Vàng/Platinum)
2.6	Bấm "Đổi điểm"	Mở màn đổi điểm với bộ chọn bước 500 điểm
2.7	Chọn 500 điểm → Xác nhận	Thông báo thành công, điểm giảm đúng
2.8	Bấm "Lịch sử điểm"	Thấy bản ghi Redeem vừa thực hiện
2.9	Quay lại danh sách khách hàng	Hiển thị bình thường, không bị lỗi reload
2.10	Thêm/Sửa/Xóa khách hàng	Vẫn hoạt động như cũ
Nếu lỗi → tắt flag
Xác nhận: menu 3 chấm khách hàng không còn mục "Xem điểm".

🔲 PHASE 3: Module Pricing
Bật flag
#	Thao tác	Kết quả mong đợi
3.1	Build lại app	Build thành công
3.2	Tạo đơn bán → thêm 1 sản phẩm	Sản phẩm thêm vào giỏ bình thường
3.3	Nhìn vào dòng sản phẩm trong giỏ	Thấy xuất hiện icon 💲 (chọn giá linh hoạt)
3.4	Bấm icon đó	Mở bottom sheet với 3 lựa chọn: Thường / VIP / Sỉ
3.5	Chọn "VIP" → Áp dụng	Sheet đóng, giá dòng sản phẩm cập nhật theo giá VIP
3.6	Kiểm tra tổng tiền đơn	Tổng tính lại đúng theo giá VIP
3.7	Bấm Áp dụng với "Thường"	Giá về lại giá gốc
3.8	Tạo đơn bán không bấm icon giá	Đơn bán hoạt động bình thường, giá không tự đổi
3.9	Lưu đơn bán	Lưu thành công, giá đúng như đã chọn
Nếu lỗi → tắt flag
Xác nhận: icon giá linh hoạt biến mất, tạo đơn bình thường.

🔲 PHASE 4: Module Advanced Inventory
Bật flag
#	Thao tác	Kết quả mong đợi
4.1	Build lại app	Build thành công
4.2	Vào danh sách sản phẩm → bấm 1 sản phẩm	Mở chi tiết sản phẩm bình thường
4.3	Trong chi tiết sản phẩm	Thấy nút "Xem tồn kho nâng cao"
4.4	Bấm nút đó	Mở màn BatchListView với 2 tab: "Còn hàng" / "Tất cả"
4.5	Lần đầu, tab Còn hàng	Hiện trống (chưa có batch)
4.6	Bấm nút ➕ (FAB) để nhập kho	Mở màn form nhập kho
4.7	Nhập: số lượng = 10, giá vốn, ngày nhập hôm nay	Form nhận đủ thông tin
4.8	Thêm vị trí kho: gõ "A1" → Thêm	Vị trí "A1" xuất hiện trong dropdown
4.9	Chọn vị trí A1 → bấm Nhập kho	Thông báo thành công, quay về BatchListView
4.10	Tab "Còn hàng"	Thấy batch mới: SL=10, vị trí A1
4.11	Nhập thêm batch 2: số lượng = 5, vị trí B1	Batch 2 xuất hiện trong danh sách
4.12	Kiểm tra thanh tổng	"Tổng tồn: 15" (10+5)
4.13	Tạo đơn bán sản phẩm đó (bán 6)	Đơn bán lưu bình thường (FIFO xử lý nền)
4.14	Quay lại BatchListView	Batch 1: còn 4 (trừ trước), Batch 2: còn 5 (chưa đụng)
4.15	Inventory cũ của app	Vẫn hiển thị đúng, không bị ảnh hưởng
Nếu lỗi → tắt flag
Xác nhận: nút "Xem tồn kho nâng cao" biến mất, inventory cũ vẫn chạy.

🔲 PHASE 5: Module Multi-Branch
Bật flag
#	Thao tác	Kết quả mong đợi
5.1	Build lại app	Build thành công
5.2	Mở Home tab	Thấy nút "Chi nhánh hiện tại: Chưa chọn" ở đầu trang
5.3	Bấm nút đó	Mở màn chọn chi nhánh (danh sách rỗng)
5.4	Quay lại, vào màn Quản lý chi nhánh	Mở được, thấy FAB "Thêm chi nhánh"
5.5	Thêm chi nhánh "HCM"	Xuất hiện trong danh sách
5.6	Thêm chi nhánh "Hà Nội"	Danh sách có 2 chi nhánh
5.7	Bấm nút Home → "Chi nhánh hiện tại: Chưa chọn"	Mở màn selector
5.8	Chọn "HCM" → Xác nhận	Thông báo "Đã chuyển sang HCM", quay về Home
5.9	Nút trên Home	Đổi thành "Chi nhánh hiện tại: HCM"
5.10	Bấm lại → chọn "Hà Nội" → Xác nhận	Nhãn đổi thành "Hà Nội"
5.11	Tạo đơn bán	Đơn bán vẫn tạo thành công, không bị ảnh hưởng
5.12	Thoát app, mở lại	App không crash, hoạt động bình thường
Nếu lỗi → tắt flag
Xác nhận: nút chi nhánh biến mất, Home hiển thị bình thường.

🔲 BƯỚC CUỐI: Kiểm tra sau khi bật tất cả
Sau khi đã test xong từng phase và không có lỗi, chạy lại baseline:

#	Thao tác	Kết quả mong đợi
F.1	Tạo đơn bán mới	Hoàn thành bình thường
F.2	Xem danh sách sản phẩm	Dữ liệu không bị mất
F.3	Xem danh sách đơn sửa (nếu có)	Dữ liệu đầy đủ
F.4	Kiểm tra doanh thu	Số liệu vẫn đúng như trước
F.5	Đăng xuất → đăng nhập lại	Không crash, vào app bình thường
Nếu bất kỳ bước nào ❌ → tắt ngay flag của phase đó và báo lại số bước và mô tả lỗi nhìn thấy.