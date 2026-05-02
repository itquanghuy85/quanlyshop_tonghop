# BÁO CÁO ĐỐI SOÁT FILE FlutterExcel (10).xlsx VỚI ẢNH

## 1) Dữ liệu kiểm tra

- File: C:\Users\Admin\Downloads\FlutterExcel (10).xlsx
- Kích thước: 7,778 bytes
- Sheet: Báo cáo ngày
- Ảnh đối chiếu:
  - Ảnh Trang chủ (thẻ tài chính nhanh)
  - Ảnh Tài chính > Tổng quan
  - Ảnh Tài chính > Phân tích

## 2) Số liệu đọc được từ file

- Ngày báo cáo: 02/05/2026
- Doanh thu vào: 36.27 Tr
- Chi phí ra: 62.40 Tr
- Ròng sổ quỹ: -26.13 Tr
- Lợi nhuận thực: -23.01 Tr
- Số giao dịch: 19

## 3) Đối soát với ảnh (mức hiển thị)

### 3.1 Ảnh Tài chính > Tổng quan/Phân tích

- Ảnh hiển thị:
  - Tiền vào: 24.27 Tr
  - Tiền ra: 52.8 Tr
  - Ròng: -28.53 Tr
  - 14 GD
  - Vốn BH: 10.3 Tr
  - Vốn SC: 2.05 Tr
  - Vốn tổng: 12.35 Tr
  - Lãi BH: 1.97 Tr
  - Lãi SC: 2.95 Tr
  - Lãi tổng: 4.92 Tr

- File hiển thị:
  - Doanh thu vào: 36.27 Tr
  - Chi phí ra: 62.4 Tr
  - Ròng: -26.13 Tr
  - 19 GD
  - Vốn BH: 20.5 Tr
  - Vốn SC: 2.05 Tr
  - Vốn tổng: 22.55 Tr
  - Lãi BH: 4.04 Tr
  - Lãi SC: 2.95 Tr
  - Lãi tổng: 6.99 Tr

Kết luận: Không khớp.

### 3.2 Ảnh Trang chủ

- Ảnh Trang chủ cho thấy:
  - Thu: 36.27 Tr
  - Chi: 65.45 Tr
  - Ròng: -29.18 Tr

- File cho thấy:
  - Thu: 36.27 Tr (khớp)
  - Chi: 62.4 Tr (không khớp)
  - Ròng: -26.13 Tr (không khớp)

Kết luận: Khớp một phần (Thu), còn lại không khớp.

## 4) Kiểm tra logic nội bộ của chính file (rất quan trọng)

Mình tính lại trực tiếp từ block GIAO DỊCH trong file:

- Khớp:
  - Doanh thu vào, Chi phí ra, Ròng sổ quỹ, Số giao dịch
  - Doanh thu bán hàng, Doanh thu sửa chữa, Thu khác
  - Vốn sửa chữa, Lãi gộp sửa chữa

- Không khớp:
  - Vốn bán hàng: file 20.5 Tr, tính từ giao dịch 10.3 Tr
  - Tổng vốn: file 22.55 Tr, tính từ giao dịch 12.35 Tr
  - Lãi gộp bán hàng: file 4.04 Tr, tính từ giao dịch 1.97 Tr
  - Tổng lãi gộp: file 6.99 Tr, tính từ giao dịch 4.92 Tr
  - Lợi nhuận thực: file -23.01 Tr, tính từ giao dịch -25.08 Tr

Kết luận logic file:

- File FlutterExcel (10).xlsx bị sai KPI vốn/lãi bán hàng so với chính bảng giao dịch trong file.

## 5) Fix đã triển khai trong code

1. Chặn lệch KPI khi export:
- Khi xuất Excel, hệ thống tính lại KPI chính trực tiếp từ danh sách giao dịch trước khi ghi file.
- Mục tiêu: số tổng quan luôn nhất quán với bảng GIAO DỊCH trong file.

2. Tăng minh bạch đối soát:
- File xuất thêm:
  - Cửa hàng
  - Shop ID
  - Thời điểm xuất

3. Sửa lỗi UI tràn tab:
- Tăng chiều cao tab bar để xử lý cảnh báo BOTTOM OVERFLOWED BY 2.0 PIXELS trên thiết bị thực tế.

## 6) Kết luận cuối cùng

- File FlutterExcel (10).xlsx hiện tại chưa đúng logic ở nhóm KPI vốn/lãi bán hàng.
- Code đã được vá để loại lỗi này ở các file xuất mới sau khi cập nhật app.
