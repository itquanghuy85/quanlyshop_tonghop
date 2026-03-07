# KIẾN TRÚC UX/UI - PHƯƠNG ÁN MỞ RỘNG CHUYÊN NGHIỆP
> Phiên bản: 2.1 | Cập nhật: 2026-03-08
> Áp dụng cho: quanlyshop (Flutter + Firebase)
> **Trạng thái: ✅ HOÀN THÀNH — Tất cả 5 giai đoạn đã triển khai**

---

## 📐 NGUYÊN TẮC THIẾT KẾ CỐT LÕI

### 1. Phân tầng thông tin (Information Hierarchy)
| Tầng | Nơi hiển thị | Nội dung | Mục đích |
|------|-------------|----------|----------|
| L1 - Glance | HOME | 3 con số + badge | Ra quyết định trong 2 giây |
| L2 - Summary | TÀI CHÍNH | Tổng quan + biểu đồ | Đánh giá tình hình ngày |
| L3 - Detail | Sổ Quỹ / Công nợ | Từng giao dịch | Đối soát, kiểm tra |
| L4 - Report | Báo cáo | Xu hướng, so sánh | Phân tích kinh doanh |

### 2. Single Source of Truth (SSOT)
- Mọi giao dịch Thu/Chi/Công nợ → **1 engine duy nhất** (`DailyFinancialAnalysisService`)
- Không view nào tự tính riêng → tránh sai lệch số liệu
- Local DB + Firestore → merge trước khi hiển thị

### 3. Progressive Disclosure (Hiển thị đúng lúc)
- Không dump hết số liệu lên Home
- User tap để đi sâu: Home → Tài chính → Sổ quỹ → Chi tiết giao dịch

---

## 🏠 TAB HOME — Tổng quan nhanh

### Cấu trúc mục tiêu
HOME
│
├── 🎯 3 Số Cốt Lõi (compact card)
│ ├ Doanh thu hôm nay ← totalIn (tổng thu thực tế)
│ ├ Lợi nhuận hôm nay ← netProfit
│ └ Tiền quỹ hiện có ← cashEnd + bankEnd (từ chốt quỹ hôm qua + biến động hôm nay)
│
├── ⚡ Thao tác nhanh (grid 4 cột)
│ ├ Bán hàng → CreateSaleView
│ ├ Đơn sửa → CreateRepairOrderView
│ ├ Nhập kho → SmartStockInView
│ ├ Kiểm kho → FastInventoryCheckView
│ ├ Thu chi → ExpenseView
│ ├ Chờ xử lý → OrderListView(status: [1,2])
│ ├ Bảo hành → WarrantyView
│ └ Báo cáo → RevenueView
│
├── 📋 Hoạt động hôm nay (timeline, max 8 items)
│ ├ Bán iPhone 16 Plus — +18.710.000đ — 12:38
│ ├ Thu nợ BÙI THỊ — +3.000.000đ — 13:36
│ ├ Nhập SIM — -1.350.000đ — 13:12
│ └ → "Xem tất cả" → CashClosingView(showOnlyTransactions)
│
└── 🔗 Truy cập nhanh (2 nút lớn)
├ Sổ quỹ → CashClosingView
└ Công nợ → DebtView

### Hiện trạng vs Mục tiêu
| Widget hiện tại | Hành động | Ghi chú |
|----------------|-----------|---------|
| `FinanceSummaryCard` (Thu/Chi/Lãi) | ✅ Giữ, đổi Chi → Tiền quỹ | Thêm tính quỹ = chốt hôm qua + biến động |
| `_financeOverviewSection` (THU/CHI detail) | ❌ Xoá khỏi Home | Chuyển sang Finance tab |
| `_buildDashboardOverview` (biến động bar chart) | ❌ Xoá khỏi Home | Chuyển sang Finance tab |
| `ActionRequiredCard` | ✅ Giữ | Tích hợp vào quick actions badge |
| `ActivityFeedCard` | ✅ Giữ | Nâng cấp: thêm debt_payments, supplier_payments |
| `_buildPinnedShortcutsSection` | ✅ Giữ | Sổ quỹ + Công nợ |
| `_buildUnifiedShortcuts` | ✅ Giữ | Grid thao tác nhanh |

### Code mapping
DashboardCardType.financeSummary → GIỮ (compact 3 số)
DashboardCardType.financeDetail → ẨN mặc định trên Home, BẬT trên Finance tab
DashboardCardType.activityFeed → GIỮ + nâng cấp
DashboardCardType.quickActions → GIỮ
DashboardCardType.actionRequired → GIỮ


---

## 💰 TAB TÀI CHÍNH — Dashboard chuyên sâu

### Cấu trúc mục tiêuTÀI CHÍNH
│
├── 📊 Tổng quan tài chính (summary card)
│ ├ Doanh thu ← saleIncome + repairIncome + settlementIncome
│ ├ Giá vốn ← saleCost + repairCost
│ ├ Chi phí ← expenseOut + importOut + supplierPaid + partnerPaid
│ ├ Lợi nhuận ← netProfit
│ └ Biến động quỹ ← bar chart Thu vs Chi (đã có _buildDashboardOverview)
│
├── 📒 Sổ quỹ (entry card → CashClosingView)
│ ├ Tổng quỹ hiện tại ← từ chốt quỹ + biến động hôm nay
│ ├ Tiền mặt / Ngân hàng
│ └ " Xem chi tiết → "
│
├── 💸 Thu chi (entry card → ExpenseView)
│ ├ Tổng thu hôm nay
│ ├ Tổng chi hôm nay
│ └ " Ghi thu chi → "
│
├── 📋 Công nợ (entry card → DebtView)
│ ├ Khách nợ ← totalDebtRemain (CUSTOMER_OWES)
│ ├ Nợ NCC ← tổng nợ SHOP_OWES
│ ├ Nợ đối tác ← partner debt
│ └ " Quản lý → "
│
└── 📈 Báo cáo & Phân tích (grid)
├ Biến động theo ngày → RevenueView (daily)
├ Biến động theo tháng → RevenueView (monthly)
├ Lịch sử tài chính → CashClosingView(showOnlyTransactions)
└ Nhật ký hoạt động → FinancialActivityLogView

### Hiện trạng vs Mục tiêu
| Widget hiện tại (`_buildFinanceTab`) | Hành động |
|--------------------------------------|-----------|
| `_financeOverviewSection` (THU/CHI card) | ✅ Giữ + Mở rộng thành "Tổng quan tài chính" |
| `_buildDashboardOverview` (bar chart) | ✅ Chuyển từ Home sang đây |
| 2 nút Sổ quỹ + Thu Chi | ✅ Nâng cấp: thêm số liệu preview |
| Grid 4 nút (Báo cáo, Công nợ, Lịch sử, Nhật ký) | ✅ Tái cấu trúc thành section |
| Không có: Tóm tắt công nợ | ➕ Thêm mới: card 3 số (Khách nợ / NCC / Đối tác) |

---

## 📒 SỔ QUỸ — Chi tiết giao dịch

### Cấu trúc mục tiêu (hiện tại đã gần đúng ✅)
SỔ QUỸ
│
├── Tab: Tổng quan
│ ├ Tổng quỹ hiện tại ✅
│ ├ Tiền mặt / Ngân hàng ✅
│ ├ Số dư đầu ngày ✅
│ ├ Biến động trong ngày (chart) ✅
│ └ Chốt quỹ cuối ngày ✅
│
├── Tab: Thu
│ ├ Bán hàng ✅
│ ├ Thu nợ khách ✅
│ ├ Sửa chữa ✅
│ ├ Tất toán NH ✅
│ └ Thu phát sinh ✅
│
├── Tab: Chi
│ ├ Nhập hàng ✅
│ ├ Chi phí ✅
│ ├ Trả nợ NCC ✅
│ ├ TT đối tác SC ✅
│ ├ Vốn LK SC ✅
│ └ Trả hàng ✅
│
└── Tab: Lịch sử
└ Timeline tất cả giao dịch (Thu + Chi + Công nợ gộp) ✅

### Vấn đề đã fix ✅
- ~~Sổ Quỹ chỉ load Firestore, mất data local~~ → Đã merge tất cả collection
- ~~debt_payments thiếu debtType~~ → LEFT JOIN + COALESCE
- ~~Home và Sổ Quỹ tính khác nhau~~ → DailyFinancialAnalysisService chung

---

## 📒 LỊCH SỬ GIAO DỊCH — Single source

### Cấu trúc mục tiêu
LỊCH SỬ GIAO DỊCH
│
├── Tất cả giao dịch (default)
│ Gộp: bán hàng + thu nợ + nhập hàng + chi phí + trả NCC + sửa chữa + tất toán
│
├── Filter theo loại
│ Thu | Chi | Công nợ
│
├── Filter theo PTTT
│ Tiền mặt | Chuyển khoản | Trả góp
│
├── Tìm kiếm
│ Theo tên, mô tả, ghi chú
│
└── Xuất Excel
Export filtered data

### Hiện trạng
| Trang | Nguồn dữ liệu | Vấn đề |
|-------|---------------|--------|
| Sổ Quỹ > Lịch sử | Firestore + Local merge | ✅ Đầy đủ |
| Nhật ký tài chính (`FinancialActivityLogView`) | `financial_activity_log` SQLite | ❗ Phụ thuộc vào service ghi log |
| Nhật ký HĐ (`AuditLogView`) | `audit_logs` SQLite + Firestore | ❗ Khác mục đích (audit trail) |

### Phương án: Gom về 1 chỗ
- **Sổ Quỹ > Tab Lịch sử** = nguồn truth cho giao dịch tài chính
- **Nhật ký tài chính** = log bổ sung (chi tiết ai làm gì, lúc nào)
- **Audit Log** = system trail (không liên quan tài chính)

→ Entry point "Lịch sử giao dịch" dù từ Home hay Tài chính đều mở `CashClosingView(showOnlyTransactions: true)`

---

## 🔁 LUỒNG DỮ LIỆU TÀI CHÍNH
┌──────────────┐
│  Bán hàng    │ ──→ sales table
│  Sửa chữa    │ ──→ repairs table
│  Thu chi      │ ──→ expenses table
│  Công nợ      │ ──→ debts / debt_payments
│  Nhập hàng    │ ──→ supplier_import_history
│  Trả NCC      │ ──→ supplier_payments
│  TT Đối tác   │ ──→ repair_partner_payments
│  Trả hàng     │ ──→ sales_returns
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────┐
│  DailyFinancialAnalysisService   │  ← SINGLE ENGINE
│  .analyze(all raw data)          │
└──────┬───────────────────────────┘
       │
 ┌─────┼─────────┐
 ▼     ▼         ▼
 HOME TÀI CHÍNH SỔ QUỸ ← Cùng nguồn, cùng số
 
---

## 🧠 QUY TẮC THIẾT KẾ ĐỂ KHÔNG RỐI

### ❶ HOME chỉ hiển thị 3 số
- **Doanh thu** (totalIn)
- **Lợi nhuận** (netProfit)  
- **Tiền quỹ hiện có** (closingBalance + todayNet)

### ❷ TÀI CHÍNH mới hiển thị chi tiết
- Doanh thu / Giá vốn / Chi phí / Lợi nhuận
- Biến động trong ngày (bar chart)
- Chi tiết Thu / Chi breakdown

### ❸ Giao dịch gom về 1 chỗ
- **Thu**: Bán hàng + Thu nợ + Sửa chữa + Tất toán + Thu phát sinh
- **Chi**: Chi phí + Nhập hàng + Trả NCC + TT đối tác + Vốn LK + Trả hàng
- **Công nợ**: Khách nợ + NCC nợ + Đối tác nợ

### ❹ Không duplicate logic
- Tất cả tính toán → `DailyFinancialAnalysisService.analyze()`
- Tất cả query debt → `getDebtPaymentsForCashFlowByDateRange()` (LEFT JOIN)
- Tất cả merge data → Firestore + Local DB dedup by firestoreId

### ❺ Data phải merge (không chỉ Firestore)
- Sổ Quỹ / Tài chính load Firestore → **merge local DB** trước khi hiển thị
- Tránh mất giao dịch offline chưa sync

---

## 📋 KẾ HOẠCH TRIỂN KHAI (PHÂN GIAI ĐOẠN)

### Giai đoạn 1: Đơn giản hoá Home ✅ HOÀN THÀNH
**Mục tiêu**: Home chỉ 3 số + thao tác nhanh + hoạt động
**File ảnh hưởng**: 
- `lib/views/home_view.dart`
- `lib/widgets/dashboard_cards.dart`
- `lib/services/dashboard_config_service.dart`

**Chi tiết**:
1. ✅ `FinanceSummaryCard`: Đổi 3 cột thành Doanh thu / Lợi nhuận / Quỹ hiện có
2. ✅ `DashboardCardType.financeDetail`: Ẩn mặc định (visible: false) trên Home
3. ✅ `ActivityFeedCard`: Thêm debt_payments + supplier_payments vào feed
4. ✅ Giữ nguyên cơ chế Tùy chỉnh dashboard (user vẫn có thể bật lại chi tiết)

### Giai đoạn 2: Nâng cấp Finance Tab ✅ HOÀN THÀNH
**Mục tiêu**: Dashboard tài chính chuyên nghiệp
**File ảnh hưởng**:
- `lib/views/home_view.dart` (`_buildFinanceTab`)

**Chi tiết**:
1. ✅ Chuyển `_buildDashboardOverview` (biến động chart) vào Finance tab
2. ✅ Thêm card tóm tắt Công nợ (3 số: Khách nợ / NCC / Đối tác)
3. ✅ Nâng cấp 2 nút Sổ quỹ + Thu Chi: thêm số liệu quick-preview (số dư quỹ + thu/chi)
4. ✅ Tái cấu trúc grid báo cáo thành section rõ ràng

### Giai đoạn 3: Nâng cấp ActivityFeed ✅ HOÀN THÀNH
**Mục tiêu**: Hoạt động hôm nay đầy đủ loại giao dịch
**File ảnh hưởng**:
- `lib/widgets/dashboard_cards.dart` (`ActivityFeedCard`)

**Chi tiết**:
1. ✅ Thêm nguồn: `debt_payments`, `supplier_payments`, `repair_partner_payments` (6 nguồn tổng cộng)
2. ✅ Icon + màu phân biệt theo loại (Bán hàng xanh, Nhập hàng cam, Trả nợ đỏ, Thu nợ xanh dương, Đối tác indigo)
3. ✅ Limit 10 items, "Xem tất cả" → CashClosingView(showOnlyTransactions: true)

### Giai đoạn 4: Quỹ hiện có (Balance Forward) ✅ HOÀN THÀNH
**Mục tiêu**: Hiển thị "Tiền quỹ hiện có" trên Home
**File ảnh hưởng**:
- `lib/views/home_view.dart`
- `lib/data/db_helper.dart`

**Chi tiết**:
1. ✅ Query chốt quỹ hôm qua: `db.getPreviousDayClosing(todayDateKey)` → `cashEnd + bankEnd`
2. ✅ Cộng biến động hôm nay: `previousClosingTotal + totalIn - totalOut`
3. ✅ Hiển thị trên `FinanceSummaryCard` cột thứ 3 (Quỹ hiện có)

### Giai đoạn 5: Báo cáo nâng cao ✅ HOÀN THÀNH
**Mục tiêu**: So sánh theo tuần/tháng, trending
**File ảnh hưởng**:
- `lib/views/revenue_view.dart`

**Chi tiết**:
1. ✅ Tab "SO SÁNH" — auto so sánh kỳ hiện tại vs kỳ trước (hôm nay/hôm qua, tuần/tuần trước, tháng/tháng trước, quý/quý trước, năm/năm trước)
   - 5 comparison cards: Doanh thu, Chi phí, Giá vốn, Lợi nhuận, Số đơn
   - Bảng chi tiết breakdown: Bán hàng, Sửa chữa, Thu khác, Chi phí HĐ, Giá vốn bán, Giá vốn SC
   - `_PeriodStats` class cho tính toán accrual-basis
2. ✅ Top 10 sản phẩm bán chạy (parsed from comma-separated productNames, ranked by quantity)
3. ✅ Top 10 khách hàng mua nhiều (ranked by totalSpent, showing order count)

---

## 🗂 FILE MAPPING — Nguồn dữ liệu cho từng màn hình

| Màn hình | Source files | Data engine | DB tables |
|----------|------------|-------------|-----------|
| Home (3 số) | `home_view.dart` | `DailyFinancialAnalysisService` | sales, repairs, expenses, debt_payments, supplier_payments... |
| Finance tab | `home_view.dart` (`_buildFinanceTab`) | `DailyFinancialAnalysisService` | (same) |
| Sổ Quỹ | `cash_closing_view.dart` | `DailyFinancialAnalysisService` | Firestore + Local merge |
| Công nợ | `debt_view.dart` | Direct query | debts, debt_payments |
| Thu Chi | `expense_view.dart` | Direct query | expenses |
| Báo cáo | `revenue_view.dart` | Aggregate query | sales, repairs |
| Nhật ký | `financial_activity_log_view.dart` | Direct query | financial_activity_log |
| Audit | `audit_log_view.dart` | Direct query | audit_logs |
---

## 📝 LỊCH SỬ TRIỂN KHAI

| Ngày | Giai đoạn | Commit | Mô tả |
|------|-----------|--------|-------|
| 2026-03-07 | GĐ1 | Nhiều commits | FinanceSummaryCard 3 số, ẩn financeDetail, ActivityFeed + debt/supplier |
| 2026-03-07 | GĐ2 | Nhiều commits | Dashboard overview, Debt summary card, finance shortcuts preview |
| 2026-03-07 | GĐ3 | `5456440` | ActivityFeed 6 nguồn + repair_partner_payments |
| 2026-03-07 | GĐ3 | `23b7c29` | "Xem tất cả" → CashClosingView, limit 10 |
| 2026-03-07 | GĐ4 | `80f75df` | Balance Forward: chốt hôm qua + biến động hôm nay |
| 2026-03-07 | GĐ4 | `bc38a8e` | Preview numbers trên Sổ quỹ + Thu Chi buttons |
| 2026-03-07 | GĐ5 | `baddc75` | Tab SO SÁNH trong RevenueView |
| 2026-03-08 | GĐ5 | `d52ad61` | Top 10 SP bán chạy + Top 10 khách hàng |

---

✅ **Tất cả 5 giai đoạn đã triển khai hoàn tất.**
- Phân tầng rõ ràng: Home (L1 glance) → Finance (L2 summary) → Sổ Quỹ (L3 detail) → Báo cáo (L4 report)
- SSOT: Mọi tính toán qua DailyFinancialAnalysisService, không view nào tự tính
- 30 unit tests pass cho DailyFinancialAnalysisService
- Live trên iOS, Google Play và web (quanlyshop.web.app)

