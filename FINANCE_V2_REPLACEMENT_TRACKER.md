# Finance V2 Replacement Tracker

Cập nhật: 29/04/2026
Phạm vi: chỉ theo dõi thay thế Finance V1 bằng Finance V2, không bao gồm thay đổi ngoài module tài chính V2.

---

## 1. Nếu V2 thay V1 thì app được lợi ích gì?

### 1.1. Lợi ích nghiệp vụ
- Một màn tài chính tập trung hơn: quản lý nhìn số nhanh hơn, ít phải nhảy qua nhiều màn rời rạc.
- Dữ liệu thu, chi, công nợ, báo cáo và nhật ký được gom trong cùng một luồng sử dụng.
- Có góc nhìn quản trị tốt hơn cho chủ shop: dòng tiền ròng, so sánh kỳ trước, công nợ quá hạn, nhóm chi phí chính.
- Giao dịch công nợ được nhìn như một phần của tài chính thật, không bị tách rời khỏi báo cáo dòng tiền.
- Báo cáo ngày V2 nhìn trực quan và chuyên nghiệp hơn, phù hợp in nhanh cho vận hành cuối ngày.

### 1.2. Lợi ích UX/UI
- Ít phân mảnh hơn V1: người dùng không phải nhớ nhiều entry point như Sổ quỹ, Báo cáo hoạt động, Nhật ký tài chính, Lịch sử giao dịch.
- Có bộ lọc thời gian thống nhất trên tất cả tab: Hôm nay, Tháng này, Năm nay, Tùy chọn.
- Mặc định vào dữ liệu hôm nay nên đúng nhu cầu thao tác thực tế của cửa hàng.
- Thông tin được chia tầng rõ hơn:
  - Tầng 1: Tổng quan
  - Tầng 2: Giao dịch
  - Tầng 3: Công nợ
  - Tầng 4: Báo cáo
  - Tầng 5: Nhật ký

### 1.3. Lợi ích kỹ thuật
- Single screen orchestration: giảm logic rải rác ở nhiều view tài chính cũ.
- Dễ chuẩn hóa bộ lọc thời gian và quy tắc hiển thị.
- Dễ mở rộng thêm chỉ số quản trị mà không phải sửa nhiều màn cũ cùng lúc.
- Thuận lợi để dần gom logic báo cáo tài chính về một chuẩn hiển thị duy nhất.

### 1.4. Lợi ích vận hành
- Dễ đào tạo nhân viên/chủ shop hơn: một màn chính thay vì nhiều màn con độc lập.
- Dễ hỗ trợ từ xa: khi user nói “tab giao dịch”, “tab công nợ”, “tab báo cáo” thì đúng một chỗ.
- Dễ kiểm thử release hơn vì có thể gom test theo 5 tab chuẩn.

---

## 2. Những file/view nào thay đổi nếu V2 thay dần V1?

### 2.1. File đang là lõi của V2
- `lib/finance_v2/finance_v2_view.dart`
- `lib/finance_v2/finance_v2_data_service.dart`
- `lib/finance_v2/finance_v2_daily_report_view.dart`
- `lib/finance_v2/finance_v2_excel_export.dart`
- `lib/finance_v2/finance_v2_theme.dart`
- `lib/finance_v2/finance_v2_feature_flag.dart`

### 2.2. File đã bị ảnh hưởng bởi việc bật V2
- `lib/views/home_view.dart`
  - thêm entry point vào Tài chính V2
  - thêm entry point vào Báo cáo ngày V2

### 2.3. Các view V1 còn đang song song và có thể bị thay thế dần
- `lib/views/revenue_view.dart`
- `lib/views/financial_report_view.dart`
- `lib/views/financial_activity_log_view.dart`
- `lib/views/daily_activity_report_view.dart`
- `lib/views/cash_closing_view.dart`
- `lib/views/debt_view.dart`
- `lib/views/expense_view.dart`

### 2.4. View nào chưa nên xóa ngay
- `lib/views/cash_closing_view.dart`
  - vẫn là màn nghiệp vụ sâu cho chốt quỹ và lịch sử chi tiết.
- `lib/views/debt_view.dart`
  - vẫn là màn xử lý nghiệp vụ công nợ sâu: thanh toán, lịch sử, đối tác.
- `lib/views/expense_view.dart`
  - vẫn là màn nhập nghiệp vụ thực tế cho thu/chi.

### 2.5. View có thể cân nhắc “deprecate” trước khi xóa thật
- `lib/views/financial_report_view.dart`
  - nếu tab Giao dịch + Báo cáo của V2 đã đủ thay thế.
- `lib/views/financial_activity_log_view.dart`
  - nếu tab Nhật ký của V2 đã đủ dùng cho quản trị.
- `lib/views/daily_activity_report_view.dart`
  - nếu báo cáo ngày V2 đạt đủ nghiệp vụ và mẫu in ổn định.
- `lib/views/revenue_view.dart`
  - chỉ nên deprecate khi chắc chắn V2 có đủ so sánh, top sản phẩm, top khách, phân tích kỳ.

### 2.6. Kết luận xóa view
- Không nên xóa ngay V1 theo kiểu cắt thẳng.
- Nên đi theo lộ trình:
  1. Bật V2 song song bằng feature flag
  2. Cho user test thật
  3. Chốt phạm vi đủ dùng
  4. Đổi entry point từ Home sang V2 mặc định
  5. Deprecate các màn V1 trùng chức năng
  6. Chỉ xóa hẳn khi qua ít nhất 1 vòng release ổn định

---

## 3. Bố cục tab Tài chính V2 nếu dùng làm màn chính

### 3.1. Mục tiêu thiết kế
- V2 không thay tất cả màn nghiệp vụ sâu.
- V2 là “trung tâm điều phối tài chính”.
- Từ V2 user xem số, lọc thời gian, so sánh, drill-down, rồi mới đi sang màn sâu khi cần thao tác.

### 3.2. Cấu trúc tổng thể

```text
Finance V2
├── AppBar
│   ├── tiêu đề Tài chính V2
│   ├── subtitle hiển thị kỳ đang xem
│   ├── nút Sổ quỹ
│   ├── nút chọn kỳ
│   └── nút làm mới
├── Tab 1: Tổng quan
├── Tab 2: Giao dịch
├── Tab 3: Công nợ
├── Tab 4: Báo cáo
└── Tab 5: Nhật ký
```

### 3.3. Bộ lọc dùng chung cho tất cả tab
- Hôm nay
- Tháng này
- Năm nay
- Tùy chọn
- Dòng hiển thị kỳ hiện tại ngay dưới chip

Lợi ích:
- User không bị lạc filter giữa các tab
- Khi đổi kỳ thì hiểu rằng toàn bộ 5 tab đổi theo cùng một mốc thời gian
- Tư duy sử dụng nhất quán hơn V1

---

## 4. Thiết kế chi tiết từng tab

## Tab 1: Tổng quan

### Vai trò
- Là dashboard điều hành.
- Mục tiêu: nhìn 5-10 giây là ra quyết định.

### Bố cục đề xuất
```text
Tổng quan
├── Hero card gradient
│   ├── Dòng tiền ròng
│   ├── kỳ đang xem
│   └── quick actions: thêm thu / thêm chi / công nợ / chốt quỹ
├── Thanh filter kỳ dùng chung
├── Smart Alert
├── Snapshot cuối ngày
├── KPI grid 2x2
│   ├── Tiền vào
│   ├── Tiền ra
│   ├── Phải thu
│   └── Phải trả
├── So sánh với kỳ trước
├── Cơ cấu nguồn thu
├── Dòng tiền trong kỳ
├── Công nợ trong kỳ
└── Nhóm chi phí chính
```

### Mục đích từng khối
- Hero: điểm nhấn số quan trọng nhất.
- Smart Alert: cảnh báo điều hành.
- Snapshot cuối ngày: tiện copy/chia sẻ nhanh.
- KPI grid: tóm tắt trục tài chính cốt lõi.
- So sánh kỳ trước: phát hiện tăng/giảm.
- Cơ cấu nguồn thu: biết tiền đến từ đâu.
- Dòng tiền trong kỳ: nhìn trực quan thu/chi.
- Công nợ: đánh giá áp lực vốn.
- Nhóm chi phí: phát hiện nhóm chi bất thường.

---

## Tab 2: Giao dịch

### Vai trò
- Là tab xem giao dịch tài chính đã chuẩn hóa.
- Mục tiêu: tra cứu nhanh theo thời gian và loại giao dịch.

### Bố cục đề xuất
```text
Giao dịch
├── Thanh filter kỳ dùng chung
├── Chip lọc loại giao dịch
│   ├── Tất cả
│   ├── Thu vào
│   ├── Chi ra
│   ├── Bán hàng
│   ├── Sửa chữa
│   ├── Thu nợ
│   └── Trả nợ
├── Nút export Excel
└── Danh sách giao dịch
    ├── avatar
    ├── tiêu đề
    ├── mô tả + thời gian
    ├── nhân viên
    └── số tiền +/-
```

### Mục tiêu UX
- Tab này thay vai trò “lịch sử giao dịch tổng hợp” kiểu V1.
- Chỉ cần nhìn là hiểu tiền vào/ra và do giao dịch gì.
- Sau này có thể mở rộng thêm tìm kiếm hoặc lọc phương thức thanh toán nếu cần.

---

## Tab 3: Công nợ

### Vai trò
- Là tab theo dõi công nợ theo kỳ.
- Không phải màn nghiệp vụ sâu nhất, mà là dashboard công nợ.

### Bố cục đề xuất
```text
Công nợ
├── Thanh filter kỳ dùng chung
├── Toggle Phải thu / Phải trả
├── Tổng strip theo loại đang chọn
├── Nếu đang xem phải thu
│   └── card phân tích tuổi nợ: 0-30 / 30-60 / >60
└── Danh sách công nợ
    ├── avatar
    ├── tên
    ├── sđt
    ├── ngày tạo
    ├── tổng / đã thanh toán
    └── còn lại
```

### Mục tiêu UX
- Người quản lý nhìn nhanh áp lực công nợ theo kỳ.
- Khi cần thao tác thanh toán thật thì bấm sang `DebtView`.

---

## Tab 4: Báo cáo

### Vai trò
- Là tab tổng hợp tài chính theo mốc.
- Mục tiêu: xem xu hướng, không phải xem từng giao dịch.

### Bố cục đề xuất
```text
Báo cáo
├── Thanh filter kỳ dùng chung
├── Card tóm tắt tài chính
│   ├── Tiền vào
│   ├── Tiền ra
│   └── Lãi tạm tính
├── Ghi chú cash-basis
├── Chip tổng hợp
│   ├── Ngày
│   ├── Tháng
│   └── Năm
├── Nút export Excel
├── Mini stat
│   ├── số mốc
│   ├── mốc cuối
│   └── lãi trung bình/mốc
└── Danh sách bucket tổng hợp
    ├── mốc
    ├── thu
    ├── chi
    ├── ròng
    └── số giao dịch
```

### Mục tiêu UX
- Đây là tab thay phần lớn vai trò báo cáo doanh thu/tài chính kiểu cũ.
- Dùng cho phân tích xu hướng ngắn hạn và đối chiếu nhanh.

---

## Tab 5: Nhật ký

### Vai trò
- Hợp nhất timeline tài chính.
- Gần với “nhật ký điều hành” hơn là “audit thuần kỹ thuật”.

### Bố cục đề xuất
```text
Nhật ký
├── Thanh filter kỳ dùng chung
├── Tiêu đề + số bản ghi + export
├── ô tìm kiếm
├── filter nguồn
│   ├── Tất cả
│   ├── Giao dịch
│   ├── Công nợ
│   └── Audit
├── filter hướng
│   ├── Tất cả
│   ├── Tiền vào
│   ├── Tiền ra
│   └── >= 1 triệu
├── dropdown nhân viên
├── dropdown phương thức thanh toán
└── danh sách timeline
    ├── thời gian
    ├── tiêu đề
    ├── tag metadata
    ├── mô tả
    └── số tiền
```

### Mục tiêu UX
- Chủ shop hoặc quản lý có thể truy vết biến động tài chính rất nhanh.
- Không cần mở nhiều màn log cũ khác nhau.

---

## 5. Gợi ý thay thế V1 bằng V2 theo giai đoạn

### Giai đoạn A – Song song an toàn
- Giữ nguyên V1.
- Cho mở V2 từ Home bằng feature flag.
- Thu thập phản hồi user thật.

### Giai đoạn B – Chuyển entry point chính
- Từ Home, card tài chính chính mở V2.
- V1 vẫn giữ nhưng chuyển thành “màn cũ” hoặc “xem thêm”.

### Giai đoạn C – Deprecate dần
- Ẩn các shortcut V1 trùng chức năng:
  - Financial Report
  - Financial Activity Log
  - Daily Activity Report V1
- Giữ lại các màn nghiệp vụ sâu:
  - ExpenseView
  - DebtView
  - CashClosingView

### Giai đoạn D – Xóa sau khi ổn định
Chỉ xóa khi đảm bảo:
- Finance V2 đã qua test thực tế
- Báo cáo ngày V2 đã được chấp nhận
- Nhật ký V2 đủ dùng cho quản trị
- Không còn phụ thuộc vào view cũ trong Home/navigation

---

## 6. Đề xuất quyết định thực tế hiện tại

## 6.1. Audit drill-down còn thiếu so với V1

Nguyên tắc audit:
- Chỉ tính các drill-down/phân tích còn thiếu trong Finance V2 hiện tại.
- Không tính các màn nghiệp vụ sâu vẫn đang chủ động giữ lại như `ExpenseView`, `DebtView`, `CashClosingView`.

### Tab Tổng quan
Hiện đã có:
- KPI Tiền vào -> drill xuống tab Giao dịch lọc thu
- KPI Tiền ra -> drill xuống tab Giao dịch lọc chi
- KPI Phải thu -> drill xuống tab Công nợ phải thu
- KPI Phải trả -> drill xuống tab Công nợ phải trả

Thiếu so với mức thay V1 tốt:
- Khối “So sánh với kỳ trước” chưa bấm được để mở chi tiết so sánh theo nguồn thu/chi.
- Khối “Cơ cấu nguồn thu” chưa bấm từng dòng để drill sang danh sách giao dịch theo nhóm tương ứng.
- Khối “Dòng tiền trong kỳ” chưa bấm trực tiếp vào thanh Tiền vào/Tiền ra để mở danh sách giao dịch.
- Khối “Công nợ trong kỳ” chưa bấm từng mini-tile để chuyển nhanh sang danh sách công nợ tương ứng.
- Khối “Nhóm chi phí chính” chưa bấm từng category để drill sang danh sách chi phí cùng danh mục.

### Tab Giao dịch
Hiện đã có:
- Lọc thời gian chung
- Lọc loại giao dịch
- Export Excel

Thiếu so với mức thay V1 tốt:
- Từng dòng giao dịch chưa bấm được để mở chứng từ gốc từ chính tab Giao dịch.
- Chưa có tìm kiếm theo tên/nội dung/nhân viên ngay trong tab Giao dịch.
- Chưa có lọc theo phương thức thanh toán trong tab Giao dịch.

### Tab Công nợ
Hiện đã có:
- Toggle Phải thu / Phải trả
- Danh sách item công nợ có bấm sang `DebtView`
- Phân tích tuổi nợ phải thu

Thiếu so với mức thay V1 tốt:
- Các card tuổi nợ 0-30 / 30-60 / >60 chưa drill xuống danh sách công nợ đã lọc theo bucket tuổi nợ.
- Chưa có tìm kiếm nhanh trong tab Công nợ.
- Chưa có drill-down theo loại đối tượng nợ: khách / NCC / đối tác.

### Tab Báo cáo
Hiện đã có:
- Tổng hợp theo Ngày / Tháng / Năm
- Danh sách bucket tổng hợp
- Export Excel

Thiếu so với mức thay V1 tốt:
- Dòng bucket tổng hợp chưa bấm được để drill xuống danh sách giao dịch của bucket tương ứng.
- Chưa có breakdown sâu theo nguồn: bán hàng / sửa chữa / thu khác / chi phí.
- Chưa có top sản phẩm bán chạy.
- Chưa có top khách hàng mua nhiều.
- Chưa có view thay thế đầy đủ cho phần phân tích sâu đang có ở `revenue_view.dart`.

### Tab Nhật ký
Hiện đã có:
- Tìm kiếm
- Filter nguồn
- Filter hướng
- Filter nhân viên
- Filter phương thức thanh toán
- Bấm item để mở chứng từ gốc trong nhiều trường hợp

Thiếu so với mức thay V1 tốt:
- Chưa có nhóm filter preset theo giá trị lớn / bất thường / rủi ro.
- Một số entry từ tab Giao dịch chính chưa mở trực tiếp từ tab Giao dịch nhưng chỉ mở qua tab Nhật ký.

### Kết luận audit drill-down
- Nếu mục tiêu là “V2 thay giao diện điều phối của V1”, trạng thái hiện tại đã đi được khá xa.
- Nếu mục tiêu là “V2 thay hoàn toàn toàn bộ góc nhìn phân tích của V1”, vẫn còn thiếu rõ nhất ở:
  1. drill-down từ tab Báo cáo
  2. drill-down từ các card phụ ở tab Tổng quan
  3. tìm kiếm/lọc sâu trong tab Giao dịch
  4. phân tích chuyên sâu thay cho `revenue_view.dart`

### Nên làm ngay
- Dùng Finance V2 làm entry point chính của tab tài chính.
- Giữ các màn nghiệp vụ sâu của V1 để điều hướng từ V2.
- Tiếp tục hoàn thiện báo cáo ngày V2 và các drill-down.

### Chưa nên làm ngay
- Xóa `CashClosingView`
- Xóa `DebtView`
- Xóa `ExpenseView`
- Xóa toàn bộ RevenueView nếu chưa bù đủ phân tích sâu

### Có thể đánh dấu sẽ bỏ dần
- `financial_report_view.dart`
- `financial_activity_log_view.dart`
- `daily_activity_report_view.dart`

---

## 7. Kết luận

Nếu Finance V2 thay V1 theo hướng đúng, app sẽ được:
- gọn hơn
- dễ dùng hơn
- dễ đào tạo hơn
- dễ hỗ trợ hơn
- nhất quán số liệu hơn ở góc nhìn người dùng

Nhưng cách an toàn nhất không phải là xóa V1 ngay.
Cách an toàn là:
- V2 làm trung tâm điều phối
- V1 sâu nghiệp vụ vẫn giữ tạm
- deprecate từng phần
- xóa sau khi qua ít nhất một vòng chạy thật ổn định


