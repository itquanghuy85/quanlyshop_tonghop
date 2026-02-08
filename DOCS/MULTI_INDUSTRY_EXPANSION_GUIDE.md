# 📋 HƯỚNG DẪN MỞ RỘNG APP ĐA NGÀNH

> **Mục đích**: Tài liệu chi tiết cho việc mở rộng app từ "Shop Điện Thoại" sang "Shop Đa Ngành".
> Đọc file này trước khi thực hiện bất kỳ thay đổi nào liên quan đến việc mở rộng.

---

## 📑 MỤC LỤC

1. [Tổng Quan Dự Án Hiện Tại](#1-tổng-quan-dự-án-hiện-tại)
2. [Mục Tiêu Mở Rộng](#2-mục-tiêu-mở-rộng)
3. [Kiến Trúc Mới](#3-kiến-trúc-mới)
4. [Các Ngành Kinh Doanh Hỗ Trợ](#4-các-ngành-kinh-doanh-hỗ-trợ)
5. [Schema Database](#5-schema-database)
6. [Flow Người Dùng](#6-flow-người-dùng)
7. [Giai Đoạn Triển Khai](#7-giai-đoạn-triển-khai)
8. [Quy Tắc Phát Triển](#8-quy-tắc-phát-triển)
9. [Checklist Trước Khi Code](#9-checklist-trước-khi-code)
10. [Files Quan Trọng](#10-files-quan-trọng)

---

## 1. TỔNG QUAN DỰ ÁN HIỆN TẠI

### 1.1 Công nghệ
```
┌─────────────────────────────────────────────────────────────┐
│ Frontend: Flutter (Dart)                                    │
│ Backend: Firebase (Auth, Firestore, Storage, Functions)     │
│ Local DB: SQLite (sqflite) - offline-first với real-time sync│
│ State: StatefulWidget + EventBus                            │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Chức năng hiện tại (Phone Repair Shop)
| Module | Mô tả | Files chính |
|--------|-------|-------------|
| Bán hàng | Bán điện thoại, phụ kiện | `create_sale_view.dart`, `sale_order_model.dart` |
| Sửa chữa | Nhận máy → Sửa → Bàn giao | `repair_detail_view.dart`, `repair_model.dart` |
| Kho | Nhập/xuất, quản lý tồn | `product_model.dart`, `stock_entry_model.dart` |
| Công nợ | KH nợ shop, shop nợ NCC | `debt_model.dart`, `supplier_debt_model.dart` |
| Tài chính | Quỹ, báo cáo, chốt sổ | `financial_report_view.dart`, `payment_intent_model.dart` |
| Nhân sự | Lương, chấm công, hoa hồng | `salary_calculation_service.dart` |
| Multi-shop | 1 owner nhiều cửa hàng | `current_shop_service.dart` |

### 1.3 Cấu trúc Product hiện tại
```dart
// lib/models/product_model.dart
class Product {
  String type;        // Cố định: 'DIEN_THOAI', 'PHU_KIEN', 'LINH_KIEN'
  String? imei;       // Số IMEI (điện thoại)
  String? capacity;   // Dung lượng: 64GB, 128GB...
  String? model;      // Model máy: iPhone 15, Galaxy S24...
  String? warranty;   // Thời gian bảo hành
  // ... các field khác
}
```

**⚠️ HẠN CHẾ:**
- `type` hardcoded 3 giá trị → Không thêm ngành mới được
- Thuộc tính `imei`, `capacity` chỉ phù hợp điện thoại
- Không có quản lý hạn sử dụng (thực phẩm)
- Không có biến thể size/màu (thời trang)

---

## 2. MỤC TIÊU MỞ RỘNG

### 2.1 Từ "Phone Shop" → "Multi-Industry Shop"
```
              HIỆN TẠI                          SAU MỞ RỘNG
         ┌─────────────┐                   ┌─────────────────┐
         │   📱 ĐIỆN   │                   │    🏪 SHOP      │
         │   THOẠI     │                   │    ĐA NGÀNH     │
         └─────────────┘                   └────────┬────────┘
                │                                   │
                │                    ┌──────────────┼──────────────┐
                │                    │              │              │
                ▼                    ▼              ▼              ▼
         ┌───────────┐        ┌───────────┐ ┌───────────┐ ┌───────────┐
         │ 3 loại    │        │ 📱 ĐIỆN TỬ│ │🍎THỰC PHẨM│ │👕THỜI TRANG
         │ cố định   │        │  (như cũ) │ │  (mới)    │ │  (mới)    │
         └───────────┘        └───────────┘ └───────────┘ └───────────┘
```

### 2.2 Nguyên tắc vàng
```
┌─────────────────────────────────────────────────────────────────┐
│ ✅ BACKWARD COMPATIBLE: Shops hiện tại KHÔNG bị ảnh hưởng       │
│ ✅ MODULAR: Tính năng theo ngành, bật/tắt linh hoạt             │
│ ✅ EXTENSIBLE: Dễ thêm ngành mới trong tương lai                │
│ ✅ DATA SAFE: Migration không mất dữ liệu cũ                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. KIẾN TRÚC MỚI

### 3.1 Module hóa theo ngành
```
┌─────────────────────────────────────────────────────────────────┐
│                        SHOP CORE                                 │
│  (Auth, Multi-shop, Payment, Reporting, Sync, HR)               │
│  ✓ Không thay đổi logic tài chính                               │
│  ✓ PaymentIntentService giữ nguyên                              │
└─────────────────────────────────────────────────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  📱 MODULE      │   │  🍎 MODULE      │   │  👕 MODULE      │
│  ĐIỆN TỬ        │   │  THỰC PHẨM      │   │  THỜI TRANG     │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ • IMEI tracking │   │ • Hạn sử dụng   │   │ • Size/màu      │
│ • Sửa chữa      │   │ • Quản lý lô    │   │ • Biến thể      │
│ • Bảo hành      │   │ • Đơn vị (kg)   │   │ • SKU variants  │
│ • Dung lượng    │   │ • Cảnh báo HSD  │   │ • Tồn kho matrix│
└─────────────────┘   └─────────────────┘   └─────────────────┘
         │                     │                     │
         └─────────────────────┴─────────────────────┘
                               │
                     ┌─────────▼─────────┐
                     │  DANH MỤC ĐỘNG    │
                     │  (categories)     │
                     │  Chủ shop tự tạo  │
                     └───────────────────┘
```

### 3.2 Cấu trúc mới
```
lib/
├── models/
│   ├── product_model.dart           # Mở rộng với categoryId, customData
│   ├── product_category_model.dart  # MỚI: Danh mục động
│   ├── product_variant_model.dart   # MỚI: Biến thể (size, màu)
│   └── shop_settings_model.dart     # MỚI: Cài đặt ngành kinh doanh
│
├── services/
│   ├── category_service.dart        # MỚI: CRUD danh mục
│   ├── expiry_alert_service.dart    # MỚI: Cảnh báo hết hạn
│   └── variant_service.dart         # MỚI: Quản lý biến thể
│
├── views/
│   ├── category_management_view.dart  # MỚI: Quản lý danh mục
│   ├── expiry_management_view.dart    # MỚI: Quản lý HSD
│   └── variant_management_view.dart   # MỚI: Quản lý biến thể
│
└── widgets/
    ├── category_selector.dart       # MỚI: Chọn danh mục
    ├── expiry_badge.dart            # MỚI: Badge cảnh báo HSD
    └── variant_selector.dart        # MỚI: Chọn biến thể
```

---

## 4. CÁC NGÀNH KINH DOANH HỖ TRỢ

### 4.1 Bảng so sánh tính năng

| Tính năng | 📱 Điện tử | 🍎 Thực phẩm | 👕 Thời trang | 📦 Tổng hợp |
|-----------|-----------|-------------|--------------|-------------|
| Quản lý IMEI/Serial | ✅ | ❌ | ❌ | Tùy chọn |
| Sửa chữa | ✅ | ❌ | ❌ | Tùy chọn |
| Bảo hành | ✅ | ❌ | ❌ | Tùy chọn |
| Hạn sử dụng | ❌ | ✅ | ❌ | Tùy chọn |
| Quản lý lô | ❌ | ✅ | ❌ | Tùy chọn |
| Đơn vị tính (kg, lít) | ❌ | ✅ | ❌ | Tùy chọn |
| Cảnh báo HSD | ❌ | ✅ | ❌ | Tùy chọn |
| Size | ❌ | ❌ | ✅ | Tùy chọn |
| Màu sắc | ✅ | ❌ | ✅ | Tùy chọn |
| Biến thể (SKU) | ❌ | ❌ | ✅ | Tùy chọn |
| Hoa hồng bán | ✅ | ✅ | ✅ | ✅ |
| Báo cáo tài chính | ✅ | ✅ | ✅ | ✅ |

### 4.2 Danh mục mặc định theo ngành

**📱 Điện tử (Electronics)**
```
├── Điện thoại      → trackSerial: true, warranty: true
├── Máy tính bảng   → trackSerial: true, warranty: true
├── Laptop          → trackSerial: true, warranty: true
├── Phụ kiện        → trackSerial: false
└── Linh kiện       → trackSerial: false
```

**🍎 Thực phẩm (Food)**
```
├── Rau củ          → trackExpiry: true, unit: 'kg'
├── Trái cây        → trackExpiry: true, unit: 'kg'
├── Thịt cá         → trackExpiry: true, unit: 'kg'
├── Đồ khô          → trackExpiry: true, unit: 'gói'
├── Đồ hộp          → trackExpiry: true, unit: 'hộp'
├── Đồ uống         → trackExpiry: true, unit: 'chai'
└── Đông lạnh       → trackExpiry: true, unit: 'kg'
```

**👕 Thời trang (Fashion)**
```
├── Áo              → hasVariants: true (size, color)
├── Quần            → hasVariants: true (size, color)
├── Váy/Đầm         → hasVariants: true (size, color)
├── Giày dép        → hasVariants: true (size)
├── Túi xách        → hasVariants: false
└── Phụ kiện        → hasVariants: false
```

**📦 Tổng hợp (General)**
```
└── Tự do tạo danh mục với thuộc tính tùy chỉnh
```

---

## 5. SCHEMA DATABASE

### 5.1 Bảng mới: `shop_settings`
```sql
CREATE TABLE shop_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  
  -- Ngành kinh doanh
  businessType TEXT NOT NULL,  -- 'electronics', 'food', 'fashion', 'general'
  
  -- Modules được bật
  enableRepair INTEGER DEFAULT 0,      -- Có module sửa chữa?
  enableExpiry INTEGER DEFAULT 0,      -- Có quản lý HSD?
  enableVariants INTEGER DEFAULT 0,    -- Có biến thể size/màu?
  enableSerial INTEGER DEFAULT 0,      -- Có quản lý IMEI/Serial?
  
  -- Cài đặt mặc định
  defaultUnit TEXT DEFAULT 'cái',      -- Đơn vị mặc định
  expiryWarningDays INTEGER DEFAULT 7, -- Số ngày cảnh báo HSD
  
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

### 5.2 Bảng mới: `categories`
```sql
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  
  name TEXT NOT NULL,           -- Tên danh mục (VD: "Điện thoại")
  parentId TEXT,                -- ID danh mục cha (tree structure)
  icon TEXT,                    -- Icon emoji hoặc path
  color TEXT,                   -- Màu hiển thị (hex)
  sortOrder INTEGER DEFAULT 0,  -- Thứ tự sắp xếp
  
  -- Tính năng theo danh mục
  trackExpiry INTEGER DEFAULT 0,    -- Có quản lý HSD?
  trackSerial INTEGER DEFAULT 0,    -- Có quản lý IMEI/Serial?
  hasVariants INTEGER DEFAULT 0,    -- Có biến thể?
  hasWarranty INTEGER DEFAULT 0,    -- Có bảo hành?
  
  -- Cài đặt đơn vị
  defaultUnit TEXT DEFAULT 'cái',   -- kg, lít, gói, hộp, cái, đôi...
  
  -- Thuộc tính tùy chỉnh (JSON)
  customFields TEXT,  -- '[{"name":"capacity","label":"Dung lượng","type":"select","options":["64GB","128GB"]}]'
  
  isActive INTEGER DEFAULT 1,
  deleted INTEGER DEFAULT 0,
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

### 5.3 Bảng mới: `product_variants`
```sql
CREATE TABLE product_variants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firestoreId TEXT UNIQUE,
  shopId TEXT NOT NULL,
  productId TEXT NOT NULL,      -- FK to products
  
  -- Thuộc tính biến thể
  sku TEXT,                     -- Mã SKU riêng
  size TEXT,                    -- S, M, L, XL, 38, 39...
  color TEXT,                   -- Trắng, Đen, Xanh...
  
  -- Giá riêng (nếu khác sản phẩm gốc)
  cost INTEGER,                 -- Giá vốn biến thể
  price INTEGER,                -- Giá bán biến thể
  
  -- Tồn kho riêng
  quantity INTEGER DEFAULT 0,
  
  -- Barcode riêng
  barcode TEXT,
  
  isActive INTEGER DEFAULT 1,
  deleted INTEGER DEFAULT 0,
  createdAt INTEGER,
  updatedAt INTEGER,
  isSynced INTEGER DEFAULT 0
);
```

### 5.4 Mở rộng bảng `products`
```sql
-- Thêm columns mới
ALTER TABLE products ADD COLUMN categoryId TEXT;      -- FK to categories
ALTER TABLE products ADD COLUMN customData TEXT;      -- JSON động theo ngành
ALTER TABLE products ADD COLUMN expiryDate INTEGER;   -- Timestamp HSD
ALTER TABLE products ADD COLUMN batchNumber TEXT;     -- Số lô (thực phẩm)
ALTER TABLE products ADD COLUMN unit TEXT DEFAULT 'cái';  -- Đơn vị tính

-- customData example cho điện thoại:
-- {"imei": "356789...", "capacity": "128GB", "ram": "8GB"}

-- customData example cho thực phẩm:
-- {"storageTemp": "2-8°C", "origin": "Đà Lạt"}

-- customData example cho thời trang:
-- {"material": "Cotton 100%", "style": "Basic"}
```

### 5.5 Migration từ `type` sang `categoryId`
```dart
// Migration logic
Future<void> migrateProductTypes() async {
  // 1. Tạo categories mặc định cho shop điện tử hiện tại
  final defaultCategories = {
    'DIEN_THOAI': CategoryModel(name: 'Điện thoại', trackSerial: true, hasWarranty: true),
    'PHU_KIEN': CategoryModel(name: 'Phụ kiện', trackSerial: false),
    'LINH_KIEN': CategoryModel(name: 'Linh kiện', trackSerial: false),
  };
  
  // 2. Lưu categories vào DB
  for (final entry in defaultCategories.entries) {
    await db.insert('categories', entry.value.toMap());
  }
  
  // 3. Update products: type → categoryId
  for (final entry in defaultCategories.entries) {
    await db.rawUpdate('''
      UPDATE products 
      SET categoryId = ? 
      WHERE type = ?
    ''', [entry.value.id, entry.key]);
  }
  
  // 4. Move imei, capacity, model → customData (JSON)
  await db.rawUpdate('''
    UPDATE products
    SET customData = json_object(
      'imei', imei,
      'capacity', capacity,
      'model', model
    )
    WHERE categoryId IS NOT NULL
  ''');
}
```

---

## 6. FLOW NGƯỜI DÙNG

### 6.1 Flow Đăng ký Shop mới
```
┌──────────────────────────────────────────────────────────────────┐
│ BƯỚC 1: ĐĂNG KÝ TÀI KHOẢN                                       │
├──────────────────────────────────────────────────────────────────┤
│ • Email + Mật khẩu                                               │
│ • Họ tên + SĐT                                                   │
│ → Tạo user trong Firebase Auth                                   │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│ BƯỚC 2: TẠO CỬA HÀNG + CHỌN NGÀNH                               │
├──────────────────────────────────────────────────────────────────┤
│ • Tên cửa hàng + Địa chỉ                                         │
│ • Chọn ngành kinh doanh:                                         │
│   ○ 📱 Điện tử (Điện thoại, laptop...)                           │
│   ○ 🍎 Thực phẩm (Rau, thịt, đồ khô...)                          │
│   ○ 👕 Thời trang (Quần áo, giày dép...)                         │
│   ○ 📦 Tổng hợp (Tự tạo)                                         │
│ → Tạo shop + shop_settings trong Firestore                       │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│ BƯỚC 3: TỰ ĐỘNG TẠO DANH MỤC MẶC ĐỊNH                           │
├──────────────────────────────────────────────────────────────────┤
│ • Theo ngành đã chọn (xem mục 4.2)                               │
│ • Có thể tùy chỉnh sau trong Cài đặt                             │
│ → Tạo categories theo businessType                               │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│ BƯỚC 4: VÀO APP VỚI GIAO DIỆN THEO NGÀNH                        │
├──────────────────────────────────────────────────────────────────┤
│ • Home: Điều chỉnh tabs theo businessType                        │
│   - Điện tử: Có tab "Sửa chữa"                                   │
│   - Thực phẩm: Có tab "Sắp hết hạn"                              │
│ • Thêm SP: Form động theo categoryId                             │
│ • Báo cáo: Thêm metrics theo ngành                               │
└──────────────────────────────────────────────────────────────────┘
```

### 6.2 Flow Shop hiện tại (Migration)
```
┌──────────────────────────────────────────────────────────────────┐
│ APP CẬP NHẬT PHIÊN BẢN MỚI                                      │
├──────────────────────────────────────────────────────────────────┤
│ 1. Kiểm tra shop chưa có businessType                            │
│ 2. TỰ ĐỘNG gán businessType = 'electronics'                      │
│ 3. TỰ ĐỘNG chạy migration type → categoryId                      │
│ 4. Giao diện KHÔNG thay đổi (backward compatible)                │
└──────────────────────────────────────────────────────────────────┘
```

### 6.3 Flow Thêm sản phẩm (Mới)
```
┌──────────────────────────────────────────────────────────────────┐
│ THÊM SẢN PHẨM                                                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│ Danh mục: [Chọn danh mục ▼]  ← Từ bảng categories               │
│           ├── 📱 Điện thoại                                      │
│           ├── 🎧 Phụ kiện                                        │
│           └── 🔧 Linh kiện                                       │
│                                                                   │
│ Tên SP: [                                   ]                    │
│ Giá vốn: [            ] Giá bán: [          ]                    │
│                                                                   │
│ ┌─────────────────────────────────────────────────────────────┐  │
│ │ THUỘC TÍNH ĐỘNG (theo category.customFields)                │  │
│ ├─────────────────────────────────────────────────────────────┤  │
│ │ Nếu category = "Điện thoại":                                │  │
│ │   IMEI: [                    ]                              │  │
│ │   Dung lượng: [64GB ▼] [128GB] [256GB]                      │  │
│ │   Bảo hành: [12 tháng ▼]                                    │  │
│ ├─────────────────────────────────────────────────────────────┤  │
│ │ Nếu category = "Rau củ":                                    │  │
│ │   Hạn sử dụng: [   📅   ]                                   │  │
│ │   Số lô: [              ]                                   │  │
│ │   Đơn vị: [kg ▼]                                            │  │
│ ├─────────────────────────────────────────────────────────────┤  │
│ │ Nếu category = "Áo":                                        │  │
│ │   Chất liệu: [               ]                              │  │
│ │   Biến thể:  [+ Thêm size/màu]                              │  │
│ │     ├── S - Trắng: SL [  5  ]                               │  │
│ │     ├── S - Đen:   SL [  3  ]                               │  │
│ │     └── M - Trắng: SL [  8  ]                               │  │
│ └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│                      [LƯU SẢN PHẨM]                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 7. GIAI ĐOẠN TRIỂN KHAI

### Phase 1: Core Extension (2-3 tuần)
```
📦 Mở rộng nền tảng
├── 1.1 Tạo ShopSettings model + service
├── 1.2 Tạo Category model + service + UI quản lý
├── 1.3 Mở rộng Product với categoryId, customData
├── 1.4 Migrate type → categoryId (backward compatible)
├── 1.5 Update db_helper.dart (schema v18)
├── 1.6 Update sync_service.dart (sync categories)
└── 1.7 Update firestore.rules

Files cần tạo:
- lib/models/shop_settings_model.dart
- lib/models/product_category_model.dart
- lib/services/category_service.dart
- lib/views/category_management_view.dart
- lib/widgets/category_selector.dart

Files cần sửa:
- lib/models/product_model.dart
- lib/data/db_helper.dart
- lib/services/sync_service.dart
- lib/services/firestore_service.dart
- firestore.rules
```

### Phase 2: Module Thực phẩm (2-3 tuần)
```
🍎 Module Food
├── 2.1 Thêm expiryDate, batchNumber vào Product
├── 2.2 Tạo ExpiryAlertService
├── 2.3 UI màn hình "Sắp hết hạn"
├── 2.4 Đơn vị tính động (kg, lít, gói)
├── 2.5 Quản lý nhập hàng theo lô
├── 2.6 Badge cảnh báo trên sản phẩm
└── 2.7 Báo cáo hàng hết hạn

Files cần tạo:
- lib/services/expiry_alert_service.dart
- lib/views/food/expiry_management_view.dart
- lib/widgets/expiry_badge.dart

Files cần sửa:
- lib/models/product_model.dart
- lib/views/add_product_view.dart
- lib/views/home_view.dart (thêm tab)
```

### Phase 3: Module Thời trang (2-3 tuần)
```
👕 Module Fashion
├── 3.1 Tạo ProductVariant model + service
├── 3.2 UI quản lý variants (size, color)
├── 3.3 Chọn variant khi tạo đơn bán
├── 3.4 Báo cáo tồn kho theo variant (matrix)
├── 3.5 Barcode cho từng variant
└── 3.6 Cảnh báo variant hết hàng

Files cần tạo:
- lib/models/product_variant_model.dart
- lib/services/variant_service.dart
- lib/views/fashion/variant_management_view.dart
- lib/widgets/variant_selector.dart

Files cần sửa:
- lib/views/create_sale_view.dart
- lib/views/product_detail_view.dart
- lib/views/inventory_report_view.dart
```

### Phase 4: Tổng quát hóa (1-2 tuần)
```
⚙️ General Shop
├── 4.1 Custom fields UI builder
├── 4.2 Template ngành (preset settings)
├── 4.3 Ẩn/hiện module theo businessType
├── 4.4 Onboarding wizard chọn ngành (shop mới)
└── 4.5 Cài đặt chuyển đổi ngành (shop cũ)

Files cần tạo:
- lib/views/onboarding/business_type_wizard.dart
- lib/widgets/dynamic_form_builder.dart

Files cần sửa:
- lib/views/create_shop_view.dart
- lib/views/shop_settings_view.dart
```

### Phase 5: Testing & QA (1-2 tuần)
```
🧪 Testing
├── 5.1 Unit tests cho services mới
├── 5.2 Integration tests migration
├── 5.3 Test với data production (clone)
├── 5.4 Test offline/online sync
└── 5.5 Rollout từng shop, A/B testing
```

---

## 8. QUY TẮC PHÁT TRIỂN

### 8.1 KHÔNG phá vỡ logic hiện tại
```
❌ KHÔNG SỬA:
- PaymentIntentService → Giữ nguyên
- SalaryCalculationService → Giữ nguyên
- Repair flow → Giữ nguyên
- Financial reports → Giữ nguyên (chỉ thêm, không sửa)

✅ CHỈ THÊM MỚI:
- Models mới (không sửa models cũ trừ khi thêm field)
- Views mới
- Services mới
```

### 8.2 Backward Compatible
```dart
// Product model - giữ 'type', thêm 'categoryId'
class Product {
  String type;          // GIỮ NGUYÊN - fallback
  String? categoryId;   // MỚI - ưu tiên nếu có
  
  String get effectiveType {
    if (categoryId != null) {
      return _getCategoryType(categoryId);
    }
    return type; // Fallback về cách cũ
  }
}
```

### 8.3 Feature Flags
```dart
// Kiểm tra feature theo businessType
class FeatureFlags {
  static bool hasRepairModule(String businessType) {
    return businessType == 'electronics';
  }
  
  static bool hasExpiryTracking(String businessType) {
    return businessType == 'food';
  }
  
  static bool hasVariants(String businessType) {
    return businessType == 'fashion';
  }
}
```

### 8.4 UI Conditional Rendering
```dart
// Home tabs theo businessType
List<Widget> _buildTabs() {
  final settings = ShopSettingsService.current;
  final tabs = [
    Tab(text: loc.homeTab),
    Tab(text: loc.salesTab),
    Tab(text: loc.inventoryTab),
  ];
  
  // Thêm tab theo ngành
  if (settings.enableRepair) {
    tabs.add(Tab(text: loc.repairTab));
  }
  if (settings.enableExpiry) {
    tabs.add(Tab(text: loc.expiryTab));
  }
  
  return tabs;
}
```

### 8.5 Service-First Pattern
```dart
// ✅ ĐÚNG: Mọi thao tác qua Service
await CategoryService.create(category);
await CategoryService.getByShopId(shopId);

// ❌ SAI: Gọi trực tiếp Firestore trong Widget
await FirebaseFirestore.instance.collection('categories').add(...);
```

### 8.6 Sync Pattern
```dart
// Thêm sync cho collection mới
class SyncService {
  static void initRealTimeSync() {
    // ... existing syncs ...
    
    // Thêm sync categories
    _firestore
        .collection('categories')
        .where('shopId', isEqualTo: shopId)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            _handleCategoryChange(change);
          }
        });
  }
}
```

---

## 9. CHECKLIST TRƯỚC KHI CODE

### Khi thêm tính năng mới:
- [ ] Đọc file này (MULTI_INDUSTRY_EXPANSION_GUIDE.md)
- [ ] Đọc DEVELOPER_ONBOARDING.md
- [ ] Đọc copilot-instructions.md
- [ ] Có filter theo `shopId` chưa?
- [ ] Có đi qua Service layer chưa?
- [ ] Có backward compatible không?
- [ ] Có emit EventBus sau khi thay đổi data?
- [ ] UI text bằng tiếng Việt, code/comments bằng tiếng Anh?

### Khi sửa Product model:
- [ ] Giữ nguyên field `type` (fallback)
- [ ] Thêm field mới, không xóa field cũ
- [ ] Update toMap/fromMap
- [ ] Update db_helper schema với migration
- [ ] Update sync_service

### Khi thêm Category/Variant:
- [ ] Tạo model với toMap/fromMap
- [ ] Tạo service với CRUD
- [ ] Thêm table vào db_helper
- [ ] Thêm vào sync_service
- [ ] Thêm rules vào firestore.rules
- [ ] Tạo UI quản lý

### Khi test:
- [ ] Test với shop hiện tại (migration)
- [ ] Test tạo shop mới từng loại (electronics, food, fashion)
- [ ] Test offline → online sync
- [ ] Test chuyển shop (multi-shop)
- [ ] flutter analyze - no errors
- [ ] flutter run - build success

---

## 10. FILES QUAN TRỌNG

### Đọc trước khi code:
| File | Mô tả |
|------|-------|
| `DOCS/MULTI_INDUSTRY_EXPANSION_GUIDE.md` | **FILE NÀY** |
| `DOCS/DEVELOPER_ONBOARDING.md` | Onboarding tổng quan |
| `.github/copilot-instructions.md` | AI agent instructions |
| `DOCS/UNIFIED_PAYMENT_GUIDE.md` | Flow thanh toán (KHÔNG SỬA) |
| `DOCS/PAYMENT_FLOW_AUDIT_REPORT.md` | Audit tài chính (KHÔNG SỬA) |

### Files cốt lõi (cẩn thận khi sửa):
| File | Mô tả | Sửa? |
|------|-------|------|
| `lib/models/product_model.dart` | Model sản phẩm | ✅ Thêm fields |
| `lib/data/db_helper.dart` | SQLite schema | ✅ Thêm tables |
| `lib/services/sync_service.dart` | Real-time sync | ✅ Thêm collections |
| `lib/services/firestore_service.dart` | Firestore CRUD | ✅ Thêm methods |
| `lib/services/payment_intent_service.dart` | Thanh toán | ❌ KHÔNG SỬA |
| `lib/services/salary_calculation_service.dart` | Tính lương | ❌ KHÔNG SỬA |
| `firestore.rules` | Security rules | ✅ Thêm rules |

### Files UI (tự do sửa):
| File | Mô tả |
|------|-------|
| `lib/views/home_view.dart` | Home screen |
| `lib/views/add_product_view.dart` | Thêm sản phẩm |
| `lib/views/product_detail_view.dart` | Chi tiết SP |
| `lib/views/shop_settings_view.dart` | Cài đặt shop |

---

## 📝 GHI CHÚ CUỐI

### Ưu tiên:
1. **Phase 1 (Core)** là bắt buộc trước khi làm Phase 2, 3, 4
2. **Backward compatible** là ưu tiên hàng đầu
3. **Test kỹ migration** trước khi deploy

### Timeline ước tính:
- Phase 1: 2-3 tuần
- Phase 2: 2-3 tuần
- Phase 3: 2-3 tuần
- Phase 4: 1-2 tuần
- Phase 5: 1-2 tuần
- **TOTAL: ~2.5-3 tháng**

### Liên hệ:
- Email: admin@huluca.com
- GitHub: https://github.com/itquanghuy85/quanlyshop

---

*Cập nhật lần cuối: 2026-02-08*
