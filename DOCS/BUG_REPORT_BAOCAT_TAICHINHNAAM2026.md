# BÁO CÁO ĐỐI SOÁT FILE XUẤT SAU SỬA

## Thông tin file kiểm tra

- File: BaoCaoNgay_01012026_31122026.xlsx
- Đường dẫn: D:\ảnh claude\BaoCaoNgay_01012026_31122026.xlsx
- Thời gian sửa file: 02/05/2026 03:45:20
- Sheet: Báo cáo ngày
- Kích thước dữ liệu: 564 dòng x 10 cột

## Kết luận nhanh

- File hiện tại vẫn sai logic tổng hợp, chưa phản ánh bản code mới.
- Mức sai lớn nhất: chỉ xuất 500 giao dịch trong khi tổng quan ghi 783 giao dịch.
- Dấu hiệu rõ: Linh kiện sửa chữa = 1 (đồng), đúng mẫu lỗi của bản code cũ.
- Code app hiện tại đã có fix đúng cho các lỗi này.

## Kết quả đối soát chi tiết

Đối soát theo block GIAO DỊCH thực tế trong file (dòng 39 -> 539):

| Chỉ tiêu | File | Tính từ giao dịch | Lệch |
|---|---:|---:|---:|
| Doanh thu vào | 4.753.398.562 | 2.265.438.562 | +2.487.960.000 |
| Chi phí ra | 9.144.349.771 | 8.197.809.770 | +946.540.001 |
| Ròng sổ quỹ | -4.390.951.209 | -5.932.371.208 | +1.541.419.999 |
| Số giao dịch | 783 | 500 | +283 |
| Doanh thu bán hàng | 4.333.989.002 | 2.053.159.002 | +2.280.830.000 |
| Doanh thu sửa chữa | 293.841.790 | 130.831.790 | +163.010.000 |
| Thu khác | 125.567.770 | 81.447.770 | +44.120.000 |
| Vốn bán hàng | 3.967.872.222 | 1.788.916.743 | +2.178.955.479 |
| Vốn sửa chữa | 80.520.001 | 46.630.000 | +33.890.001 |
| Tổng vốn | 4.048.392.223 | 1.835.546.743 | +2.212.845.480 |
| Lãi gộp bán hàng | 366.116.780 | 264.242.259 | +101.874.521 |
| Lãi gộp sửa chữa | 213.321.789 | 84.201.790 | +129.119.999 |
| Tổng lãi gộp | 579.438.569 | 348.444.049 | +230.994.520 |
| Lợi nhuận thực | 280.478.798 | 86.184.279 | +194.294.519 |

## Các lỗi logic xác nhận từ file

1. Cắt danh sách giao dịch ở mức 500 dòng
- Tác động: thiếu 283 giao dịch, kéo sai toàn bộ tổng hợp.

2. Linh kiện sửa chữa hiển thị 1 đồng
- Tác động: danh mục chi phí sửa chữa sai nghiêm trọng.

3. Danh mục chi phí không khớp chi phí vận hành
- Tổng danh mục trong file: 298.959.771
- Chi phí vận hành suy ra từ giao dịch: 262.259.770
- Lệch: +36.700.001

## Trạng thái code app hiện tại

Đã kiểm tra mã nguồn hiện tại và xác nhận đã sửa đúng:

- Xuất toàn bộ giao dịch, không còn take(500) trong export báo cáo.
- Vốn sửa chữa tính theo cash basis (không tính đơn CÔNG NỢ chưa thu).
- Lãi gộp sửa chữa = Doanh thu sửa chữa cash - Vốn sửa chữa cash.
- Linh kiện sửa chữa tính theo vốn sửa chữa trừ chi đối tác, không phụ thuộc repair.services rỗng.

## Kết luận nguyên nhân

File 03:45 là file xuất từ bản app cũ (hoặc cache build cũ), không phải từ code đã fix hiện tại.

## Hành động cần làm ngay

1. Chạy lại app từ mã hiện tại.
2. Xuất lại báo cáo cùng kỳ 01/01/2026 - 31/12/2026.
3. Đối soát lại; kỳ vọng PASS_ALL, không còn lệch.
