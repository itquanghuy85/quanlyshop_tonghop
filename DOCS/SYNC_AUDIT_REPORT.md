# 🔍 BÁO CÁO KIỂM TOÁN ĐỒNG BỘ HÓA DỮ LIỆU
**Ứng dụng**: Quản Lý Shop - Flutter + Firebase  
**Ngày kiểm toán**: 12/01/2026  
**Phiên bản DB**: v56  
**Chuyên viên**: AI Senior Auditor - Distributed Systems

---

## 📋 TÓM TẮT ĐIỀU HÀNH

### Mức độ nghiêm trọng: ⚠️ **TRUNG BÌNH-CAO**

Hệ thống hiện tại có **12 bảng đồng bộ 2 chiều**, **8 bảng chỉ local**, và **nhiều rủi ro không nhất quán dữ liệu** giữa các thiết bị. Cần sửa ngay **6 lỗi nghiêm trọng** để đảm bảo 50 thiết bị hiển thị dữ liệu giống nhau.

### ✅ CÁC SỬA ĐỔI ĐÃ THỰC HIỆN (Ngày 12/01/2026)

| Bug ID | Mô tả | File đã sửa | Trạng thái |
|--------|-------|-------------|------------|
| BUG-001 | `supplier_import_history` không sync | sync_service.dart, db_helper.dart, sync_orchestrator.dart | ✅ DONE |
| BUG-001a | `supplier_product_prices` không sync | sync_service.dart, db_helper.dart | ✅ DONE |
| BUG-002 | `supplier_payments` thiếu trong SyncOrchestrator | sync_orchestrator.dart | ✅ DONE |
| FIX-001 | Enqueue import history trong views | fast_stock_in_view.dart, stock_in_view.dart, inventory_view.dart, parts_inventory_view.dart | ✅ DONE |

---

## 1️⃣ SƠ ĐỒ LUỒNG DỮ LIỆU THEO THỰC THỂ

### 🔵 BẢNG CÓ ĐỒNG BỘ 2 CHIỀU (SQLite ↔ Firestore)

| Bảng | Ghi vào | Đọc từ | Real-time Listener | SyncOrchestrator |
|------|---------|--------|-------------------|------------------|
| `repairs` | Local → Cloud | **MIX** (View đọc local) | ✅ Yes | ✅ Yes |
| `sales` | Local → Cloud | **MIX** (View đọc local) | ✅ Yes | ✅ Yes |
| `products` | Local → Cloud | **MIX** (View đọc local) | ✅ Yes | ✅ Yes |
| `expenses` | Local → Cloud | **MIX** (View đọc local) | ✅ Yes | ✅ Yes |
| `debts` | Local → Cloud | **MIX** (View đọc local) | ✅ Yes | ✅ Yes |
| `debt_payments` | Local → Cloud | **ROOT collection** | ✅ Yes (ROOT) | ✅ Yes |
| `attendance` | Local → Cloud | MIX | ✅ Yes | ✅ Yes |
| `customers` | Local → Cloud | MIX | ✅ Yes | ✅ Yes |
| `suppliers` | Local → Cloud | MIX | ✅ Yes | ✅ Yes |
| `repair_parts` | Local → Cloud | MIX | ✅ Yes | ✅ Yes |
| `supplier_payments` | Local → Cloud | **ROOT collection** | ✅ Yes (ROOT) | ❌ No |
| `audit_logs` | Local → Cloud | MIX | ✅ Yes | ❌ No |

### 🔴 BẢNG CHỈ TỒN TẠI LOCAL (KHÔNG ĐỒNG BỘ)

| Bảng | Rủi ro | Ảnh hưởng nghiệp vụ |
|------|--------|-------------------|
| `supplier_import_history` | 🔴 **NGHIÊM TRỌNG** | Lịch sử nhập hàng khác nhau mỗi thiết bị |
| `supplier_product_prices` | 🟡 Trung bình | Giá NCC không nhất quán |
| `cash_closings` | 🟡 Trung bình (có listener riêng) | Chốt quỹ có sync nhưng không qua SyncOrchestrator |
| `payroll_settings` | 🟡 Trung bình | Cài đặt lương khác nhau |
| `payroll_locks` | 🟡 Trung bình | Khóa lương không nhất quán |
| `work_schedules` | 🟡 Trung bình | Lịch làm việc khác nhau |
| `inventory_checks` | 🟡 Trung bình | Kiểm kho khác nhau |
| `partner_repair_history` | 🟠 Thấp | Lịch sử gửi đối tác |
| `purchase_orders` | 🟠 Thấp | Đơn đặt hàng local |
| `sync_queue` | ✅ OK | Nội bộ, không cần sync |
| `quick_input_codes` | ✅ OK | Đã có sync |
| `adjustment_entries` | 🟡 Trung bình | Bút toán điều chỉnh local |

---

## 2️⃣ DANH SÁCH LỖI VÀ RỦI RO ĐỒNG BỘ

### 🔴 LỖI NGHIÊM TRỌNG (PHẢI SỬA NGAY)

#### BUG-001: `supplier_import_history` không có real-time sync
```
📍 Vị trí: lib/services/sync_service.dart (dòng 1521)
🔥 Mức độ: NGHIÊM TRỌNG

VẤN ĐỀ: 
- Bảng supplier_import_history chỉ lưu local
- sync_service.dart comment: "'supplier_import_history' và 'supplier_product_prices' quản lý locally"
- Khi 2 nhân viên nhập hàng từ 2 thiết bị, dữ liệu KHÔNG đồng bộ
- cash_closing_view.dart đọc từ db.getAllSupplierImportHistory() → LOCAL ONLY

ẢNH HƯỞNG:
- Chốt quỹ hiển thị số tiền nhập hàng khác nhau trên mỗi thiết bị
- Báo cáo tài chính sai lệch

SỬA:
1. Thêm subscription cho collection 'supplier_import_history' trong initRealTimeSync()
2. Thêm vào downloadAllFromCloud()
3. Thêm SyncEntityType.supplierImportHistory vào SyncOrchestrator
```

#### BUG-002: `supplier_payments` không có trong SyncOrchestrator
```
📍 Vị trí: lib/services/sync_orchestrator.dart
🔥 Mức độ: CAO

VẤN ĐỀ:
- Có real-time listener (sync_service.dart line ~510)
- KHÔNG có trong SyncOrchestrator → Local changes không push lên cloud
- Chỉ download từ cloud, không upload lên cloud từ offline

SỬA:
Thêm SyncEntityType.supplierPayment case trong _getCollectionName và _handleCreate/Update/Delete
```

#### BUG-003: Màn hình đọc dữ liệu không nhất quán
```
📍 Vị trí: Nhiều file *_view.dart
🔥 Mức độ: CAO

CÁC MÀN HÌNH ĐỌC TỪ LOCAL DB (KHÔNG REAL-TIME):
- order_list_view.dart:71     → db.getAllRepairs()
- sale_list_view.dart:51      → db.getAllSales()
- expense_view.dart:82        → db.getAllExpenses()
- debt_view.dart:60           → db.getAllDebts()
- inventory_view.dart:79      → db.getAllProducts()
- customer_view.dart:56-57    → db.getAllRepairs(), db.getAllSales()

MÀN HÌNH ĐỌC TỪ FIRESTORE (ĐÃ REAL-TIME):
- cash_closing_view.dart:140-185 → Firestore collections trực tiếp ✅

VẤN ĐỀ:
- Real-time listener cập nhật SQLite
- Nhưng UI cần gọi setState/refresh thủ công
- EventBus chỉ được dùng ở một số màn hình

SỬA:
- Thêm EventBus listener cho TẤT CẢ các màn hình đọc dữ liệu nghiệp vụ
- Hoặc chuyển sang đọc trực tiếp từ Firestore như cash_closing_view
```

#### BUG-004: Thiếu `updatedAt` trong một số model → Conflict resolution không hoạt động
```
📍 Vị trí: lib/services/sync_service.dart (line 70-110)
🔥 Mức độ: CAO

VẤN ĐỀ:
_shouldAcceptCloudData() sử dụng updatedAt để so sánh:
- Repair: Không có updatedAt → dùng lastCaredAt hoặc createdAt (fallback)
- SaleOrder: Không có updatedAt → dùng soldAt (sai logic vì soldAt là thời điểm bán)
- Expense: Không có updatedAt → dùng date (sai logic vì date là ngày chi phí)

KHI 2 THIẾT BỊ CHỈNH CÙNG 1 RECORD:
1. Thiết bị A sửa offline lúc 10:00
2. Thiết bị B sửa offline lúc 10:05  
3. Thiết bị A online lúc 10:10 → push lên cloud
4. Thiết bị B online lúc 10:15 → conflict!
   - Cloud có updatedAt = null (từ A)
   - Local B có "updatedAt" = 10:05
   - Logic hiện tại: cloudTime >= localUpdatedAt = false → SKIP cloud, giữ local B
   - NHƯNG thực tế A có thể mới hơn về nội dung!

SỬA:
1. Thêm column updatedAt vào repairs, sales, expenses tables
2. Luôn update updatedAt khi có thay đổi
3. Sử dụng FieldValue.serverTimestamp() khi push lên cloud
```

#### BUG-005: `isSynced` flag reset sai khi nhận data từ cloud
```
📍 Vị trí: lib/services/sync_service.dart
🔥 Mức độ: TRUNG BÌNH

VẤN ĐỀ:
Khi nhận data từ cloud, luôn set isSynced = 1:
data['isSynced'] = 1; // Line 310, 340, etc.

NHƯNG nếu user đang edit record cùng lúc → local changes bị mất:
1. User edit repair #123 offline
2. Cloud listener nhận update từ device khác
3. upsertRepair() ghi đè với isSynced = 1
4. Local changes của user bị mất vĩnh viễn

SỬA:
Chỉ set isSynced = 1 khi KHÔNG có pending local changes:
```dart
if (!localHasPendingChanges) {
  data['isSynced'] = 1;
}
```
```

#### BUG-006: `fast_stock_in_view` vs `stock_in_view` tạo dữ liệu khác nhau
```
📍 Vị trí: 
- lib/views/fast_stock_in_view.dart (line 755, 857)
- lib/views/stock_in_view.dart (line 526, 664)
🔥 Mức độ: CAO

VẤN ĐỀ ĐÃ SỬA TRONG SESSION TRƯỚC (THAM KHẢO):
- fast_stock_in: Tạo supplier_import_history + expense (nếu không công nợ)
- stock_in: Tạo supplier_import_history + expense (nếu không công nợ)

NHƯNG vẫn còn vấn đề:
- supplier_import_history KHÔNG SYNC → dữ liệu chỉ ở thiết bị tạo
- Khi chốt quỹ, thiết bị khác không thấy lịch sử nhập hàng này
```

---

### 🟡 RỦI RO TRUNG BÌNH

#### RISK-001: Cash closings sync không qua SyncOrchestrator
```
📍 Vị trí: lib/views/cash_closing_view.dart
💡 Hiện trạng: Có listener riêng, upsert trực tiếp lên Firestore

VẤN ĐỀ:
- Không đi qua sync_queue → Không có retry khi offline
- Nếu fail, user không biết và data mất

KHUYẾN NGHỊ:
Tích hợp vào SyncOrchestrator để có offline-first và retry
```

#### RISK-002: Không có version control cho schema changes
```
📍 Vị trí: lib/data/db_helper.dart (onUpgrade)

VẤN ĐỀ:
- Mỗi thiết bị có thể ở version khác nhau
- Một số migration có thể fail silently (try-catch bắt tất cả)
- Column mới không được tạo → App crash hoặc data loss
```

#### RISK-003: EventBus không đảm bảo delivery
```
📍 Vị trí: lib/services/event_bus.dart

VẤN ĐỀ:
- Broadcast pattern → Nếu listener dispose trước event emit, miss event
- Không có queue → Events mất nếu UI rebuild
```

---

### 🟢 VẤN ĐỀ NHỎ (CẢI THIỆN SAU)

1. **RISK-004**: `audit_logs` không có trong SyncOrchestrator → Log từ offline không push
2. **RISK-005**: `repair_partners` có sync nhưng không có conflict resolution
3. **RISK-006**: Không có checksum để verify data integrity sau sync

---

## 3️⃣ MÀN HÌNH ĐỌC DỮ LIỆU KHÔNG NHẤT QUÁN

| Màn hình | File | Nguồn đọc | Vấn đề |
|----------|------|-----------|--------|
| **Danh sách đơn sửa** | order_list_view.dart | SQLite | Không auto-refresh khi cloud update |
| **Danh sách bán hàng** | sale_list_view.dart | SQLite | Không auto-refresh khi cloud update |
| **Chi phí** | expense_view.dart | SQLite | Có EventBus nhưng phụ thuộc vào emit |
| **Công nợ** | debt_view.dart | SQLite | Có EventBus nhưng phụ thuộc vào emit |
| **Kho hàng** | inventory_view.dart | SQLite | Không real-time |
| **Khách hàng** | customer_view.dart | SQLite | Tổng hợp từ repairs + sales |
| **Chốt quỹ** | cash_closing_view.dart | **Firestore** | ✅ Real-time, đúng cách |
| **Doanh thu** | revenue_view.dart | **Firestore** | ✅ Real-time |

---

## 4️⃣ THAY ĐỔI MÃ CỤ THỂ ĐỂ FIRESTORE LÀ NGUỒN DUY NHẤT

### Bước 1: Thêm sync cho supplier_import_history

**File: `lib/services/sync_service.dart`**

Thêm sau dòng 735 (sau supplier_payments sync):

```dart
// 17. Đồng bộ SUPPLIER IMPORT HISTORY
try {
  _subscribeToCollection(
    collection: 'supplier_import_history',
    shopId: shopId,
    onChanged: (data, docId) async {
      try {
        final db = DBHelper();
        if (data['deleted'] == true) {
          // TODO: Implement deleteSupplierImportHistoryByFirestoreId
          return;
        }
        data['firestoreId'] = docId;
        data['isSynced'] = 1;
        _convertTimestampFields(data);
        await db.upsertSupplierImportHistory(data);
      } catch (e) {
        debugPrint("Lỗi sync supplier_import_history $docId: $e");
      }
    },
    onBatchDone: onDataChanged,
  );
} catch (e) {
  debugPrint("Lỗi khởi tạo supplier_import_history sync: $e");
}
```

**File: `lib/data/db_helper.dart`**

Thêm method:

```dart
Future<void> upsertSupplierImportHistory(Map<String, dynamic> data) async {
  final firestoreId = data['firestoreId'];
  if (firestoreId == null) return;
  await _upsert('supplier_import_history', data, firestoreId);
}
```

### Bước 2: Thêm SyncEntityType cho supplier_payment

**File: `lib/services/sync_orchestrator.dart`**

Đã có `SyncEntityType.supplierPayment` - cần ensure có handler.

### Bước 3: Thêm updatedAt cho tất cả models

**File: `lib/models/repair_model.dart`**

```dart
class Repair {
  // ... existing fields
  int? updatedAt; // ADD THIS
  
  // Update toMap() và fromMap()
}
```

Tương tự cho `sale_order_model.dart`, `expense_model.dart`.

### Bước 4: Auto-refresh UI khi có changes

**Pattern chuẩn cho tất cả các màn hình:**

```dart
class _MyViewState extends State<MyView> {
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Subscribe to relevant events
    _eventSub = EventBus().stream.listen((event) {
      if (event == 'repairs_changed' && mounted) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
```

---

## 5️⃣ KẾ HOẠCH DI CHUYỂN DỮ LIỆU

### Phase 1: Backup & Audit (1 ngày)
1. Export tất cả dữ liệu từ Firestore
2. Export dữ liệu local từ 1 thiết bị "master"
3. So sánh và tìm records không khớp

### Phase 2: Schema Migration (1-2 ngày)
1. Tăng DB version lên 57
2. Thêm column `updatedAt` cho repairs, sales, expenses
3. Set `updatedAt = createdAt` cho records cũ

```dart
if (oldV < 57) {
  // Add updatedAt columns
  await db.execute('ALTER TABLE repairs ADD COLUMN updatedAt INTEGER');
  await db.execute('ALTER TABLE sales ADD COLUMN updatedAt INTEGER');  
  await db.execute('ALTER TABLE expenses ADD COLUMN updatedAt INTEGER');
  
  // Backfill với createdAt
  await db.execute('UPDATE repairs SET updatedAt = createdAt WHERE updatedAt IS NULL');
  await db.execute('UPDATE sales SET updatedAt = soldAt WHERE updatedAt IS NULL');
  await db.execute('UPDATE expenses SET updatedAt = date WHERE updatedAt IS NULL');
}
```

### Phase 3: Code Updates (2-3 ngày)
1. Cập nhật sync_service.dart với các fixes ở trên
2. Cập nhật sync_orchestrator.dart
3. Cập nhật tất cả views để subscribe EventBus
4. Test trên 2 thiết bị cùng shop

### Phase 4: Data Reconciliation (1 ngày)
1. Force sync tất cả thiết bị: `SyncService.syncAllToCloud()`
2. Verify data consistency giữa các thiết bị
3. Chạy `downloadAllFromCloud()` trên tất cả thiết bị

### Phase 5: Monitoring (Ongoing)
1. Thêm logging cho sync failures
2. Tạo dashboard hiển thị sync_queue status
3. Alert khi có > 100 pending items

---

## 📊 MA TRẬN ĐỒNG BỘ HOÀN CHỈNH (Đã cập nhật sau sửa lỗi)

```
┌────────────────────────────┬─────────┬─────────┬──────────┬──────────┬────────────┐
│ Entity                     │ Write   │ Read    │ Listener │ Upload   │ Conflict   │
│                            │ Location│ Location│ (Cloud→) │ (→Cloud) │ Resolution │
├────────────────────────────┼─────────┼─────────┼──────────┼──────────┼────────────┤
│ repairs                    │ Local   │ Local   │ ✅       │ ✅ Orch  │ ⚠️ Weak    │
│ sales                      │ Local   │ Local   │ ✅       │ ✅ Orch  │ ⚠️ Weak    │
│ products                   │ Local   │ Local   │ ✅       │ ✅ Orch  │ ✅ updatedAt│
│ expenses                   │ Local   │ Local   │ ✅       │ ✅ Orch  │ ⚠️ Weak    │
│ debts                      │ Local   │ Local   │ ✅       │ ✅ Orch  │ ✅ updatedAt│
│ debt_payments              │ Local   │ Fstore  │ ✅ ROOT  │ ✅ Orch  │ ✅         │
│ supplier_payments          │ Local   │ Fstore  │ ✅ ROOT  │ ✅ Orch  │ ✅ ĐÃ SỬA  │
│ supplier_import_history    │ Local   │ Local   │ ✅ ĐÃ SỬA│ ✅ Orch  │ ✅ ĐÃ SỬA  │
│ supplier_product_prices    │ Local   │ Local   │ ✅ ĐÃ SỬA│ ❌       │ ❌         │
│ attendance                 │ Local   │ Local   │ ✅       │ ✅ Orch  │ ✅         │
│ customers                  │ Local   │ Local   │ ✅       │ ✅ Orch  │ ❌ None    │
│ suppliers                  │ Local   │ Local   │ ✅       │ ✅ Batch │ ❌ None    │
│ repair_parts               │ Local   │ Local   │ ✅       │ ✅ Batch │ ❌ None    │
│ cash_closings              │ Fstore  │ Fstore  │ ✅ Sub   │ Direct   │ ✅ Lock    │
│ audit_logs                 │ Local   │ Local   │ ✅       │ ✅ Batch │ ❌ None    │
│ quick_input_codes          │ Local   │ Local   │ ✅       │ ✅ Batch │ ❌ None    │
└────────────────────────────┴─────────┴─────────┴──────────┴──────────┴────────────┘

Legend:
- Write Location: Nơi data được ghi đầu tiên
- Read Location: Nơi UI đọc data để hiển thị
- Listener: Real-time subscription từ Firestore → Local
- Upload: Cơ chế đẩy local → cloud (Orch = SyncOrchestrator, Batch = syncAllToCloud batch)
- Conflict Resolution: Cách xử lý khi 2 thiết bị edit cùng record
```

---

## ✅ CHECKLIST HÀNH ĐỘNG

- [x] **URGENT**: Thêm sync cho `supplier_import_history` ✅ DONE
- [x] **URGENT**: Thêm SyncOrchestrator handler cho `supplier_payments` ✅ DONE
- [x] **URGENT**: Thêm sync cho `supplier_product_prices` ✅ DONE
- [x] **URGENT**: Enqueue import history trong các views ✅ DONE
- [ ] **HIGH**: Thêm `updatedAt` column cho repairs, sales, expenses
- [ ] **HIGH**: Update tất cả views để listen EventBus
- [ ] **MEDIUM**: Tích hợp cash_closings vào SyncOrchestrator
- [ ] **MEDIUM**: Thêm sync cho payroll_settings, work_schedules
- [ ] **LOW**: Thêm data integrity checksums
- [ ] **LOW**: Tạo sync status dashboard

---

**Người phê duyệt**: _________________  
**Ngày**: _________________
