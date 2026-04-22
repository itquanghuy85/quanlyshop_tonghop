# TÀI LIỆU TỔNG HỢP TOÀN BỘ DỰ ÁN QUANLYSHOP

Tài liệu này được viết để người mới có thể đọc một lần và nắm toàn bộ hệ thống mà không cần mở từng file mã nguồn.

Phiên bản tài liệu: 2026-04-22

---

## 1. Mục tiêu tài liệu

- Cung cấp bản đồ tổng thể dự án từ nghiệp vụ đến kỹ thuật.
- Mô tả đầy đủ luồng dữ liệu, kiến trúc offline-first, bảo mật, phân quyền.
- Tóm tắt các module chính, dịch vụ cốt lõi, cách build/test/deploy.
- Trở thành tài liệu bàn giao kỹ thuật và vận hành.

---

## 2. Thông tin nhận diện hệ thống

### 2.1. Ứng dụng

- Tên project: quanlyshop
- Mô tả: Phần mềm quản lý tiệm sửa chữa mua bán điện thoại chuyên nghiệp
- Phiên bản hiện tại: 1.0.3+513
- Nền tảng Flutter SDK: >=3.10.0 <4.0.0

### 2.2. Định danh app

- Android namespace/applicationId: com.huluca.shopmanager
- iOS bundleId trong Firebase options: com.huluca.shop

### 2.3. Firebase

- Firebase project: huyaka-1809
- Region Cloud Functions: asia-southeast1
- Các platform đã cấu hình trong firebase_options.dart: android, ios, macos, web
- Windows/Linux trong firebase_options.dart: chưa cấu hình FirebaseOptions (ném UnsupportedError)

---

## 3. Bức tranh nghiệp vụ

Ứng dụng là hệ thống quản trị cửa hàng theo mô hình đa tenant (multi-shop), tập trung vào 5 nhóm nghiệp vụ lớn:

1. Sửa chữa: nhận máy, theo dõi trạng thái kỹ thuật, dịch vụ sửa, giao máy, duyệt giao.
2. Bán hàng và kho: bán lẻ, trả hàng, nhập hàng, kiểm kho, quản lý tồn kho, mã nhanh.
3. Tài chính: doanh thu, chi phí, công nợ, thanh toán, chốt quỹ, phân tích tài chính ngày.
4. Nhân sự: chấm công, ca làm, đổi ca, lương và cấu hình lương theo vai trò.
5. Vận hành: chat nội bộ, thông báo đẩy, in ấn tem hóa đơn, báo cáo, audit log.

Ngoài nghiệp vụ điện thoại, hệ thống có nền tảng mở rộng đa ngành (food/fashion/general/electronics) qua shop settings, category, variants, expiry.

---

## 4. Công nghệ và stack

### 4.1. Frontend và local data

- Flutter (Dart)
- SQLite local với sqflite
- sqflite_common_ffi_web cho web
- SharedPreferences cho cache nhẹ

### 4.2. Firebase backend

- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Cloud Functions (Node 20)
- Firebase Messaging + Local Notifications
- Firebase App Check

### 4.3. Tích hợp khác

- In ấn nhiệt/Bluetooth/WiFi
- QR/Barcode scanner
- PDF/printing/share
- Social auth: Google Sign-In, Sign in with Apple

---

## 5. Cấu trúc dự án (đọc nhanh theo thư mục)

### 5.1. Root workspace

- lib/: toàn bộ mã app Flutter
- functions/: Cloud Functions
- DOCS/: tài liệu release/vận hành/bàn giao
- test/: test logic và test nghiệp vụ
- android, ios, web, windows, macos, linux: host platform
- firebase.json, firestore.rules, firestore.indexes.json, storage.rules: cấu hình backend

### 5.2. Cấu trúc trong lib

- main.dart: bootstrap app, auth gate, init sync/notifications
- models/: 38 file model dữ liệu
- services/: 67 service nghiệp vụ/tích hợp
- views/: 96 màn hình (bao gồm subfolder food/fashion/hr/onboarding)
- widgets/: widget tái sử dụng
- data/db_helper.dart: SQLite schema + CRUD local + migration
- theme/: AppTheme/AppColors/AppTextStyles
- constants/: hằng số nghiệp vụ/tài chính
- core/: utility lõi
- utils/: helper chung
- l10n/: localization ARB và generated localizations

### 5.3. Điểm đặc biệt

- README.md hiện là placeholder mặc định Flutter, không phản ánh hệ thống thật.
- Nguồn sự thật kiến trúc nên dựa vào file này + code thật trong lib và functions.

---

## 6. Bootstrap và lifecycle app (main.dart)

main.dart dài khoảng 972 dòng, là trung tâm khởi động toàn hệ thống.

### 6.1. Luồng khởi động tổng quát

1. WidgetsFlutterBinding.ensureInitialized
2. preserve splash
3. initializeDateFormatting vi_VN
4. enforce Firebase-only mode (bỏ qua flag backend cũ)
5. Khởi tạo Firebase + App Check (khác nhau giữa iOS và Android/Web)
6. Đăng ký background handler cho Firebase Messaging
7. Khởi tạo NotificationService và ConnectivityService
8. runApp(MyApp)

### 6.2. Tách nhánh iOS vs Android/Web

- iOS: chạy UI sớm để tránh cảm giác treo, init Firebase defer nền.
- Android/Web: init Firebase trước rồi chạy app.

### 6.3. AuthGate là cổng vào thực tế

AuthGate xử lý:

- Theo dõi authStateChanges
- Super admin route sang ShopSelectorView
- User thường route sang HomeView(role)
- Restore auth cache từ SharedPreferences
- Đồng bộ thông tin user/shop và claims
- Khởi tạo SyncOrchestrator, CashClosingNotifier, PaymentIntentService nền
- Clear local data khi đổi shop hoặc đổi user
- Purge dữ liệu ngoài shop hiện tại để chống lộ chéo tenant

### 6.4. Notification deep-link

AuthGate đăng ký navigation handler để mở nhanh:

- RepairDetailView từ targetType=repair
- SaleDetailView từ targetType=sale

---

## 7. Kiến trúc ứng dụng theo lớp

Hệ thống theo mô hình service-first, mọi nghiệp vụ đi qua service thay vì gọi Firebase trực tiếp từ UI.

1. UI layer: views + widgets
2. Service layer: business logic, sync, auth, notification, storage, payment
3. Data layer local: DBHelper + models
4. Cloud layer: Firestore + Functions + Storage + FCM

### 7.1. Pattern quan trọng

- Service-first access
- Singleton service ở các điểm điều phối (SyncOrchestrator, ClaimsService, EventBus)
- Upsert/merge-first thay vì overwrite
- Soft delete bằng cờ deleted
- Multi-tenant bằng shopId xuyên suốt

---

## 8. Mô hình dữ liệu cốt lõi

### 8.1. Repair (đơn sửa)

Trạng thái chuẩn:

- 1: nhận
- 2: đang sửa
- 3: đã xong
- 4: đã giao

Điểm quan trọng:

- pendingDeliveryApproval dùng cho trạng thái 3 cần duyệt giao.
- totalCost canonical ưu tiên cost; fallback servicesCost nếu cost=0.
- Có normalize status từ nhiều dạng dữ liệu cũ (string/int).
- Hỗ trợ services chi tiết theo RepairService (đối tác, phương thức thanh toán).

### 8.2. SaleOrder (đơn bán)

- Quản lý giá, vốn, giảm giá, góp, phương thức thanh toán hỗn hợp.
- Có field phục vụ đối soát bank installment.

### 8.3. Product

- Hỗ trợ type chuẩn hóa (DIEN_THOAI, LINH_KIEN, PHU_KIEN)
- Hỗ trợ mở rộng size, unit, expiryDate, variantParentId, customData cho đa ngành.

### 8.4. Nhóm model khác

- Customer, Supplier, Expense, Debt
- Attendance, LeaveRequest, SalaryBreakdown
- PaymentIntent, PaymentRequest
- RepairPartner, RepairPartnerPayment, PartnerRepairHistory
- StockEntry, ImportOrder, SalesReturn, SalvagePhone

---

## 9. SQLite local (offline-first)

DBHelper là trung tâm local data, khoảng 9072 dòng.

### 9.1. File và version

- DB file: repair_shop_v22.db
- openDatabase version: 95

### 9.2. Mục tiêu của local DB

- Cho phép app chạy mượt khi mạng chập chờn/offline
- Là nguồn dữ liệu hiển thị chính trên thiết bị
- Đồng bộ 2 chiều với Firestore qua SyncService + SyncOrchestrator

### 9.3. Bảng dữ liệu chính (rút gọn)

- repairs
- products
- sales
- customers
- suppliers
- expenses
- debts
- attendance
- leave_requests
- audit_logs
- supplier_payments
- repair_partner_payments
- cash_closings
- payroll_settings
- payroll_locks
- employee_salary_settings
- purchase_orders
- work_schedules
- debt_payments
- quick_input_codes
- supplier_product_prices
- supplier_import_history
- repair_partners
- partner_repair_history
- repair_parts
- sync_queue
- sales_returns
- sales_return_items
- financial_activity_log
- shop_settings
- product_categories
- product_variants
- salvage_phones
- import_orders
- import_order_items
- adjustment_entries
- payment_intents
- payment_requests

### 9.4. Cơ chế cờ chuẩn

- firestoreId: liên kết bản ghi cloud
- isSynced: trạng thái đồng bộ
- deleted: soft-delete marker
- updatedAt/createdAt: base cho conflict resolution

---

## 10. Đồng bộ dữ liệu (Sync)

Đây là phần quan trọng nhất của hệ thống vì app dùng chiến lược offline-first.

### 10.1. SyncService (cloud -> local)

Vai trò:

- Lắng nghe realtime collection theo quyền user
- Poll/refresh có kiểm soát cooldown
- Chuẩn hóa dữ liệu trước khi upsert local
- Phát event bus để UI refresh

Thông số kỹ thuật hiện tại:

- cloud read timeout: 20 giây
- cooldown log timeout read: 15 giây
- refresh collection cooldown: 5 giây
- poll limit mặc định: 20

### 10.2. SyncOrchestrator (local -> cloud)

Vai trò:

- Quản lý queue sync_queue cho create/update/delete
- Retry theo retryCount
- Upload ảnh và fallback folder theo Storage rules
- Chuẩn hóa payload nghiệp vụ (ví dụ repair status)

Thông số kỹ thuật:

- cloud write timeout: 25 giây
- cooldown log timeout write: 15 giây
- max retry mặc định: 3

### 10.3. Bảo vệ dữ liệu trong conflict

Các lớp bảo vệ đã có trong code:

- chuẩn hóa status repair về phạm vi 1..4
- giữ pendingDeliveryApproval nhất quán với status
- tránh ghi đè local bởi snapshot partial từ cloud
- bootstrap full payload khi patch status lên doc cloud chưa tồn tại

---

## 11. Phân quyền và multi-tenant

### 11.1. Vai trò

- super admin
- owner
- manager
- employee
- technician
- user (fallback)

### 11.2. Super admin

- Nhận diện bằng email admin@huluca.com
- Có thể chọn shop để xem dữ liệu toàn cục
- Bỏ qua filter shopId khi cần quản trị hệ thống

### 11.3. Permission flags chính

- allowViewSales
- allowViewRepairs
- allowViewInventory
- allowViewParts
- allowViewSuppliers
- allowViewCustomers
- allowViewPurchaseOrders
- allowCreatePurchaseOrders
- allowViewWarranty
- allowViewChat
- allowViewAttendance
- allowViewPrinter
- allowViewRevenue
- allowViewExpenses
- allowViewDebts
- allowViewCostPrice
- allowViewSettings
- allowManageStaff
- shopAppLocked
- shopAdminFinanceLocked

### 11.4. shopId là trục cô lập dữ liệu

- Query cloud luôn gắn shopId (trừ super admin).
- Query local scoped theo shopId.
- Khi đổi user/shop: clear local + purge dữ liệu ngoài shop.

---

## 12. Bảo mật dữ liệu

### 12.1. Firestore Rules

- rules_version = 2
- File rules có khoảng 1180 dòng
- Header rules ghi version 5.0 ngày 2026-01-10
- Ưu tiên user document cho role/shopId để tránh claims stale
- Claims vẫn là fallback

Nhóm collection được quản lý theo domain:

- AUTH: users, shops, invites
- BUSINESS: repairs, sales, products, customers
- FINANCE: expenses, debts, debt_payments, cash_closings, adjustment_entries
- SUPPLIER: suppliers, supplier_payments, purchase_orders
- PARTNER: repair_partners, repair_partner_payments
- HR: attendance, leave_requests, shift_swap_requests, work_schedules
- CHAT: chats, chat_messages
- NOTIFY: notifications, shop_notifications
- SYSTEM: audit_logs, quick_input_codes, repair_parts

### 12.2. Storage Rules

Nguyên tắc:

- Yêu cầu authenticated user
- Với folder shop-scoped, bắt buộc shopId path khớp claim hoặc super admin
- Chỉ cho upload image/*
- Giới hạn kích thước tối đa 10MB/file
- Mặc định chặn toàn bộ path không khai báo

### 12.3. Mã hóa dữ liệu (EncryptionService)

- AES-256-CBC
- Key derive từ shopId + master secret
- Đánh dấu payload mã hóa bằng _encrypted=true
- decryptMap hỗ trợ cả dữ liệu cũ không có marker nhưng có chuỗi ENC/ENC2
- Có cooldown log lỗi decrypt để tránh spam log

Trường nhạy cảm được mã hóa gồm: customerName, phone, address, email, notes, issue, imei, productImeis, bankName, description, accessories, warranty, ...

---

## 13. Payment architecture

PaymentIntentService là trung tâm thanh toán thống nhất.

Nguyên tắc:

- Tạo intent trước khi thực thi thanh toán
- Mỗi intent chỉ được execute một lần
- Validate qua MoneyValidationService
- Ghi nhận giao dịch qua MoneyTransactionService
- Persist vào DB local (payment_intents) và sync cloud

Các trạng thái chính:

- pending
- completed
- cancelled
- failed

Từ góc độ kiến trúc, đây là lớp bắt buộc để tránh nghiệp vụ tự trừ/thu tiền rải rác ở nhiều module.

---

## 14. Chat và thông báo

### 14.1. ChatService

Hỗ trợ:

- text message
- linked message (gắn với đơn sửa/đơn bán)
- image message (upload Firebase Storage)
- reaction, edit, soft delete, pin, read receipts
- typing indicator, online presence

### 14.2. NotificationService

Hỗ trợ:

- local notifications
- Firebase Messaging foreground/background
- push cloud notification
- rate limit: tối đa 3 thông báo trong 10 giây
- kiểm tra và làm mới FCM token định kỳ
- deep-link sang màn hình mục tiêu qua payload

Kênh thông báo Android:

- new_order_channel
- payment_channel
- inventory_channel
- staff_channel
- system_channel

---

## 15. In ấn và phần cứng

Hệ thống hỗ trợ nhiều ngữ cảnh in:

- hóa đơn bán hàng
- phiếu sửa chữa
- tem nhãn
- phiếu lương

Nhóm service liên quan:

- unified_printer_service
- thermal_printer_service
- bluetooth_printer_service
- wifi_printer_service
- web_print_bridge_service
- label_settings_service

Ngoài ra có scanner QR/IMEI và các màn hình thiết kế template in.

---

## 16. Social authentication

SocialAuthService xử lý:

- Google sign-in và link account
- Apple sign-in và link account
- Cơ chế account-exists-with-different-credential để tránh tạo UID mới
- Mục tiêu: bảo toàn dữ liệu user cũ khi thêm provider mới

---

## 17. Cloud Functions (functions/index.js)

File functions/index.js khoảng 1437 dòng, Node 20.

Các function export chính hiện có:

1. syncUserClaims
2. refreshMyClaims
3. updateUserRole
4. addUserToShop
5. updateUserProfileSecure
6. updateShopProfileSecure
7. removeUserFromShop
8. getUserClaims
9. notifyNewRepair
10. notifyNewChat
11. notifyStatusChange
12. createStaffAccount
13. cleanupDeletedRepairs
14. sendShopNotification
15. batchSyncAllClaims
16. syncUserClaimsV2
17. refreshMyClaimsV2
18. getMyClaimsV2
19. cleanupFCMTokens
20. deleteUserData

Vai trò backend trọng tâm:

- Đồng bộ custom claims role/shopId/isSuperAdmin
- Các thao tác bảo mật bắt buộc qua callable (khi client không đủ quyền trực tiếp)
- Trigger thông báo hệ thống
- Dọn dẹp dữ liệu định kỳ

---

## 18. Firestore indexes

- File: firestore.indexes.json
- Số composite index hiện có: 52
- Bao phủ các collection chính: payment_requests, repairs, sales, products, expenses, attendance, cash_closings, stock_entries, quick_input_codes, debt_payments, supplier_payments, repair_partner_payments, ...

Lưu ý vận hành:

- Một số query có fallback mode khi thiếu index (đặc biệt ở màn hình danh sách đơn sửa).
- Nên tạo đầy đủ index theo log Firestore để tránh degraded mode.

---

## 19. Localization và ngôn ngữ

- ARB source: app_vi.arb, app_en.arb
- Generated: app_localizations.dart, app_localizations_vi.dart, app_localizations_en.dart
- Supported locales: en, vi
- UI mặc định thiên về tiếng Việt

---

## 20. Đa ngành (multi-industry)

Nền tảng hiện đã có:

- businessType trong shop settings
- module food (expiry management)
- module fashion (variant management)
- category/variant/expiry trong data model và DB schema

Lưu ý trạng thái tài liệu:

- Có tham chiếu nội bộ đến file DOCS/MULTI_INDUSTRY_EXPANSION_GUIDE.md trong hướng dẫn AI.
- Ở workspace hiện tại không thấy file này trong thư mục DOCS.
- Khi bàn giao, nên bổ sung lại file guide này hoặc cập nhật đường dẫn tham chiếu tương ứng.

---

## 21. Danh sách service trọng yếu (đọc để nắm lõi)

1. user_service.dart: auth profile, role, permission, shop cache
2. firestore_service.dart: CRUD cloud chính
3. sync_service.dart: realtime cloud -> local
4. sync_orchestrator.dart: queue local -> cloud
5. db_helper.dart: schema + query local
6. payment_intent_service.dart: payment center
7. notification_service.dart: FCM + local notification
8. encryption_service.dart: encrypt/decrypt field nhạy cảm
9. claims_service.dart: custom claims lifecycle
10. storage_service.dart: upload/download ảnh với fallback rules-aware
11. category_service.dart + business_type_helper.dart: bật/tắt module đa ngành
12. salary_calculation_service.dart: engine tính lương

---

## 22. Danh sách màn hình quan trọng theo nghiệp vụ

### 22.1. Nền tảng

- splash_view
- login_view
- home_view
- shop_selector_view
- settings_view

### 22.2. Sửa chữa

- create_repair_order_view
- order_list_view
- repair_detail_view
- repair_partner_view
- parts_inventory_view
- warranty_view

### 22.3. Bán hàng và kho

- create_sale_view
- sale_list_view
- sale_detail_view
- inventory_view
- smart_stock_in_view
- import_history_view
- quick_input_codes_view

### 22.4. Tài chính

- revenue_view
- expense_view
- debt_view
- financial_report_view
- cash_closing_view
- bank_installment_report_view

### 22.5. Nhân sự

- attendance_view
- attendance_management_view
- staff_list_view
- staff_performance_view
- hr_salary_settings_view
- work_schedule_settings_view

### 22.6. Hỗ trợ vận hành

- advanced_chat_view
- notifications_view
- audit_log_view
- daily_activity_report_view
- firebase_rw_stats_view
- firestore_connectivity_test_view

---

## 23. Event bus và cập nhật UI

EventBus được dùng để đồng bộ trạng thái giữa nhiều màn hình không phụ thuộc trực tiếp.

Một số event điển hình:

- repairs_changed
- sales_changed
- expenses_changed
- products_changed
- debts_changed
- debt_payments_changed
- supplier_payments_changed
- repair_partner_payments_changed
- users_changed
- shopChanged
- dataRefresh

HomeView đăng ký listener cho phần lớn event để tự load lại thống kê.

---

## 24. Chất lượng mã nguồn và kiểm thử

### 24.1. Analyzer

- Sử dụng flutter_lints
- include từ package:flutter_lints/flutter.yaml

### 24.2. Test

- Thư mục test có nhiều nhóm test nghiệp vụ: tài chính, đồng bộ, model, QR, đa ngành, salary
- Có test scenario dạng markdown cho mô tả use case
- Đây là lớp bảo vệ regression quan trọng trước release

---

## 25. Build, chạy và deploy

### 25.1. App Flutter

- Cài dependencies: flutter pub get
- Chạy debug: flutter run
- Build APK release: flutter build apk --release
- Chạy test: flutter test
- Analyze: flutter analyze

### 25.2. Firebase

- Deploy functions: cd functions && npm install && firebase deploy --only functions
- Deploy rules/indexes/hosting theo firebase.json

### 25.3. Android build config

- compileSdk: 36
- targetSdk: 36
- Java/Kotlin target: 17
- Release bật minify + shrinkResources

---

## 26. Vận hành và troubleshooting

### 26.1. Nhóm lỗi thường gặp trong log

1. App Check chưa cài provider hoặc token placeholder
2. Firestore permission-denied do role/claims/shop mismatch
3. Storage 403 permission denied do sai path hoặc claim shopId
4. Thiếu Firestore index cho query phức hợp
5. Snapshot partial gây ghi đè dữ liệu nếu không merge đúng

### 26.2. Checklist debug nhanh

1. Xác nhận user đã có shopId hợp lệ
2. Kiểm tra claims role/shopId trong token
3. Kiểm tra rules Firestore/Storage và đường dẫn upload
4. Kiểm tra sync queue và cờ isSynced
5. Kiểm tra index theo link Firestore error
6. Đối chiếu local DB với cloud bằng sync health report

### 26.3. Lưu ý release

- Không bypass PaymentIntentService ở luồng tiền
- Không viết trực tiếp Firebase từ UI
- Không làm mất shopId trong dữ liệu mới
- Bảo toàn backward compatibility cho dữ liệu cũ (legacy rows)

---

## 27. Các tài liệu liên quan trong thư mục DOCS

Trong DOCS hiện có nhiều tài liệu phục vụ release/store/vận hành, ví dụ:

- APPSTORE_RELEASE_CHECKLIST.md
- APPSTORE_METADATA_COPY_PASTE_VI.md
- RELEASE_1.0.2_STORE_PACKAGE.md
- RELEASE_NOTES_11.0.1.md
- UAT_REPORT_APP_CHECK_2026-04-20.md
- WEB_PRINT_BRIDGE.md
- SYNC_OBSERVABILITY_PROGRESS.md

Khuyến nghị dùng file này làm tài liệu tổng hợp gốc, còn các file trên là tài liệu chuyên đề.

---

## 28. Onboarding cho kỹ sư mới (đọc theo thứ tự)

1. Đọc toàn bộ file này
2. Đọc main.dart để hiểu bootstrap/auth gate
3. Đọc user_service.dart + firestore_service.dart
4. Đọc db_helper.dart + sync_service.dart + sync_orchestrator.dart
5. Đọc repair_model.dart + sale_order_model.dart + product_model.dart
6. Chạy app local với dữ liệu test
7. Chạy test + analyze trước khi sửa tính năng

---

## 29. Checklist bàn giao kỹ thuật

1. Xác nhận phiên bản app và release notes
2. Xác nhận rules/indexes/functions đã deploy đúng môi trường
3. Xác nhận login role chính (owner/manager/employee/technician/super admin)
4. Xác nhận flow sửa chữa, bán hàng, công nợ, chốt quỹ, chat hoạt động
5. Xác nhận sync 2 chiều local-cloud không có bản ghi pending kéo dài
6. Xác nhận push notifications và deep-link hoạt động
7. Xác nhận in ấn và scanner trên thiết bị mục tiêu
8. Đính kèm tài liệu DOCS chuyên đề cho team vận hành

---

## 30. Kết luận

Quanlyshop là hệ thống quản trị cửa hàng quy mô lớn, thiên về offline-first, đa vai trò, đa nghiệp vụ và tích hợp sâu với Firebase.

Để giữ hệ thống ổn định trong production, các nguyên tắc sống còn là:

1. Service-first, không truy cập Firebase trực tiếp từ UI.
2. Luôn giữ nhất quán shopId và phân quyền theo role/claims.
3. Đồng bộ có kiểm soát timeout/retry, tránh ghi đè dữ liệu bởi snapshot partial.
4. Duy trì test nghiệp vụ và kiểm tra log runtime trước khi release.

Tài liệu này là điểm vào duy nhất để nắm toàn cảnh kiến trúc và vận hành dự án.
