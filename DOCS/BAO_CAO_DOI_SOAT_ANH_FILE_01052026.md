# BÁO CÁO ĐỐI SOÁT ẢNH + FILE EXCEL (01/05/2026)

## 1) Dữ liệu đầu vào đã kiểm tra

- File: `D:\ảnh claude\BaoCaoNgay_01052026_01052026.xlsx`
- Kích thước: `7,622 bytes`
- Sheet: `Báo cáo ngày`
- Ảnh giao diện:
  - Ảnh trang chủ (thẻ tài chính nhanh)
  - Ảnh tab `Tài chính > Tổng quan`
  - Ảnh tab `Tài chính > Phân tích`

## 2) Kết quả đối soát “Ảnh vs File”

### 2.1 Chỉ tiêu tổng quan

| Chỉ tiêu | Ảnh Tài chính (Tổng quan/Phân tích) | File 01/05 | Kết luận |
|---|---:|---:|---|
| Tiền thu vào | 24.27 Tr | 51.65 Tr | Không khớp |
| Tiền chi ra | 52.8 Tr | 56.00 Tr | Không khớp |
| Dòng tiền ròng | -28.53 Tr | -4.35 Tr | Không khớp |
| Số giao dịch | 14 GD | 18 GD | Không khớp |

### 2.2 Ghi chú quan trọng

- Ảnh tab `Phân tích` thể hiện kỳ đang xem là `02/05`.
- File đính kèm lại là `BaoCaoNgay_01052026_01052026.xlsx` (kỳ `01/05`).
- Do khác kỳ ngày, việc không khớp số là **đúng về mặt dữ liệu**, không phải sai cộng trừ trong file.

## 3) Kiểm tra logic nội bộ của file Excel (rất chi tiết)

Đối chiếu từng chỉ tiêu tổng hợp với block `GIAO DỊCH` trong chính file:

| Chỉ tiêu | Trong file | Tính lại từ giao dịch | Lệch |
|---|---:|---:|---:|
| Doanh thu vào | 51,650,000 | 51,650,000 | 0 |
| Chi phí ra | 56,000,000 | 56,000,000 | 0 |
| Ròng sổ quỹ | -4,350,000 | -4,350,000 | 0 |
| Số giao dịch | 18 | 18 | 0 |
| Doanh thu bán hàng | 48,150,000 | 48,150,000 | 0 |
| Doanh thu sửa chữa | 2,500,000 | 2,500,000 | 0 |
| Thu khác | 1,000,000 | 1,000,000 | 0 |
| Vốn bán hàng | 40,100,000 | 40,100,000 | 0 |
| Vốn sửa chữa | 11,000,000 | 11,000,000 | 0 |
| Tổng vốn | 51,100,000 | 51,100,000 | 0 |
| Lãi gộp bán hàng | 8,050,000 | 8,050,000 | 0 |
| Lãi gộp sửa chữa | -8,500,000 | -8,500,000 | 0 |
| Tổng lãi gộp | -450,000 | -450,000 | 0 |

Kiểm tra lợi nhuận thực:

- `Tổng lãi gộp = -450,000`
- `Chi vận hành (EXPENSE) = 36,000,000`
- `Lợi nhuận thực = -450,000 - 36,000,000 = -36,450,000`
- Khớp với file: `-36,450,000`

Kết luận logic file:

- File `01/05` hiện tại **đúng logic nội bộ**, không có sai số cộng trừ ở phần tổng hợp.

## 4) Các lỗi thực tế đã fix trong code

1. Chặn xuất file bị “stale data” sau khi đổi shop:
- Khi bấm xuất, hệ thống nạp lại snapshot theo shop và kỳ hiện tại trước khi ghi Excel.

2. Tự động reload trang tài chính khi đổi shop/sync:
- Lắng nghe `SHOP_CHANGED`, `financial_changed`, `SYNC_COMPLETE` để không giữ dữ liệu cũ trên màn hình/export.

3. Tăng khả năng đối soát trực quan trong Excel:
- Ghi thêm vào đầu file xuất:
  - Tên cửa hàng
  - Shop ID
  - Thời điểm xuất

4. Sửa tràn giao diện tab (ảnh báo `BOTTOM OVERFLOWED BY 2.0 PIXELS`):
- Tăng chiều cao tab bar để tránh tràn 2px trên thiết bị/font scale như ảnh bạn gửi.

## 5) Kết luận cuối cùng

- Với cặp dữ liệu bạn gửi (ảnh hiển thị kỳ `02/05`, file lại là `01/05`): **không thể khớp số tuyệt đối** vì khác kỳ ngày.
- Bản thân file `01/05` đã **đúng logic** khi kiểm tra từng mục/từng dòng.
- Code đã được vá để giảm khả năng xuất nhầm ngữ cảnh shop/kỳ và tăng minh bạch khi đối soát.
