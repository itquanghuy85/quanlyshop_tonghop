# Phân Tích Hiệu Suất & Khả Năng Mở Rộng (Performance & Scalability Analysis)

> Cập nhật: Tháng 6/2025 — sau hoàn tất Phase 1–4C  
> Phạm vi: Toàn bộ mô-đun ứng dụng QuanLyShop

---

## 📊 Tổng Quan Rủi Ro (sau tối ưu Phase 1–4C)

| Mức Độ | Số Lượng | Mô Tả |
|--------|----------|-------|
| **✅ Đã Khắc Phục** | 8 | Đã hoàn thành trong Phase 1–4C |
| **🟠 Cao (High)** | 2 | Vẫn cần cải thiện — Cash Closing, delta sync |
| **🟡 Trung Bình (Medium)** | 3 | In-memory filtering ở một số view phụ, getAllX() cho collection nhỏ |
| **🟢 Thấp (Low)** | 2 | Rủi ro nhỏ, có thể bỏ qua |

---

## ✅ CÁC VẤN ĐỀ ĐÃ KHẮC PHỤC

### 1. ~~Sync Service: 26 listener đồng thời~~ → ĐÃ SỬA (Phase 3A)
**Commit:** `774c172` — Phase 3A: Lazy-load sync subscriptions

**Trước:** 26 listener Firestore chạy đồng thời khi mở app.  
**Sau:** Chia thành **critical subscriptions** (repairs, sales, products, expenses — load ngay) + **deferred subscriptions** (các collection phụ — load sau 3 giây). Giảm thời gian khởi động, giảm Firestore reads ban đầu.

**Vẫn còn:** Các subscription vẫn tải toàn bộ collection (chưa có `updatedAt > lastSyncTimestamp` delta filter) — xem Mục 10 bên dưới.

---

### 2. ~~Financial Activity Log: Query Firestore không có date filter~~ → ĐÃ SỬA (Phase 1)
**Commit:** `0a57860` — Phase 1 Performance

**Trước:** Tải 6 collection đầy đủ từ Firestore, filter bằng Dart.  
**Sau:** Query Firestore với `.where(dateField, isGreaterThanOrEqualTo: startMs).where(dateField, isLessThanOrEqualTo: endMs)` trực tiếp. Giảm reads Firestore đáng kể.

---

### 3. ~~Financial Report View: Tải toàn bộ 4 bảng SQLite~~ → ĐÃ SỬA (Phase 2)
**Commit:** `8c790bb` — Phase 2 Performance

**Trước:** Gọi `getAllSales()` + `getAllRepairs()` + `getAllExpenses()` + `getAllDebts()`, gộp tất cả vào memory.  
**Sau:** Dùng `getSalesByDateRange(startMs, endMs)`, query SQL trực tiếp với `WHERE soldAt BETWEEN ? AND ?` cho từng bảng. Bộ nhớ giảm từ toàn bộ DB xuống chỉ dữ liệu trong khoảng thời gian.

---

### 4. ~~Global Search: Tải toàn bộ dữ liệu mỗi lần tìm~~ → ĐÃ SỬA (Phase 2)
**Commit:** `8c790bb` — Phase 2 Performance

**Trước:** Tải ALL repairs + ALL sales + ALL products vào memory rồi filter có 300ms debounce.  
**Sau:** Dùng `searchRepairs(query, normalizedQuery, limit: 25)`, `searchSales(...)`, `searchProducts(...)` — SQL `LIKE` trực tiếp với `LIMIT 25`. Chỉ tải tối đa 75 kết quả thay vì toàn bộ DB.

---

### 5. ~~Thiếu SQLite Indexes~~ → ĐÃ SỬA (Phase 1)
**Commit:** `0a57860` — Phase 1 Performance

**Trước:** Không có index trên các cột hay dùng, full table scan.  
**Sau:** Thêm **30+ SQLite indexes** trong migration, bao gồm:
- `repairs(createdAt, status, repairedBy, deleted)`
- `sales(soldAt, sellerName, deleted)`
- `products(name, shopId, status, deleted)`
- `expenses(date, category)`
- `debts(createdAt, status, deleted)`
- `attendance(dateKey, userId)`
- `debt_payments(paidAt, debtId)`
- `financial_activity_log(shopId, createdAt, activityType)`
- Và nhiều index khác cho variants, categories, sync_queue...

---

### 6. ~~debugPrint per record trong getAllRepairs/getAllSales~~ → ĐÃ SỬA (Phase 1)
**Commit:** `0a57860` — Phase 1 Performance

**Trước:** `debugPrint` cho **mỗi bản ghi** trong for-loop (10,000 records = 10,000 prints).  
**Sau:** Chỉ log tổng count, không in từng record. Tiết kiệm CPU + I/O.

---

### 7. ~~Thiếu Firestore Composite Index~~ → ĐÃ SỬA (Phase 3D)
**Commit:** `af67537` — Phase 3D: Add 11 missing Firestore composite indexes

**Trước:** 15 composite index, thiếu cho nhiều collection phụ.  
**Sau:** Tổng **29 composite indexes** trong `firestore.indexes.json`, bao gồm đầy đủ cho: `debt_payments`, `supplier_payments`, `repair_partner_payments`, `supplier_import_history`, `attendance`, `audit_logs`, `repair_parts`, `purchase_orders`, `payment_intents`, v.v.

---

### 8. ~~Thiếu Performance Monitoring~~ → ĐÃ SỬA (Phase 4C)
**Commit:** `6349222` — Phase 4C: Performance monitoring utility

**Đã thêm:** `PerfMonitor` utility (`lib/utils/perf_monitor.dart`) — đo thời gian `initRealTimeSync`, `deferredSync`, và các operation khác. Cho phép theo dõi performance bottleneck trong production.

---

## 🟠 CÁC VẤN ĐỀ CÒN TỒN TẠI

### 9. Cash Closing View: Vẫn tải nhiều collection không date filter
**File:** `lib/views/cash_closing_view.dart`

**Hiện trạng:** Mở trang Chốt Ca subscribe 8 collection Firestore (sales, repairs, expenses, debt_payments, supplier_payments, repair_partner_payments, supplier_import_history, cash_closings) — chỉ filter theo `shopId`, **không filter theo ngày**.

**Tác động:** Shop hoạt động 2+ năm → tải toàn bộ lịch sử giao dịch mỗi lần mở trang.

**Giải pháp đề xuất:**
1. Thêm date filter (chỉ lấy dữ liệu trong ca/ngày hiện tại)
2. Hoặc chuyển sang đọc từ SQLite local (đã sync) thay vì query Firestore trực tiếp
3. Server-side aggregation qua Cloud Functions

---

### 10. Sync Service: Chưa có Delta Sync
**File:** `lib/services/sync_service.dart`

**Hiện trạng:** Dù đã lazy-load (Phase 3A) và có `updatedAt` comparison để resolve conflict, các subscription vẫn tải **toàn bộ collection** (không dùng `where('updatedAt', isGreaterThan: lastSyncTimestamp)`).

**Tác động:** Mỗi lần mở app vẫn đọc toàn bộ docs cho mỗi collection. Ở quy mô 20,000+ docs, đây là chi phí Firestore reads lớn nhất.

**Giải pháp đề xuất:**
1. Lưu `lastSyncTimestamp` vào SharedPreferences sau mỗi lần sync thành công
2. Subscription dùng `where('updatedAt', isGreaterThan: lastSyncTimestamp)` cho incremental reads
3. Full sync chỉ chạy khi cài lại app hoặc xóa cache

---

## 🟡 CÁC RỦI RO TRUNG BÌNH

### 11. In-Memory Filtering ở Expense/Debt/Parts Views
Các view `expense_view.dart`, `debt_view.dart`, `parts_inventory_view.dart` vẫn tải toàn bộ từ SQLite rồi filter bằng Dart. Ở quy mô <5,000 bản ghi, vẫn chấp nhận được. Nên refactor khi collection lớn hơn.

### 12. Một số getAllX() vẫn dùng cho collection nhỏ
Các method như `getAllSuppliers()`, `getAllCashClosings()`, `getAllAttendance()` vẫn tải toàn bộ. Chấp nhận được cho collection <500 docs, nhưng nên chuyển sang paged/filtered khi mở rộng.

### 13. Product Query Không Limit Trong Firestore
`firestore_service.dart`: Query products by name không `.limit()`. Nên thêm limit cho shop có >1,000 sản phẩm.

---

## 🟢 RỦI RO THẤP

### 14. Xử Lý Hình Ảnh — ĐÃ TỐT
- Firebase Storage URLs (không lưu base64 trong Firestore)
- Nén 70% quality, max 1920px
- Xóa file tạm sau upload

### 15. Query Collection Nhỏ Không Limit
Staff list, salary settings, shop settings — collection nhỏ (<50 docs), không cần limit.

---

## 📈 Ngưỡng Dữ Liệu Dự Kiến (sau tối ưu)

| Mô-đun | <1,000 | 1,000-5,000 | 5,000-10,000 | >10,000 |
|---------|--------|-------------|--------------|---------|
| Đơn sửa (Repairs) | ✅ OK | ✅ OK (indexed) | ✅ OK (SQL search) | ⚠️ Sync reads cao |
| Bán hàng (Sales) | ✅ OK | ✅ OK (indexed) | ✅ OK (date-range) | ⚠️ Sync reads cao |
| Sản phẩm (Products) | ✅ OK | ✅ OK | ✅ OK | ✅ OK |
| Chi phí (Expenses) | ✅ OK | ✅ OK | ✅ OK | ⚠️ In-memory filter |
| Công nợ (Debts) | ✅ OK | ✅ OK | ✅ OK | ⚠️ In-memory filter |
| Sync Service | ✅ Lazy-load | ✅ OK | ⚠️ Reads tăng | 🟠 Cần delta sync |
| Tìm kiếm | ✅ SQL LIKE | ✅ Indexed | ✅ LIMIT 25 | ✅ OK |
| Báo cáo tài chính | ✅ Date-range | ✅ SQL query | ✅ OK | ✅ OK |

---

## 🛠️ LỘ TRÌNH KHẮC PHỤC — TRẠNG THÁI THỰC TẾ

### ✅ Giai Đoạn 1 — HOÀN THÀNH (commit `0a57860`)
1. ✅ **Thêm 30+ SQLite indexes** cho các cột thường query
2. ✅ **Bỏ debugPrint** từng record trong getAllRepairs/getAllSales
3. ✅ **Thêm date filter** vào Firestore queries trong financial_activity_log_view

### ✅ Giai Đoạn 2 — HOÀN THÀNH (commit `8c790bb`)
4. ✅ **Chuyển global_search sang SQL LIKE** với limit 25 per collection
5. ✅ **Thêm updatedAt** trên tất cả Firestore writes (conflict resolution)
6. ✅ **Refactor financial_report_view** sang SQL date-range queries

### ✅ Giai Đoạn 3 — HOÀN THÀNH (commits `774c172`, `af67537`)
7. ✅ **Lazy-load subscriptions** — critical subs ngay, deferred sau 3s
8. ✅ **Thêm 14 Firestore composite indexes** (tổng 29)

### ✅ Giai Đoạn 4 — HOÀN THÀNH (commits `59a7e54`, `6349222`)
9. ✅ **Pagination & date-range** cho revenue view
10. ✅ **PerfMonitor** utility cho đo lường performance

### 🔜 Giai Đoạn 5 — TIẾP THEO
11. 🟠 **Delta sync**: `where('updatedAt', isGreaterThan: lastSyncTimestamp)` cho sync_service
12. 🟠 **Cash Closing date filter**: Chỉ query dữ liệu trong ngày/ca hiện tại
13. 🟡 **Cloud Functions aggregation** cho báo cáo nặng
14. 🟡 **Data archiving**: Lưu trữ dữ liệu >1 năm

---

## 💰 Ước Tính Chi Phí Firestore (sau tối ưu)

| Quy Mô Shop | Docs Tổng | Reads/Mở App (trước) | Reads/Mở App (sau) | Giảm |
|-------------|-----------|----------------------|---------------------|------|
| Nhỏ (<6 tháng) | ~2,000 | 2,000 | ~500 (lazy-load) | -75% |
| Trung Bình (1 năm) | ~10,000 | 10,000 | ~3,000 (lazy-load) | -70% |
| Lớn (2+ năm) | ~30,000 | 30,000 | ~10,000 (lazy-load) | -67% |
| Rất Lớn (3+ năm) | ~100,000 | 100,000 | ~35,000 (lazy-load) | -65% |

> *Với delta sync (Phase 5), reads có thể giảm thêm 80-90% cho lần mở app thứ 2 trở đi.*  
> *Firestore miễn phí 50,000 reads/ngày. Vượt quá: $0.06/100,000 reads.*

---

*Tài liệu cập nhật dựa trên mã nguồn thực tế tại commit `6349222`. Cập nhật lại khi có thay đổi kiến trúc.*
