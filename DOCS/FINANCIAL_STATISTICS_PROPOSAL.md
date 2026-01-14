# Giải Pháp Thiết Kế Trang Thống Kê Tài Chính

## Tổng Quan

Đề xuất nâng cấp trang **Revenue View** hiện tại thành trang **Thống Kê Tài Chính** toàn diện với các thông tin:
- Doanh thu (bán hàng + sửa chữa)
- Công nợ phải thu
- Chi phí (nhập hàng, chi tiêu)
- Lợi nhuận ròng

## Hiện Trạng

File: `lib/views/revenue_view.dart` đã có:
- ✅ Filter theo thời gian: Hôm nay, 7 ngày, Tháng này, Tùy chọn
- ✅ Dữ liệu: repairs, sales, expenses, closings, debtPayments, supplierImports
- ✅ Phân quyền xem doanh thu

## Đề Xuất Thiết Kế

### 1. Bổ Sung Filter "Năm Nay" và "Quý"

```dart
// Thêm vào _timeFilter options
String _timeFilter = 'today'; // today, week, month, quarter, year, custom
```

### 2. Dashboard Tổng Hợp (Tab Mới)

```
┌─────────────────────────────────────────────────┐
│            THỐNG KÊ TÀI CHÍNH                   │
│        [Hôm nay] [Tuần] [Tháng] [Năm] [...]    │
├─────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐              │
│  │ DOANH THU   │  │ CHI PHÍ     │              │
│  │  45,000,000 │  │  30,000,000 │              │
│  │ ▲ +15%      │  │ ▲ +5%       │              │
│  └─────────────┘  └─────────────┘              │
│  ┌─────────────┐  ┌─────────────┐              │
│  │ LỢI NHUẬN   │  │ CÔNG NỢ     │              │
│  │  15,000,000 │  │   8,000,000 │              │
│  │ ▲ +20%      │  │ ▼ -10%      │              │
│  └─────────────┘  └─────────────┘              │
├─────────────────────────────────────────────────┤
│  📊 BIỂU ĐỒ DOANH THU THEO NGÀY/THÁNG          │
│  [Chart - có thể dùng fl_chart package]         │
├─────────────────────────────────────────────────┤
│  📋 CHI TIẾT                                    │
│  • Bán hàng: 30,000,000 (10 đơn)               │
│  • Sửa chữa: 15,000,000 (25 đơn)               │
│  • Thu nợ:    5,000,000 (3 khách)              │
│  • Nhập hàng: 20,000,000 (5 NCC)               │
│  • Chi tiêu:  10,000,000 (8 khoản)             │
└─────────────────────────────────────────────────┘
```

### 3. Cấu Trúc Dữ Liệu Tính Toán

```dart
class FinancialSummary {
  // THU
  final int saleRevenue;      // Doanh thu bán hàng (đã thanh toán)
  final int repairRevenue;    // Doanh thu sửa chữa (status == 4)
  final int debtCollected;    // Nợ đã thu
  final int bankSettlement;   // Tiền tất toán NH
  
  // CHI
  final int supplierPayments; // Thanh toán NCC
  final int expenses;         // Chi tiêu khác
  final int saleCost;         // Giá vốn hàng bán
  final int repairCost;       // Chi phí sửa chữa
  
  // NỢ
  final int customerDebt;     // Nợ khách phải thu
  final int supplierDebt;     // Nợ NCC phải trả
  final int bankPending;      // Tiền NH chưa nhận
  
  // Getters
  int get totalRevenue => saleRevenue + repairRevenue + debtCollected + bankSettlement;
  int get totalExpense => supplierPayments + expenses + saleCost + repairCost;
  int get netProfit => totalRevenue - totalExpense;
  int get receivables => customerDebt + bankPending;
  int get payables => supplierDebt;
}
```

### 4. Files Cần Sửa/Tạo

| File | Hành động | Mô tả |
|------|-----------|-------|
| `lib/views/revenue_view.dart` | Sửa | Thêm filter năm, quý |
| `lib/views/financial_dashboard_view.dart` | Tạo mới | Dashboard tổng hợp |
| `lib/models/financial_summary_model.dart` | Tạo mới | Model tính toán |
| `lib/services/financial_service.dart` | Tạo mới | Logic tổng hợp |

### 5. Package Đề Xuất

```yaml
# pubspec.yaml
dependencies:
  fl_chart: ^0.65.0  # Biểu đồ đẹp
```

### 6. Quyền Truy Cập

Chỉ hiển thị cho:
- Admin (super admin email)
- User có quyền `allowViewRevenue: true`

### 7. Ưu Tiên Triển Khai

1. **Phase 1** (Nhanh): Thêm filter "Năm nay", "Quý này" vào revenue_view hiện tại
2. **Phase 2** (Trung bình): Tạo FinancialSummary model và tính toán tổng hợp
3. **Phase 3** (Dài hạn): Tạo dashboard mới với biểu đồ

## Kết Luận

Trang `revenue_view.dart` hiện tại đã có nền tảng tốt. Nên nâng cấp dần từ việc:
1. Thêm filter thời gian (năm, quý)
2. Tạo summary card tổng hợp ở đầu trang
3. Sau đó mới tách thành dashboard riêng nếu cần

---
*Tài liệu này được tạo bởi AI Agent - 14/01/2026*
