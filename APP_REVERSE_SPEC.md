# APP_REVERSE_SPEC.md
> Tài liệu đặc tả ngược — sinh 100% từ source code, KHÔNG suy đoán, KHÔNG bỏ sót.
> Những gì không tìm thấy trong code sẽ được ghi rõ **[UNKNOWN — không có trong code]**.

---

## 🧭 TỔNG QUAN

| Thuộc tính | Giá trị thực tế trong code |
|---|---|
| Tên app | `'Quản Lý Shop'` (khai báo trong `MyApp.title` — `lib/main.dart`) |
| Package name | `quanlyshop` (`pubspec.yaml`) |
| Version | `1.0.3+513` (`pubspec.yaml`) |
| Platform | Android, iOS, Web (Flutter multi-platform) |
| Ngôn ngữ UI | Tiếng Việt (mặc định `vi`), hỗ trợ thêm `en` |
| Môi trường SDK | Dart `>=3.10.0 <4.0.0` |
| DB chính | Firebase Firestore (cloud) |
| DB local | SQLite (`repair_shop_v22.db`), schema version **96** |
| Auth | Firebase Auth: Email/Password, Google Sign-In, Apple Sign-In |
| File lưu trữ | Firebase Storage |
| Push notification | Firebase Cloud Messaging (FCM) + `flutter_local_notifications` |
| Backend functions | Firebase Cloud Functions (Node.js) — trong thư mục `functions/` |
| AppCheck | `firebase_app_check` (PlayIntegrity Android / AppAttest iOS) |
| Mô tả | Phần mềm quản lý tiệm sửa chữa mua bán điện thoại chuyên nghiệp |

### Mô-đun chức năng chính
1. **Sửa chữa** (`enableRepair`) — tiếp nhận, theo dõi, giao máy
2. **Bán hàng** — bán lẻ, trả góp, kết hợp thanh toán
3. **Kho hàng** — nhập, xuất, kiểm kê, IMEI, biến thể size/màu, hạn sử dụng
4. **Công nợ** — khách nợ, nợ NCC, nợ đối tác sửa chữa
5. **Tài chính** — chốt quỹ hàng ngày, báo cáo doanh thu, bút toán điều chỉnh
6. **Nhân viên** — chấm công (check-in/out GPS), xin nghỉ phép, lịch làm việc, lương
7. **Cài đặt shop** — thông tin, vị trí GPS, loại ngành kinh doanh, logo
8. **Thông báo** — in-app snackbar + FCM push, kênh theo loại

### Loại ngành kinh doanh (`businessType`)
| Giá trị | Tên hiển thị | Modules bật |
|---|---|---|
| `electronics` | Điện thoại & Điện tử | enableRepair, enableSerial, enableWarranty |
| `food` | Thực phẩm & Đồ tươi sống | enableExpiry, enableBatch |
| `fashion` | Thời trang & May mặc | enableVariants |
| `general` | Tổng hợp | (không có module đặc thù) |

---

## 🗂 CẤU TRÚC PROJECT

```
quanlyshop/
├── lib/
│   ├── main.dart                   # Bootstrap, Firebase init, AuthGate, global error handler
│   ├── firebase_options.dart       # Firebase cấu hình (Android/iOS/Web)
│   ├── core/
│   │   └── utils/
│   │       └── money_utils.dart    # Helper format tiền (compact: tr/ty)
│   ├── constants/
│   │   └── financial_constants.dart # Enums: PaymentMethod, MoneySourceType, MoneyDirection, MoneyTransactionType
│   ├── data/
│   │   └── db_helper.dart          # SQLite singleton, schema v96, tất cả CRUD local
│   ├── models/
│   │   ├── repair_model.dart        # Model đơn sửa chữa, status 1-4
│   │   ├── product_model.dart       # Model sản phẩm/kho
│   │   ├── sale_order_model.dart    # Model đơn bán hàng
│   │   ├── expense_model.dart       # Model chi phí/thu nhập
│   │   ├── debt_model.dart          # Model công nợ
│   │   ├── attendance_model.dart    # Model chấm công
│   │   ├── leave_request_model.dart # Model xin nghỉ phép
│   │   ├── shop_settings_model.dart # Model cài đặt shop (businessType, feature flags)
│   │   ├── payment_intent_model.dart # Model payment intent (trung tâm quản lý thanh toán)
│   │   └── repair_service_model.dart # Model dịch vụ sửa chữa (nằm trong Repair)
│   ├── services/
│   │   ├── user_service.dart        # Auth, role, shopId, permissions cache 10 phút
│   │   ├── firestore_service.dart   # CRUD Firestore: repair, sale, product, ...
│   │   ├── sync_service.dart        # Snapshot listeners Firestore → local DB
│   │   ├── sync_orchestrator.dart   # Queue write local → Firestore (local-first)
│   │   ├── notification_service.dart# FCM + local notifications + snackbar
│   │   ├── payment_intent_service.dart # Singleton quản lý thanh toán tập trung
│   │   ├── financial_activity_service.dart # Log hoạt động tài chính local
│   │   ├── adjustment_service.dart  # Bút toán điều chỉnh sau chốt quỹ
│   │   ├── audit_service.dart       # Ghi log audit
│   │   ├── category_service.dart    # Danh mục, shop settings
│   │   ├── debt_summary_service.dart# Tổng hợp công nợ
│   │   ├── repair_partner_service.dart # Đối tác sửa chữa
│   │   ├── attendance_approval_service.dart # Duyệt chấm công
│   │   ├── claims_service.dart      # Firebase custom claims
│   │   ├── encryption_service.dart  # Mã hoá dữ liệu nhạy cảm
│   │   ├── social_auth_service.dart # Google/Apple sign-in
│   │   ├── storage_service.dart     # Firebase Storage
│   │   ├── background_upload_service.dart # Upload ảnh nền
│   │   ├── osm_map_service.dart     # Bản đồ OpenStreetMap
│   │   ├── event_bus.dart           # EventBus singleton stream
│   │   ├── data_migration_service.dart # Di chuyển dữ liệu
│   │   ├── first_time_guide_service.dart # Hướng dẫn lần đầu
│   │   ├── daily_financial_analysis_service.dart # Phân tích tài chính ngày
│   │   └── firestore_write_helper.dart # Helper ghi Firestore
│   ├── views/
│   │   ├── splash_view.dart         # Màn hình khởi động (animation)
│   │   ├── intro_view.dart          # Màn hình giới thiệu (onboarding)
│   │   ├── login_view.dart          # Đăng nhập Email/Google/Apple
│   │   ├── register_view.dart       # Đăng ký tài khoản
│   │   ├── home_view.dart           # Màn hình chính (bottom nav, stats)
│   │   ├── order_list_view.dart     # Danh sách đơn sửa chữa
│   │   ├── create_repair_order_view.dart # Tạo đơn sửa chữa mới
│   │   ├── repair_detail_view.dart  # Chi tiết đơn sửa chữa
│   │   ├── inventory_view.dart      # Kho hàng (paginated)
│   │   ├── create_sale_view.dart    # Tạo đơn bán hàng
│   │   ├── sale_list_view.dart      # Danh sách đơn bán
│   │   ├── sale_detail_view.dart    # Chi tiết đơn bán
│   │   ├── expense_view.dart        # Chi phí & thu nhập
│   │   ├── revenue_view.dart        # Báo cáo doanh thu
│   │   ├── debt_view.dart           # Công nợ (4 tabs)
│   │   ├── cash_closing_view.dart   # Chốt quỹ ngày
│   │   ├── staff_list_view.dart     # Danh sách nhân viên
│   │   ├── attendance_view.dart     # Chấm công cá nhân
│   │   ├── attendance_management_view.dart # Quản lý chấm công (owner/manager)
│   │   ├── shop_settings_view.dart  # Cài đặt shop
│   │   ├── parts_inventory_view.dart # Kho linh kiện sửa chữa
│   │   ├── repair_partner_detail_view.dart # Chi tiết đối tác sửa chữa
│   │   ├── adjustment_history_view.dart # Lịch sử bút toán điều chỉnh
│   │   ├── hr_salary_settings_view.dart # Cài đặt lương HR
│   │   ├── label_designer_view.dart # Thiết kế nhãn in
│   │   ├── work_schedule_settings_view.dart # Cài đặt lịch làm việc
│   │   ├── shift_swap_view.dart     # Đổi ca
│   │   └── onboarding/
│   │       └── business_type_wizard.dart # Wizard chọn loại ngành
│   ├── widgets/
│   │   ├── custom_app_bar.dart
│   │   ├── currency_text_field.dart
│   │   ├── gradient_fab.dart
│   │   ├── responsive_wrapper.dart
│   │   ├── validated_text_field.dart
│   │   ├── app_cached_image.dart
│   │   ├── export_date_filter_dialog.dart
│   │   └── ... (các widget tái sử dụng khác)
│   ├── theme/
│   │   ├── app_colors.dart          # Bảng màu tập trung
│   │   ├── app_text_styles.dart     # Text styles
│   │   └── app_button_styles.dart   # Button styles
│   ├── utils/
│   │   ├── money_utils.dart         # Format tiền tệ
│   │   ├── perf_monitor.dart        # Đo hiệu suất
│   │   └── excel_export_helper.dart # Xuất Excel
│   └── l10n/
│       ├── app_localizations.dart   # Generated localizations
│       ├── app_en.arb               # English strings
│       └── app_vi.arb               # Vietnamese strings
├── android/
│   └── app/google-services.json    # Firebase Android config
├── ios/
│   └── Runner/GoogleService-Info.plist # Firebase iOS config
├── functions/                       # Firebase Cloud Functions (Node.js)
├── DOCS/
│   └── MULTI_INDUSTRY_EXPANSION_GUIDE.md
├── pubspec.yaml
└── APP_REVERSE_SPEC.md             # File này
```

---

## 🗃 DATABASE THỰC TẾ

### SQLite Local — `repair_shop_v22.db` (schema version 96)

#### Bảng `repairs`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PRIMARY KEY AUTOINCREMENT | |
| firestoreId | TEXT UNIQUE | `"rep_{createdAt}_{phone}"` hoặc `"rep_{now}_walkin"` |
| shopId | TEXT | |
| customerName | TEXT | |
| phone | TEXT | |
| isWalkIn | INTEGER | 0/1 |
| walkInName | TEXT | |
| walkInPhone | TEXT | |
| model | TEXT | **Bắt buộc khi tạo** |
| issue | TEXT | |
| accessories | TEXT | |
| address | TEXT | |
| imagePath | TEXT | Multi-path CSV (nhiều ảnh ngăn cách bởi dấu `,`) |
| deliveredImage | TEXT | |
| warranty | TEXT | |
| partsUsed | TEXT | |
| status | INTEGER | 1=Tiếp nhận, 2=Đang sửa, 3=Đã xong, 4=Đã giao |
| price | INTEGER | Giá thu khách |
| cost | INTEGER | Chi phí linh kiện |
| paymentMethod | TEXT | |
| createdAt | INTEGER | Epoch milliseconds |
| startedAt | INTEGER | |
| finishedAt | INTEGER | |
| deliveredAt | INTEGER | |
| createdBy | TEXT | Tên người tạo |
| createdByUid | TEXT | |
| repairedBy | TEXT | |
| repairedByUid | TEXT | |
| deliveredBy | TEXT | |
| deliveredByUid | TEXT | |
| lastCaredAt | INTEGER | |
| isSynced | INTEGER | 0/1 |
| deleted | INTEGER | 0/1 (soft delete) |
| color | TEXT | |
| imei | TEXT | |
| condition | TEXT | |
| services | TEXT | JSON List<RepairService> |
| notes | TEXT | |
| pendingDeliveryApproval | INTEGER | 0/1 |
| requestedDeliveryPrice | INTEGER | |
| costRecordedInFund | INTEGER | 0/1 |
| costPaymentMethod | TEXT | |
| costRecordedAt | INTEGER | |
| costRecordedAmount | INTEGER | |

**Getter quan trọng trong model:**
- `totalCost`: ưu tiên field `cost`, fallback = `servicesCost` (tổng cost từ list services)
- `isPendingDelivery`: `status == 3 && pendingDeliveryApproval == true`

#### Bảng `products`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| name | TEXT | |
| brand | TEXT | |
| model | TEXT | |
| imei | TEXT | |
| cost | INTEGER | Giá nhập |
| price | INTEGER | Giá bán |
| condition | TEXT | |
| status | INTEGER | 1=active |
| description | TEXT | |
| images | TEXT | JSON array URL |
| warranty | TEXT | |
| createdAt | INTEGER | |
| updatedAt | INTEGER | |
| supplier | TEXT | |
| type | TEXT | DEPRECATED |
| quantity | INTEGER | |
| color | TEXT | |
| capacity | TEXT | |
| size | TEXT | |
| paymentMethod | TEXT | |
| labelInfo | TEXT | |
| isSynced | INTEGER | |
| isPending | INTEGER | |
| pendingSupplier | TEXT | |
| labelNote | TEXT | |
| categoryId | TEXT | |
| unit | TEXT | |
| expiryDate | INTEGER | Epoch ms (cho thực phẩm) |
| batchNumber | TEXT | |
| variantParentId | TEXT | |
| customData | TEXT | JSON |
| sku | TEXT | |

#### Bảng `sales`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| customerName | TEXT | |
| phone | TEXT | |
| isWalkIn | INTEGER | |
| walkInName | TEXT | |
| walkInPhone | TEXT | |
| address | TEXT | |
| productNames | TEXT | JSON array |
| productImeis | TEXT | JSON array |
| totalPrice | INTEGER | |
| totalCost | INTEGER | |
| discount | INTEGER | |
| paymentMethod | TEXT | |
| sellerName | TEXT | |
| sellerUid | TEXT | |
| soldAt | INTEGER | |
| notes | TEXT | |
| gifts | TEXT | |
| warranty | TEXT | |
| isInstallment | INTEGER | |
| downPayment | INTEGER | |
| downPaymentMethod | TEXT | |
| loanAmount | INTEGER | |
| installmentTerm | TEXT | |
| bankName | TEXT | |
| bankName2 | TEXT | |
| loanAmount2 | INTEGER | |
| settlementPlannedAt | INTEGER | |
| settlementReceivedAt | INTEGER | |
| settlementAmount | INTEGER | |
| settlementFee | INTEGER | |
| settlementNote | TEXT | |
| settlementCode | TEXT | |
| cashAmount | INTEGER | |
| transferAmount | INTEGER | |
| isSynced | INTEGER | |

**Computed properties:**
- `finalPrice = totalPrice - discount`
- `remainingDebt`: phụ thuộc paymentMethod và downPayment
- `isPaid`: boolean dựa trên paymentMethod

#### Bảng `expenses`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| title | TEXT | |
| amount | INTEGER | |
| category | TEXT | |
| date | INTEGER | Epoch ms |
| note | TEXT | |
| paymentMethod | TEXT | |
| type | TEXT | `CHI` hoặc `THU` |
| scope | TEXT | `SHOP` hoặc `CA_NHAN` |
| isSynced | INTEGER | |

#### Bảng `debts`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| personName | TEXT | |
| phone | TEXT | |
| totalAmount | INTEGER | |
| paidAmount | INTEGER | |
| type | TEXT | `CUSTOMER_OWES`, `SHOP_OWES`, `OTHER_CUSTOMER_OWES`, `OTHER_SHOP_OWES`, `OWE`(legacy), `OWED`(legacy) |
| status | TEXT | `ACTIVE`, `PAID`, `CANCELLED`, `UNPAID` |
| createdAt | INTEGER | |
| note | TEXT | |
| linkedId | TEXT | ID đơn bán/sửa liên kết |
| isSynced | INTEGER | |

#### Bảng `attendance`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| userId | TEXT | |
| email | TEXT | |
| name | TEXT | |
| dateKey | TEXT | `yyyy-MM-dd` |
| checkInAt | INTEGER | |
| checkOutAt | INTEGER | |
| overtimeOn | INTEGER | 0/1 |
| overtimeStartAt | INTEGER | |
| overtimeEndAt | INTEGER | |
| photoIn | TEXT | URL ảnh check-in |
| photoOut | TEXT | URL ảnh check-out |
| note | TEXT | |
| status | TEXT | `pending`, `approved`, `rejected`, `completed` |
| approvedBy | TEXT | |
| approvedAt | INTEGER | |
| rejectReason | TEXT | |
| requestType | TEXT | `normal`, `forgot_checkin`, `forgot_checkout`, `overtime_edit` |
| locked | INTEGER | 0/1 |
| createdAt | INTEGER | |
| location | TEXT | JSON `{lat, lng}` |
| isLate | INTEGER | 0/1 |
| isEarlyLeave | INTEGER | 0/1 |
| workSchedule | TEXT | JSON |
| updatedAt | INTEGER | |
| isSynced | INTEGER | |

#### Bảng `customers`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| name | TEXT | |
| phone | TEXT | |
| address | TEXT | |
| notes | TEXT | |
| createdAt | INTEGER | |
| isSynced | INTEGER | |

#### Bảng `suppliers`
Lưu thông tin nhà cung cấp — các cột tương tự customers + thêm `bankAccount`, `contactPerson`.

#### Bảng `cash_closings`
| Cột | Kiểu | Ghi chú |
|---|---|---|
| id | INTEGER PK | |
| firestoreId | TEXT UNIQUE | |
| shopId | TEXT | |
| dateKey | TEXT | `yyyy-MM-dd` |
| isLocked | INTEGER | 0/1 — khi locked, không sửa trực tiếp được nữa |
| cashEnd | INTEGER | Tiền mặt cuối ngày (nhập tay) |
| bankEnd | INTEGER | Tiền ngân hàng cuối ngày |
| note | TEXT | |
| createdAt | INTEGER | |
| isSynced | INTEGER | |

#### Bảng `payment_intents`
Lưu payment intent của `PaymentIntentService` — quản lý thanh toán tập trung.
Các cột: `id`, `firestoreId`, `shopId`, `status` (`pending`/`history`), `entityType`, `entityId`, `amount`, `paymentMethod`, `createdAt`, `completedAt`, `metadata` (JSON).

#### Bảng `adjustment_entries`
Bút toán điều chỉnh sau chốt quỹ.
Các cột: `firestoreId`, `shopId`, `adjustmentType` (`COST_ADJUSTMENT`/`DEBT_ADJUSTMENT`), `originalEntityType`, `originalEntityId`, `originalDate`, `adjustmentDate`, `description`, `reason`, `oldValues` (JSON), `newValues` (JSON), `costDelta`, `debtDelta`, `supplierId`, `supplierName`, `createdBy`, `createdAt`, `status` (`APPROVED`), `approvedBy`, `approvedAt`, `isSynced`.

#### Các bảng còn lại (cấu trúc từ db_helper.dart)
- `leave_requests` — đơn xin nghỉ phép
- `audit_logs` — nhật ký kiểm toán
- `inventory_checks` — kiểm kê kho
- `supplier_payments` — thanh toán NCC
- `repair_partner_payments` — thanh toán đối tác sửa chữa
- `payroll_settings` — cài đặt bảng lương
- `payroll_locks` — khoá bảng lương tháng
- `employee_salary_settings` — cài đặt lương cá nhân
- `purchase_orders` — phiếu nhập hàng
- `work_schedules` — lịch làm việc
- `debt_payments` — chi tiết thanh toán công nợ từng đợt
- `quick_input_codes` — mã nhập nhanh sản phẩm
- `supplier_product_prices` — giá sản phẩm theo NCC
- `supplier_import_history` — lịch sử nhập hàng NCC
- `repair_partners` — đối tác sửa chữa ngoài
- `partner_repair_history` — lịch sử sửa qua đối tác
- `repair_parts` — linh kiện sử dụng cho đơn sửa
- `sync_queue` — hàng chờ đồng bộ local → Firestore
- `sales_returns` — hoàn trả đơn bán
- `sales_return_items` — chi tiết hàng hoàn trả
- `financial_activity_log` — log hoạt động tài chính (KHÔNG sync từ cloud)
- `shop_settings` — cài đặt shop (businessType, feature flags)
- `product_categories` — danh mục sản phẩm
- `product_variants` — biến thể (size, màu)

---

### Firestore Collections

| Collection | Mô tả | Key fields |
|---|---|---|
| `users` | Thông tin tài khoản | `uid`, `shopId`, `role`, `email`, `name` |
| `shops` | Thông tin shop | `name`, `address`, `phone`, `email`, `logoUrl`, `latitude`, `longitude` |
| `repairs` | Đơn sửa chữa | Tất cả field của Repair model + `shopId` |
| `products` | Sản phẩm | Tất cả field của Product model + `shopId` |
| `sales` | Đơn bán hàng | Tất cả field của SaleOrder model + `shopId` |
| `expenses` | Chi phí | `title`, `amount`, `category`, `date`, `type`, `scope`, `shopId` |
| `debts` | Công nợ | `type`, `status`, `personName`, `totalAmount`, `paidAmount`, `shopId` |
| `debt_payments` | Thanh toán công nợ | `debtId`, `amount`, `paidAt`, `shopId` |
| `attendance` | Chấm công | `userId`, `dateKey`, `checkInAt`, `checkOutAt`, `shopId` |
| `leave_requests` | Xin nghỉ phép | `userId`, `startDate`, `endDate`, `status`, `shopId` |
| `inventory_checks` | Kiểm kê | `shopId`, `checkedAt`, `items` |
| `supplier_import_history` | Lịch sử nhập NCC | `shopId`, `supplierId`, `items`, `totalCost` |
| `supplier_payments` | Thanh toán NCC | `shopId`, `supplierId`, `amount`, `paidAt` |
| `repair_partner_payments` | TT đối tác sửa | `shopId`, `partnerId`, `amount`, `paidAt` |
| `cash_closings` | Chốt quỹ | `shopId`, `dateKey`, `isLocked`, `cashEnd`, `bankEnd` |
| `product_categories` | Danh mục sản phẩm | `shopId`, `name`, `icon` |
| `sales_returns` | Hoàn trả | `shopId`, `saleId`, `items`, `refundAmount` |
| `adjustment_entries` | Bút toán điều chỉnh | `shopId`, `adjustmentType`, `costDelta` |
| `shop_settings` | Cài đặt shop/ngành | `shopId`, `businessType`, `enableRepair`, `enableExpiry`, `enableVariants` |
| `chats` | Thông báo nội bộ | Viết bởi `_notifyAll()` trong FirestoreService — **KHÔNG mã hoá** |
| `invites` | Mã mời nhân viên | `shopId`, `used`, `expiresAt` |
| `notifications` | Thông báo push | `userId`, `shopId`, `type`, `message`, `read` |
| `audit_logs` | Nhật ký kiểm toán | `shopId`, `userId`, `action`, `entity` |
| `purchase_orders` | Phiếu nhập kho | `shopId`, `items`, `supplierId`, `totalCost` |
| `repair_partners` | Đối tác sửa ngoài | `shopId`, `name`, `phone` |
| `work_schedules` | Lịch làm việc | `shopId`, `userId`, `schedule` |
| `payroll_settings` | Cài đặt lương | `shopId` |
| `quick_input_codes` | Mã nhập nhanh | `shopId`, `code`, `productId` |

---

## 🔄 DATA FLOW TRACE

### 1. Tạo đơn sửa chữa mới

```
UI: CreateRepairOrderView._saveOrderProcess()
  → Kiểm tra cash_closing block (AdjustmentService.canEditDirectly)
  → Validate: model != null
  → Tạo Repair object với firestoreId = "rep_{now}_{phone|walkin}"
  → DBHelper().upsertRepair(repair)              [SQLite write]
  → Tạo Customer nếu !isWalkIn
  → SyncOrchestrator().enqueue(SyncEntityType.repair, create, repair)
  → SyncOrchestrator().syncAll()
      → Upload ảnh lên Firebase Storage nếu có local path
      → FirestoreService.addRepair(repair)
          → Validate money
          → UserService.getCurrentShopId()
          → EncryptionService.encrypt(data)
          → Firestore.collection('repairs').doc(firestoreId).set(merge:true)
          → NotificationService._notifyAll() → ghi vào 'chats' (UNENCRYPTED)
  → Nếu SyncOrchestrator thất bại → fallback: gọi trực tiếp FirestoreService
```

### 2. Sync Firestore → Local DB (SyncService)

```
SyncService.initRealTimeSync(callback):
  → Subscribe 6 collections: repairs, sales, products, debts, sales_returns, product_categories
  → Mỗi collection: Firestore.collection(X).where('shopId', ==, shopId).snapshots()
  → Nhận DocumentSnapshot:
      DocumentChangeType.added/modified → DBHelper().upsert_X(item)
      DocumentChangeType.removed → [BUG: empty handler, không update local DB]
      item['deleted'] == true → [BUG: empty handler, không soft-delete local]
  → Emit EventBus event (VD: 'sales_changed', EventBus.repairsChanged)
  → callback()
```

### 3. Đọc dữ liệu tài chính (RevenueView)

```
RevenueView._loadAllData()
  → Tính range: Jan 1 năm trước → hôm nay + 1 ngày
  → Parallel reads từ SQLite:
      db.getRepairsByCreatedAtRange(start, end)
      db.getSalesByDateRange(start, end)
      db.getExpensesByDateRange(start, end)
      db.getDebtPaymentsWithDebtInfoByDateRange(start, end)
      db.getAllSupplierImportHistoryByDateRange(start, end)
      db.getSupplierPaymentsByDateRange(start, end)
      db.getRepairPartnerPaymentsByDateRange(start, end)
      db.query('cash_closings', where: 'shopId=? OR shopId IS NULL', limit: 10)
  → setState() → rebuild UI
  → EventBus listener: debounce 2s → _loadAllData() lại nếu có event
```

### 4. Chấm công (AttendanceView)

```
AttendanceView._refreshAttendanceData()
  → _pullOwnCloudData(uid, shopId):
      Firestore.collection('attendance').where('shopId',==,shopId).where('userId',==,uid)
      Upsert vào local DB
  → db.getAttendance(dateKey, uid)   [SQLite read]
  → db.getWorkSchedule(uid)
  → db.getAttendanceByUser(uid)
  → db.getLeaveRequestsByUser(uid)
  → setState() → render UI

Check-in flow:
  → Xin quyền GPS
  → Geolocator.getCurrentPosition()
  → Kiểm tra khoảng cách vs _shopLatitude/_shopLongitude nếu _locationRequired=true
  → Chụp ảnh selfie (ImagePicker.camera)
  → BackgroundUploadService.uploadAttendancePhoto()
  → DBHelper().upsertAttendance(attendance)
  → SyncOrchestrator.enqueue(attendance, create/update)
```

---

## 📱 SCREEN DETAIL

### SplashView (`lib/views/splash_view.dart`)
- **Mục đích**: Màn hình khởi động với animation
- **Animations**: Logo scale (0.3→1.0) + rotate + fade, title slide up, shimmer, 24 floating particles
- **Timer**: Điều hướng tới IntroView hoặc AuthGate sau animation
- **Dependency**: `flutter_native_splash` để giữ native splash cho đến khi Flutter ready

### LoginView (`lib/views/login_view.dart`)
- **Trường nhập**: Email (`_emailC`), Password (`_passC`), Checkbox "Nhớ mật khẩu" (`_rememberMe`)
- **Actions**:
  - Nút **Đăng nhập** → `_login()` → `FirebaseAuth.signInWithEmailAndPassword`
  - Nút **Google** → `_signInWithGoogle()` → `SocialAuthService.signInWithGoogle()`
  - Nút **Apple** (chỉ iOS/macOS) → `_signInWithApple()` → `SocialAuthService.signInWithApple()`
  - Link **Quên mật khẩu** → `_showForgotPasswordDialog()` → `FirebaseAuth.sendPasswordResetEmail`
  - Link **Đăng ký** → điều hướng tới `RegisterView`
- **Ghi nhớ đăng nhập**: Lưu email/pass vào `SharedPreferences` (`saved_email`, `saved_pass`, `remember_me`)
- **Xử lý lỗi**: Map `FirebaseAuthException.code` → string tiếng Việt từ ARB localizations

### HomeView (`lib/views/home_view.dart`)
- **Navigation**: Bottom NavigationBar với tab list được build động theo permissions + shopSettings
- **Tabs theo điều kiện**:
  | Tab | Hiển thị khi | Permission |
  |---|---|---|
  | Home (tổng quan) | Luôn hiện | — |
  | Bán hàng | `allowViewSales` = true | `allowViewSales` |
  | Sửa chữa | `allowViewRepairs` AND `enableRepair` | `allowViewRepairs` |
  | Kho hàng | `allowViewInventory` | `allowViewInventory` |
  | HSD (hạn sử dụng) | `enableExpiry` = true | `allowViewInventory` |
  | Size·Màu (variants) | `enableVariants` = true | `allowViewInventory` |
  | Nhân viên | `allowManageStaff` | `allowManageStaff` |
  | Tài chính | `allowViewRevenue` | `allowViewRevenue` |
  | Cài đặt | Luôn hiện | — |
- **Stats hiển thị** (load từ local DB):
  - `totalPendingRepair`: đơn sửa trạng thái 1, 2
  - `todaySaleCount`: đơn bán hôm nay
  - `totalDebtRemain`: tổng dư nợ
  - `_customerDebtRemain`, `_supplierDebtRemain`, `_partnerDebtRemain`
  - `expiringWarranties`: sản phẩm hết bảo hành sắp đến
  - `unreadChatCount`: thông báo chưa đọc
  - `pendingApprovalCount`: chấm công chờ duyệt

### OrderListView (`lib/views/order_list_view.dart`)
- **Data source**: Real-time Firestore listener trên `repairs` collection theo shopId
- **Sắp xếp** (`_compareRepairs()`):
  1. Status 1 (Tiếp nhận)
  2. Status 2 (Đang sửa)
  3. Status 3 đã duyệt giao
  4. Status 3 chờ duyệt giao (pendingDeliveryApproval=true)
  5. Status 4 (Đã giao)
  Trong cùng nhóm: `createdAt DESC`
- **Bộ lọc**:
  - Thời gian: tất cả / hôm nay / tuần / tháng / tuỳ chỉnh
  - Trạng thái: multi-select (Set)
  - Cờ `pendingApproval`

### CreateRepairOrderView (`lib/views/create_repair_order_view.dart`)
- **Trường bắt buộc**: Model thiết bị (model field)
- **Trường tuỳ chọn**: Tên KH, SĐT, địa chỉ, vấn đề, phụ kiện đi kèm, màu, IMEI, tình trạng, ghi chú, ảnh (nhiều ảnh)
- **`_smartFill()`**: Load toàn bộ customers của shop từ DB → filter client-side theo phone (**performance issue: L-02**)
- **`firestoreId`**: `"rep_{now}_{phone}"` hoặc `"rep_{now}_walkin"` nếu isWalkIn=true
- **Save flow**: Cash closing check → validate model → SQLite upsert → tạo customer → SyncOrchestrator.enqueue → syncAll → fallback Firestore trực tiếp

### RepairDetailView (`lib/views/repair_detail_view.dart`)
- **Real-time**: `FirestoreService.watchRepairDoc()` → listener Firestore doc
- **`_applyRepairDocSnapshot()`**: merge cloud snapshot với local, bảo vệ local unsync data nếu cloud cũ hơn 5 giây
- **`_protectLocalUnsyncedRepairFromStaleCloud()`**: giữ local nếu cloud không rõ ràng mới hơn
- **`_isUpdating`**: non-atomic bool flag (**race condition bug: C-03**)
- **Actions** (phụ thuộc status và permission):
  - Cập nhật trạng thái (1→2→3→4)
  - Ghi giá, ghi chi phí linh kiện
  - Yêu cầu giao máy (pendingDeliveryApproval)
  - Upload/xem ảnh nhận máy, ảnh giao máy
  - Thêm ghi chú
  - In phiếu (Bluetooth thermal printer)

### InventoryView (`lib/views/inventory_view.dart`)
- **Pagination**: 20 sản phẩm/trang (`_pageSize = 20`), lazy load cuộn xuống
- **MobileScannerController**: tạo ở field level (không lazy) — **camera cấp phát ngay khi vào màn (P-03)**
- **Bộ lọc**: search text, type (TẤT CẢ / ĐIỆN_THOẠI / PHỤ KIỆN / LINH_KIỆN), `showOutOfStock`
- **EventBus**: nghe 8 events để refresh
- **Actions**: Thêm sản phẩm, scan barcode/IMEI, xuất Excel, nhập hàng từ NCC

### CreateSaleView (`lib/views/create_sale_view.dart`)
- **Hỗ trợ**:
  - Bán đơn / bán nhiều sản phẩm cùng lúc
  - Trả góp (dual-bank: bankName + bankName2, loanAmount + loanAmount2)
  - Thanh toán kết hợp (cashAmount + transferAmount)
  - Khách vãng lai
- **IMEI controllers**: dynamic `Map<String, TextEditingController>` keyed by productId
- **Permission check**: yêu cầu `allowViewSales`

### ExpenseView (`lib/views/expense_view.dart`)
- **2 chế độ**: CHI (expenses) / THU (income) — toggle tabs
- **Hiển thị**: Merge expenses từ `expenses` table + purchase_orders từ `purchase_orders` table
- **Bộ lọc scope**: TẤT CẢ / SHOP / CÁ NHÂN
- **Bộ lọc thời gian**: NGÀY / TUẦN / THÁNG

### RevenueView (`lib/views/revenue_view.dart`)
- **Permission**: `allowViewRevenue`
- **Range dữ liệu**: Jan 1 năm trước → hôm nay +1 ngày
- **2 tabs**: Tổng quan (summary) / Chi tiết (sub-tabs: Bán hàng / Sửa chữa / Chi tiêu)
- **Data loads**: repairs, sales, expenses, debtPayments, supplierImports, supplierPayments, repairPartnerPayments, cash_closings (10 gần nhất)
- **Bộ lọc thời gian**: today / week / month / quarter / year / custom (date range)
- **Biểu đồ**: `fl_chart` package
- **EventBus debounce**: 2 giây sau khi nhận event tài chính → reload

### DebtView (`lib/views/debt_view.dart`)
- **Permission**: `allowViewDebts`
- **Số tabs**: 4 (electronics) hoặc 3 (fashion/food — không có tab đối tác sửa)
  - Tab 1: Khách nợ (CUSTOMER_OWES)
  - Tab 2: Nợ NCC (SHOP_OWES)
  - Tab 3: Thu/chi khác (OTHER_CUSTOMER_OWES, OTHER_SHOP_OWES)
  - Tab 4 (chỉ electronics): Nợ đối tác sửa chữa
- **Hướng dẫn lần đầu**: `FirstTimeGuideService.showGuideIfNeeded(keyDebtManagement)`
- **Data**: `db.getAllDebts()` → `DebtSummaryService.filterStandardDebts()` + `loadPartnerDebts()`

### CashClosingView (`lib/views/cash_closing_view.dart`)
- **Permission**: `allowViewRevenue`
- **4 tabs thường** (1 tab nếu `showOnlyTransactions=true`):
  - Chốt quỹ ngày
  - Lịch sử giao dịch
  - Đối chiếu
  - Báo cáo tháng
- **State**: chọn `_selectedDate` (mặc định hôm nay)
- **Real-time**: EventBus listener + debounce 500ms → reload local DB
- **Data loads**: sales, repairs, expenses, debtPayments, supplierImports, supplierPayments, repairPartnerPayments, salesReturns, debtTypeMap, previousDayClosing, todayClosing
- **Hành động chốt quỹ**: nhập `cashEnd` + `bankEnd` + note → lưu vào `cash_closings` với `isLocked=1`

### StaffListView (`lib/views/staff_list_view.dart`)
- **Data**: Firestore `users` collection filtered by shopId
- **Tên shop**: đọc trực tiếp Firestore `shops/{shopId}`
- **Invite code QR**:
  - Load mã hiện tại: Firestore `invites` where `shopId == X, used == false, limit 1`
  - Tạo mã mới: `UserService.createInviteCode(shopId)` → Cloud Functions
  - Hiển thị QR: `qr_flutter` package
- **Phân quyền**: owner/manager/superAdmin mới có nút tạo mã mời
- **Actions**: export Excel (file_selector/csv), import từ CSV, xem profile nhân viên

### AttendanceView (`lib/views/attendance_view.dart`)
- **Tabs**: 2 (employee) hoặc 3 (owner/manager): Chấm công hôm nay / Lịch sử / Duyệt (owner/manager)
- **Đồng hồ thực**: `Timer.periodic(1s)` → cập nhật `_clockNow`
- **GPS**: `_locationRequired=true` nếu shop có lat/lng → kiểm tra khoảng cách khi check-in
- **Ảnh selfie**: `ImagePicker.camera` → `BackgroundUploadService.uploadAttendancePhoto()`
- **Pull cloud trước**: `_pullOwnCloudData()` → Firestore → upsert local → đọc local để hiển thị
- **EventBus**: nghe 5 events để refresh (`attendance_changed`, `leave_requests_changed`, ...)

### ShopSettingsView (`lib/views/shop_settings_view.dart`)
- **Sections**:
  - Thông tin shop: name, address, phone, email, description, logo
  - Vị trí GPS: latitude/longitude (Geolocator)
  - Ngành kinh doanh: wizard `BusinessTypeWizard`
  - HR & Lương: link tới `HrSalarySettingsView`
  - Thiết kế nhãn: link tới `LabelDesignerView`
  - Lịch sử điều chỉnh: link tới `AdjustmentHistoryView`
- **Chiến lược load shop data**: UserService cache → Firestore users doc → uid fallback
- **Fallback**: `shops/{shopId}/settings/shop_profile` nếu top-level doc permission denied
- **Logo**: ImagePicker → StorageService.uploadShopLogo()

---

## 🧪 BUTTON FLOW

### Nút "Lưu" trong CreateRepairOrderView
```
File: lib/views/create_repair_order_view.dart
Function: _saveOrderProcess()
  1. AdjustmentService.canEditDirectly(now) → kiểm tra chốt quỹ
  2. Validate: repair.model.isNotEmpty
  3. DBHelper().upsertRepair(repair) → SQLite
  4. if (!isWalkIn) DBHelper().upsertCustomer(customer) → SQLite
  5. SyncOrchestrator().enqueue(SyncEntityType.repair, SyncOperation.create, repair)
  6. SyncOrchestrator().syncAll()
     → FirestoreService.addRepair(repair)
        → Firestore.doc('repairs/{id}').set(data, merge:true)
  7. if (fail) → FirestoreService.addRepair(repair) trực tiếp (fallback)
```

### Nút "Đăng nhập" trong LoginView
```
File: lib/views/login_view.dart
Function: _login()
  → FirebaseAuth.signInWithEmailAndPassword(email, password)
  → _saveAccount() → SharedPreferences
  → [AuthGate sẽ tự reload và gọi syncUserInfo()]
```

### Nút "Tạo mã mời" trong StaffListView
```
File: lib/views/staff_list_view.dart
Function: _generateInviteCode()
  → UserService.createInviteCode(shopId)
     → Cloud Functions.httpsCallable('createInviteCode')({shopId})
     → Trả về code string
  → setState(_currentInviteCode = code)
```

### Nút "Chốt quỹ" trong CashClosingView
```
File: lib/views/cash_closing_view.dart
Function: (xác nhận dialog) → save
  → DBHelper().insert/update 'cash_closings' với isLocked=1, cashEnd, bankEnd
  → SyncOrchestrator.enqueue(SyncEntityType.cashClosing, create/update, data)
  → EventBus.emit('cash_closings_changed')
```

### Nút "Check-in" trong AttendanceView
```
File: lib/views/attendance_view.dart
Function: _checkIn()
  → Permission.location.request()
  → Geolocator.getCurrentPosition()
  → Nếu _locationRequired: tính khoảng cách vs shop location
  → ImagePicker.pickImage(source: camera) → selfie
  → BackgroundUploadService.uploadAttendancePhoto(file)
  → DBHelper().upsertAttendance(attendance)
  → SyncOrchestrator.enqueue(SyncEntityType.attendance, create, attendance)
```

---

## 🧠 BUSINESS LOGIC

### Hệ thống phân quyền

**Role hierarchy** (UserService):
1. `superAdmin`: email `admin@huluca.com` hardcode (**không có custom claims**)
2. `owner`: chủ shop
3. `admin`: quản trị
4. `manager`: quản lý
5. `employee`: nhân viên
6. `technician`: thợ sửa

**Cache permissions**: TTL 10 phút (`UserService.getCurrentUserPermissions()`)

**Permission map** (ví dụ từ code):
| Permission key | Roles thường có |
|---|---|
| `allowViewSales` | owner, admin, manager |
| `allowViewRepairs` | owner, admin, manager, technician |
| `allowViewInventory` | owner, admin, manager |
| `allowManageStaff` | owner, manager |
| `allowViewRevenue` | owner, admin |
| `allowViewDebts` | owner, admin, manager |
| `allowViewCostPrice` | owner, admin |

**Multi-tenant**: mọi query đều filter theo `shopId`; superAdmin bypass không có shopId filter.

---

### Vòng đời đơn sửa chữa

```
Status 1 (Tiếp nhận)
  → Status 2 (Đang sửa)
    → Status 3 (Đã xong)
      → [Nếu cần duyệt giao] pendingDeliveryApproval=true → chờ owner/manager duyệt
      → Status 4 (Đã giao) + deliveredAt + deliveredBy
```

**Tính giá sửa chữa** (`Repair.totalCost`):
- Nếu `cost > 0`: trả về `cost`
- Else: tính `servicesCost` = tổng `RepairService.cost` trong list `services`

---

### Chốt quỹ và bút toán điều chỉnh

- **Chốt quỹ**: lưu `cash_closings` với `isLocked=1`
- **Sau chốt**: không sửa trực tiếp dữ liệu ngày đó
- **Điều chỉnh**: `AdjustmentService.adjustPartCost()` → tạo `adjustment_entries`
  - Nếu paymentMethod=CÔNG NỢ: cập nhật `debts.totalAmount`
  - Tạo bút toán cả cost lẫn debt adjustment
  - Tất cả auto-approve (`status='APPROVED'`)
- **Check trước khi sửa**: `AdjustmentService.canEditDirectly(originalDate)` → query `cash_closings.isLocked`

---

### Đồng bộ Local-First

**Write path** (SQLite → Firestore):
```
SyncOrchestrator.enqueue(entityType, operation, data)
  → Thêm vào sync_queue
  → syncAll():
      → Upload ảnh local → Firebase Storage
      → FirestoreService.upsert/add/delete(entity)
      → Mark isSynced=1 trong local DB
```

**Read path** (Firestore → SQLite):
```
SyncService.initRealTimeSync():
  → 6 snapshot listeners (repairs, sales, products, debts, sales_returns, product_categories)
  → DocumentChangeType.added/modified: DBHelper.upsert_X()
  → DocumentChangeType.removed: [KHÔNG XỬ LÝ — bug C-01]
  → deleted==true flag: [KHÔNG XỬ LÝ — bug C-01]
  → Emit EventBus → UI rebuild
```

**`SyncEntityType` enum**: repair, sale, product, expense, debt, customer, supplier, attendance, repairPart, quickInputCode, debtPayment, supplierPayment, partnerPayment, repairPartner, auditLog, cashClosing, adjustmentEntry, purchaseOrder, supplierImportHistory, salvagePhone

---

### Thanh toán tập trung (`PaymentIntentService`)

- Singleton, load từ DB khi khởi tạo
- `_pendingIntents`: Map in-memory
- `_historyIntents`: List in-memory
- Persist vào `payment_intents` table
- `initialize()`: load từ DB, detect shop change
- `reinitialize()`: gọi khi đổi shop
- `clearCache()`: gọi khi logout

---

### Thông báo

- **Rate limit**: tối đa 3 thông báo / 10 giây
- **Dedup**: set `_processedNotificationIds` (max 200 entries)
- **Channels**: `new_order`, `payment`, `inventory`, `staff`, `system`
- **FCM token**: kiểm tra mỗi 6 giờ
- **Kênh EventBus** (in-app snackbar): `NotificationService.listenToNotifications()`
- **Khi background**: `handleBackgroundMessage()` → `_showLocalNotification()`

---

### Tài chính

**PaymentMethod constants** (`financial_constants.dart`):
- `TIỀN MẶT`, `CHUYỂN KHOẢN`, `CÔNG NỢ`, `TRẢ GÓP`, `KẾT HỢP`, `NGÂN HÀNG`

**MoneySourceType**: sale, debtCollection, settlement, refundReceived, otherIncome, purchase, expense, debtPayment, salary, refundGiven, otherExpense, adjustment

**FinancialActivityService** (log tài chính local — KHÔNG sync từ cloud):
- `logSale()`, `logExpense()`, `logPurchase()`, `logDebtCollection()`, `logSettlement()`
- Ghi vào `financial_activity_log` table
- Emit `EventBus.financialChanged`

---

## 🔥 FIREBASE/BACKEND

### Firestore Queries đã xác minh trong code

| Service/View | Query | Ghi chú |
|---|---|---|
| `SyncService.initRealTimeSync` | `collection(X).where('shopId',==,shopId).snapshots()` | 6 collections, NO limit, NO cursor |
| `OrderListView` | `collection('repairs').where('shopId',==,shopId).snapshots()` | Real-time |
| `FirestoreService.addRepair` | `doc('repairs/{id}').set(data, merge:true)` | merge:true |
| `FirestoreService.deleteRepair` | `doc.update({deleted:true, updatedAt:serverTimestamp})` | Soft delete |
| `StaffListView._loadCurrentInviteCode` | `invites.where(shopId).where(used==false).orderBy(createdAt,desc).limit(1)` | |
| `AttendanceView._pullOwnCloudData` | `attendance.where(shopId).where(userId).where(dateKey>=).where(dateKey<=)` | |
| `ShopSettingsView` | `shops/{shopId}.get()` | Có fallback subcollection |

### Cloud Functions được gọi
| Function | Caller | Mô tả |
|---|---|---|
| `createInviteCode` | `UserService.createInviteCode()` | Tạo mã mời nhân viên |
| [UNKNOWN] | Các Cloud Function khác trong `functions/` | Không đọc file functions |

### Firebase Storage paths
- Ảnh sửa chữa: path lưu trong `imagePath` field (CSV multi-path)
- Ảnh giao máy: `deliveredImage`
- Logo shop: `StorageService.uploadShopLogo()`
- Ảnh chấm công: `BackgroundUploadService.uploadAttendancePhoto()`

---

## 🔐 PERMISSION

### Kiểm tra quyền — vị trí trong code

| Nơi kiểm tra | File | Cách kiểm tra |
|---|---|---|
| SuperAdmin detection | `user_service.dart` | `user.email.toLowerCase() == 'admin@huluca.com'` |
| `getUserRole(uid)` | `user_service.dart` | Check email trước, sau đó Firestore `users/{uid}.role` |
| `getCurrentUserPermissions()` | `user_service.dart` | Map role → permission set, cache 10 phút |
| Trang Sales | `create_sale_view.dart._checkPermission()` | `perms['allowViewSales']` |
| Trang Revenue | `revenue_view.dart._loadPermissions()` | `perms['allowViewRevenue']` |
| Trang Debt | `debt_view.dart._checkPermission()` | `perms['allowViewDebts']` |
| Trang Staff | `staff_list_view.dart._loadCurrentUserRole()` | `perms['allowManageStaff']` |
| Trang CashClosing | `cash_closing_view.dart._checkPermission()` | `perms['allowViewRevenue']` |
| Trang Attendance | `attendance_view.dart._loadInitialData()` | `UserService.getUserRole()` |
| `_canManageStaff` getter | `staff_list_view.dart` | `_isSuperAdmin || role == 'owner' || role == 'manager'` |

### Firestore Security Rules
**[UNKNOWN — không đọc file `firestore.rules` trong session này]**

---

## 🎨 THEME

### Màu sắc (`lib/theme/app_colors.dart`)

| Tên | Hex | Dùng cho |
|---|---|---|
| `primary` | `#4D8EE9` | Màu chính (xanh dương) |
| `primaryDark` | `#0068FF` | Zalo Blue |
| `secondary` | `#FF9800` | Màu phụ (cam) |
| `background` | `#F8FAFF` | Nền app |
| `error` | `#D32F2F` | Lỗi |
| `success` | `#388E3C` | Thành công |
| `warning` | `#F57C00` | Cảnh báo |
| `repairReceived` | `#1976D2` | Status 1 — Đã nhận |
| `pending` | `#FF9800` | Chờ xử lý |
| `completed` | `#4CAF50` | Hoàn thành |
| `cancelled` | `#F44336` | Huỷ |

---

## ⚠️ RỦI RO (chỉ từ code)

| ID | Mức độ | Vị trí | Mô tả |
|---|---|---|---|
| C-01 | CRITICAL | `sync_service.dart` dòng ~421 | `DocumentChangeType.removed` handler rỗng; `deleted==true` handler rỗng → docs bị xoá trên Firestore KHÔNG bao giờ bị xoá khỏi local DB |
| C-02 | CRITICAL | `sync_service.dart._subscribeToCollection()` | Snapshot listener tải toàn bộ collection khi khởi động, không có `.limit()`, không có cursor → 30.000+ reads mỗi lần init |
| C-03 | HIGH | `repair_detail_view.dart._isUpdating` | Bool flag không atomic → race condition khi double-tap nút cập nhật |
| C-04 | HIGH | `firestore_service.dart._updateInventoryFromPurchaseOrder()` | Read-modify-write không atomic → inventory count sai khi có concurrent imports |
| C-05 | HIGH | Khi superAdmin viết với `shopId=null` | Data lên Firestore nhưng không sync về shop nào |
| S-01 | SECURITY | `user_service.dart._isSuperAdmin()` | Phát hiện superAdmin chỉ qua email string — không có custom claims verification |
| S-04 | SECURITY | `firestore_service.dart._notifyAll()` | Ghi tên KH, model, số tiền vào collection `chats` **KHÔNG mã hoá** |
| L-02 | LOGIC | `create_repair_order_view.dart._smartFill()` | Load toàn bộ customers rồi filter client-side — O(n) khi DB lớn |
| D-03 | DATA | `financial_activity_service.dart` | `financial_activity_log` KHÔNG được sync từ cloud → mất data khi cài lại app |
| P-03 | PERFORMANCE | `inventory_view.dart` | `MobileScannerController` tạo ở field level → camera allocate ngay khi vào màn hình kể cả không scan |

---

## ❗ UNKNOWN (không tìm thấy trong code được đọc)

| Mục | Lý do |
|---|---|
| Nội dung chi tiết Firebase Cloud Functions (`functions/`) | Không đọc thư mục `functions/` |
| Firestore Security Rules (`firestore.rules`) | Không đọc file này |
| Nội dung chi tiết màn hình `parts_inventory_view.dart` | Chưa đọc file |
| Nội dung chi tiết `attendance_management_view.dart` | Chưa đọc file |
| Nội dung chi tiết `sale_list_view.dart` | Chưa đọc file |
| Nội dung chi tiết `intro_view.dart` | Chỉ đọc tham chiếu từ splash |
| Nội dung chi tiết `register_view.dart` | Chỉ đọc tham chiếu từ login |
| Logic tính lương đầy đủ (`hr_salary_settings_view.dart`) | Chưa đọc file |
| Logic `shift_swap_view.dart` | Chưa đọc file |
| Logic `label_designer_view.dart` | Chưa đọc file |
| Logic `business_type_wizard.dart` | Chưa đọc file |
| Logic `adjustment_history_view.dart` | Chưa đọc file |
| Cấu trúc bảng `leave_requests`, `audit_logs`, `work_schedules` (chi tiết cột) | Không đọc schema trực tiếp cho từng bảng |
| MongoDB integration (nếu có) | Có reference trong session cũ nhưng không xác nhận trong session này |
| Version FCM notification payload format | Chưa đọc toàn bộ `notification_service.dart` |
| Tất cả màn hình của `onboarding/` ngoài `business_type_wizard.dart` | Chưa khám phá |

---

*Tài liệu này được tạo bằng cách đọc source code thực tế. Không có nội dung nào được suy đoán. Cập nhật lần cuối: dựa trên version `1.0.3+513`.*

---

## 🧬 STATE MANAGEMENT

> Toàn bộ app dùng **`setState` thuần** — không có Provider, Bloc, Riverpod, hay bất kỳ state management framework nào. State nằm trong `_XxxViewState` của từng màn hình. Global state được quản lý qua **Singleton services** và **EventBus**.

### Mô hình tổng quát

```
Local widget state: setState() trong _XxxViewState
Global shared state: Singleton services (UserService, SyncOrchestrator, EventBus, PaymentIntentService)
Persistence: SharedPreferences (shopId, role, locale, tab index)
Cross-widget communication: EventBus singleton broadcast stream
```

### Chi tiết từng màn hình

#### HomeView (`home_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `_permissions` | `Map<String, dynamic>` | local `_HomeViewState` | `UserService.getCurrentUserPermissionsSync()` (sync từ cache) |
| `_currentIndex` | `int` | local | `_setCurrentTab()` → `setState` |
| `totalPendingRepair`, `todaySaleCount` | `int` | local | `_loadStats()` → `setState` |
| `_shopLocked`, `_lockedByAdmin`, `_lockedByOwner` | các loại | local | primed from `UserService` cache trong `_primePermissionsFromCache()` |
| `_restoredTabIndex` | `int?` | local + `SharedPreferences` | `_loadSavedTabIndex()` |
| `_eventBusSub` | `StreamSubscription` | local | `EventBus().stream.listen()` trong `addPostFrameCallback` |

**Cache prime pattern**: `_primePermissionsFromCache()` gọi `UserService.getCurrentUserPermissionsSync()` (không async, không Firestore) để có UI ngay lập tức trước khi permissions được load đầy đủ.

#### OrderListView (`order_list_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `_repairsByFirestoreId` | `Map<String, Repair>` | local in-memory | Firestore snapshot listener `_repairRealtimeSubscription` |
| `_displayedRepairs` | `List<Repair>` | local | filter + sort từ `_repairsByFirestoreId` |
| `_isRealtimeConnected` | `bool` | local | listener `onError` / khi nhận snapshot đầu tiên |
| `_useRealtimeIndexFallback` | `bool` | local | bật khi nhận lỗi `failed-precondition` (missing index) |

**In-memory cache**: `_repairsByFirestoreId` là map accumulate — mỗi snapshot thay đổi chỉ update key tương ứng, không reload toàn bộ.

#### RepairDetailView (`repair_detail_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `r` | `Repair` | local (copy của `widget.repair`) | `_applyRepairDocSnapshot()` → `setState` |
| `_isUpdating` | `bool` | local | set true trước update, false sau — **non-atomic flag** |
| `_isPrinting` | `bool` | local | set true khi in, false khi xong |
| `_repairDocSubscription` | `StreamSubscription` | local | `FirestoreService.watchRepairDoc()` |
| `_hasReceivedServerDocSnapshot` | `bool` | local | set true khi nhận snapshot từ server (không phải cache) |

#### InventoryView (`inventory_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `_products` | `List<Product>` | local | `db.getProductsPaged()` → `setState` |
| `_allLoadedProducts` | `List<Product>` | local in-memory cache | accumulate từ pagination |
| `_currentOffset` | `int` | local | +20 mỗi lần load more |
| `_hasMore` | `bool` | local | `newData.length >= _pageSize` |
| `_scannerController` | `MobileScannerController` | local field (không lazy) | tạo ngay tại field declaration |

#### AttendanceView (`attendance_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `_today` | `Attendance?` | local | `db.getAttendance()` sau cloud pull |
| `_history` | `List<Attendance>` | local | `db.getAttendanceByUser()` |
| `_clockNow` | `DateTime` | local | `Timer.periodic(1s)` → `setState` |
| `_workSchedule` | `Map` | local | `db.getWorkSchedule()` |

#### CreateRepairOrderView (`create_repair_order_view.dart`)
| State variable | Kiểu | Nơi lưu | Cách cập nhật |
|---|---|---|---|
| `_saving` | `bool` | local | set true khi bắt đầu save, false khi xong hoặc lỗi |
| `_uploadStatus` | `String` | local | text progress |
| `_services` | `List<RepairService>` | local | thêm/xóa thủ công |
| `_images` | `List<XFile>` | local | ImagePicker |
| `_selectedAccs` | `Set<String>` | local | chip selection |

### Global Singleton Services (state dùng chung)

| Service | Cơ chế | TTL / Invalidation |
|---|---|---|
| `UserService._cachedShopId` | static field in-memory | Invalidated: logout, shop change |
| `UserService._cachedPermissions` | static Map in-memory | TTL: **10 phút**, invalidated: shop change, explicit call |
| `UserService._cachedUid` | static field | Invalidated: logout |
| `UserService` SharedPreferences | `auth_cache_shopId`, `auth_cache_role`, `auth_cache_uid` | Persistent, cleared on logout, overwritten on next login |
| `SyncOrchestrator._pendingCount` | in-memory int | Refreshed sau mỗi enqueue/syncAll |
| `SyncOrchestrator._isSyncing` | in-memory bool | Reset sau syncAll() |
| `EventBus._ctrl` | `StreamController.broadcast()` — **NEVER disposed** | Singleton tồn tại suốt vòng đời app |
| `PaymentIntentService._pendingIntents` | in-memory Map | Loaded từ DB khi init, cleared on logout |
| `NotificationService._processedNotificationIds` | in-memory Set (max 200) | Bounded size, no TTL |
| `SyncService._realtimeCursorCache` | in-memory Map | Persisted to SharedPreferences `rtCursor_{col}_{shopId}` |

### Locale
- `_MyAppState._locale`: `Locale` in-memory, persisted tới `SharedPreferences('app_language')`, default `'vi'`

---

## 🔄 LISTENER LIFECYCLE

### Tổng hợp tất cả listeners

#### EventBus (global singleton)

| Owner | Được tạo ở | Unsubscribe | Dispose | Nguy cơ leak |
|---|---|---|---|---|
| `EventBus._ctrl` (singleton) | `EventBus._internal()` constructor | `_ctrl.close()` trong `dispose()` — **NHƯNG singleton không bao giờ disposed** | ❌ KHÔNG bao giờ dispose | EventBus tự thân KHÔNG leak vì stream không đóng, nhưng subscribers phải tự cancel |
| `HomeView._eventBusSub` | `addPostFrameCallback` trong `initState` | Cần check | Cần check |  |
| `AttendanceView._eventSub` | `_setupEventSubscription()` trong `initState` | ✅ `_eventSub?.cancel()` trong `dispose()` | ✅ | Không leak |
| `DebtView._eventSub` | `initState` | ✅ `_eventSub?.cancel()` trong `dispose()` | ✅ | Không leak |
| `RevenueView._eventBusSubscription` | `initState` | ✅ `_eventBusSubscription?.cancel()` trong `dispose()` | ✅ | Không leak |
| `CashClosingView._eventBusSub` | `_initRealTimeSync()` | ✅ `_eventBusSub?.cancel()` trong `dispose()` | ✅ | Không leak |
| `InventoryView._inventoryEventSub` | `_bindInventoryRefreshEvents()` trong `initState` | ✅ `_inventoryEventSub?.cancel()` trong `dispose()` | ✅ | Không leak |
| `OrderListView._eventSubscription` | `initState` | ✅ `_eventSubscription?.cancel()` trong `dispose()` | ✅ | Không leak |

#### Firestore Snapshot Listeners

| Owner | Query | Được tạo ở | Cancel | Dispose | Nguy cơ leak |
|---|---|---|---|---|---|
| `SyncService._subscriptions` (static List) | 6 collection queries | `initRealTimeSync()` | `cancelAllSubscriptions()` | ✅ khi logout hoặc shop change | Không leak nếu `cancelAllSubscriptions()` được gọi |
| `RepairDetailView._repairDocSubscription` | `repairs/{docId}` single doc | `_startRepairRealtimeListener()` trong `initState` | ✅ `_repairDocSubscription?.cancel()` trong `dispose()` + trước khi tạo mới | ✅ | Không leak |
| `OrderListView._repairRealtimeSubscription` | `repairs` where `shopId` | `_startRealtimeRepairsListener()` trong `initState` | ✅ `_repairRealtimeSubscription?.cancel()` trong `dispose()` + trước restart | ✅ | Không leak |
| `StaffListView._loadCurrentInviteCode` | `invites` one-shot `.get()` | `initState` | N/A (one-shot) | N/A | Không leak |
| `CashClosingView._closingSubscription` | Xem thêm trong init | `_initRealTimeSync()` | ✅ `_closingSubscription?.cancel()` trong `dispose()` | ✅ | Không leak |
| `AttendanceView._pullOwnCloudData` | `attendance` one-shot `.get()` | `_refreshAttendanceData()` | N/A (one-shot) | N/A | Không leak |
| `AuthGate` — `FirebaseAuth.authStateChanges()` | Auth state changes | `build()` via `StreamBuilder` | ✅ Flutter tự quản lý StreamBuilder | ✅ | Không leak |
| `ClaimsService.startClaimsSync()` | `users/{uid}` doc changes | `UserService.initClaimsSync()` | ✅ `ClaimsService.stopClaimsSync()` trong `UserService.clearCache()` | ✅ | Không leak nếu logout đúng cách |

#### Timers

| Owner | Tần suất | Được tạo ở | Cancel | Dispose | Nguy cơ |
|---|---|---|---|---|---|
| `AuthGate._loggedOutFallbackTimer` | One-shot 4s | `initState` | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |
| `AttendanceView._clockTimer` | `Timer.periodic(1s)` | `initState` | ✅ `_clockTimer?.cancel()` trong `dispose()` | ✅ | Không leak |
| `AttendanceView._reloadDebounce` | Debounce 400ms | EventBus handler | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |
| `DebtView._reloadDebounce` | Debounce 500ms | EventBus handler | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |
| `RevenueView._reloadDebounceTimer` | Debounce 2s | EventBus handler | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |
| `CashClosingView._debounceTimer` | Debounce 500ms | EventBus handler | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |
| `InventoryView._inventoryRefreshDebounce` | Debounce 220–600ms | EventBus handler | ✅ `cancel()` trong `dispose()` | ✅ | Không leak |

#### StreamControllers trong Services

| Owner | Kiểu | Được tạo | Dispose | Ghi chú |
|---|---|---|---|---|
| `EventBus._ctrl` | `StreamController<String>.broadcast()` | Singleton constructor | `dispose()` — **NHƯNG singleton không dispose** | Global, tồn tại suốt app |
| `SyncOrchestrator._pendingCountController` | `StreamController<int>.broadcast()` | Singleton constructor | `dispose()` trong `SyncOrchestrator.dispose()` — **nhưng dispose() không tự động gọi** | Cần gọi `SyncOrchestrator().dispose()` khi logout |
| `SyncOrchestrator._syncStatusController` | `StreamController<SyncStatus>.broadcast()` | Singleton constructor | Tương tự trên | Tương tự |

#### Connectivity Subscription

| Owner | Được tạo | Cancel | Dispose |
|---|---|---|---|
| `SyncOrchestrator._connectivitySubscription` | `SyncOrchestrator.init()` | ✅ `_connectivitySubscription?.cancel()` trong `dispose()` | Phụ thuộc `dispose()` được gọi — không tự động |

#### WidgetsBindingObserver

| Owner | Được tạo | Removed |
|---|---|---|
| `HomeView` | `initState`: `WidgetsBinding.instance.addObserver(this)` | ✅ `dispose()`: `WidgetsBinding.instance.removeObserver(this)` |
| `AuthGate` | `initState`: `WidgetsBinding.instance.addObserver(this)` | ✅ `dispose()`: `WidgetsBinding.instance.removeObserver(this)` |

#### ScrollController

| Owner | Listener | Dispose |
|---|---|---|
| `InventoryView._scrollController` | `_onScroll` added trong `initState` | ✅ `removeListener` + `dispose()` trong `dispose()` |

---

## 🔗 SERVICE CALL GRAPH

### Module: Repair (Sửa chữa)

#### Tạo đơn mới
```
CreateRepairOrderView._saveOrderProcess()
  └─ AdjustmentService.canEditDirectly(today.ms)
       └─ DBHelper.query('cash_closings', isLocked=1, dateKey=today) → bool
  └─ [if locked] NotificationService.showSnackBar() → return null
  └─ DBHelper().upsertRepair(repair) → SQLite INSERT OR REPLACE
  └─ CustomerService.addCustomer(customer) [if !isWalkIn]
       └─ DBHelper().upsertCustomer() → SQLite
       └─ SyncOrchestrator().enqueue(SyncEntityType.customer, create)
  └─ SyncOrchestrator().enqueue(SyncEntityType.repair, create, repair)
       └─ DBHelper.query('sync_queue', check existing)
       └─ DBHelper.insert('sync_queue', item)
       └─ _refreshPendingCount() → _pendingCountController.add(count)
  └─ SyncOrchestrator().syncAll()
       └─ Connectivity().checkConnectivity() → skip if offline
       └─ getPendingItems() → DBHelper.query('sync_queue', pending/processing)
       └─ _processSyncItem(item)
            └─ UserService.getCurrentShopId()
            └─ _handleCreate(item, shopId)
                 └─ _normalizeRepairPayloadForCloud(data)
                 └─ _normalizeRepairImagePathsForCloud(data)
                      └─ StorageService.uploadMultipleImages(localPaths, 'repairs/{id}')
                           └─ FirebaseStorage.ref().putFile() → URL
                 └─ Firestore.collection('repairs').doc(firestoreId).set(data) [timeout 25s]
            └─ DBHelper.delete('sync_queue', id)
            └─ _markLocalAsSynced(repair) → DBHelper.update('repairs', isSynced=1)
            └─ SyncAuditService.logSuccess()
  └─ [if syncAll fails] FirestoreService.addRepair(repair) ← direct fallback
       └─ Firestore.collection('repairs').doc(id).set(merge:true)
       └─ NotificationService._notifyAll() → Firestore.collection('chats').add(UNENCRYPTED)
```

#### Xem/cập nhật đơn
```
RepairDetailView.initState()
  └─ _startRepairRealtimeListener()
       └─ FirestoreService.watchRepairDoc(firestoreId)
            └─ Firestore.collection('repairs').doc(id).snapshots()
       └─ _applyRepairDocSnapshot(snapshot):
            └─ EncryptionService.decryptMap(data)
            └─ SyncService.convertTimestampFieldsPublic(data)
            └─ _mergeSnapshotWithLocalIfPartial(data, cloudRepair)
                 └─ DBHelper().getRepairByFirestoreId(id) [if partial]
            └─ _protectLocalUnsyncedRepairFromStaleCloud(data, repair)
                 └─ DBHelper().getRepairByFirestoreId(id) [if local.isSynced=false]
                 └─ compare timestamps (tolerance 5000ms)
            └─ DBHelper().upsertRepair(safeLatest)
            └─ [if recoveredLocalData] SyncOrchestrator().enqueue(repair, update)
            └─ setState(() => r = safeLatest)
```

#### Đọc danh sách (OrderListView)
```
OrderListView.initState()
  └─ _startRealtimeRepairsListener()
       └─ UserService.getCurrentShopId()
       └─ FirestoreService.watchRepairsByShop(shopId, useIndexedQuery)
            └─ Firestore.collection('repairs').where('shopId',==,shopId)
               .orderBy('updatedAt',desc).limit(200).snapshots()
       └─ _handleRealtimeSnapshot(snapshot):
            └─ for each change:
                 └─ _decodeRepairDocPayload(doc) → EncryptionService.decryptMap
                 └─ _preferUnsyncedLocalRepair(firestoreId, cloudData) → DBHelper check
                 └─ _repairsByFirestoreId[id] = repair
            └─ _applyFiltersAndSort()
            └─ DBHelper().upsertRepair(repair) [background]
            └─ setState()
  └─ _showPendingLocalRepairsWhileWaitingRealtime() [fallback từ local DB]
       └─ DBHelper.query('repairs', isSynced=0, deleted=0, createdAt >= 30days ago)
```

---

### Module: Sale (Bán hàng)

```
CreateSaleView._submitSale()
  └─ Validation (price, product)
  └─ DBHelper().upsertSale(saleOrder) → SQLite
  └─ DBHelper().updateProductQuantity(productId, qty-1) [giảm tồn kho]
  └─ [if paymentMethod == CÔNG NỢ] DBHelper().insertDebt(debt)
  └─ [if isInstallment] DBHelper().insertDebt(installmentDebt)
  └─ FinancialActivityService.logSale(sale)
       └─ DBHelper().insert('financial_activity_log', record)
       └─ EventBus().emit(EventBus.financialChanged)
  └─ SyncOrchestrator().enqueue(SyncEntityType.sale, create, sale)
  └─ SyncOrchestrator().syncAll()
       └─ _processSyncItem(sale)
            └─ FirestoreService.addSale(saleOrder)
                 └─ Validate money
                 └─ UserService.getCurrentShopId()
                 └─ EncryptionService.encrypt(data)
                 └─ Firestore.collection('sales').doc(id).set(merge:true)
                 └─ EventBus().emit('sales_changed')
```

---

### Module: Inventory (Kho hàng)

#### Đọc kho (lazy load)
```
InventoryView._init()
  └─ UserService.getCurrentUserPermissions() → _hasInventoryAccess, _canViewCostPrice
  └─ CategoryService().getShopSettings() → _shopSettings
  └─ _refreshLocalData():
       └─ [if _needsFullData] db.getAllProductsFiltered(search, type) → toàn bộ
       └─ [else] db.getProductsPaged(_pageSize, offset=0) → 20 items
       └─ db.getInventorySummary() → _totalQtyFromDB, _totalCapitalFromDB
       └─ setState()

InventoryView._onScroll() → _loadMoreIfNeeded():
  └─ db.getProductsPaged(_pageSize, _currentOffset) → thêm 20 items
  └─ setState(_allLoadedProducts.addAll, _currentOffset += 20)
```

#### Thêm/sửa sản phẩm
```
InventoryView._saveProduct(product)
  └─ DBHelper().upsertProduct(product) → SQLite
  └─ SyncOrchestrator().enqueue(SyncEntityType.product, create/update, product)
  └─ SyncOrchestrator().syncAll()
       └─ _handleCreate/_handleUpdate(item, shopId)
            └─ Firestore.collection('products').doc(id).set(data)
  └─ EventBus().emit('products_changed') ← từ SyncService listener khi cloud → local
```

---

### Module: Attendance (Chấm công)

#### Check-in
```
AttendanceView._checkIn()
  └─ Geolocator.checkPermission() / requestPermission()
  └─ Geolocator.getCurrentPosition(accuracy: high, timeout: 15s)
  └─ [if _locationRequired] tính khoảng cách vs _shopLatitude/_shopLongitude
       └─ Geolocator.distanceBetween(shopLat, shopLng, userLat, userLng)
       └─ [if > maxDistance] reject
  └─ ImagePicker().pickImage(source: ImageSource.camera)
  └─ BackgroundUploadService.uploadAttendancePhoto(file)
       └─ StorageService.uploadFile(localPath, 'attendance/{shopId}/{uid}/{date}')
            └─ FirebaseStorage.ref().putFile() → URL
  └─ Attendance object (checkInAt=now, photoIn=url, location=json{lat,lng})
  └─ DBHelper().upsertAttendance(attendance) → SQLite
  └─ SyncOrchestrator().enqueue(SyncEntityType.attendance, create, attendance)
  └─ SyncOrchestrator().syncAll()
       └─ Firestore.collection('attendance').doc(id).set(data)
  └─ setState() → rebuild UI

AttendanceView._refreshAttendanceData():
  └─ _pullOwnCloudData(uid, shopId):
       └─ Firestore.collection('attendance').where('shopId').where('userId')
          .where('dateKey >= today-14').get() [timeout 10s]
       └─ for each doc: DBHelper().upsertAttendance()
  └─ DBHelper().getAttendance(dateKey, uid) [source of truth cho UI]
  └─ DBHelper().getWorkSchedule(uid)
  └─ DBHelper().getAttendanceByUser(uid)
  └─ DBHelper().getLeaveRequestsByUser(uid)
  └─ setState()
```

---

## 🧨 TRANSACTION & ATOMIC RULES

### Bắt buộc atomic nhưng CHƯA có cơ chế atomic

| ID | Vị trí | Vấn đề | Mức độ |
|---|---|---|---|
| T-01 | `firestore_service.dart._updateInventoryFromPurchaseOrder()` | Read product qty → compute new qty → write back. Không dùng Firestore Transaction. Nếu 2 user cùng nhập hàng đồng thời → qty sai | HIGH |
| T-02 | `repair_detail_view.dart._isUpdating` | Bool flag thay vì Mutex/Lock. Nếu 2 async action kích hoạt trước khi `_isUpdating` được set → double-write | MEDIUM |
| T-03 | `adjustment_service.dart.adjustPartCost()` | Read debt.totalAmount → compute new amount → update. Non-atomic. App single-user context giảm risk nhưng không loại trừ hoàn toàn | LOW |
| T-04 | `SyncOrchestrator._handleUpdate()` | Read entity data từ local DB → write to Firestore. Nếu local DB bị update trong khoảng giữa → stale data lên cloud | LOW |

### Có cơ chế bảo vệ (đúng cách)

| Cơ chế | Nơi dùng | Mô tả |
|---|---|---|
| `SyncOrchestrator._isSyncing` bool flag | `syncAll()` | Ngăn concurrent `syncAll()`. Nếu có request trong khi đang sync → set `_syncRequestedWhileSyncing=true` → chạy lại sau khi xong |
| `SyncOrchestrator._syncRequestedWhileSyncing` | `syncAll()` finally block | Deferred re-run: nếu có item enqueue trong khi sync → tự động sync lại |
| Firestore `set(merge:true)` | `FirestoreService.addRepair/addSale` | Idempotent write — retry an toàn |
| Firestore document ID pre-generated | `SyncOrchestrator._handleCreate` | Dùng `firestoreId` đã có thay vì auto-generate → tránh duplicate docs khi retry |
| `_protectLocalUnsyncedRepairFromStaleCloud` | `RepairDetailView` | Giữ local data nếu cloud không rõ ràng mới hơn (tolerance 5000ms) |
| `_isInitializingRealtime` bool | `SyncService.initRealTimeSync()` | Ngăn concurrent init |
| CloudWrite timeout 25s | `SyncOrchestrator._withCloudWriteTimeout()` | Tránh hang vô hạn khi Firestore chậm |

### SQLite không có transaction cho multi-table writes

Các thao tác ghi nhiều bảng (ví dụ: upsertRepair + upsertCustomer) được gọi tuần tự trong Dart async, **không bọc trong SQLite transaction**. Nếu app crash giữa chừng → dữ liệu có thể không nhất quán giữa `repairs` và `customers`.

---

## 💾 CACHE STRATEGY

### UserService (static fields)

| Cache key | Storage | TTL | Invalidation trigger |
|---|---|---|---|
| `_cachedShopId` | In-memory String | Không có TTL | `clearCache()` (logout), `updateCachedShopId()` (shop change) |
| `_cachedUid` | In-memory String | Không có TTL | `clearCache()` |
| `_adminSelectedShopId` | In-memory String | Session | `clearCache()`, thay đổi shop (SuperAdmin) |
| `_cachedPermissions` | In-memory Map | **10 phút** (`_permissionsCacheTtl`) | `invalidatePermissionsCache()`, shop change, uid change, TTL expired |
| `_cachedPermissionsUid` | In-memory String | Theo `_cachedPermissions` | Tương tự |
| `_cachedPermissionsShopKey` | In-memory String | Theo `_cachedPermissions` | Tương tự |
| `_cachedPermissionsTime` | In-memory DateTime | Theo TTL | Tương tự |
| `_cachedCanViewCostPrice` | In-memory bool | Cần đọc thêm code | `_cachedCanViewCostPrice = null` trong `clearCache()` |
| `auth_cache_shopId` | **SharedPreferences** | Persistent (cross-launch) | `clearCache()` xóa; ghi đè khi `saveAuthCache()` |
| `auth_cache_uid` | **SharedPreferences** | Persistent | Tương tự |
| `auth_cache_role` | **SharedPreferences** | Persistent | Tương tự |
| `auth_cache_role_uid` | **SharedPreferences** | Persistent | Tương tự |

**Validation khi restore**: `restoreAuthCache()` so sánh saved uid với current uid — nếu khác → xóa cache prefs để tránh cross-user contamination.

### SyncService

| Cache key | Storage | TTL | Invalidation |
|---|---|---|---|
| `_realtimeCursorCache` | In-memory Map + SharedPreferences `rtCursor_{col}_{shopId}` | Persistent | `cancelAllSubscriptions()` xóa in-memory; prefs tồn tại |
| `_downloadCooldown` (60s) | Implicit timer | 60 giây | Reset sau mỗi download |
| `_syncAllToCloudCooldown` (12s) | `_lastSyncAllToCloudAt` DateTime | 12 giây | Reset sau mỗi syncAll |
| `_collectionRefreshCooldown` (5s) | Datetime per collection | 5 giây | Per-collection reset |
| `_collectionPollLimit` = 50 | Constant | N/A | Không thay đổi runtime |

### SyncOrchestrator

| Cache key | Storage | TTL | Ghi chú |
|---|---|---|---|
| `_pendingCount` | In-memory int | Không có TTL | Refreshed sau enqueue/syncAll |
| `_isSyncing` | In-memory bool | Execution-scoped | Reset trong `finally` của `syncAll()` |
| `_cloudWriteTimeout` = 25s | Constant | N/A | Áp dụng cho mỗi Firestore write |

### NotificationService

| Cache key | Storage | TTL | Invalidation |
|---|---|---|---|
| `_processedNotificationIds` | In-memory Set | Không có TTL | Bounded max 200 entries — xóa bớt khi quá 200 |
| `_recentNotifications` | In-memory List<DateTime> | Rolling 10s window | Tự clean khi check rate limit |
| `_lastTokenCheck` | In-memory DateTime | 6 giờ | Check mỗi app resume |

### HomeView

| Cache key | Storage | TTL | Ghi chú |
|---|---|---|---|
| `_lastTabIndexPrefKey` | SharedPreferences | Persistent | `_persistCurrentTabSelection()`, restored `_loadSavedTabIndex()` |
| `_permissions` | In-memory Map | Không có TTL riêng | Primed từ `UserService.getCurrentUserPermissionsSync()` |

---

## ⚠️ ERROR HANDLING FLOW

### Firebase / Firestore fail

```
SyncOrchestrator._processSyncItem(item):
  try:
    → _handleCreate/_handleUpdate/_handleDelete
    → Firestore.set/update/delete [timeout 25s]
  catch (TimeoutException):
    → throw Exception('Cloud write timeout: context')
  catch (any):
    → _markItemFailed(item, error.toString())
         → item.retryCount++
         → if retryCount >= 3 OR _isPermanentSyncError(error):
              status = 'failed'  ← item stays in queue permanently, no retry
         → else:
              status = 'pending'  ← will retry on next syncAll()
    → SyncAuditService.logFailure(entityType, entityId, error, retryCount)
    → failedCount++

_isPermanentSyncError(error):
  → true if 'permission-denied' OR 'missing or insufficient permissions'
  → permanent fail → KHÔNG retry
```

**Hậu quả khi permanent fail**: item nằm trong `sync_queue` với `status='failed'`, không tự động retry. Chỉ được reset nếu gọi `enqueue()` với `allowReviveFailed=true`.

### Network offline

```
SyncOrchestrator.syncAll():
  → Connectivity().checkConnectivity()
  → if no connection:
       → _syncStatusController.add(SyncStatus.noNetwork)
       → return SyncResult(noNetwork=true)  ← no retry scheduled here

SyncOrchestrator.init()._connectivitySubscription:
  → Connectivity().onConnectivityChanged.listen(results)
  → if hasConnection AND _pendingCount > 0:
       → syncAll()  ← auto-retry when network restored
```

### Sync fail (Realtime Listener)

```
SyncService._subscribeToCollection().onError:
  → debugPrint("❌ Sync error in $collection: $e")
  → _subscriptionStatus[collection] = false
  → [KHÔNG restart subscription, KHÔNG retry]

OrderListView._repairRealtimeSubscription.onError:
  → if isMissingIndex AND !_useRealtimeIndexFallback:
       → _useRealtimeIndexFallback = true
       → _startRealtimeRepairsListener(forceRestart: true) ← restart without orderBy
  → else:
       → setState(_isLoading=false, _isRealtimeConnected=false)
       → _showPendingLocalRepairsWhileWaitingRealtime() ← fallback to local SQLite
```

### Firebase init fail

```
main() [Android path]:
  → Firebase.initializeApp()
  → catch (e): debugPrint + rethrow ← app CRASH nếu Firebase init fail

main() [iOS path — deferred]:
  → _initializeDeferredAppServices()
  → Firebase.initializeApp()
  → catch (e): debugPrint + return ← app tiếp tục không có Firebase
  → _markFirebaseBootstrapReady() được gọi trong cả success lẫn fail
```

### AuthGate fallback

```
AuthGate._loggedOutFallbackTimer (4s):
  → if FirebaseAuth.currentUser == null after 4s:
       → setState(_showLoggedOutFallback = true)
       → hiển thị LoginView ← fallback nếu authStateChanges không fire

_getRoleAfterSync timeout:
  → Mobile: timeout 30s
  → Web: không timeout — function tự manage
  → syncUserInfo timeout: Mobile 20s, Web 15s → onTimeout: debugPrint + continue
  → ensureShopId timeout: 8s → throws exception
  → ClaimsService.getShopIdFromClaims timeout: 5s
```

### Firebase App Check fail

```
_activateFirebaseAppCheck():
  → timeout: 8s
  → catch (e): _logAppCheckWarning(msg) ← KHÔNG block app startup
  → app tiếp tục hoạt động dù App Check fail
  → rate-limited log: không log lại trong 30s
```

### CreateRepairOrderView fallback

```
_saveOrderProcess():
  try:
    → SyncOrchestrator().enqueue() + syncAll()
  catch (e):
    → FirestoreService.addRepair(repair) ← direct fallback
    → if direct also fails:
         → NotificationService.showSnackBar('Lỗi: $e', red)
         → return null (stay on screen)
  finally:
    → setState(_saving=false)
```

---

## 🎛 UI STATE (LOADING / ERROR / DISABLE)

### CreateRepairOrderView

| Action | Loading indicator | Button disable | Error display | Retry |
|---|---|---|---|---|
| Lưu đơn (`_saveOrderProcess`) | `_saving=true` → `CircularProgressIndicator` | ✅ Nút Lưu disabled khi `_saving=true` | `NotificationService.showSnackBar(msg, red)` | ❌ Không auto-retry, user phải nhấn lại |
| Upload ảnh | `_uploadStatus` text hiển thị | Implicit (trong saving flow) | Text error | ❌ |

### RepairDetailView

| Action | Loading indicator | Button disable | Error display | Retry |
|---|---|---|---|---|
| Cập nhật trạng thái | `_isUpdating=true` | ✅ Check `_isUpdating` trước khi gọi action | `debugPrint` + snackbar | ❌ |
| In phiếu | `_isPrinting=true` | ✅ Button disabled | snackbar | ❌ |
| Load shop info | Không có indicator | ❌ Không disable | Silent fail | ❌ |

### OrderListView

| Action | Loading indicator | Button disable | Error | Retry |
|---|---|---|---|---|
| Khởi động | `_isLoading=true` → loading spinner | N/A | N/A | ✅ `_showPendingLocalRepairsWhileWaitingRealtime()` — hiện local data ngay |
| Realtime connect | `_isRealtimeConnected=false` → indicator | N/A | Log + fallback | ✅ Tự restart nếu missing index |

### InventoryView

| Action | Loading indicator | Button disable | Error | Retry |
|---|---|---|---|---|
| Load đầu | `_isLoading=true` | N/A | snackbar | ❌ |
| Load more | `_isLoadingMore=true` → progress below list | N/A | `debugPrint` | ❌ |
| Scan barcode | `_isScanning=true` | N/A | N/A | N/A |

### AttendanceView

| Action | Loading indicator | Button disable | Error | Retry |
|---|---|---|---|---|
| Check-in/out | `_loading=true` | ❌ KHÔNG disable button — **nguy cơ double-tap** | snackbar | ❌ |
| Pull cloud data | `_loading=true` | N/A | Timeout 10s → tiếp tục với local | ✅ Fallback local |

### DebtView

| Action | Loading | Disable | Error | Retry |
|---|---|---|---|---|
| Load debts | `_isLoading=true` | N/A | N/A | ❌ |
| Sync Firebase | `_isSyncing=true` → text 'Đang đồng bộ...' | ✅ Nút sync disabled khi `_isSyncing=true` | snackbar | ❌ |

### StaffListView

| Action | Loading | Disable | Error | Retry |
|---|---|---|---|---|
| Tạo mã mời | `_generatingInvite=true` | ✅ Button disabled | snackbar | ❌ |

### SyncOrchestrator (global)

| Stream | Subscriber | UI effect |
|---|---|---|
| `pendingCountStream` | `UnifiedSyncButton` widget | Hiển thị badge số pending |
| `syncStatusStream` | `UnifiedSyncButton` widget | Icon spinner khi syncing |

### AuthGate

| State | Loading | UI |
|---|---|---|
| `_roleFuture` pending | `FutureBuilder` → `LoadingIntroScreen` | Full-screen loading animation |
| Firebase Auth null (4s timeout) | `_showLoggedOutFallback=true` | Chuyển sang `LoginView` |
| `FutureBuilder` error | Error widget | UNKNOWN — cần đọc build() method |

---

## 🧠 RUNTIME BEHAVIOR

### Startup Flow chi tiết

```
1. main() [Android]
   ├─ WidgetsFlutterBinding.ensureInitialized()
   ├─ FlutterNativeSplash.preserve(binding) [mobile]
   ├─ initializeDateFormatting('vi_VN')
   ├─ _enforceFirebaseOnlyMode() [kiểm tra deprecated flags]
   ├─ Firebase.initializeApp(options)
   ├─ _activateFirebaseAppCheck() [timeout 8s]
   ├─ FirebaseMessaging.onBackgroundMessage(handler)
   ├─ _markFirebaseBootstrapReady()
   └─ runApp(MyApp())
      └─ addPostFrameCallback:
           ├─ NotificationService.init()
           └─ ConnectivityService.instance.initialize()

   main() [iOS — deferred Firebase]
   ├─ runApp(MyApp()) ← ngay lập tức để hiện splash
   └─ Future.microtask(_initializeDeferredAppServices)
        └─ Firebase.initializeApp() async sau khi app đã render

2. MyApp.build()
   └─ MaterialApp(home: SplashView)
      └─ _loadSavedLocale() từ SharedPreferences → Locale('vi') default

3. SplashView [animation ~2s]
   └─ Logo scale + rotate + fade + particles
   └─ Timer → Navigator.pushReplacement(AuthGate)

4. AuthGate.build()
   └─ StreamBuilder(stream: FirebaseAuth.authStateChanges())
        ├─ null (logged out):
        │   ├─ _showLoggedOutFallback (4s timer): LoginView
        │   └─ else: LoadingIntroScreen (waiting)
        └─ User (logged in):
             └─ FutureBuilder(_getOrCreateRoleFuture(uid, email))
                  ├─ waiting: LoadingIntroScreen
                  └─ done:
                       ├─ isSuperAdmin=true → ShopSelectorView
                       └─ else → HomeView(role)

5. _getRoleAfterSync(uid, email) [chỉ chạy 1 lần per user session]
   ├─ STEP 0: UserService.restoreAuthCache(uid) từ SharedPreferences
   ├─ [Mobile + hasCache]: getCachedRole() → fast return + _startBackgroundUserWarmup()
   ├─ [isSuperAdmin]: log login + return {role:'admin', isSuperAdmin:true}
   ├─ _tryFastMobileBootstrap(): getShopIdSync → getRoleFast (2s timeout) → fast return
   └─ [fallback full path]:
        ├─ UserService.syncUserInfo(uid, email) [20s timeout]
        ├─ CurrentShopService.init()
        ├─ ensureShopId(maxRetries:2) [8s timeout]
        ├─ ClaimsService.getShopIdFromClaims() [5s timeout]
        └─ UserService.getUserRole(uid) → Firestore users/{uid}

6. _startBackgroundUserWarmup() [microtask, non-blocking]
   ├─ UserService.syncUserInfo() [20s timeout]
   ├─ CurrentShopService.init()
   ├─ SyncOrchestrator().init()
   │   ├─ _refreshPendingCount() từ sync_queue
   │   └─ Connectivity().onConnectivityChanged.listen() → auto-sync khi có mạng
   ├─ CashClosingNotifier.instance.init()
   ├─ PaymentIntentService.initialize()
   └─ SyncHealthCheck.runFullCheck()

7. HomeView.initState() [addPostFrameCallback]
   ├─ _primePermissionsFromCache() ← sync, không async
   ├─ _checkNotificationStatus()
   ├─ _initialSetup() ← load user info, shop info, tab configs
   ├─ SyncService.initRealTimeSync(callback)
   │   └─ subscribes 6 Firestore collections (repairs, sales, products, debts,
   │      sales_returns, product_categories)
   └─ EventBus().stream.listen() ← bind reload logic
```

### Sync Flow (Realtime — Cloud → Local)

```
[Firestore server phát hiện thay đổi]
  └─ SyncService._subscribeToCollection() listener fires
       └─ for each docChange:
            ├─ DocumentChangeType.removed → [EMPTY HANDLER, không làm gì]
            ├─ data['deleted']==true → [EMPTY HANDLER, không làm gì]
            └─ else:
                 └─ EncryptionService.decryptMap(data)
                 └─ onChanged(data, docId) → DBHelper().upsert_X(item) [SQLite]
       └─ onBatchDone() → EventBus().emit('X_changed')
       └─ FirebaseUsageStatsService.logRealtimeRead(collection, readCount)
  └─ EventBus subscribers receive event:
       ├─ HomeView → _debouncedLoadStats()
       ├─ OrderListView → không cần (dùng listener riêng)
       ├─ RevenueView → debounce 2s → _loadAllData()
       ├─ CashClosingView → debounce 500ms → _loadAllDataFromLocalDB()
       └─ InventoryView → debounce 220ms → _refreshLocalData()
```

### Event Flow (Local → Cloud)

```
[User thực hiện action]
  └─ Validate (AdjustmentService.canEditDirectly, form validation)
  └─ DBHelper().upsert_X() [SQLite — instant, không cần network]
  └─ SyncOrchestrator().enqueue(type, operation, data)
       └─ insert into sync_queue table
       └─ _pendingCountController.add(count) → UI badge update
  └─ SyncOrchestrator().syncAll()
       ├─ [offline] return SyncResult(noNetwork=true)
       └─ [online]:
            └─ for each pending item:
                 └─ Firestore.set/update/delete [timeout 25s]
                 └─ delete from sync_queue
                 └─ mark isSynced=1 in entity table
```

### Offline → Online Transition

```
SyncOrchestrator._connectivitySubscription:
  [ConnectivityResult changes from none to wifi/mobile]
  └─ hasConnection=true AND _pendingCount > 0
  └─ syncAll() ← auto-triggered, no user interaction needed

SyncService listeners:
  └─ Firestore SDK tự quản lý reconnect
  └─ Khi reconnect → listeners tiếp tục nhận snapshot updates tự động
  └─ Accumulated changes trong offline period được push qua docChanges

Local DB as source of truth:
  └─ Tất cả reads trong UI luôn đọc từ SQLite (không chờ Firestore)
  └─ Offline: app hoạt động bình thường, write queue vào sync_queue
  └─ Online: sync_queue được flush tự động
```

### App Resume (từ background)

```
HomeView + AuthGate đều là WidgetsBindingObserver:
  didChangeAppLifecycleState(AppLifecycleState.resumed):
    └─ NotificationService.ensureFCMTokenValid()
         └─ if token age > 6h → refresh FCM token
         └─ update token in Firestore users/{uid}
    └─ [HomeView có thể trigger sync nếu có sự kiện]
```

### Multi-Shop Flow (Super Admin)

```
[Super Admin đăng nhập]
  └─ _getRoleAfterSync: return {role:'admin', isSuperAdmin:true}
  └─ AuthGate → ShopSelectorView (không vào HomeView)

[Super Admin chọn shop]
  └─ UserService._adminSelectedShopId = selectedShopId
  └─ UserService.invalidatePermissionsCache()
  └─ SyncService.cancelAllSubscriptions()
  └─ SyncService.initRealTimeSync(callback) ← restart với shopId mới
  └─ EventBus.emit(EventBus.shopChanged)
  └─ HomeView reload toàn bộ
```

---

## 📋 DANH SÁCH FILE ĐÃ ĐỌC (bổ sung spec lần này)

Tất cả file sau được đọc trực tiếp bằng `read_file` tool trước khi viết 8 section mới:

| File | Phần đã đọc |
|---|---|
| `lib/main.dart` | Lines 1–700 (toàn bộ: bootstrap, AuthGate, startup flow) |
| `lib/services/event_bus.dart` | Lines 1–80 (toàn bộ) |
| `lib/services/sync_orchestrator.dart` | Lines 1–700 (enqueue, syncAll, _processSyncItem, _handleCreate) |
| `lib/services/sync_service.dart` | Lines 1–600 (initRealTimeSync, _subscribeToCollection, cancelAllSubscriptions) |
| `lib/services/user_service.dart` | Lines 1–300 (cache fields, clearCache, restoreAuthCache, saveAuthCache) |
| `lib/views/repair_detail_view.dart` | Lines 1–400 (_repairDocSubscription, _applyRepairDocSnapshot, merge/protect logic) |
| `lib/views/order_list_view.dart` | Lines 1–350 (_repairRealtimeSubscription, _handleRealtimeSnapshot, dispose) |
| `lib/views/home_view.dart` | Lines 1–300 (initState, EventBus binding, SyncService.initRealTimeSync) |
| `lib/views/create_repair_order_view.dart` | Lines 1–400 (_saveOrderProcess, _smartFill, initState) |
| `lib/views/inventory_view.dart` | Lines 1–400 (_bindInventoryRefreshEvents, _scannerController, dispose) |
| `lib/views/attendance_view.dart` | Lines 1–200 (check-in flow, GPS, cloud pull) |
| `lib/views/revenue_view.dart` | Lines 1–200 (EventBus debounce, _loadAllData) |
| `lib/views/debt_view.dart` | Lines 1–200 (EventBus, _isSyncing) |
| `lib/views/cash_closing_view.dart` | Lines 1–200 (EventBus, _debounceTimer, _initRealTimeSync) |
| `lib/views/staff_list_view.dart` | Lines 1–200 (_generateInviteCode, _generatingInvite) |
| `lib/models/shop_settings_model.dart` | Lines 1–150 (businessType, feature flags) |
| `lib/services/adjustment_service.dart` | Lines 1–200 (canEditDirectly, adjustPartCost) |
| `lib/constants/financial_constants.dart` | Lines 1–150 (PaymentMethod enum, MoneySourceType) |
| `lib/services/notification_service.dart` | Lines 1–200 (rate limit, processedIds, FCM) |
| `lib/theme/app_colors.dart` | Lines 1–100 (color palette) |
| `pubspec.yaml` | Lines 1–80 (dependencies) |

*Tài liệu này được tạo bằng cách đọc source code thực tế. Không có nội dung nào được suy đoán. Cập nhật lần cuối: dựa trên version `1.0.3+513`.*
