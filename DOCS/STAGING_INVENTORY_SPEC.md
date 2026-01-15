# PHƯƠNG ÁN HYBRID: KHO TẠM TÙY CHỌN

> Phiên bản: 1.0 | Ngày: 2026-01-15  
> Áp dụng: **Điện thoại + Phụ kiện + Linh kiện**

---

## 1. MỤC TIÊU THIẾT KẾ

### 1.1. Vấn đề cần giải quyết
- Hàng về nhưng CHƯA đủ thông tin kế toán (giá vốn, thanh toán)
- Cần ghi nhận hàng vật lý mà KHÔNG ảnh hưởng số liệu chính
- Shop nhỏ cần linh hoạt - không bắt buộc quy trình phức tạp

### 1.2. Giải pháp HYBRID

```
┌─────────────────────────────────────────────────────────┐
│                    NHẬP KHO MỚI                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   Đủ thông tin?                                        │
│        │                                               │
│   ┌────┴────┐                                          │
│   │         │                                          │
│   ▼         ▼                                          │
│  CÓ        KHÔNG                                       │
│   │         │                                          │
│   ▼         ▼                                          │
│ ┌─────┐   ┌─────────┐                                  │
│ │NHẬP │   │NHẬP TẠM │                                  │
│ │NHANH│   │(DRAFT)  │                                  │
│ └──┬──┘   └────┬────┘                                  │
│    │           │                                       │
│    │           ▼                                       │
│    │    Bổ sung thông tin                             │
│    │           │                                       │
│    │           ▼                                       │
│    │    ┌──────────────┐                              │
│    │    │XÁC NHẬN NHẬP │                              │
│    │    │KHO (ATOMIC)  │                              │
│    │    └──────┬───────┘                              │
│    │           │                                       │
│    ▼           ▼                                       │
│   ┌─────────────────────┐                              │
│   │     KHO CHÍNH       │                              │
│   │  (Có số liệu KT)    │                              │
│   └─────────────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

---

## 2. NGUYÊN TẮC CỐT LÕI (BẮT BUỘC)

| # | Nguyên tắc | Vi phạm = |
|---|------------|-----------|
| 1 | Kho tạm KHÔNG phải kho kế toán | ❌ Logic sai |
| 2 | Kho tạm KHÔNG sinh con số tài chính | ❌ Logic sai |
| 3 | Chỉ khi "XÁC NHẬN" mới sinh số | ❌ Logic sai |
| 4 | Không sửa lịch sử sau xác nhận | ❌ Logic sai |
| 5 | Không xóa dữ liệu kế toán | ❌ Logic sai |
| 6 | **IMEI được phép trùng** (không check unique) | ✅ Cho phép |

---

## 3. CẤU TRÚC DỮ LIỆU

### 3.1. Collection: `stock_entries` (Phiếu nhập kho)

```dart
{
  // === ĐỊNH DANH ===
  "id": "SE-20260115-001",
  "shopId": "shop_xxx",
  
  // === TRẠNG THÁI ===
  "status": "DRAFT" | "CONFIRMED" | "CANCELLED",
  "entryType": "QUICK" | "STAGING",  // Nhập nhanh | Nhập tạm
  "productType": "DIEN_THOAI" | "PHU_KIEN" | "LINH_KIEN",
  
  // === THÔNG TIN SẢN PHẨM ===
  "items": [{
    // Bắt buộc (tất cả loại)
    "name": "IPHONE 15 PRO MAX",
    "quantity": 1,
    
    // Chỉ ĐIỆN THOẠI (ẩn với phụ kiện/linh kiện)
    "imei": "123456789012345",      // Có thể trùng - KHÔNG CHECK
    "brand": "IPHONE",
    "model": "15 PRO MAX",
    "capacity": "256GB",
    "color": "ĐEN",
    "condition": "MỚI",
    
    // Chỉ PHỤ KIỆN / LINH KIỆN (ẩn với điện thoại)
    "sku": "PK-CAP-001",
    "unit": "Cái",
  }],
  
  // === THÔNG TIN KẾ TOÁN (bắt buộc khi CONFIRM) ===
  "supplierId": "supplier_xxx",
  "supplierName": "KHO HÀ NỘI",
  "totalCost": 25000000,            // Tổng giá vốn
  "paymentMethod": "CÔNG NỢ" | "TIỀN MẶT" | "CHUYỂN KHOẢN",
  
  // === METADATA ===
  "notes": "Ghi chú...",
  "createdAt": Timestamp,
  "createdBy": "user_xxx",
  "confirmedAt": Timestamp | null,
  "confirmedBy": "user_xxx" | null,
  "locked": true | false,
}
```

### 3.2. Ảnh hưởng theo trạng thái

| Trạng thái | Tồn kho | Giá vốn | Công nợ | Thu/Chi | Báo cáo | Bán được |
|------------|---------|---------|---------|---------|---------|----------|
| DRAFT      | ❌      | ❌      | ❌      | ❌      | ❌      | ❌       |
| CONFIRMED  | ✅      | ✅      | ✅      | ✅      | ✅      | ✅       |
| CANCELLED  | ❌      | ❌      | ❌      | ❌      | ❌      | ❌       |

---

## 4. UI LINH HOẠT THEO LOẠI SẢN PHẨM

### 4.1. Quy tắc ẩn/hiện field

```dart
/// Điều kiện hiển thị field theo loại sản phẩm
Map<String, bool> getFieldVisibility(String productType) {
  final isPhone = productType == 'DIEN_THOAI';
  final isAccessory = productType == 'PHU_KIEN' || productType == 'LINH_KIEN';
  
  return {
    // === CHỈ ĐIỆN THOẠI ===
    'imei':      isPhone,
    'brand':     isPhone,
    'model':     isPhone,
    'capacity':  isPhone,
    'color':     isPhone,
    'condition': isPhone,
    
    // === CHỈ PHỤ KIỆN / LINH KIỆN ===
    'sku':       isAccessory,
    'unit':      isAccessory,
    
    // === CHUNG (luôn hiện) ===
    'name':      true,
    'quantity':  true,
    
    // === KẾ TOÁN (ẩn khi DRAFT, hiện khi bổ sung/xác nhận) ===
    'cost':      true,  // Hiện nhưng KHÔNG bắt buộc khi lưu tạm
    'supplier':  true,
    'payment':   true,
  };
}
```

### 4.2. Mockup UI - Form nhập kho thông minh

```
┌─────────────────────────────────────────────────────────┐
│  ◀ NHẬP KHO MỚI                                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Loại sản phẩm                                  │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐          │   │
│  │  │📱 ĐT   │ │🎧 PK   │ │🔧 LK   │          │   │
│  │  │ (chọn) │ │         │ │         │          │   │
│  │  └─────────┘ └─────────┘ └─────────┘          │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ═══════════════════════════════════════════════════   │
│                                                         │
│  ┌─── KHI CHỌN: ĐIỆN THOẠI ─────────────────────────┐  │
│  │                                                   │  │
│  │  Tên máy *     [IPHONE 15 PRO MAX         ]      │  │
│  │  IMEI          [123456789012345       ][📷]      │  │
│  │  Hãng          [▼ IPHONE                  ]      │  │
│  │  Model         [15 PRO MAX                ]      │  │
│  │  Dung lượng    [▼ 256GB                   ]      │  │
│  │  Màu sắc       [▼ ĐEN                     ]      │  │
│  │  Tình trạng    [▼ MỚI                     ]      │  │
│  │  Số lượng      [1        ] (mặc định 1)          │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─── KHI CHỌN: PHỤ KIỆN ───────────────────────────┐  │
│  │                                                   │  │
│  │  Tên sản phẩm * [Cáp sạc Lightning        ]      │  │
│  │  Mã SKU         [PK-CAP-001               ]      │  │
│  │  Đơn vị         [▼ Cái                    ]      │  │
│  │  Số lượng       [10                       ]      │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─── THÔNG TIN KẾ TOÁN ────────────────────────────┐  │
│  │                                                   │  │
│  │  💰 Giá vốn       [____________] VNĐ             │  │
│  │  🏢 Nhà cung cấp  [▼ Chọn NCC         ][+]       │  │
│  │  💳 Thanh toán    ○ Tiền mặt ○ CK ○ Công nợ     │  │
│  │                                                   │  │
│  │  ⓘ Để trống nếu chưa biết, bổ sung sau          │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────┐  ┌────────────────────────┐      │
│  │    💾 LƯU TẠM    │  │  ✅ LƯU & XÁC NHẬN    │      │
│  │    (Chờ duyệt)   │  │  (Nhập kho ngay)       │      │
│  └──────────────────┘  └────────────────────────┘      │
│                         ↑                              │
│              Chỉ bật khi đủ: Giá + NCC + Thanh toán    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 4.3. Mockup UI - Danh sách hàng chờ xác nhận

```
┌─────────────────────────────────────────────────────────┐
│  ◀ HÀNG CHỜ XÁC NHẬN                         [5] 🔴    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  🔍 Tìm kiếm...                                        │
│                                                         │
│  [Tất cả ▼] [Điện thoại] [Phụ kiện] [Linh kiện]       │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 📱 IPHONE 15 PRO MAX 256GB ĐEN                    │ │
│  │    IMEI: 123456789012345                          │ │
│  │    SL: 1 │ Tạo: 3 ngày trước                      │ │
│  │    ⚠️ Thiếu: Giá vốn, NCC, Thanh toán            │ │
│  │                          [✏️ Sửa] [✓] [✗]        │ │
│  └───────────────────────────────────────────────────┘ │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 🎧 Cáp sạc Lightning                              │ │
│  │    SKU: PK-CAP-001 │ ĐVT: Cái                     │ │
│  │    SL: 10 │ Tạo: 1 ngày trước                     │ │
│  │    ✅ Đủ thông tin - sẵn sàng xác nhận           │ │
│  │                          [✏️ Sửa] [✓] [✗]        │ │
│  └───────────────────────────────────────────────────┘ │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │ 🔧 Màn hình iPhone 15                             │ │
│  │    SKU: LK-MH-IP15 │ ĐVT: Cái                     │ │
│  │    SL: 5 │ Tạo: Hôm nay                           │ │
│  │    ⚠️ Thiếu: Thanh toán                          │ │
│  │                          [✏️ Sửa] [✓] [✗]        │ │
│  └───────────────────────────────────────────────────┘ │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  [✓ Xác nhận tất cả đủ điều kiện (1)]                  │
└─────────────────────────────────────────────────────────┘
```

---

## 5. LUỒNG NGHIỆP VỤ CHI TIẾT

### 5.1. Nhập nhanh (Đủ thông tin)

```
User nhập đầy đủ → Bấm "LƯU & XÁC NHẬN"
                         │
                         ▼
              ┌──────────────────────┐
              │   ATOMIC TRANSACTION │
              ├──────────────────────┤
              │ 1. Tạo stock_entry   │
              │    status=CONFIRMED  │
              │ 2. Tạo product(s)    │
              │ 3. Ghi financial_log │
              │ 4. Cập nhật công nợ  │
              │    (nếu ghi nợ NCC)  │
              └──────────────────────┘
                         │
                         ▼
                    ✅ Hoàn tất
```

### 5.2. Nhập tạm (Chưa đủ)

```
User nhập cơ bản → Bấm "LƯU TẠM"
                         │
                         ▼
              ┌──────────────────────┐
              │ Tạo stock_entry      │
              │ status = DRAFT       │
              │ locked = false       │
              └──────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
   Để đó (chờ)                    Vào "Hàng chờ"
                                         │
                                         ▼
                                  Bổ sung thông tin
                                         │
                                         ▼
                              Bấm "XÁC NHẬN NHẬP KHO"
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │   ATOMIC TRANSACTION │
                              │   (giống nhập nhanh) │
                              └──────────────────────┘
```

---

## 6. XỬ LÝ SAI SÓT

### 6.1. Khi còn DRAFT

| Hành động | Được phép | Cách làm |
|-----------|-----------|----------|
| Sửa thông tin | ✅ | Sửa trực tiếp |
| Xóa phiếu | ✅ | status = CANCELLED |
| Thay đổi loại SP | ✅ | Chọn lại từ đầu |

### 6.2. Sau khi CONFIRMED

| Hành động | Được phép | Cách làm |
|-----------|-----------|----------|
| Sửa thông tin | ❌ | Không cho sửa |
| Xóa phiếu | ❌ | Không cho xóa |
| Sửa sai giá vốn | ❌ | Tạo phiếu điều chỉnh |
| Nhập nhầm hàng | ❌ | Tạo phiếu trả NCC |

---

## 7. PHÂN QUYỀN

| Vai trò | Tạo Draft | Sửa Draft | Xác nhận | Điều chỉnh | Xem tất cả |
|---------|-----------|-----------|----------|------------|------------|
| Nhân viên | ✅ | ✅ (của mình) | ❌ | ❌ | ❌ |
| Admin | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 8. DASHBOARD CẢNH BÁO

### 8.1. Widget hiển thị trên trang chủ

```dart
Widget _buildPendingStockAlert() {
  return Card(
    color: pendingCount > 0 ? Colors.orange.shade50 : Colors.grey.shade100,
    child: ListTile(
      leading: Badge(
        label: Text('$pendingCount'),
        isLabelVisible: pendingCount > 0,
        backgroundColor: Colors.red,
        child: Icon(Icons.inventory_2, size: 32),
      ),
      title: Text('Hàng chờ xác nhận'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pendingCount > 0) ...[
            Text('Có $pendingCount sản phẩm chờ nhập kho'),
            if (oldestDays > 3)
              Text('⚠️ Lâu nhất: $oldestDays ngày', 
                style: TextStyle(color: Colors.red)),
          ] else
            Text('Không có hàng chờ'),
        ],
      ),
      trailing: Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, 
        MaterialPageRoute(builder: (_) => PendingStockView())),
    ),
  );
}
```

### 8.2. Thống kê nhanh

```
┌─────────────────────────────────────────────────────────┐
│  📊 HÀNG CHỜ THEO LOẠI                                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  📱 Điện thoại:  2 sản phẩm   │  Giá trị: ~50,000,000đ │
│  🎧 Phụ kiện:    8 sản phẩm   │  Giá trị: chưa có      │
│  🔧 Linh kiện:   3 sản phẩm   │  Giá trị: ~5,000,000đ  │
│  ─────────────────────────────────────────────────────  │
│  TỔNG:          13 sản phẩm                            │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 9. ATOMIC TRANSACTION KHI XÁC NHẬN

```dart
/// Xác nhận nhập kho - PHẢI atomic
Future<bool> confirmStockEntry(String entryId) async {
  final firestore = FirebaseFirestore.instance;
  
  return firestore.runTransaction((transaction) async {
    // 1. Lấy phiếu nhập
    final entryRef = firestore.collection('stock_entries').doc(entryId);
    final entryDoc = await transaction.get(entryRef);
    final entry = entryDoc.data()!;
    
    if (entry['status'] != 'DRAFT') {
      throw Exception('Phiếu đã được xử lý');
    }
    
    // 2. Validate đủ thông tin
    if (entry['totalCost'] == null || entry['totalCost'] <= 0) {
      throw Exception('Chưa có giá vốn');
    }
    if (entry['supplierId'] == null) {
      throw Exception('Chưa chọn nhà cung cấp');
    }
    if (entry['paymentMethod'] == null) {
      throw Exception('Chưa chọn phương thức thanh toán');
    }
    
    // 3. Tạo products từ items
    final items = entry['items'] as List;
    for (final item in items) {
      final productRef = firestore.collection('products').doc();
      transaction.set(productRef, {
        ...item,
        'stockEntryId': entryId,
        'status': 1, // Trong kho
        'shopId': entry['shopId'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    
    // 4. Ghi financial_activity
    final activityRef = firestore.collection('financial_activities').doc();
    transaction.set(activityRef, {
      'type': 'STOCK_IN',
      'amount': entry['totalCost'],
      'direction': 'OUT', // Chi tiền mua hàng
      'referenceId': entryId,
      'description': 'Nhập kho: ${items.length} sản phẩm',
      'paymentMethod': entry['paymentMethod'],
      'shopId': entry['shopId'],
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    // 5. Cập nhật công nợ NCC (nếu ghi nợ)
    if (entry['paymentMethod'] == 'CÔNG NỢ') {
      final debtRef = firestore.collection('supplier_debts').doc();
      transaction.set(debtRef, {
        'supplierId': entry['supplierId'],
        'amount': entry['totalCost'],
        'type': 'STOCK_IN',
        'referenceId': entryId,
        'status': 'PENDING',
        'shopId': entry['shopId'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    
    // 6. Cập nhật trạng thái phiếu
    transaction.update(entryRef, {
      'status': 'CONFIRMED',
      'locked': true,
      'confirmedAt': FieldValue.serverTimestamp(),
      'confirmedBy': FirebaseAuth.instance.currentUser?.uid,
    });
    
    return true;
  });
}
```

---

## 10. QUY TẮC VÀNG CHO DEV

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   "Kho tạm là vùng đệm nghiệp vụ,                      │
│    không phải kho kế toán.                             │
│                                                         │
│    Chỉ khi XÁC NHẬN NHẬP KHO                          │
│    thì dữ liệu mới trở thành SỰ THẬT KẾ TOÁN."        │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   ✅ Có dữ liệu ≠ Có giao dịch kế toán                │
│   ✅ DRAFT = Vô hình với mọi báo cáo                  │
│   ✅ CONFIRMED = Khóa sổ, không thay đổi              │
│   ✅ Sai thì THÊM giao dịch mới, KHÔNG sửa cũ         │
│   ✅ IMEI cho phép trùng - KHÔNG check unique         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 11. CHECKLIST TRIỂN KHAI

### Phase 1: Backend
- [ ] Tạo collection `stock_entries` trên Firestore
- [ ] Tạo model `StockEntry` trong Dart
- [ ] Tạo `StockEntryService` với các method CRUD
- [ ] Implement atomic transaction cho confirm
- [ ] Cập nhật Firestore Rules

### Phase 2: UI
- [ ] Tạo form nhập kho mới (linh hoạt theo loại SP)
- [ ] Tạo UI danh sách hàng chờ xác nhận
- [ ] Thêm widget cảnh báo trên Dashboard
- [ ] Form chỉnh sửa phiếu DRAFT

### Phase 3: Integration
- [ ] Tích hợp với financial_activity_log
- [ ] Tích hợp với supplier_debts
- [ ] Cập nhật sync offline
- [ ] Test đầy đủ các luồng

---

## 12. SO SÁNH PHƯƠNG ÁN

| Tiêu chí | Bắt buộc Kho Tạm | HYBRID (Đề xuất) |
|----------|------------------|------------------|
| Độ phức tạp | Cao | Trung bình |
| Linh hoạt | Thấp | Cao |
| Phù hợp shop nhỏ | ❌ | ✅ |
| Đúng chuẩn kế toán | ✅ | ✅ |
| Breaking change | Lớn | Nhỏ |
| Thời gian triển khai | Lâu | Nhanh hơn |

**→ HYBRID là lựa chọn tối ưu cho app hiện tại.**
