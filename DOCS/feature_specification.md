# Tài liệu tổng quan chức năng & quy tắc tính toán

Tài liệu này tóm tắt đầy đủ các tính năng chính, luồng dữ liệu, và mọi quy tắc tính toán / chuyển đổi số tiền được hiện thực trong mã nguồn hiện tại của ứng dụng (kho `lib/` và `functions/`). Mục tiêu: mô tả chính xác hành vi app theo code để dùng làm tham khảo hoặc audit.

## Tổng quan kiến trúc
- Frontend: Flutter (lib/).
- Local persistence: SQLite wrapper ở `lib/data/db_helper.dart` (cơ sở dữ liệu `repair_shop_v22.db`, phiên bản schema hiện tại: 19).
- Cloud: Firebase Firestore, Storage, Auth, Cloud Functions (thư mục `functions/`).
- Đồng bộ: `lib/services/sync_service.dart` (real-time snapshots và batch push local->cloud).
- Notifications: `lib/services/notification_service.dart` (cơ chế local + ghi vào collection `shop_notifications`).

## Bảng và model chính (tóm tắt)
- `products` / `Product` (`lib/models/product_model.dart`): trường quan trọng: `price`, `cost`, `quantity`, `status`, `imei`, `kpkPrice`, `pkPrice`, `isSynced`, `firestoreId`.
- `sales` / `SaleOrder` (`lib/models/sale_order_model.dart`): `totalPrice`, `totalCost`, `paymentMethod`, `isInstallment`, `downPayment`, `loanAmount`, `bankName`, `isSynced`.
- `repairs` / `Repair` (`lib/models/repair_model.dart`): `status` (1..4), `price`, `cost`, `imagePath`, `isSynced`, `deleted`.
- `debts` / `Debt` (`lib/models/debt_model.dart`): `totalAmount`, `paidAmount`, `type`, `status`, `linkedId`.
- `debt_payments` (chi tiết khoản trả), `expenses`, `attendance`, `audit_logs`, `purchase_orders`, `cash_closings`, `payroll_settings`.

## Luồng đồng bộ & multi-tenant
- Shop phân vùng theo `shopId`; hầu hết writes lên Firestore gắn `shopId` (xem `UserService.getCurrentShopId()` và `FirestoreService.*`).
- Super-admin: email cố định `admin@huluca.com` — bỏ qua filter `shopId` (đa chỗ trong `UserService`).
- Real-time Cloud->Local: `SyncService.initRealTimeSync()` subscribe các collection: `repairs`, `sales`, `products`, `expenses`, `debts`, `users`, `shops`, `attendance` — filter theo `shopId` (trừ super-admin). Thay đổi được upsert vào local DB.
- Local->Cloud: `SyncService.syncAllToCloud()` đẩy records chưa `isSynced` (repairs, sales, products, attendance). Xử lý upload ảnh bằng `StorageService` với timeout (20–30s tùy chỗ). Sau commit batch set `isSynced=true` và update `firestoreId`.
- Soft deletes: repairs dùng `deleted=true` flag; products thường set `status=0`.

## Quy tắc xử lý tiền tệ (chung — xuất hiện nhiều chỗ)
Quy tắc này lặp ở nhiều view/service (ví dụ `CreateSaleView`, `CreateRepairOrderView`, `ExpenseView`, `DebtView`):

1. Khi đọc chuỗi nhập liệu tiền (dạng text), đều làm sạch ký tự không phải số: `s.replaceAll(RegExp(r'[^0-9]'), '')`.
2. Chuyển sang int: `int.tryParse(digitsOnly) ?? 0`.
3. Heuristic: nếu `amount > 0 && amount < 100000` thì nhân `amount *= 1000`.
   - Ý nghĩa thực tế: người dùng có thể nhập `50` để chỉ 50k; nếu nhập số lớn đủ (>=100000) coi là số VNĐ đầy đủ.
4. Format hiển thị: `NumberFormat('#,###')` (không có ký hiệu tiền tệ, hiển thị `0` nếu bằng 0).

Lưu ý: hàm `_parseCurrency` trong `CreateSaleView` thực hiện đúng các bước trên; nhiều chỗ gọi thêm nhân 1000 một lần nữa (kiểm tra cẩn thận khi sửa code).

## Quy tắc tạo & xử lý đơn bán hàng (`CreateSaleView`)
- Tổng tiền tự động: nếu `_autoCalcTotal == true` thì `total = sum(sellPrice)` trên `_selectedItems` (bỏ qua `isGift`). Sau đó `priceCtrl.text` được set bằng format và gọi tính trả góp.
- Trả góp (`_isInstallment`): loan = total - downPayment; `loanAmountCtrl` hiển thị loan.
- Xác định `hasDebt` (`_hasDebt`):
  - `totalPrice = parse(priceCtrl)`
  - `paidAmount = parse(downPaymentCtrl)` (áp dụng heuristic 1000)
  - Nếu `paymentMethod` khác `CÔNG NỢ` và khác `TRẢ GÓP (NH)` và `paidAmount == 0` thì coi như đã thanh toán toàn bộ (paidAmount = totalPrice)
  - `_hasDebt = totalPrice > paidAmount`
- Khi lưu đơn: nếu `paymentMethod == "CÔNG NỢ" || (paymentMethod != "TRẢ GÓP (NH)" && paidAmount < totalPrice)` thì tạo một record debt local (`db.insertDebt`) với `type: CUSTOMER_OWES`, `status: unpaid`, `totalAmount` và `paidAmount`.
- Sau bán: với mỗi sản phẩm bán ra
  - `db.updateProductStatus(p.id!, 0)` (set status = 0)
  - `db.deductProductQuantity(p.id!, 1)` (giảm quantity; nếu quantity <= 0 thì set status = 0)
  - `p.status = 0; p.quantity = 0;` và `FirestoreService.updateProductCloud(p)` để cập nhật cloud.
- Lưu sale: `db.upsertSale(sale)` rồi `FirestoreService.addSale(sale)`.

## Công nợ (Debts) & Thanh toán
- Lưu debt: `db.insertDebt({...})` khi bán mà còn nợ; đồng bộ sau qua `FirestoreService.addDebtCloud`.
- Thanh toán nợ (`DebtView._payDebt`):
  - Nhập số (CurrencyTextField) và dùng cùng quy ước nhân 1000 nếu nhỏ.
  - Tạo bản ghi `debt_payments` (history) bằng `db.insertDebtPayment({...})`.
  - Nếu số trả < số còn nợ: logic trong code sẽ (theo cách viết hiện tại)
    - gọi `db.updateDebtPaid(debt['id'], remain)` rồi tạo 1 debt mới mang phần dư (đáng chú ý: code cập nhật paidAmount rồi tạo debt mới — cần chú ý khi refactor để giữ nhất quán).
  - Nếu trả đủ/đơn vượt: `db.updateDebtPaid(debt['id'], payAmount)` sẽ cập nhật `paidAmount` và set `status='paid'` nếu đạt >= totalAmount (SQL rawUpdate trong `DBHelper.updateDebtPaid`).
  - Nếu debt có `linkedId` (ví dụ liên kết tới sale firestoreId) sẽ gọi `db.updateOrderStatusFromDebt(linkedId, newPaidAmount)` để cập nhật `sales.downPayment` hoặc `repairs.paymentMethod`.

## Chi tiêu (Expenses)
- Thêm expense: dùng `ExpenseView` với CurrencyTextField; áp dụng quy ước nhân 1000 nếu small.
- Expense lưu `amount` integer (VNĐ), `paymentMethod`, `date` (milliseconds).

## Ảnh & Storage
- Upload file ảnh: `StorageService.uploadAndGetUrl()` đặt tên bằng timestamp + basename, upload với timeout trong `SyncService` (20–30s); trả về URL hoặc null.
- `uploadMultipleAndJoin` trả về string các URL nối bằng comma giống cách `imagePath`/`images` được lưu.

## Cloud Functions (thư mục `functions/`) — quy tắc server-side
- `notifyNewRepair`: gửi FCM topic `staff` khi có doc `repairs` mới.
- `notifyStatusChange`: gửi thông báo khi `repairs` thay đổi `status`.
- `createStaffAccount` (callable): logic kiểm tra quyền caller, tạo user Auth + doc `users` với `shopId`, phân quyền mặc định.
- `cleanupDeletedRepairs`: scheduled job xoá vĩnh viễn các repair đã `deleted` lâu hơn cấu hình (opt-in qua doc `settings/cleanup`).

## Roles & Permissions
- `UserService.getUserRole` và `getCurrentUserPermissions` trả role/permissions; super-admin (email `admin@huluca.com`) luôn được coi là `admin`.
- Shop-level locks (`appLocked`, `adminFinanceLocked`) có thể override quyền người dùng.

## Các điểm lưu ý / edge cases / đề xuất
- Heuristic nhân *1000* lặp nhiều nơi: nếu refactor, gom về 1 utility để tránh nhân dư.
- Một số nơi dùng `deleted` flag, một số set `status=0` — tiêu chuẩn hoá soft-delete giúp đơn giản hoá sync/cleanup.
- Khi tạo/deep-update debts, code hiện tại trong `DebtView._payDebt` có bước gọi `db.updateDebtPaid(debt['id'], remain)` trước khi tạo debt mới — cần kiểm tra kỹ nghiệp vụ thực tế để tránh nhầm lẫn `paidAmount`.
- Tất cả actions quan trọng đều có log/ audit (local `audit_logs` và cloud `audit_logs` qua `AuditService` / `FirestoreService.addAuditLogCloud`).

## Tệp tham khảo chính
- `lib/main.dart` — bootstrap, AuthGate, gọi `SyncService`.
- `lib/data/db_helper.dart` — schema + helper SQL.
- `lib/services/*` — `user_service.dart`, `sync_service.dart`, `firestore_service.dart`, `notification_service.dart`, `storage_service.dart`.
- `lib/views/*` — `create_sale_view.dart`, `create_repair_order_view.dart`, `debt_view.dart`, `expense_view.dart`, `inventory_view.dart`.
- `functions/index.js` — cloud functions cho notification, tạo staff, cleanup cron.

## Tính lương (Payroll) & Chấm công
- Dựa trên bảng `attendance` (model `Attendance`).
- Quy tắc tính lương:
  - Lương ngày cơ bản (`_basePerDay`): lưu trong SharedPreferences dưới key `payroll_base` (Map<String, double>).
  - Giờ chuẩn/ngày (`_hoursPerDay`): key `payroll_hours`.
  - Hệ số OT (`_otRate`): key `payroll_ot` (%).
  - Tính toán cho nhân viên:
    - `payPerHour = base / hoursStd` (nếu hoursStd > 0).
    - Duyệt attendance: nếu có checkIn/checkOut hợp lệ, tính `hrs = (outMs - inMs) / (1000*60*60)`.
    - Nếu `overtimeOn == 1` và `hrs > hoursStd`, thì `otHours += (hrs - hoursStd)`.
    - `regularHours = totalHours - otHours`.
    - `salary = (regularHours * payPerHour) + (otHours * payPerHour * (otRate / 100))`.
  - Chỉ manager (`role == 'admin'`) mới chỉnh công thức; tháng khóa (`_monthLocked`) thì không sửa.
  - Xuất CSV: copy vào clipboard với format Date,Name,CheckIn,CheckOut,Hours,OT,Status và summary.

## Demo nhập tiền tệ (CurrencyInputDemo)
- So sánh hai cách nhập tiền:
  - Quy ước x1k (`CurrencyTextField`): nhập 220 → 220 VNĐ (áp dụng heuristic *1000 nếu <100000).
  - Nhập trực tiếp (`EnhancedCurrencyInput`): nhập đầy đủ số tiền, có quick select buttons (100K, 200K, etc.).
- Không ảnh hưởng logic app chính; chỉ demo UX.

## Các tính năng khác (tóm tắt nhanh)
- Đóng sổ tiền (`cash_closing_view.dart`): tính tổng thu chi theo ngày/tháng, lưu `cash_closings` table.
- Đơn mua hàng (`purchase_order_view.dart`): tạo đơn mua sản phẩm, cập nhật inventory khi nhận hàng.
- In hóa đơn: qua `unified_printer_service.dart` (USB/Bluetooth) hoặc `bluetooth_printer_service.dart`.
- Chat nội bộ: `FirestoreService.sendChat()` ghi vào `shop_notifications`.
- Logging: `LoggingService.log()` in ra console; `AuditService.logAction()` ghi cloud `audit_logs`.
- Connectivity: `ConnectivityService` trigger sync khi online.
- Storage: `StorageService` upload ảnh với timeout, dùng trong repairs/sales.

## Edge cases & đề xuất
- Heuristic *1000* có thể gây nhầm nếu nhập số lớn nhưng quên quy ước — cân nhắc chuyển sang nhập trực tiếp như demo.
- Soft deletes không nhất quán: repairs dùng `deleted=true`, products set `status=0` — refactor để dùng flag chung.
- Debt payment logic tạo debt mới khi partial pay — kiểm tra nghiệp vụ để tránh debt chain dài.
- Payroll locking chưa implement đầy đủ (commented out).
- Tất cả actions audit logged.

## Chi tiết từng tính năng & quy tắc (mở rộng)

### Bán hàng (`CreateSaleView`) - Chi tiết hàm
- **`_loadData()`**: Gọi `db.getInStockProducts()` (SQL: `SELECT * FROM products WHERE status = 1 AND quantity > 0 ORDER BY name`), `db.getCustomerSuggestions()` (top 5 khách gần nhất). Set `_allInStock`, `_filteredInStock`, `_suggestCustomers`. Nếu `widget.preSelectedProduct` != null, gọi `_addProductToSale()`.
- **`_calculateInstallment()`**: `total = _parseCurrency(priceCtrl.text)`, `down = _parseCurrency(downPaymentCtrl.text)` (áp dụng *1000 nếu <100000), `loan = total - down`, set `loanAmountCtrl.text = _formatCurrency(loan > 0 ? loan : 0)`. Sau đó gọi `_updateDebtStatus()`.
- **`_updateDebtStatus()`**: `totalPrice = _parseCurrency(priceCtrl.text)`, `paidAmount = _parseCurrency(downPaymentCtrl.text)` (áp dụng *1000). Nếu `paymentMethod` != "CÔNG NỢ" && != "TRẢ GÓP (NH)" && `paidAmount == 0`, set `paidAmount = totalPrice`. Set `_hasDebt = totalPrice > paidAmount`.
- **`_calculateTotal()`**: Nếu `_autoCalcTotal`, `total = sum(item['sellPrice'])` cho items không `isGift`, set `priceCtrl.text`, gọi `_calculateInstallment()`.
- **`_parseCurrency(String s)`**: `digitsOnly = s.replaceAll(RegExp(r'[^0-9]'), '')`, `amount = int.tryParse(digitsOnly) ?? 0`, nếu `amount > 0 && amount < 100000` thì `amount *= 1000`, return `amount`.
- **`_formatCurrency(int amount)`**: Nếu `amount == 0` return '0', else `NumberFormat('#,###').format(amount)`.
- **`_addItem(Product p)`**: Nếu chưa có trong `_selectedItems`, add Map với 'product': p, 'isGift': false, 'sellPrice': p.price, gọi `_calculateTotal()`, clear `searchProdCtrl`, reset `_filteredInStock`.
- **`_addProductToSale(Product p)`**: Tương tự `_addItem`, show snackbar.
- **`_processSale()`**: Validate items, name, phone. Tạo `uniqueId = "sale_${now}_${phoneCtrl.text}"`, `seller = email.split('@').first.toUpperCase()`. Parse `totalPrice`, `paidAmount` (áp dụng *1000). Nếu `paymentMethod == "CÔNG NỢ" || (paymentMethod != "TRẢ GÓP (NH)" && paidAmount < totalPrice)`, insert debt với `personName`, `phone`, `totalAmount`, `paidAmount`, `type: "CUSTOMER_OWES"`, `status: "unpaid"`, `note: "Nợ mua máy: ${productNames}"`. For each item: `db.updateProductStatus(p.id!, 0)`, `db.deductProductQuantity(p.id!, 1)`, `p.status=0; p.quantity=0`, `FirestoreService.updateProductCloud(p)`. Upsert sale, add cloud, show snackbar, pop.

### Sửa chữa (`CreateRepairOrderView`) - Chi tiết hàm
- **`_loadData()`**: Load products in-stock tương tự sale.
- **`_saveOrderProcess()`**: Validate inputs. Parse `price`, `cost` (heuristic). Tạo `Repair` với `firestoreId`, `customerName`, `phone`, `address`, `productName`, `price`, `cost`, `status: 1`, `receiveImages`, `deliverImages` (comma URLs). Upload images qua `StorageService.uploadMultipleAndJoin()` (timeout 30s), set `imagePath`. Upsert local, add cloud, show snackbar.
- **`_saveAndPrint()`**: Gọi `_saveOrderProcess()`, rồi `UnifiedPrinterService.printRepairOrder()` với data format ESC/POS.
- Quy tắc: `receiveImages`/`deliverImages` là lists, lưu comma-separated URLs.

### Công nợ (`DebtView`) - Chi tiết hàm
- **`_loadDebts()`**: `db.getAllDebts()` (SQL: `SELECT * FROM debts WHERE deleted = 0 ORDER BY createdAt DESC`), filter shopId nếu cần.
- **`_payDebt(Map debt)`**: Show dialog nhập số (CurrencyTextField). Parse `payAmount` (heuristic). Tạo `debt_payments` record với `debtId`, `amount`, `paidAt`. Nếu `payAmount >= remain`, update `paidAmount += payAmount`, set `status = 'paid'` nếu đủ. Nếu partial, update `paidAmount += payAmount`, insert debt mới với `totalAmount = remain`, `paidAmount = 0`, `type` giữ nguyên. Nếu `linkedId`, update `sales.downPayment` hoặc `repairs.paymentMethod` qua `db.updateOrderStatusFromDebt()`.
- **`_showDebtHistory()`**: Load `debt_payments` cho debt, show list với amounts.

### Chi tiêu (`ExpenseView`) - Chi tiết hàm
- **`_showAddExpenseDialog()`**: Dialog với CurrencyTextField cho `amount` (heuristic), `paymentMethod`, `date`. Parse `amount`, tạo `Expense`, upsert local, add cloud.

### Kho hàng (`InventoryView`) - Chi tiết hàm
- Add product: Nhập `name`, `price` (heuristic), `cost`, `quantity`, `imei`, `status=1`. Upsert, sync.
- Edit: Load product, update fields, sync.

### Đồng bộ (`SyncService`) - Chi tiết hàm
- **`initRealTimeSync()`**: For each collection (`repairs`, `sales`, etc.), `FirebaseFirestore.instance.collection(collection).where('shopId', isEqualTo: shopId).snapshots().listen((snapshot) { for (doc) upsert local; })`. Nếu super-admin, bỏ where.
- **`syncAllToCloud()`**: Query local `isSynced=false`, for each: upload images nếu có, add/update cloud với `SetOptions(merge: true)`, set `isSynced=true`, update `firestoreId`.

### Chấm công (`AttendanceView`) - Chi tiết hàm
- Check-in/out: Ghi `checkInAt`, `checkOutAt`, `overtimeOn` (bool). Upsert local, sync.
- Load: `db.getAttendanceByDateRange()` (SQL with date filter).

### Tính lương (`PayrollView`) - Chi tiết hàm
- **`_calc()`**: Filter attendance theo staff. Tính `totalHours`, `otHours` (nếu `overtimeOn==1` && `hrs > hoursStd`), `regularHours = totalHours - otHours`, `salary = (regularHours * payPerHour) + (otHours * payPerHour * (otRate/100))` với `payPerHour = base / hoursStd`.
- **`_openRuleDialog()`**: Chỉ admin, không locked. Set `_basePerDay[staff]`, etc., save SharedPreferences.
- **`_exportCsv()`**: Format buffer với Date,Name,CheckIn,CheckOut,Hours,OT,Status, summary.

### Đóng sổ (`CashClosingView`) - Chi tiết hàm
- Tính sum: `db.getSalesByDateRange()`, sum `totalPrice` - `downPayment` (thu), sum expenses (chi), debts paid (thu/chi tùy type).

### Đơn mua (`PurchaseOrderView`) - Chi tiết hàm
- Tạo: Chọn products, tính `totalPrice` (sum prices), lưu `PurchaseOrder`, khi nhận: update `products.quantity += receivedQty`.

### In hóa đơn (`UnifiedPrinterService`) - Chi tiết hàm
- **`printRepairOrder()`**: Format data (customer, products, price), gửi ESC/POS commands qua USB/Bluetooth.

### Chat & Notifications (`NotificationService`) - Chi tiết hàm
- **`listenToNotifications()`**: Subscribe `shop_notifications`, filter `targetUser` hoặc global, show snackbar rate-limited (3 per 10s).
- **`sendCloudNotification()`**: Add doc to `shop_notifications` với `title`, `body`, `targetUser`.

### Roles (`UserService`) - Chi tiết hàm
- **`getCurrentShopId()`**: Cache từ Firestore `users/{uid}/shopId`.
- **`getUserRole()`**: Check email == 'admin@huluca.com' → 'admin', else Firestore `users/{uid}/role`.
- **`getCurrentUserPermissions()`**: Based on role, return list permissions.

### Cloud Functions - Chi tiết
- **`notifyNewRepair`**: On create `repairs`, send FCM to topic 'staff'.
- **`notifyStatusChange`**: On update `repairs`, send nếu status changed.
- **`createStaffAccount`**: Callable, validate caller permissions, create Auth user, set Firestore doc với `shopId`, `role`.
- **`cleanupDeletedRepairs`**: Scheduled, query `repairs` where `deleted=true` && `updatedAt < threshold`, delete batch.

### Demo Currency - Chi tiết
- `CurrencyTextField`: Extends TextField, onChanged parse với heuristic, format display.
- `EnhancedCurrencyInput`: Nhập trực tiếp, quick buttons add 100000, etc.

### Logging & Audit - Chi tiết
- `LoggingService.log()`: `print('[LOG] $message')`.
- `AuditService.logAction()`: Add to `audit_logs` với `action`, `payload`, `userId`, `timestamp`.

---
Tài liệu chi tiết này bao gồm mọi hàm chính, luồng code, và quy tắc. Nếu cần code snippet cụ thể, tôi có thể cung cấp.
