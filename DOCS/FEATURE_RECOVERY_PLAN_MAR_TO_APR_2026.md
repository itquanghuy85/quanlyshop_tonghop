# Bao cao Audit Tinh nang (03/2026 -> 04/2026) va Ke hoach Khoi phuc

## Cap nhat trang thai 2026-04-19 (Firebase-only)

- Da chot he thong chay Firebase-only tren `master`.
- Commit da phat hanh: `v276 - Chuyen he thong ve Firebase-only, loai bo MongoDB local mode`.
- Runtime da them guard bo qua cac `dart-define` cu: `LOCAL_API_BASE_URL`, `MONGODB_URI`, `USE_MONGO`.
- Da xoa thu muc local `backend/` trong workspace de tranh chay nham local mode.
- Da xac nhan lai: `flutter test` (552 passed) va `flutter build apk --debug --no-pub` thanh cong.
- Luu y: cac noi dung Mongo/API ben duoi la lich su audit phuc vu doi chieu, khong con duoc su dung lam huong runtime hien tai.

Ngay lap: 2026-04-18
Nguon du lieu:
- git log --first-parent origin/master --since=2026-03-01
- git log --first-parent origin/mongodb-mode --since=2026-03-01
- git log HEAD..origin/mongodb-mode --since=2026-03-01
- git show rollback commit bc6cd07

## 1) Tong quan nhanh

- Nhanh github hien tai dang chay de test iPhone: test/v262-firebase-iphone
- Build hien tai: 11.3.4+265
- Head commit: 74ab33c

So lieu commit tu 2026-03-01:
- Dong chinh Firebase (origin/master, first-parent): 239 commit
- Dong mo rong Mongo/API (origin/mongodb-mode, first-parent): 409 commit
- Chenh lech chua co tren ban hien tai so voi Mongo line: 192 commit
- Chinh sua rollback v262 (bc6cd07): 51 files changed, ~2962 insertions, ~7543 deletions

Ket luan tong quan:
- Ban hien tai da dung Firebase line (khong thieu commit so voi origin/master).
- Tuy nhien, sau rollback v262 va diverge branch, mot luong lon tinh nang/cải tien (dac biet 192 commit v295->v444 tren mongodb-mode) chua co trong ban hien tai.

## 2) Mo ta chi tiet toan bo project (state hien tai)

### 2.1 Cong nghe va kieu kien truc

- Frontend: Flutter (Dart)
- Auth + cloud: Firebase Auth, Firestore, Storage, Functions, FCM
- Local offline: SQLite (sqflite), web fallback sqflite_common_ffi_web
- In an/tem nhan: Niimbot BLE, thermal printer, esc/pos wrappers
- Export/report: Excel, PDF, printing
- Localization: VI/EN (ARB)

Kien truc tong quat:
- UI (lib/views) -> Service layer (lib/services) -> Data layer (Firebase + SQLite) -> Sync layer (SyncService/SyncOrchestrator)
- Muc tieu van hanh: Offline-first, dong bo theo shopId, soft-delete, incremental sync

### 2.2 Entry points va dong startup

- Main app bootstrap: lib/main.dart
- Auth gate + role routing: trong main.dart (AuthGate)
- Deferred init tren iOS de giam cam giac freeze startup
- Notification listeners va FCM background handler duoc dang ky trong startup

### 2.3 Cau truc module lon

UI man hinh:
- Thu muc: lib/views
- Nhom chuc nang: home, sales, repair, inventory, finance, HR/attendance, reports, settings, printing

Service layer:
- Thu muc: lib/services
- Nhom service trong tam:
  - Firestore/data CRUD: firestore_service.dart
  - User/role/permissions/shopId cache: user_service.dart
  - Sync realtime + incremental: sync_service.dart, sync_orchestrator.dart
  - Notification: notification_service.dart
  - Finance: payment_intent_service.dart, debt_summary_service.dart, financial_activity_service.dart
  - HR: attendance_approval_service.dart, salary_calculation_service.dart
  - Inventory: stock_entry_service.dart, supplier_service.dart, category/variant services
  - Printing: unified_printer_service.dart, bluetooth_printer_service.dart, wifi_printer_service.dart

Data + models:
- Thu muc model: lib/models
- Thu muc DB helper: lib/data/db_helper.dart
- DB file: repair_shop_v22.db
- DB schema version hien tai: 93

### 2.4 Bang du lieu trong SQLite (tom tat)

Cac bang chinh dang co trong DB helper:
- repairs, products, sales, customers, suppliers
- expenses, debts, debt_payments
- attendance, leave_requests, work_schedules
- purchase_orders, import_orders, import_order_items
- quick_input_codes, repair_parts, repair_partners, partner_repair_history
- payment_intents, payment_requests
- sales_returns, sales_return_items
- financial_activity_log, cash_closings, adjustment_entries
- product_categories, product_variants, salvage_phones, shop_settings
- sync_queue, audit_logs, employee_salary_settings, payroll_locks, payroll_settings

Mau field canh tranh dong bo duoc su dung rong rai:
- firestoreId, shopId, createdAt, updatedAt, deleted/isDeleted, isSynced

### 2.5 Da nen nghiep vu

- Domain app: quan ly tiem sua chua + mua ban dien thoai
- Cac luong nghiep vu truc tiep:
  - Sua chua: tiep nhan, cap nhat trang thai, giao may, linh kien su dung
  - Ban hang: tao don, thanh toan, tra hang
  - Kho: nhap kho, fast input, salvage inventory
  - Tai chinh: thu/chi, so quy, cong no, dong tien
  - Nhan su: cham cong, nghi phep, luong, hieu suat
  - Van hanh: thong bao, chat noi bo, diagnostics, health checks

## 3) Liet ke chi tiet tinh nang moi tu thang 3 den nay

Luu y:
- Danh sach duoi day la tinh nang/cải tien moi ghi nhan tu commit logs 03/2026 -> 04/2026.
- Bao gom ca dong Firebase va dong mo rong Mongo/API.

### 3.1 Giai doan 03/01 -> 03/15 (nen tang va business features)

1. Chinh sach bao hanh/doi tra in hoa don (eaa8d47)
2. iOS Firebase crash + Xcode compat hardening (3d30eca, 1e3574e, 2580de0, 3870711)
3. Bao mat key Firebase qua dart-define (8b6886a)
4. Sales Return feature day du (017e62c, 1d10c10, 6adac4f)
5. Tai chinh redesign + charts fl_chart + monthly profit (b13469d, 0366eda, a6ee0ec, baddc75)
6. Finance shortcuts tren Home + debt summary cards (9248d0c, f2b1d8f)
7. Payment request chat + tich hop thu/chi (dc9c9e4, 019612a, c2d28a3, 817c259)
8. Super admin professional shop selector (f9ecce2, 6e441aa, 8ef6a5b)
9. Google/Apple sign-in + link/unlink account card settings (323aeec, e6b0d56, 929855f)
10. Delete account cho Apple guideline 5.1.1(v) (877ec9d, 9e2581a)
11. Register page social sign-in + wizard fix (72582cc)
12. Import order history system + shortcut + export Excel (33f1eca, 01432c4, 8b76a17)
13. Kho linh kien sua chua + filter chips + xuat Excel doi tac/NCC (482617f, 58f83f8, 7d8f465)
14. Task reminders role-based (408ee3c)
15. Attendance 3-tab UI + leave requests + salary filters (5b60860, a761111)
16. iOS/web fixes: logout web, keyboard IP printer, FCM entitlement/tokens (0e4d059, d32751f, f225e95)
17. Permission hardening rong khap app (f47de02, 4f5d9bc, 8356dfb)

### 3.2 Giai doan 03/16 -> 03/31 (on dinh hoa tac vu va sync)

1. Luu tam don ban + don sua; hien thi gia von tung mon theo phan quyen (d49ad1f)
2. Sua field mapping RepairService serviceName (ec19bff)
3. Apple sign-in invalid OAuth response fix (6101cbb)
4. Profit don sua + toi uu UI cong no + tai chinh back behavior fix (6c55716, 71b98e4)
5. Link/unlink social update UI ngay, khong can restart (13fd6f3, 8d448b2, 5f8a84b)
6. Xu ly race condition link account + owner permission update (42bfa4f, 1c8a894, 55c33c2)
7. Khong nhan nham du lieu/shop thong bao cu (847f5fe, 71a787f)
8. Loai bo spinner vo han khi ban hang/giao may/signOut (dd0511f, c98e540)
9. Giam flash/flicker sau login do idTokenChanges loop (fc4b418)
10. Dong bo do bong vang/do do claims + failed items recovery (11545fe)
11. Hardening sync timeout, fire-and-forget, retries, non-blocking UI (2903ff2, f5764d8, 52c6ec6, f2e934b)
12. Thiet lap timeout Firestore cho nhieu luong nghiep vu (e0c9289, e56f0bc)

### 3.3 Giai doan 04/01 -> 04/11 (quality wave va diagnostics)

1. Critical sync data integrity: shopId + timestamp + soft-delete (94bc482)
2. Sua timeout toan app + fallback cache (73798a3, c5d6ca7, e7529f5)
3. Salvage inventory + sync + QR fixes (5ed0b7a, 23a67d3, 68caeb5)
4. Deep-link thong bao vao thang man chi tiet don (f2b1431)
5. Expense category filter, finance logic fixes, daily report improvements (fba4b26, 0808d53)
6. EXC_BAD_ACCESS hardening: idempotency key auto + double-tap guard + leak fixes (6619486)
7. Expense scope SHOP/CA NHAN va exclusion logic trong revenue (339bf05)
8. Dark theme + VI/EN switch qua AppSettingsService (256b369)
9. Health check dashboard (8b4954a, 557613f, edd3d9b, f072015)
10. App diagnostics center + auto-fix queue + open error record/copy report (cd7791c, 822572f, ddd7538, ea2af26)
11. Firestore connectivity test page step-by-step (9dfa57b)
12. Niimbot B1 BLE + PTY label designer + iOS BLE permission/timeout fixes (88549b7, da86e97, 84c5a56, 54c5365, 070f99f)
13. Chat/staff/salary spinner fixes + Firestore cache tuning + listener storm reduction (a7d15f1, 5a0d5be, 6887be7, e96c632)
14. Them man hinh Hoat dong gan day (2e35c40)
15. Firebase stats dashboard read/write realtime metrics (cdb07d5)

### 3.4 Giai doan 04/11 -> 04/15 (dong local backend + Mongo/API migration)

1. Them backend local Express + JWT auth + upload local (f150428)
2. Chuan hoa local/prod API base URL va deploy Vultr/Atlas (bf0995a, ccdb518, b418975)
3. Port local mode cho sales/repair/expense/supplier/fast stock in (a893cdf, 3f14eb4, 0dacdbb)
4. Guard Firebase no-app trong local mode, lazy init service (9cdb732, a14c617)
5. MongoDB cloud migration + chat API route/model (c7a05d5)
6. Phase migration 7-10: mo rong sync 15 entities + smoke test (b8552fa)
7. Chuoi bugfix Mongo mode (v433->v444):
   - chat image upload/sync
   - debt/payment sync
   - attendance field mapping
   - API mode cash flow correctness
   - bootstrap consistency shopId
   - local DB stream cho payment requests
   (5161623, 363815d, e51b908, 13544ef, 99c0efc, 41ed027, 2ba4b79, ea02166, 21481ee, 7876321, 637687a)

### 3.5 Giai doan 04/18 (rollback va sau rollback)

1. Rollback lon ve stable base v262 (bc6cd07)
2. Sau rollback, bo sung 2 fix:
   - v263: crash iOS + splash lifecycle + DB migration idempotent (5a31573)
   - v264: chuan hoa PRAGMA DBHelper sang rawQuery (6a66582)
3. Nhieu module bi mat/bi thu gon trong rollback (xac nhan qua diff)

## 4) Tinh nang da mat tren ban hien tai (xac nhan)

### 4.1 Mat chac chan do rollback v262

Xac nhan tu bc6cd07:
- Xoa hoan toan firebase stats module:
  - lib/services/firebase_stats_service.dart (deleted)
  - lib/views/firebase_stats_view.dart (deleted)
- Xoa man hinh Hoat dong gan day:
  - lib/views/recent_activity_view.dart (deleted)
- Xoa module doi ca:
  - lib/models/shift_swap_model.dart (deleted)
  - lib/services/shift_swap_service.dart (deleted)
  - lib/views/shift_swap_tab.dart (deleted)
- Thu gon/roll back manh cac man hinh: settings, home, attendance_management, debt, inventory, expense, create_sale, create_repair, sale_detail...

### 4.2 Mat chac chan do chua co 192 commit tren Mongo/API line

Tinh den hien tai, HEAD thieu 192 commit so voi origin/mongodb-mode (tu v295 den v444).
Cac cum tinh nang bi thieu noi bat:
- Diagnostics va health center nang cao (auto-fix sau, report thao tac)
- Chat/staff/salary spinner hardening wave (v401-v402)
- Recent activity list phan trang + filter role (v376)
- Expense scope SHOP/CA NHAN (v314)
- Notification deep-link vao sale/repair detail (v308)
- Idempotency + double-tap guard + memory leak hardening (v312)
- Niimbot full flow + PTY designer (v337-v343)
- Local backend/API mode + Mongo migration phases (v403-v444)

## 5) Ke hoach khoi phuc tinh nang bi mat (de xuat chi tiet)

Nguyen tac:
- Uu tien Firebase-compatible features truoc, khong dua Mongo architecture vao ban Firebase production neu chua co yeu cau.
- Khoi phuc theo cum nho, moi cum co regression test va smoke test.
- Giu shopId isolation, idempotency, soft-delete, updatedAt logic.

### Phase 0 - Dong bang baseline va co che an toan (1-2 ngay)

Muc tieu:
- Tao nhanh recovery tren Firebase, khong pha du lieu that.

Viec can lam:
1. Tao branch: recovery/firebase-feature-backfill-v266
2. Bat feature flags cho module khoi phuc lon (diagnostics, recent_activity, firebase_stats)
3. Them checklist migration DB idempotent cho cac bang lien quan
4. Chuan hoa test smoke matrix tren iPhone/Android/Web

Done criteria:
- App boot on dinh, schema khong crash, toggle module an toan.

### Phase 1 - Khoi phuc P0 business critical (3-5 ngay)

Muc tieu:
- Khoi phuc tinh nang anh huong truc tiep giao dich va du lieu tien.

Nguon commit tham chieu:
- 94bc482, 6619486, f2b1431, 339bf05, e47bfa9, a7d15f1

Hang muc:
1. Deep-link thong bao vao chi tiet don ban/sua
2. Expense scope SHOP/CA NHAN + loai tru doanh thu chinh xac
3. Idempotency key + anti double-tap tren tao giao dich
4. Spinner hardening cho chat/staff/salary
5. Sync integrity guard (shopId, updatedAt, soft-delete, retries)

Done criteria:
- Khong tao don trung, khong treo loading vo han, so quy/thu-chi dung logic.

### Phase 2 - Khoi phuc module van hanh va giam rui ro support (3-4 ngay)

Nguon commit tham chieu:
- cd7791c, 822572f, ddd7538, ea2af26, f072015, 9dfa57b

Hang muc:
1. App diagnostics center
2. Health check dashboard
3. Firestore connectivity test view
4. Auto-fix scripts co guard (chi chay khi co xac nhan)

Done criteria:
- Co dashboard debug nhanh, support tim root cause trong 5-10 phut.

### Phase 3 - Khoi phuc printing/labels + hardware quality (2-3 ngay)

Nguon commit tham chieu:
- 88549b7, da86e97, 84c5a56, 54c5365, 070f99f

Hang muc:
1. Niimbot B1 + PTY label designer
2. BLE permissions flow iOS
3. In tem timeout/error messaging ro rang

Done criteria:
- In tem thanh cong tren iOS/Android voi 3 mau kich thuoc tem.

### Phase 4 - Khoi phuc firebase stats + recent activity + shift swap (2-4 ngay)

Nguon commit tham chieu:
- cdb07d5, 2e35c40, 38600b8

Hang muc:
1. Firebase Read/Write stats page
2. Recent activity view (filter, paging, role)
3. Shift swap module (neu con nhu cau nghiep vu)

Done criteria:
- Settings co lai cac muc thong ke/hoat dong can thiet.

### Phase 5 - Danh gia va tach rieng nhom Mongo/API mode (song song)

Nguon commit tham chieu:
- f150428 -> 637687a (v403-v444)

Huong xu ly:
- Khong merge thang toan bo vao Firebase branch.
- Tach theo 3 nhom:
  1) Reusable logic khong phu thuoc Mongo (co the backport)
  2) Logic can adapter Firebase (port 1 phan)
  3) Logic chi danh cho local backend/Mongo (giu branch rieng)

Done criteria:
- Co danh sach commit nao cherry-pick duoc ngay, commit nao can rewrite.

## 6) Ma tran uu tien khoi phuc

P0 (lam ngay):
- Deep-link notification (f2b1431)
- Expense scope SHOP/CA NHAN (339bf05)
- Idempotency + anti double-tap + leak fixes (6619486)
- Spinner/sync hardening (a7d15f1, 94bc482)

P1:
- Diagnostics center + health checks (cd7791c, f072015)
- Recent activity (2e35c40)
- Niimbot full flow (88549b7 + 070f99f)

P2:
- Firebase stats dashboard (cdb07d5)
- Shift swap module phuc hoi theo nhu cau nghiep vu (38600b8)

P3:
- Mongo/API mode migration track (f150428 -> 637687a) de danh gia tich hop sau

## 7) Checklist test bat buoc sau moi phase

1. CRUD tao/sua/xoa tren: sales, repairs, expenses, debts, customers
2. Multi-device sync: tao du lieu may A, kiem tra may B
3. Shop isolation: tuyet doi khong leak du lieu giua shop
4. No duplicate: tao don, thanh toan no, payment intents
5. Offline/online transition: queue len cloud khong treo
6. iOS startup: khong freeze splash, khong crash Firebase init
7. Notification tap-routing dung vao man chi tiet
8. Printer flow: scan, connect, print, timeout fallback

## 8) De xuat cach trien khai practical

Cach merge de an toan:
- Khong merge nguyen branch mongodb-mode vao Firebase line.
- Chon commit theo nhom (cherry-pick -n), resolve conflict theo huong Firebase-first.
- Sau moi nhom 5-10 commit: chay smoke test + commit nho.

Nhan su de xuat:
- 1 nguoi core app (service/sync)
- 1 nguoi UI/UX regression
- 1 nguoi QA iOS + Android + Web

Milestone de xuat:
- M1 (P0) 3-5 ngay
- M2 (P1) +3-4 ngay
- M3 (P2/P3) +4-7 ngay

## 9) Ket luan

- Tu 03/2026 den nay da co so luong lon tinh nang moi va quality fixes.
- Ban hien tai dung Firebase base de test iPhone, nhung da mat nhieu module quan trong sau rollback va diverge.
- Ke hoach khuyen nghi: khoi phuc theo phase, uu tien P0/P1, bỏ qua merge tong khoi Mongo line de tranh dua rui ro kien truc vao production Firebase.
