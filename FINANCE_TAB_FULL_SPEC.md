# FINANCE_TAB_FULL_SPEC

Tài liệu này mô tả theo code hiện có trong project, không suy đoán. Mọi mục không xác minh được trực tiếp từ mã đều ghi:

UNKNOWN (không tìm thấy trong code)

---

## PHẦN 1: DANH SÁCH MÀN THUỘC FINANCE TAB

### 1) Finance tab container (inline trong Home)
- Màn: Finance tab của Home
- File: lib/views/home_view.dart
- Hàm chính: `_buildFinanceTab()`

### 2) RevenueView
- File: lib/views/revenue_view.dart

### 3) ExpenseView
- File: lib/views/expense_view.dart

### 4) DebtView
- File: lib/views/debt_view.dart

### 5) CashClosingView (Sổ quỹ + lịch sử giao dịch)
- File: lib/views/cash_closing_view.dart

### 6) FinancialReportView
- File: lib/views/financial_report_view.dart

### 7) FinancialActivityLogView (Nhật ký tài chính/hệ thống)
- File: lib/views/financial_activity_log_view.dart

### 8) Các màn report tài chính được mở từ Finance tab
- MonthlyProfitReportView
  - File: lib/views/monthly_profit_report_view.dart
- DailyActivityReportView
  - File: lib/views/daily_activity_report_view.dart
- AuditLogView
  - File: lib/views/audit_log_view.dart

Ghi chú: 3 màn ở mục 8 được điều hướng trực tiếp từ grid “Report & Analysis” trong finance tab của Home.

---

## PHẦN 2: CHI TIẾT TỪNG MÀN

## Screen: Finance Tab (Home)

### File
- lib/views/home_view.dart

### 1) LAYOUT TREE
```text
Scaffold
 ├── backgroundColor: AppColors.background
 └── body: RefreshIndicator
     └── ResponsiveCenter
         └── ListView(padding horizontal responsive, vertical 16)
             ├── _buildTabHeader("Tài chính", icon wallet)
             ├── _buildSectionHeader("Tổng quan hôm nay")
             ├── FinanceSummaryCard(onTap -> CashClosingView)
             ├── _buildDashboardOverview()
             ├── _buildSectionHeader("CÔNG NỢ")
             ├── _buildDebtSummaryCard(onTap -> DebtView)
             ├── _buildSectionHeader("Thao tác nhanh")
             ├── Row
             │   ├── _financeQuickCard("Sổ quỹ") -> CashClosingView
             │   └── _financeQuickCard("Thu Chi") -> ExpenseView (có điều kiện quyền)
             ├── _buildSectionHeader("Report & Analysis")
             └── GridView.count (quick cards điều hướng)
                 ├── RevenueView
                 ├── DebtView (có điều kiện quyền)
                 ├── CashClosingView(showOnlyTransactions: true)
                 ├── AuditLogView
                 ├── MonthlyProfitReportView
                 └── DailyActivityReportView (có điều kiện quyền)
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- nền trang: `AppColors.background`
- header finance: `Colors.indigo`
- quick card nền: `color.withOpacity(0.05)`
- quick card border: `color.withOpacity(0.2)`
- debt summary card: nền trắng + shadow đen opacity 0.05

#### Text
| Nội dung | Size | Weight | Color |
| --- | --- | --- | --- |
| title quick card | theo `AppTextStyles.body2` | w600 | color card |
| subtitle quick card | 12 | default | color opacity 0.7 |
| tiêu đề tab header | theo `AppTextStyles.headline3` | bold | trắng |
| ngày trong tab header | theo `AppTextStyles.caption` | default | trắng opacity 0.8 |
| debt tổng | 12 | bold | đỏ/ghi tùy giá trị |

#### Spacing
- ListView padding: horizontal responsive + vertical 16
- khoảng cách section: nhiều `SizedBox(height: 16/20)`
- quick card radius: 10
- tab header radius: 12
- debt summary radius: 14

### 3) BUTTON / ACTION

- FinanceSummaryCard onTap
  - `onTap -> _pushRoute(... CashClosingView())`

- DebtSummaryCard onTap
  - `onTap -> _pushRoute(... DebtView())`

- Quick card “Sổ quỹ”
  - `onTap -> CashClosingView()`

- Quick card “Thu Chi”
  - `onTap -> ExpenseView()`
  - chỉ hiển thị khi `hasFullAccess || _permissions['allowViewExpenses'] == true`

- Grid quick cards
  - Báo cáo doanh thu -> `RevenueView()`
  - Quản lý công nợ -> `DebtView()`
  - Lịch sử tài chính -> `CashClosingView(showOnlyTransactions: true)`
  - Nhật ký hệ thống -> `AuditLogView()`
  - Lợi nhuận theo tháng -> `MonthlyProfitReportView()`
  - Báo cáo hoạt động -> `DailyActivityReportView()`

### 4) INPUT
- Không có input form trong `_buildFinanceTab()`.

### 5) CARD
- `FinanceSummaryCard`
  - truyền `revenue`, `netProfit`, `currentFund`
- `_buildDebtSummaryCard`
  - hiển thị tổng công nợ + breakdown
- `_financeQuickCard`
  - icon + title + subtitle + chevron

### 6) LIST / TABLE
- GridView quick actions ở cuối tab.

### 7) POPUP / DIALOG
- UNKNOWN (không có dialog trực tiếp trong `_buildFinanceTab()`)

### 8) USER FLOW
```text
User mở tab Tài chính
→ xem tổng quan + công nợ + sổ quỹ
→ bấm card tương ứng
→ push sang màn nghiệp vụ (Revenue/Expense/Debt/Cash/Report...)
```

### 9) NAVIGATION
- toàn bộ bằng `MaterialPageRoute` qua `_pushRoute(...)`

### 10) LOGIC
- tab cần quyền `allowViewRevenue` từ cấu hình tab Home
- hiển thị card theo quyền (`allowViewExpenses`, `allowViewDebts`, `allowViewRevenue`)
- dữ liệu tổng quan lấy từ state thống kê ngày trong `_HomeViewState`

### 11) PERMISSION
- vào tab finance: `allowViewRevenue`
- nút Thu Chi: `allowViewExpenses` hoặc full access
- nút Quản lý công nợ: `allowViewDebts` hoặc full access
- nút Báo cáo hoạt động: `allowViewRevenue` hoặc full access

---

## Screen: RevenueView

### File
- lib/views/revenue_view.dart

### 1) LAYOUT TREE
```text
Scaffold
 ├── AppBar: CustomAppBar
 └── Body: Column
     ├── TabBar (2 tab)
     └── TabBarView
         ├── TỔNG QUAN
         └── SO SÁNH
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- app accent: `AppBarAccents.finance` (qua custom app bar)
- nhiều màu biểu đồ/nhóm theo `fl_chart`
- trạng thái sync lỗi: cam

#### Text
- dùng `AppTextStyles` xuyên suốt
- sync status text hiển thị trên appbar actions

#### Spacing
- UNKNOWN (chi tiết pixel tất cả section con không thể liệt kê hết ở một hàm duy nhất)

### 3) BUTTON / ACTION
- filter button -> mở `_showFilterSheet()`
- sync button -> `_syncWithFirebase()`
- tab chuyển giữa tổng quan và so sánh
- custom date range (khi filter custom)

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| cashEndCtrl | TextEditingController (liên quan chốt quỹ) | UNKNOWN | UNKNOWN |
| bankEndCtrl | TextEditingController | UNKNOWN | UNKNOWN |

### 5) CARD
- card tổng hợp doanh thu/lợi nhuận
- card so sánh kỳ hiện tại vs kỳ trước
- card breakdown (bán hàng/sửa chữa/chi tiêu...) theo filter

### 6) LIST / TABLE
- dữ liệu nguồn: repairs, sales, expenses, debtPayments, supplierImports, supplierPayments, repairPartnerPayments, closings
- lọc theo `_timeFilter`: today/week/month/quarter/year/custom

### 7) POPUP / DIALOG
- BottomSheet filter thời gian
- Date range picker khi chọn custom

### 8) USER FLOW
```text
User vào RevenueView
→ chọn bộ lọc thời gian
→ hệ thống load dữ liệu theo range
→ xem tổng quan hoặc so sánh kỳ
→ có thể bấm sync thủ công
```

### 9) NAVIGATION
- chủ yếu ở nội bộ màn bằng tab/filter
- không thấy push sang màn khác trong khung chính revenue

### 10) LOGIC
- `_loadPermissions()` lấy `allowViewRevenue`, `allowViewCostPrice`
- `_loadAllData()` load DB theo range lớn (từ Jan 1 năm trước -> hiện tại)
- event bus debounce reload khi có thay đổi finance
- tính actual paid cho sale (trả góp/công nợ/thanh toán thường)

### 11) PERMISSION
- không có quyền `allowViewRevenue` -> chặn xem màn
- `allowViewCostPrice` điều khiển hiển thị giá vốn

---

## Screen: ExpenseView

### File
- lib/views/expense_view.dart

### 1) LAYOUT TREE
```text
Scaffold
 ├── AppBar: CustomAppBar (title theo mode CHI/THU)
 ├── Body: ResponsiveCenter -> Column
 │   ├── _buildViewModeToggle()
 │   ├── _buildFilterBar()
 │   ├── Header summary (CHI hoặc THU)
 │   └── Expanded
 │       ├── CircularProgressIndicator (loading)
 │       ├── _buildEmpty() (empty)
 │       └── ListView.builder(_expenseProfessionalCard)
 └── FloatingActionButton: GradientFab
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- nền scaffold: `Color(0xFFF8FAFF)`
- mode CHI: tông đỏ (`0xFFD32F2F`, `0xFFEF5350`)
- mode THU: tông xanh lá (`0xFF2E7D32`, `0xFF66BB6A`)

#### Text
| Nội dung | Size | Weight | Color |
| --- | --- | --- | --- |
| title appbar | theo CustomAppBar | standard | trắng |
| subtitle appbar | theo `AppTextStyles.caption` | normal/bold theo sync | staff accent / cam lỗi |
| danh sách khoản | theo `AppTextStyles` | varied | theo card state |

#### Spacing
- list padding: horizontal 12, vertical 4
- nhiều card radius/shadow theo `_expenseProfessionalCard`

### 3) BUTTON / ACTION
- Toggle CHI/THU -> đổi `_viewMode`
- FAB -> `_showAddExpenseDialog()` hoặc `_showAddIncomeDialog()`
- Sync button -> `_syncWithFirebase()`
- Export Excel -> `ExportDateFilterDialog.show(...)`
- icon nhập kho -> mở `FastStockInView()`
- delete expense -> `_handleDeleteExpense(...)`

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| nội dung chi/thu | TextField | theo dialog | bắt buộc (trong flow lưu) |
| số tiền | CurrencyTextField | số tiền | validate qua MoneyUtils (min > 0) |
| ghi chú | TextField | optional | optional |
| paymentMethod | lựa chọn chip/dropdown | tiền mặt/chuyển khoản | bắt buộc theo flow |
| phạm vi scope | lựa chọn | SHOP/CA_NHAN/TAT_CA | filter logic |

### 5) CARD
- `_expenseProfessionalCard(item, index)`
  - hiển thị category, amount, thời gian, note, action delete

### 6) LIST / TABLE
- `_filteredExpenses`
- lọc theo:
  - mode CHI/THU
  - phạm vi scope
  - filter type ngày/tuần/tháng

### 7) POPUP / DIALOG
- dialog thêm chi phí
- dialog thêm thu phát sinh
- dialog xác nhận xóa
- dialog xác thực mật khẩu trước khi xóa (reauth)
- export date filter dialog

### 8) USER FLOW
```text
User mở ExpenseView
→ chọn mode CHI hoặc THU
→ bấm FAB thêm khoản mới
→ nhập dữ liệu và lưu
→ emit expenses_changed
→ list cập nhật
```

### 9) NAVIGATION
- AppBar action nhập kho -> `FastStockInView`
- các thao tác còn lại trong màn

### 10) LOGIC
- quyền: `allowViewExpenses`
- `_refresh()` load expense + debt purchase mapping
- xóa có check ngày đã chốt qua `AdjustmentService.canEditDirectly(...)`
- xóa cloud dùng soft delete payload

### 11) PERMISSION
- không có quyền -> hiển thị “Bạn không có quyền truy cập tính năng này”

---

## Screen: DebtView

### File
- lib/views/debt_view.dart

### 1) LAYOUT TREE
```text
Scaffold
 ├── AppBar: CustomAppBar.buildWithTabs
 │   └── TabBar: Khách / NCC / Đối tác (nếu enableRepair) / Khác
 ├── Body: TabBarView
 │   ├── _buildSimpleDebtList hoặc _buildSplitOtherDebtList
 │   ├── _buildSimpleDebtList (NCC)
 │   ├── _buildPartnerDebtList (đối tác sửa chữa)
 │   └── tab khác
 └── floating action / action bar theo tab
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- nợ phải thu: tông đỏ
- nợ phải trả: tông xanh
- đối tác sửa chữa: tông cam
- card xen kẽ zebra bằng alpha blend nhẹ

#### Text
| Nội dung | Size | Weight | Color |
| --- | --- | --- | --- |
| tên đối tượng nợ | headline5 | bold | đậm |
| tổng nợ header | body1 | bold | theo nhóm màu |
| info chip | caption | bold/normal | theo chip |

#### Spacing
- list/card dày đặc, margin card ~3 px
- card radius ~9
- summary header padding gọn

### 3) BUTTON / ACTION
- ghi nhận thanh toán -> `_payDebt(...)`
- xem lịch sử thanh toán -> `_showDebtHistory(...)`
- sync -> `_syncWithFirebase()`
- export excel -> `ExportDateFilterDialog`
- vào chi tiết đối tác -> `_navigateToPartnerDetail(...)`

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| số tiền thanh toán | CurrencyTextField | theo dialog | min > 0, <= còn nợ |
| phương thức thanh toán | lựa chọn | tiền mặt/chuyển khoản | bắt buộc |
| tìm kiếm | TextField | theo tên/sđt/ghi chú | filter mềm |

### 5) CARD
- `_debtCard`, `_debtCardWithIcon`, `_partnerDebtCard`
- hiển thị: total, paid, remaining, note, loại nợ, chỉ số index

### 6) LIST / TABLE
- nợ chuẩn: `_debts`
- nợ đối tác: `_partnerDebts`
- tab OTHER tách 2 khối: phải thu / phải trả
- có filter ẩn/hiện đã thanh toán

### 7) POPUP / DIALOG
- bottom sheet lịch sử thanh toán
- dialog/bottomsheet thu/chi nợ

### 8) USER FLOW
```text
User vào DebtView
→ chọn tab loại nợ
→ mở khoản nợ
→ xem lịch sử
→ nhập số tiền thanh toán
→ execute PaymentIntent
→ emit debts_changed
→ reload list
```

### 9) NAVIGATION
- vào `RepairPartnerDetailView` khi bấm card đối tác

### 10) LOGIC
- load quyền `allowViewDebts`
- load shop settings để quyết định có tab đối tác hay không
- event bus debounce refresh (`debts_changed`, `repair_partners_changed`)
- payment chạy qua `PaymentIntentService.executePaymentDirect(...)`

### 11) PERMISSION
- không có quyền -> chặn màn

---

## Screen: CashClosingView (Sổ quỹ)

### File
- lib/views/cash_closing_view.dart

### 1) LAYOUT TREE
```text
Scaffold
 ├── AppBar: CustomAppBar.buildWithTabs (khi showOnlyTransactions=false)
 └── Body: TabBarView
     ├── Tab 1: Tổng quan
     ├── Tab 2: Giao dịch thu
     ├── Tab 3: Giao dịch chi
     └── Tab 4: Chốt quỹ / chi tiết
```

Ghi chú: khi `showOnlyTransactions = true` thì rút còn 1 tab giao dịch.

### 2) STYLE CHI TIẾT

#### Màu sắc
- accent: `AppBarAccents.finance`
- thu: xanh
- chi: đỏ
- nhiều chip/card breakdown theo tông màu giao dịch

#### Text
- dùng `AppTextStyles` và `MoneyUtils` cho hiển thị tiền

#### Spacing
- UNKNOWN (không thể xác định toàn bộ pixel-level do file rất lớn và nhiều sub-widget)

### 3) BUTTON / ACTION
- chọn ngày / range ngày
- filter loại giao dịch
- tìm kiếm giao dịch (`_txSearchController`)
- lưu chốt quỹ
- sửa chốt quỹ
- xuất excel sổ quỹ

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| cashEndCtrl | TextEditingController | số dư tiền mặt cuối | UNKNOWN |
| bankEndCtrl | TextEditingController | số dư ngân hàng cuối | UNKNOWN |
| noteCtrl | TextEditingController | ghi chú | optional |
| search transaction | TextField | query | filter mềm |

### 5) CARD
- card phân tích tài chính ngày
- card breakdown doanh thu/chi phí/giá vốn
- card tổng hợp thu chi và net

### 6) LIST / TABLE
- tổng hợp từ sales/repairs/expenses/debt_payments/supplier imports/supplier payments/partner payments/sales returns
- mapping thêm debtTypeMap cho phân loại debt payment

### 7) POPUP / DIALOG
- dialog chốt quỹ
- dialog xác nhận/sửa
- UNKNOWN (chi tiết toàn bộ title/nút của từng dialog không trích xuất đủ trong đoạn code đã đọc)

### 8) USER FLOW
```text
User mở Sổ quỹ
→ chọn ngày hoặc khoảng ngày
→ xem danh sách giao dịch thu/chi
→ nhập số dư cuối ngày
→ lưu chốt quỹ
→ dữ liệu lưu local + sync cloud
```

### 9) NAVIGATION
- có điều hướng sang `SaleDetailView`, `RepairDetailView` khi bấm item giao dịch tương ứng

### 10) LOGIC
- `_loadAllData()` và `_loadAllDataFromLocalDB()`
- có nhánh `_loadAllDataFromFirestore()` để merge cloud + local unsynced
- lắng nghe event bus rất nhiều event finance để debounce reload
- khi shopId null fallback local

### 11) PERMISSION
- `allowViewRevenue` + `allowViewCostPrice`
- không có quyền -> chặn màn

---

## Screen: FinancialReportView

### File
- lib/views/financial_report_view.dart

### 1) LAYOUT TREE
```text
Scaffold (hoặc embedded)
 ├── AppBar / embedded header
 └── Body: Column
     ├── date range controls
     ├── loại giao dịch filter chips
     ├── search
     ├── summary cards (income/expense/profit)
     └── tab/segment hiển thị danh sách giao dịch
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- type filter cố định:
  - SALE xanh lá
  - REPAIR xanh dương
  - EXPENSE đỏ
  - PURCHASE cam
  - DEBT_COLLECT teal
  - DEBT_PAY xanh

#### Text
| Nội dung | Size | Weight | Color |
| --- | --- | --- | --- |
| type labels | theo app text style | varied | theo màu loại |
| amount | format tiền | bold | xanh/đỏ theo chiều tiền |

#### Spacing
- UNKNOWN (không có block style duy nhất cho toàn màn)

### 3) BUTTON / ACTION
- chọn ngày bắt đầu/kết thúc
- chọn type filters
- toggle chỉ thu / chỉ chi
- refresh
- export

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| searchQuery | TextField | tìm theo mô tả/người/liên quan | substring |

### 5) CARD
- summary tổng thu/tổng chi
- list item transaction theo model `TransactionItem`

### 6) LIST / TABLE
- hợp nhất giao dịch nhiều nguồn thành `_transactions`
- chuẩn hóa thành `TransactionItem`
- lọc theo date/type/search/direction

### 7) POPUP / DIALOG
- UNKNOWN (không thấy dialog bắt buộc trong đoạn đọc chính)

### 8) USER FLOW
```text
User mở FinancialReportView
→ chọn khoảng ngày
→ chọn loại giao dịch
→ xem tổng thu/chi
→ tìm kiếm item
→ xuất dữ liệu
```

### 9) NAVIGATION
- embedded có thể được nhúng trong màn khác
- có thể mở `DailyActivityReportView` (import tồn tại)

### 10) LOGIC
- `_loadData()` load theo `startMs/endMs`
- tính actual paid sale (xử lý trả góp và công nợ)
- sửa chữa chỉ tính đơn đã giao và không công nợ
- expense/thu khác/debt payments/import/supplier payments đều map về transaction chung

### 11) PERMISSION
- `allowViewRevenue`

---

## Screen: FinancialActivityLogView

### File
- lib/views/financial_activity_log_view.dart

### 1) LAYOUT TREE
```text
Scaffold (non-embedded)
 ├── AppBar CustomAppBar (title, subtitle, actions refresh/export)
 │   └── bottom: search field
 └── Body: ResponsiveCenter -> _buildActivityTab()

Embedded mode:
Column
 ├── header
 ├── search field
 └── Expanded(_buildActivityTab)
```

### 2) STYLE CHI TIẾT

#### Màu sắc
- scaffold nền: `Color(0xFFF0F4F8)`
- search nền: `grey.shade100`
- accent: `AppBarAccents.finance`

#### Text
| Nội dung | Size | Weight | Color |
| --- | --- | --- | --- |
| title appbar | mặc định custom appbar | default | trắng |
| search hint | subtitle1 size | default | grey 500 |
| permission denied | default text | normal | grey |

#### Spacing
- search field height 34, radius 17
- appbar bottom padding 12/6

### 3) BUTTON / ACTION
- refresh -> `_loadActivities()`
- export -> `ExcelExportHelper.exportActivityLog(...)`
- clear search

### 4) INPUT
| Field | Type | Placeholder | Validate |
| --- | --- | --- | --- |
| search text | TextField | Tìm theo loại, tiêu đề, người tạo, mô tả... | không validate cứng |

### 5) CARD
- mỗi activity card hiển thị icon, loại, title, amount, time, mô tả, metadata

### 6) LIST / TABLE
- nguồn từ `db.getFinancialActivities(limit: 500)`
- filter client-side theo `_searchQuery`

### 7) POPUP / DIALOG
- không thấy dialog bắt buộc trong main flow

### 8) USER FLOW
```text
User mở nhật ký tài chính
→ danh sách load 500 bản ghi gần nhất
→ tìm kiếm theo chuỗi
→ có thể export excel
```

### 9) NAVIGATION
- không push màn khác trong flow chính

### 10) LOGIC
- setup EventBus listener nhiều sự kiện finance/sync
- debounce reload 400ms
- parse map -> `FinancialActivity.fromMap`

### 11) PERMISSION
- `allowViewRevenue`

---

## PHẦN 3: COMPONENT DÙNG CHUNG (FINANCE)

- `CustomAppBar` / `CustomAppBar.buildWithTabs`
- `ResponsiveCenter` / responsive wrapper
- `CurrencyTextField`
- `MoneyUtils`
- `ExportDateFilterDialog`
- `GradientFab`
- `FinanceSummaryCard` (trong home finance tab)

UNKNOWN (không tìm thấy trong code)
- “custom card tài chính” dùng chung duy nhất toàn bộ finance module dưới 1 class duy nhất.

---

## PHẦN 4: STATE (LOADING / EMPTY / ERROR)

### Loading
- RevenueView: `_isLoading` + spinner
- ExpenseView: `_isLoading` + spinner
- DebtView: `_isLoading`
- CashClosingView: `_isLoading` / `_isLoadingFromFirestore`
- FinancialReportView: `_loading` / `_isLoadingData`
- FinancialActivityLogView: `_loading`

### Empty
- ExpenseView: `_buildEmpty()`
- DebtView: text “Không có công nợ...” theo từng tab
- FinancialActivityLogView: empty message trong tab list
- Revenue/Report/Cash: hiển thị theo nhánh list rỗng

### Error
- đồng bộ lỗi: `_syncStatus = 'Lỗi đồng bộ'`
- snackbar/toast lỗi khi sync/export/save thất bại
- quyền bị từ chối: hiển thị màn “Bạn không có quyền truy cập tính năng này”

---

## DATA FLOW TỔNG QUAN
```text
UI (View State)
→ DBHelper / Services (UserService, PaymentIntentService, SyncService, CategoryService, DebtSummaryService...)
→ Local SQLite
→ (Sync) Firestore qua SyncService/SyncOrchestrator
→ EventBus phát sự kiện
→ View debounce reload
```

---

## FINANCE FLOW TỔNG QUAN
```text
User mở tab Tài chính (Home)
→ chọn module (Revenue / Expense / Debt / Cash / Report / Log)
→ thao tác thêm/sửa/xóa/thanh toán/chốt quỹ
→ ghi local + queue sync/cloud
→ EventBus phát thay đổi
→ màn finance reload dữ liệu theo debounce
```

---

## GHI CHÚ PHẠM VI VÀ UNKNOWN

- Một số file rất lớn (đặc biệt `cash_closing_view.dart`, `expense_view.dart`) chứa nhiều widget con/hàm private; các giá trị style pixel-level của tất cả nhánh UI không thể liệt kê 100% dòng nếu không tách toàn bộ file thành tài liệu dòng-đến-dòng.
- Các mục không xác minh trực tiếp đã đánh dấu theo quy tắc:

UNKNOWN (không tìm thấy trong code)
