# Hướng dẫn Hệ thống Đồng bộ Dữ liệu (Sync System)

## Tổng quan

Hệ thống sync mới được thiết kế theo kiến trúc **Offline-First** với các nguyên tắc:

1. **Local là Primary** - Dữ liệu được lưu local trước, app hoạt động bình thường khi offline
2. **Cloud là Backup** - Cloud là nơi backup và sync giữa các thiết bị  
3. **User Control** - User có thể chọn khi nào đồng bộ (nút sync trên AppBar)
4. **Visual Indicator** - Hiển thị số lượng thay đổi chưa sync

## Các thành phần

### 1. `sync_queue` table (SQLite)

Bảng lưu trữ các thay đổi chờ sync lên cloud:

```sql
CREATE TABLE sync_queue(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entityType TEXT NOT NULL,      -- loại entity: repair, sale, product, etc.
  entityId INTEGER NOT NULL,     -- ID trong bảng local
  firestoreId TEXT,              -- ID trên Firestore (null nếu chưa tạo)
  operation TEXT NOT NULL,       -- create, update, delete
  data TEXT,                     -- JSON data (optional)
  createdAt INTEGER NOT NULL,    -- timestamp
  retryCount INTEGER DEFAULT 0,  -- số lần thử lại
  lastError TEXT,                -- lỗi cuối cùng
  status TEXT DEFAULT 'pending'  -- pending, processing, completed, failed
)
```

### 2. `SyncOrchestrator` service

Service quản lý sync queue:

```dart
// Import
import 'package:quanlyshop/services/sync_orchestrator.dart';

// Lấy instance (singleton)
final orchestrator = SyncOrchestrator();

// Enqueue một thay đổi
await orchestrator.enqueue(
  entityType: SyncEntityType.repair,
  entityId: repairId,
  firestoreId: repair.firestoreId,
  operation: SyncOperation.update,
);

// Hoặc dùng convenience methods
await orchestrator.enqueueRepair(repairId, firestoreId: repair.firestoreId);
await orchestrator.enqueueSale(saleId, operation: SyncOperation.create);
await orchestrator.enqueueDebt(debtId, operation: SyncOperation.delete);

// Sync tất cả pending items
final result = await orchestrator.syncAll();
print('Success: ${result.success}, Failed: ${result.failed}');

// Lấy pending count
int count = await orchestrator.getPendingCount();

// Stream để listen changes
orchestrator.pendingCountStream.listen((count) {
  print('Pending: $count');
});

// Retry failed items
await orchestrator.retryFailedItems();

// Clear failed items
await orchestrator.clearFailedItems();
```

### 3. `PendingSyncIndicator` widget

Widget hiển thị trạng thái sync:

```dart
// Trong AppBar actions
const PendingSyncIndicator(iconSize: 22)

// Với text
const PendingSyncIndicator(showText: true)

// Custom tap handler
PendingSyncIndicator(
  onTap: () => showMyCustomDialog(),
)
```

### 4. Tự động sync

Orchestrator tự động sync khi:
- Network được kết nối lại (auto-detect via connectivity_plus)
- User tap vào indicator để mở dialog và bấm "Đồng bộ ngay"

## Cách tích hợp vào code hiện tại

### Khi tạo/sửa/xóa entity

```dart
import 'package:quanlyshop/services/sync_orchestrator.dart';

// Sau khi save vào local DB
final id = await DBHelper().insertRepair(repair);
if (id > 0) {
  // Enqueue để sync lên cloud sau
  await SyncOrchestrator().enqueueRepair(
    id, 
    operation: SyncOperation.create,
  );
}

// Sau khi update
await DBHelper().updateRepair(repair);
await SyncOrchestrator().enqueueRepair(
  repair.id!,
  firestoreId: repair.firestoreId,
  operation: SyncOperation.update,
);

// Sau khi delete (soft delete)
await DBHelper().deleteRepair(repairId);
await SyncOrchestrator().enqueueRepair(
  repairId,
  firestoreId: repair.firestoreId,
  operation: SyncOperation.delete,
);
```

## Entity Types hỗ trợ

| EntityType | Collection | Table |
|------------|------------|-------|
| repair | repairs | repairs |
| sale | sales | sales |
| product | products | products |
| expense | expenses | expenses |
| debt | debts | debts |
| customer | customers | customers |
| supplier | suppliers | suppliers |
| attendance | attendance | attendance |
| repairPart | repair_parts | repair_parts |
| quickInputCode | quick_input_codes | quick_input_codes |
| debtPayment | debt_payments | debt_payments |
| supplierPayment | supplier_payments | supplier_payments |
| partnerPayment | repair_partner_payments | repair_partner_payments |
| repairPartner | repair_partners | repair_partners |
| auditLog | audit_logs | audit_logs |
| cashClosing | cash_closings | cash_closings |
| adjustmentEntry | adjustment_entries | adjustment_entries |

## Flow hoạt động

```
[User thao tác] 
    ↓
[Save vào Local DB] 
    ↓
[Enqueue vào sync_queue với status='pending']
    ↓
[PendingSyncIndicator hiển thị badge số lượng]
    ↓
[User tap indicator hoặc network restored]
    ↓
[SyncOrchestrator.syncAll() được gọi]
    ↓
[Với mỗi item trong queue:]
    ├── Create: POST lên Firestore, lấy docId, update local
    ├── Update: PUT lên Firestore với docId
    └── Delete: PATCH set deleted=true trên Firestore
    ↓
[Nếu thành công: xóa khỏi queue, mark local isSynced=1]
[Nếu thất bại: tăng retryCount, nếu >3 thì mark failed]
    ↓
[Refresh pending count và notify UI]
```

## Lưu ý quan trọng

1. **Offline mode**: App hoạt động bình thường khi offline, tất cả thay đổi được queue
2. **Conflict resolution**: Last-write-wins (dùng updatedAt timestamp)
3. **Data integrity**: Firestore rules vẫn enforce shopId và security
4. **Max retries**: 3 lần thử trước khi mark là failed
5. **Manual retry**: User có thể retry failed items trong dialog

## Migration Notes

- DB version 50 thêm bảng `sync_queue`
- `SyncOrchestrator.init()` được gọi trong AuthGate
- Các file hiện tại vẫn dùng `SyncService` để download từ cloud
- Hệ thống mới chỉ quản lý upload (local -> cloud)
