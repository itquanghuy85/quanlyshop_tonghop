# Phân Tích Hiệu Suất & Khả Năng Mở Rộng (Performance & Scalability Analysis)

> Phân tích ngày: $(date)  
> Phạm vi: Toàn bộ mô-đun ứng dụng QuanLyShop

---

## 📊 Tổng Quan Rủi Ro

| Mức Độ | Số Lượng | Mô Tả |
|--------|----------|-------|
| **🔴 Nghiêm Trọng (Critical)** | 8 | Ảnh hưởng trực tiếp đến trải nghiệm người dùng, chi phí Firestore, crash khi dữ liệu lớn |
| **🟠 Cao (High)** | 7 | Gây chậm đáng kể ở quy mô >5,000 bản ghi |
| **🟡 Trung Bình (Medium)** | 5 | Ảnh hưởng nhẹ, cần khắc phục trong lộ trình dài hạn |
| **🟢 Thấp (Low)** | 2 | Rủi ro nhỏ, có thể bỏ qua |

---

## 🔴 CÁC RỦI RO NGHIÊM TRỌNG

### 1. Sync Service: Tải Toàn Bộ Dữ Liệu Mỗi Lần Khởi Động
**File:** `lib/services/sync_service.dart`

**Vấn đề:** 26 listener Firestore chạy đồng thời, mỗi listener tải TOÀN BỘ collection (không có `lastSyncTimestamp` filter). Không có cơ chế delta sync.

**Tác động tại quy mô lớn:**
- Shop có 10,000 repairs + 5,000 sales + 2,000 products + 3,000 expenses = **20,000+ Firestore reads mỗi lần mở app**
- 3 thiết bị × 10 lần mở/ngày = **600,000 reads/ngày** → **chi phí Firestore tăng gấp bội**
- RAM thiết bị: Tải 20,000+ object vào bộ nhớ cùng lúc có thể gây crash trên thiết bị yếu

**Giải pháp đề xuất:**
1. **Thêm `updatedAt` filter**: `where('updatedAt', isGreaterThan: lastSyncTimestamp)` cho mỗi subscription
2. **Lưu `lastSyncTimestamp`** vào SharedPreferences/SQLite sau mỗi lần sync
3. **Lazy loading**: Chỉ subscribe vào collection khi user thực sự mở tab tương ứng
4. **Batch sync**: Nhóm các collection ít thay đổi (suppliers, categories) thành sync theo lịch (hourly)

---

### 2. Cash Closing View: Tải 7 Collections Đầy Đủ
**File:** `lib/views/cash_closing_view.dart` (dòng 228-262)

**Vấn đề:** Mỗi lần mở trang Chốt Ca, app tải 7 collection Firestore hoàn toàn: `sales`, `repairs`, `expenses`, `debt_payments`, `supplier_payments`, `repair_partner_payments`, `debts` — không có `.limit()` hay date range.

**Tác động:** Có thể tải >100MB dữ liệu cho shop hoạt động 2+ năm.

**Giải pháp:**
1. Thêm filter date range (chỉ lấy dữ liệu trong ca hiện tại hoặc ngày hiện tại)
2. Sử dụng server-side aggregation (Cloud Functions tính tổng)
3. Cache kết quả chốt ca trước đó, chỉ tải dữ liệu mới

---

### 3. Financial Activity Log: Tải 6 Collections Không Filter
**File:** `lib/views/financial_activity_log_view.dart` (dòng 179-342)

**Vấn đề:** Tải 6 collection đầy đủ từ Firestore, rồi filter trong Dart. Dù có tính `startMs`/`endMs`, query Firestore KHÔNG dùng date filter.

**Giải pháp:** Thêm `.where('createdAt', isGreaterThanOrEqualTo: startMs).where('createdAt', isLessThanOrEqualTo: endMs)` trực tiếp vào query Firestore.

---

### 4. Financial Report View: Tải Toàn Bộ 4 Bảng SQLite
**File:** `lib/views/financial_report_view.dart` (dòng 165-324)

**Vấn đề:** Gọi `getAllSales()` + `getAllRepairs()` + `getAllExpenses()` + `getAllDebts()`, gộp thành 1 list `allTransactions` rồi sort.

**Tác động:** 20,000+ bản ghi vào bộ nhớ → OOM trên thiết bị 2GB RAM.

**Giải pháp:**
1. Query trực tiếp với date range trong SQL: `WHERE soldAt BETWEEN ? AND ?`
2. Dùng SQL aggregation cho tổng hợp (SUM, COUNT) thay vì Dart loop

---

### 5. Global Search: Tải Toàn Bộ Dữ Liệu Mỗi Lần Tìm Kiếm
**File:** `lib/views/global_search_view.dart` (dòng 85-122)

**Vấn đề:** Mỗi lần search (dù có 300ms debounce), app tải ALL repairs + ALL sales + ALL products vào memory rồi filter.

**Giải pháp:**
1. Dùng SQLite FTS (Full-Text Search) cho tìm kiếm text
2. Hoặc thêm method `searchRepairs(query, limit)` dùng SQL `LIKE '%query%' LIMIT 20`
3. Cache kết quả search gần nhất

---

## 🟠 CÁC RỦI RO CAO

### 6. Thiếu Index SQLite
**File:** `lib/data/db_helper.dart`

**Các cột thiếu index (thường xuyên dùng trong WHERE/ORDER BY):**
- `repairs(createdAt)`, `repairs(status)`, `repairs(repairedBy)`
- `sales(soldAt)`, `sales(sellerName)`
- `products(shopId)`, `products(name)`
- `expenses(date)`, `expenses(category)`
- `debts(createdAt)`, `debts(status)`
- `attendance(dateKey)`

**Tác động:** Full table scan ở 10,000+ rows → chậm 5-10x so với indexed query.

**Giải pháp:** Thêm các index trong `_onCreate` hoặc migration:
```sql
CREATE INDEX IF NOT EXISTS idx_repairs_createdAt ON repairs(createdAt);
CREATE INDEX IF NOT EXISTS idx_repairs_status ON repairs(status);
CREATE INDEX IF NOT EXISTS idx_repairs_repairedBy ON repairs(repairedBy);
CREATE INDEX IF NOT EXISTS idx_sales_soldAt ON sales(soldAt);
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date);
CREATE INDEX IF NOT EXISTS idx_debts_createdAt ON debts(createdAt);
```

---

### 7. getAllX() Được Dùng Thay Vì Paged Methods
**File:** `lib/data/db_helper.dart`

**Phát hiện:** Có `getRepairsPaged()`, `getSalesPaged()`, `getProductsPaged()` nhưng hầu hết code gọi `getAllRepairs()`, `getAllSales()`, `getAllProducts()`.

19 method `getAll*` tải toàn bộ bảng: repairs, sales, products, expenses, debts, cash_closings, attendance, purchase_orders, parts, debt_payments, supplier_import_history, supplier_payments, payment_intents...

**Giải pháp:** Refactor dần sang paged methods + server-side filtering.

---

### 8. debugPrint Trong getAllRepairs()/getAllSales()
**File:** `lib/data/db_helper.dart` (dòng 2807-2828, 2897-2908)

**Vấn đề:** `debugPrint` cho **mỗi bản ghi** trong for-loop. 10,000 repairs = 10,000+ lần print. Dù `debugPrint` throttle, string interpolation vẫn tốn CPU.

**Giải pháp:** Chỉ debugPrint tổng count, không print từng record.

---

## 🟡 CÁC RỦI RO TRUNG BÌNH

### 9. Thiếu Firestore Composite Index
**File:** `firestore.indexes.json`

Có 15 composite index nhưng THIẾU cho: `debt_payments`, `supplier_payments`, `repair_partner_payments`, `supplier_import_history`, `attendance`, `audit_logs`, `repair_parts`, `purchase_orders`, `payment_intents`.

### 10. In-Memory Filtering ở Expense/Debt/Parts Views
Các view `expense_view.dart`, `debt_view.dart`, `parts_inventory_view.dart` tải toàn bộ rồi filter. Ở quy mô trung bình (<5,000), vẫn chấp nhận được.

### 11. Product Query Không Limit Trong Firestore
`firestore_service.dart` dòng 91-97: Query products by name không `.limit()`.

---

## 🟢 RỦI RO THẤP

### 12. Xử Lý Hình Ảnh — ĐÃ TỐT
- Firebase Storage URLs (không lưu base64 trong Firestore)
- Nén 70% quality, max 1920px
- Xóa file tạm sau upload

### 13. Query Nhỏ Không Limit
Staff list, salary settings — collection nhỏ (<50 docs), không cần limit.

---

## 📈 Ngưỡng Dữ Liệu Dự Kiến

| Mô-đun | <1,000 | 1,000-5,000 | 5,000-10,000 | >10,000 |
|---------|--------|-------------|--------------|---------|
| Đơn sửa (Repairs) | ✅ OK | ⚠️ Chậm search | 🔴 Chậm load | 🔴 Crash |
| Bán hàng (Sales) | ✅ OK | ⚠️ Chậm report | 🔴 Chậm load | 🔴 Crash |
| Sản phẩm (Products) | ✅ OK | ✅ OK | ⚠️ Chậm search | 🔴 Chậm load |
| Chi phí (Expenses) | ✅ OK | ✅ OK | ⚠️ Chậm | 🟠 Chậm |
| Công nợ (Debts) | ✅ OK | ✅ OK | ⚠️ Chậm | 🟠 Chậm |
| Sync Service | ⚠️ Tải 26 collections | 🟠 Nhiều reads | 🔴 Chi phí cao | 🔴 Quá tải |

---

## 🛠️ LỘ TRÌNH KHẮC PHỤC ĐỀ XUẤT

### Giai Đoạn 1 — Khẩn Cấp (1-2 tuần)
1. **Thêm SQLite indexes** cho các cột thường query
2. **Bỏ debugPrint** từng record trong getAllRepairs/getAllSales
3. **Thêm date filter** vào Firestore queries trong cash_closing_view và financial_activity_log_view

### Giai Đoạn 2 — Ngắn Hạn (2-4 tuần)
4. **Chuyển global_search sang SQL LIKE** thay vì tải toàn bộ
5. **Thêm delta sync** (updatedAt > lastSyncTimestamp) cho sync_service
6. **Refactor financial_report_view** sang SQL aggregation

### Giai Đoạn 3 — Trung Hạn (1-2 tháng)
7. **Lazy-load subscriptions** trong sync_service
8. **Cloud Functions aggregation** cho báo cáo tài chính
9. **Data archiving**: Lưu trữ dữ liệu >1 năm vào collection riêng
10. **Thêm Firestore composite indexes** cho các collection còn thiếu

### Giai Đoạn 4 — Dài Hạn (3-6 tháng)
11. **Offline-first architecture**: Ưu tiên SQLite, sync nền
12. **Pagination toàn bộ**: Thay getAllX() bằng paged methods
13. **Monitoring**: Thêm performance metrics (Firestore reads/day, sync time, RAM usage)

---

## 💰 Ước Tính Chi Phí Firestore Theo Quy Mô

| Quy Mô Shop | Docs Tổng | Reads/Mở App | 3 Devices × 10/ngày | Chi Phí/Tháng (USD) |
|-------------|-----------|-------------|---------------------|---------------------|
| Nhỏ (<6 tháng) | ~2,000 | 2,000 | 60,000/ngày | ~$1-2 |
| Trung Bình (1 năm) | ~10,000 | 10,000 | 300,000/ngày | ~$5-10 |
| Lớn (2+ năm) | ~30,000 | 30,000 | 900,000/ngày | ~$15-30 |
| Rất Lớn (3+ năm) | ~100,000 | 100,000 | 3,000,000/ngày | ~$50-100+ |

> *Ghi chú: Firestore miễn phí 50,000 reads/ngày. Vượt quá: $0.06/100,000 reads.*

---

*Tài liệu này được tạo tự động dựa trên phân tích mã nguồn thực tế. Cập nhật lại khi có thay đổi kiến trúc.*
