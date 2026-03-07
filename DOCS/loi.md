# THIẾT KẾ UX & TIẾN ĐỘ CẢI THIỆN APP
> Cập nhật: 07/03/2026

---

## 🏠 TAB HOME — Xem nhanh + Thao tác nhanh

```
HOME
│
├── ✅ Tóm tắt hôm nay (FinanceSummaryCard)
│     ├ 💰 Doanh thu      ← saleIncome + settlementIncome + repairIncome
│     ├ 📈 Lợi nhuận      ← netProfit
│     └ 🏦 Quỹ            ← totalIn - totalOut (dòng tiền ròng)
│
├── ✅ Cần xử lý (ActionRequiredCard)
│     ├ Đơn sửa chờ
│     ├ Tồn kho chờ duyệt
│     └ Bảo hành sắp hết
│
├── ✅ Thao tác nhanh (QuickActions)
│     ├ Bán hàng, Đơn sửa, Nhập kho, Kiểm kho
│     ├ Thu chi, Chờ xác nhận, Bảo hành, Báo cáo
│     └ (config-driven, tuỳ quyền)
│
├── ✅ Hoạt động hôm nay (ActivityFeedCard)
│     ├ Bán hàng
│     ├ Sửa chữa
│     ├ Thu chi
│     ├ Thu nợ KH / Trả nợ NCC   ← MỚI thêm
│     └ Trả NCC (supplier_payments) ← MỚI thêm
│
├── ⬜ Truy cập nhanh tài chính   ← ĐÃ LÀM (financeShortcuts card)
│     ├ ✅ Sổ quỹ
│     ├ ✅ Công nợ
│     └ ✅ Thu chi
│
└── 🟡 Chi tiết tài chính (financeDetail) — ẩn mặc định trên Home
      └ Bar chart + CHI TIẾT THU/CHI + Lợi nhuận (đã có, user bật trong Settings)
```

👉 **Quy tắc**: Home chỉ 3 số chính (Doanh thu / Lợi nhuận / Quỹ). Chi tiết ở tab Tài chính.

---

## 💰 TAB TÀI CHÍNH — Chi tiết đầy đủ

```
TÀI CHÍNH
│
├── ✅ Tổng quan tài chính (_financeOverviewSection)
│     ├ 📥 Thu hôm nay (totalIn)
│     ├ 📤 Chi hôm nay (totalOut)
│     ├ 📦 Chi nhập kho (nếu có)
│     └ 💰 Lợi nhuận ròng (gradient card)
│
├── ✅ Biến động trong ngày (_buildDashboardOverview) ← MỚI chuyển từ Home
│     ├ Bar chart THU vs CHI
│     ├ CHI TIẾT THU: Bán hàng, Tất toán, Sửa chữa, Thu nợ, Thu phát sinh
│     ├ CHI TIẾT CHI: Chi phí, Nhập hàng, Trả nợ NCC, TT đối tác, Vốn LK SC, Trả hàng
│     ├ LỢI NHUẬN RÒNG (giá vốn bán + giá vốn SC)
│     └ HOẠT ĐỘNG: Đơn sửa chờ, Đơn hàng, Công nợ
│
├── ✅ Thao tác nhanh
│     ├ Sổ quỹ → CashClosingView
│     └ Thu Chi → ExpenseView
│
├── ✅ Báo cáo & Phân tích (grid)
│     ├ Báo cáo doanh thu → RevenueView
│     ├ Quản lý công nợ → DebtView
│     ├ Lịch sử tài chính → CashClosingView(showOnlyTransactions)
│     └ Nhật ký hoạt động → FinancialActivityLogView
│
├── ✅ Công nợ tổng hợp card         ← ĐÃ LÀM
│     ├ ✅ Tổng nợ khách hàng (CUSTOMER_OWES)
│     ├ ✅ Tổng nợ NCC (SHOP_OWES)
│     └ ✅ Tổng nợ đối tác (partner_repair_history)
│
└── ⬜ Báo cáo nâng cao              ← CHƯA LÀM
      ├ Biến động theo tháng
      └ Thống kê lợi nhuận dài hạn
```

---

## 📊 SỔ QUỸ (CashClosingView) — Đã hoàn thiện

```
SỔ QUỸ
│
├── ✅ Tab Tổng quan
│     ├ Tổng quỹ (cashIn + bankIn - cashOut - bankOut)
│     ├ Tiền mặt (cashIn - cashOut)
│     ├ Ngân hàng (bankIn - bankOut)
│     └ Lợi nhuận ròng + Giá vốn
│
├── ✅ Tab Thu (chi tiết từng giao dịch)
│     ├ Bán hàng, Thu nợ, Sửa chữa, Tất toán, Thu phát sinh
│     └ Merge Firestore + Local DB (dedup by firestoreId)
│
├── ✅ Tab Chi (chi tiết từng giao dịch)
│     ├ Chi phí, Nhập hàng, Trả nợ NCC, TT đối tác, Vốn LK, Trả hàng
│     └ Merge Firestore + Local DB (dedup by firestoreId)
│
└── ✅ Tab Lịch sử (chốt quỹ các ngày)
```

---

## 🔁 LUỒNG DỮ LIỆU TÀI CHÍNH

```
Bán hàng → Doanh thu → Giá vốn → Chi phí → Lợi nhuận → Sổ quỹ → Báo cáo
```

Engine tính toán duy nhất: **DailyFinancialAnalysisService.analyze()**
- Home gọi → lấy từ Local DB
- Sổ quỹ gọi → lấy từ Firestore + merge Local DB
- 30 unit tests: `test/daily_financial_analysis_service_test.dart`

---

## 🧠 QUY TẮC THIẾT KẾ

1️⃣ **HOME chỉ hiển thị 3 số**: Doanh thu / Lợi nhuận / Quỹ hiện có
2️⃣ **TÀI CHÍNH hiển thị chi tiết**: Thu/Chi/Giá vốn/Lợi nhuận + Biến động + Breakdown
3️⃣ **Giao dịch gom về 1 chỗ**: Thu / Chi / Công nợ (Sổ quỹ là nguồn chính)

---

## ✅ ĐÃ HOÀN THÀNH

| # | Hạng mục | Commit | Ghi chú |
|---|----------|--------|---------|
| 1 | Fix Sổ Quỹ merge local DB | `c76b121` | 8 collections merge, LEFT JOIN debt_payments |
| 2 | Home: 3 số (Doanh thu/Lợi nhuận/Quỹ) | `034805e` | FinanceSummaryCard đổi giao diện |
| 3 | ActivityFeed: +debt_payments +supplier_payments | `034805e` | 5 loại giao dịch thay vì 3 |
| 4 | Finance tab: +Biến động trong ngày | `034805e` | Bar chart + breakdown chuyển từ Home |
| 5 | 30 unit tests cho DailyFinancialAnalysisService | `034805e` | Bao phủ tất cả loại giao dịch |
| 6 | Home: Truy cập nhanh tài chính (financeShortcuts) | `9248d0c` | 3 nút: Sổ quỹ/Công nợ/Thu chi |
| 7 | Finance: Công nợ tổng hợp card | `f2b1d8f` | Khách nợ/NCC/Đối tác split |
| 8 | Finance: Báo cáo lợi nhuận theo tháng | `a6ee0ec` | MonthlyProfitReportView + bar chart + breakdown |

## ✅ HOÀN TẤT TẤT CẢ HẠNG MỤC