# FINANCE V2 – User Test Checklist (v4.2)

> Cập nhật: 29/04/2026 | Feature flag: `FinanceV2FeatureFlag.enableFinanceV2 = true`

---

## Kích hoạt Finance V2
- [ ] Bật flag trong `lib/finance_v2/finance_v2_feature_flag.dart` → `enableFinanceV2 = true`
- [ ] Build & chạy app
- [ ] Vào tab Tài chính → xuất hiện card "Tài chính V2" → nhấn mở

---

## TỔNG QUAN (Tab 1 – Dashboard chuyên nghiệp)

### Hero section
- [ ] Banner gradient xanh đậm hiển thị đúng
- [ ] Số "Dòng tiền ròng" lớn, rõ (Tr/Tỷ format)
- [ ] Số phụ hiện đầy đủ VNĐ bên dưới
- [ ] Pill hiển thị kỳ ngày bên phải hero

### KPI grid 2×2
- [ ] 4 cards: Tiền vào (xanh), Tiền ra (đỏ), Phải thu (indigo), Phải trả (cam)
- [ ] Mỗi card có icon màu riêng, số Tr/Tỷ lớn, số đầy đủ nhỏ bên dưới

### So sánh với kỳ trước
- [ ] 3 ô so sánh hiển thị: Dòng tiền ròng / Tiền vào / Tiền ra
- [ ] Có mũi tên tăng giảm và màu xanh/đỏ theo xu hướng
- [ ] Giá trị delta hiển thị đúng theo kỳ trước liền kề

### Cơ cấu nguồn thu
- [ ] Hiển thị 3 nguồn: Bán hàng / Sửa chữa / Thu khác
- [ ] Có % và thanh tiến trình cho từng nguồn
- [ ] Tổng tỷ trọng không vượt 100%

### Dòng tiền visual
- [ ] Thanh Tiền vào (xanh) dài 100%
- [ ] Thanh Tiền ra (đỏ) tỉ lệ so với tiền vào
- [ ] Không bị tràn/lỗi khi tiền ra > tiền vào

### Công nợ nhanh
- [ ] Hiện "Phải thu" + "Phải trả" trong 2 ô màu riêng
- [ ] Số khoản hiển thị đúng
- [ ] Hiển thị thêm: Số giao dịch và Thu TB/giao dịch

### Nhóm chi phí chính
- [ ] Hiển thị top nhóm chi phí trong kỳ
- [ ] Mỗi nhóm có thanh mức độ theo tỷ lệ nhóm lớn nhất

---

## GIAO DỊCH (Tab 2)
- [ ] Danh sách transactions filter đúng theo kỳ đã chọn
- [ ] Giao dịch vào (+) màu xanh, ra (-) màu đỏ
- [ ] Ngày giờ định dạng dd/MM/yyyy HH:mm
- [ ] Nếu khách hàng có ảnh đại diện -> hiện ảnh, không dùng chữ cái đầu
- [ ] Hiện thêm chi tiết: loại giao dịch, nhân viên thực hiện, mã tham chiếu
- [ ] Khi không có giao dịch → hiện empty state "Không có giao dịch trong kỳ đã chọn"

---

## CÔNG NỢ (Tab 3 – Toggle Phải thu / Phải trả)

### BUG FIX – Lọc theo ngày
- [x] **Tạo TK tháng 4, lọc kỳ tháng 3 → Phải thu = 0, Phải trả = 0**
- [ ] Lọc kỳ tháng 4 → hiện đúng công nợ tạo trong tháng 4
- [ ] Lọc kỳ tuần này → chỉ hiện công nợ tạo trong tuần

### Toggle UI
- [ ] Nút "Phải thu" khi active: nền xanh indigo, chữ trắng + số Tr/Tỷ
- [ ] Nút "Phải trả" khi active: nền cam, chữ trắng + số Tr/Tỷ
- [ ] Chuyển qua lại mượt (animated 200ms)
- [ ] Thanh tổng dưới toggle đổi màu theo loại đang chọn

### Danh sách
- [ ] Nếu khách/NCC/đối tác có ảnh đại diện -> hiện ảnh thật
- [ ] Chưa có ảnh -> fallback chữ cái đầu tên
- [ ] Hiện Tổng / Đã TT / Còn lại
- [ ] Hiện thêm SĐT và ngày tạo công nợ
- [ ] Khi rỗng → empty state "Không có công nợ trong kỳ đã chọn"

---

## BÁO CÁO (Tab 4)

### Tóm tắt tài chính
- [ ] Tiền vào, Tiền ra, Lãi tạm tính đúng theo kỳ
- [ ] Lãi âm → màu đỏ + icon cảnh báo
- [ ] Note giải thích "cash-basis" hiển thị rõ

### Tổng hợp theo kỳ
- [ ] Chọn được chế độ tổng hợp Ngày / Tháng / Năm
- [ ] Danh sách tổng hợp hiển thị Thu / Chi / Lãi cho từng mốc
- [ ] Số mốc, mốc cuối, lãi TB/mốc hiển thị đúng

---

## NHẬT KÝ (Tab 5 – Activity Log chi tiết)
- [ ] Có tab riêng "Nhật ký"
- [ ] Mỗi log hiển thị: thời gian, người thực hiện, phương thức thanh toán, tham chiếu
- [ ] Có mô tả thay đổi và dữ liệu chi tiết (nếu có)
- [ ] Số tiền +/- màu đúng theo hướng IN/OUT

### So sánh kỳ trước
- [ ] Hiển thị rõ khối "So sánh với kỳ trước" trên Dashboard
- [ ] 3 chỉ số có mũi tên tăng/giảm + delta đúng

---

## CHỌN KỲ (Date Range Filter)

### Kiểm tra chính xác
- [ ] Nhấn icon 📅 → date range picker mở
- [ ] Nhấn chip kỳ ngày trên Dashboard (góc phải hero) → date range picker mở
- [ ] Chọn tháng 3 → TẤT CẢ tabs (Tổng quan, Giao dịch, Công nợ, Báo cáo) đều lọc đúng
- [ ] Nếu TK tạo tháng 4, lọc tháng 3 → tất cả đều = 0
- [ ] Subtitle appbar cập nhật ngay sau khi chọn kỳ
- [ ] Icon refresh → tải lại đúng kỳ hiện tại

---

## THIẾT KẾ & UX

### Tab bar
- [ ] 4 tabs (không phải 7): Tổng quan / Giao dịch / Công nợ / Báo cáo
- [ ] Mỗi tab có icon + text
- [ ] Tab indicator gradient/màu nổi bật
- [ ] Không cần scroll tab bar (fits trong màn hình)

### Màu sắc & theme
- [ ] Nền trang: light blue-gray (FinanceV2Theme.pageBg)
- [ ] Card: trắng với shadow nhẹ (elevatedPanel)
- [ ] Positive: xanh lá #0F8A5F
- [ ] Negative: đỏ #C0392B
- [ ] Accent (phải thu): indigo #164A9E
- [ ] Warn (phải trả): cam #B9770E

### Responsive
- [ ] Kiểm tra màn nhỏ (360dp): không bị tràn layout
- [ ] KPI cards không bị overflow text

---

## KIỂM TRA SONG SONG (Backward Compatibility)
- [ ] Finance V1 (Tài chính cũ) vẫn hoạt động bình thường khi V2 bật
- [ ] Tắt flag `enableFinanceV2 = false` → card V2 biến mất, V1 không ảnh hưởng
- [ ] Không có shared state giữa V1 và V2

---

## TRẠNG THÁI TỔNG
| Hạng mục | Trạng thái |
|---|---|
| Date filter bug (debts) | ✅ Đã fix |
| Dashboard chuyên nghiệp | ✅ Đã làm |
| Giảm tabs 7→4 | ✅ Đã làm |
| Công nợ toggle UI | ✅ Đã làm |
| Báo cáo + Audit gộp | ✅ Đã làm |
| Analyze sạch (0 error) | ✅ Confirmed |
