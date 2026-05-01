# GHI CHÚ CẬP NHẬT CH PLAY (SO VỚI 1.0.2)

Mốc so sánh: 1.0.2 (2026-04-19)
Bản phát hành hiện tại: 1.0.5+523
Ngày cập nhật note: 2026-05-01

## 1) Tóm tắt thay đổi nổi bật

- Nâng cấp trải nghiệm tài chính với Finance V2 làm luồng chính.
- Cải thiện độ chính xác dữ liệu nhập kho linh kiện theo phương thức thanh toán.
- Dọn dẹp giao diện vận hành, loại bỏ nút tạo data demo khỏi khu Cài đặt/Home.
- Tăng ổn định đồng bộ và theo dõi tài chính.

## 2) Cải tiến nghiệp vụ chính

### 2.1 Tài chính
- Chuẩn hóa hiển thị số âm/dương ở các chỉ số ròng.
- Bổ sung nhóm chỉ số vốn/lãi theo nguồn (bán hàng, sửa chữa).
- Cải thiện so sánh kỳ hiện tại với kỳ trước.

### 2.2 Nhập kho linh kiện/phụ kiện
- Khi chọn TIỀN MẶT/CHUYỂN KHOẢN:
  - Ghi chi phí tài chính đầy đủ.
  - Ghi nhật ký hoạt động tài chính.
- Khi chọn CÔNG NỢ:
  - Bắt buộc có NCC.
  - Ghi nhận công nợ NCC (SHOP_OWES) đầy đủ.
  - Đồng bộ dữ liệu công nợ lên cloud qua hàng đợi.

### 2.3 Vệ sinh hệ thống
- Loại bỏ các entry UI tài chính V1 không còn dùng.
- Loại bỏ điểm truy cập tạo dữ liệu demo trong luồng cài đặt vận hành.

## 3) Lợi ích cho người dùng cuối

- Số liệu tài chính và công nợ nhất quán hơn khi nhập kho.
- Dễ theo dõi vốn/lãi theo từng nguồn doanh thu.
- Giảm thao tác thừa và giảm rủi ro bấm nhầm tính năng demo.

## 4) Đề xuất nội dung ngắn cho ô Release Notes trên CH Play

Bản cập nhật mới giúp quản lý tài chính chính xác và dễ theo dõi hơn:
- Nâng cấp màn hình tài chính (Finance V2) với so sánh kỳ trước rõ ràng.
- Sửa lỗi ghi nhận tài chính/công nợ khi nhập thêm linh kiện theo từng hình thức thanh toán.
- Tối ưu giao diện cài đặt, loại bỏ chức năng tạo dữ liệu demo khỏi môi trường vận hành.
- Cải thiện ổn định và đồng bộ dữ liệu.

## 5) Checklist trước khi đẩy CH Play

- Build AAB release thành công.
- Xác nhận web deploy thành công.
- Xác nhận chức năng nhập kho 3 case: tiền mặt, chuyển khoản, công nợ NCC.
- Commit/tag release nội bộ.
- Upload AAB lên Play Console + điền release notes.
