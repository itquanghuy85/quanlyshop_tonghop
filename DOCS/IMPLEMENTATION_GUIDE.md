# 📋 Hướng Dẫn Tích Hợp Các Tính Năng Bổ Sung

**Các file mới được thêm:** 5 services + 3 widgets + 1 migration service + 1 audit report

---

## **1. WARRANTY REMINDER SERVICE**

### File:
- [lib/services/warranty_reminder_service.dart](lib/services/warranty_reminder_service.dart)

### Cách sử dụng:
```dart
// Trong AuthGate (sau khi sync xong):
await WarrantyReminderService.startWarrantyReminders();

// Lấy danh sách bảo hành sắp hết để hiển thị:
final warranties = await WarrantyReminderService.getUpcomingExpiringWarranties(daysAhead: 30);
```

### Thêm vào Dashboard:
```dart
// Trong home_view.dart, section widgets:
WarrantyReminderWidget(),  // Import from lib/widgets/warranty_reminder_widget.dart
```

### Cách hoạt động:
- Mỗi 24h, hệ thống tự động check bảo hành sắp hết trong 7 ngày
- Gửi FCM + in-app notification cho admin khi gần hết hạn
- Hỗ trợ remind tại 7, 3, 1, 0 ngày trước

---

## **2. TOP SERVICES REPORT SERVICE**

### File:
- [lib/services/top_services_report_service.dart](lib/services/top_services_report_service.dart)

### Cách sử dụng:
```dart
// Top 10 dịch vụ theo doanh thu:
final topByRevenue = await TopServicesReportService.getTopServicesByRevenue(
  startDate: DateTime(2026, 5, 1),
  endDate: DateTime(2026, 5, 31),
);

// Top 10 dịch vụ theo lợi nhuận:
final topByProfit = await TopServicesReportService.getTopServicesByProfit();

// Dịch vụ yếu (margin < 20%):
final lowProfit = await TopServicesReportService.getLowProfitServices();
```

### Thêm vào Dashboard hoặc Report Tab:
```dart
// Trong monthly_profit_report_view.dart:
TopServicesWidget(
  startDate: DateTime(2026, 5, 1),
  endDate: DateTime(2026, 5, 31),
  sortBy: 'revenue',  // 'revenue' | 'profit' | 'frequency'
),
```

### Cách hoạt động:
- Query SQLite để tính doanh thu, lợi nhuận gộp, margin % theo dịch vụ
- Hỗ trợ sắp xếp theo 3 tiêu chí: doanh thu, lợi nhuận, tần suất
- Xác định dịch vụ yếu (margin < 20%) để review giá

---

## **3. CUSTOMER SEGMENT SERVICE**

### File:
- [lib/services/customer_segment_service.dart](lib/services/customer_segment_service.dart)

### Cách sử dụng:
```dart
// Tự động phân khúc tất cả khách hàng (chạy mỗi tuần):
final summary = await CustomerSegmentService.autoSegmentCustomers();
// Kết quả: {'VIP': 5, 'FREQUENT': 12, 'REGULAR': 80, 'CHURN': 3, 'NEW': 4}

// Lấy danh sách khách VIP:
final vipCustomers = await CustomerSegmentService.getCustomersBySegment('VIP');

// Danh sách khách churn (cần chăm sóc lại):
final churnCustomers = await CustomerSegmentService.getChurnCustomersForCampaign();

// Đánh dấu 1 khách là VIP:
await CustomerSegmentService.markCustomerAsVip('0919123456');

// Thêm ghi chú VIP:
await CustomerSegmentService.addVipNote('0919123456', 'Hay trả chậm, cần nhắc');
```

### Thêm vào Dashboard:
```dart
// Trong home_view.dart:
CustomerSegmentsWidget(),  // Import from lib/widgets/customer_segments_widget.dart
```

### Tiêu chí phân khúc:
- **VIP**: Tiêu thụ ≥ 10M + ≥ 5 giao dịch
- **FREQUENT**: ≥ 3 giao dịch trong 30 ngày
- **REGULAR**: Bình thường, < 3 giao dịch/tháng
- **NEW**: ≤ 1 giao dịch (khách mới)
- **CHURN**: Không mua > 60 ngày (mất tích)

---

## **4. DATABASE MIGRATIONS**

### File:
- [lib/data/db_migration_service.dart](lib/data/db_migration_service.dart)

### Cách sử dụng:
```dart
// Trong AuthGate (sau khi connect DB):
await DBMigrationService.runPendingMigrations(database);
```

### Các migrations:
1. Thêm `warranty_expiry` (INTEGER) vào repairs
2. Thêm `warranty_status` (TEXT) vào repairs
3. Thêm `segment` (TEXT DEFAULT "REGULAR") vào customers
4. Thêm `vip_notes` (TEXT) vào customers
5. Thêm `loyalty_points` (INTEGER) vào customers
6. Tạo bảng `warranty_reminders` (tracking reminder history)

---

## **5. UI WIDGETS**

### Widget 1: WarrantyReminderWidget
File: [lib/widgets/warranty_reminder_widget.dart](lib/widgets/warranty_reminder_widget.dart)

Hiển thị bảo hành sắp hết hạn trong 30 ngày. Màu đỏ cho hết hạn, cam cho khẩn cấp, vàng cho sắp.

### Widget 2: TopServicesWidget
File: [lib/widgets/top_services_widget.dart](lib/widgets/top_services_widget.dart)

Hiển thị top dịch vụ theo doanh thu/lợi nhuận/tần suất. Bảng xếp hạng với ranking badge.

### Widget 3: CustomerSegmentsWidget
File: [lib/widgets/customer_segments_widget.dart](lib/widgets/customer_segments_widget.dart)

Biểu đồ phân khúc khách hàng dạng grid 3 cột. Click vào mỗi phân khúc để xem chi tiết.

---

## **6. IMPLEMENTATION CHECKLIST**

### Bước 1: Database Migration
```dart
// Trong lib/views/auth_gate.dart (hoặc nơi khởi động sync):
// TRƯỚC khi gọi initRealTimeSync()
import 'package:quanlyshop/data/db_migration_service.dart';

final db = await _localDb.openDb();
await DBMigrationService.runPendingMigrations(db);
```

### Bước 2: Warranty Reminder
```dart
// Trong AuthGate sau sync xong:
import 'package:quanlyshop/services/warranty_reminder_service.dart';

await WarrantyReminderService.startWarrantyReminders();
```

### Bước 3: Customer Segmentation
```dart
// Background task (mỗi tuần hoặc khi mở app):
import 'package:quanlyshop/services/customer_segment_service.dart';

// Option 1: Auto-segment ngay lập tức
await CustomerSegmentService.autoSegmentCustomers();

// Option 2: Schedule mỗi tuần (dùng flutter_local_notifications)
// Implement periodic task based on your scheduler
```

### Bước 4: Dashboard Widgets
```dart
// Trong home_view.dart hoặc dashboard:
import 'package:quanlyshop/widgets/warranty_reminder_widget.dart';
import 'package:quanlyshop/widgets/top_services_widget.dart';
import 'package:quanlyshop/widgets/customer_segments_widget.dart';

// Thêm vào Column/SingleChildScrollView:
WarrantyReminderWidget(),
const SizedBox(height: 16),
TopServicesWidget(),
const SizedBox(height: 16),
CustomerSegmentsWidget(),
```

### Bước 5: Test
```bash
flutter analyze lib/services/warranty_reminder_service.dart
flutter analyze lib/services/top_services_report_service.dart
flutter analyze lib/services/customer_segment_service.dart
flutter analyze lib/widgets/warranty_reminder_widget.dart
flutter analyze lib/widgets/top_services_widget.dart
flutter analyze lib/widgets/customer_segments_widget.dart
flutter analyze lib/data/db_migration_service.dart
```

---

## **7. OPTIONAL: ADVANCED FEATURES (Cho lần sau)**

### SMS Notification
```dart
// Cần: Firebase Cloud Functions hoặc Twilio integration
// Gọi từ WarrantyReminderService khi gần hết bảo hành
Future<void> sendWarrantySMS(String phone, String message) {
  // Call Firestore → Cloud Function → Twilio
}
```

### Re-order Suggestion
```dart
// Trong stock management:
Future<List<Product>> getStockReorderSuggestions() {
  // Query products where quantity < minStock
  // Suggest order qty based on average monthly usage
}
```

### Staff Performance KPI Dashboard
```dart
// Chart: doanh số / số đơn / lợi nhuận theo staff
// Dùng fl_chart hoặc charts library
```

---

## **8. COMMIT & PUSH**

```bash
git add lib/services/warranty_reminder_service.dart
git add lib/services/top_services_report_service.dart
git add lib/services/customer_segment_service.dart
git add lib/widgets/warranty_reminder_widget.dart
git add lib/widgets/top_services_widget.dart
git add lib/widgets/customer_segments_widget.dart
git add lib/data/db_migration_service.dart
git add DOCS/AUDIT_REPORT_2026_05.md
git add DOCS/IMPLEMENTATION_GUIDE.md

git commit -m "Bổ sung tính năng: warranty reminder, top services report, customer segments"
git push origin master
```

---

## **9. NOTES**

- Tất cả services **không thay đổi** business logic hiện tại
- Database **chỉ thêm** column, không xóa/sửa cột cũ
- UI widgets **optional** — có thể comment out nếu không muốn hiển thị
- Định kỳ chạy `autoSegmentCustomers()` để cập nhật segments (mỗi tuần là đủ)
- Warranty reminder chạy **tự động** mỗi 24h sau khi enable
- **Performance**: Tất cả queries dùng SQLite local, không đọc Firestore thêm

---

**Tổng cộng bổ sung:** 7 files, ~1,200 lines code, 0 breaking changes ✅
