# Multi-Shop Phase 1 - Hướng dẫn sử dụng

## Tổng quan

Multi-Shop Phase 1 cho phép **chủ cửa hàng (owner)** quản lý nhiều chi nhánh từ một tài khoản duy nhất.

## Tính năng

### 1. Chuyển đổi Shop
- **Vị trí**: Cài đặt → Chọn cửa hàng
- **Điều kiện hiển thị**: Chỉ hiển thị khi user có role `owner` VÀ sở hữu >= 2 shops
- **Chức năng**: Dropdown cho phép chọn shop để quản lý

### 2. Shop Indicator
- **Vị trí**: AppBar của Home view
- **Hiển thị**: Tên shop đang hoạt động (dưới title "Quản lý")
- **Điều kiện**: Chỉ hiển thị khi owner có >= 2 shops

### 3. Tạo chi nhánh mới
- **Vị trí**: Settings → Chọn cửa hàng → "Tạo chi nhánh mới"
- **Chức năng**: Tạo shop mới với cùng ownerUid
- **Tự động**: Đặt shop mới làm shop hoạt động

## Cách hoạt động

### Data Isolation
```
User login → Check ownedShops → if count >= 2 → Show ShopSwitcher
                              → if count == 1 → Hide ShopSwitcher (use default shop)
```

### Khi chuyển shop
1. Cancel tất cả Firestore subscriptions
2. Clear local SQLite cache
3. Re-init EncryptionService
4. Restart SyncService với shopId mới
5. Emit EventBus.shopChanged
6. Notify tất cả listeners để reload UI

### Backward Compatibility
- Nếu `activeShopId` null → fallback về `UserService.getCurrentShopId()`
- Single-shop owners không thấy ShopSwitcher
- Không có breaking changes

## Files chính

| File | Mô tả |
|------|-------|
| `lib/services/current_shop_service.dart` | Service quản lý activeShopId |
| `lib/widgets/shop_switcher_widget.dart` | UI dropdown chọn shop |
| `lib/views/settings_view.dart` | Tích hợp ShopSwitcher |
| `lib/views/home_view.dart` | Shop indicator + EventBus listener |

## API Reference

### CurrentShopService

```dart
// Singleton
final service = CurrentShopService();

// Initialize (gọi sau khi login)
await service.init();

// Lấy shopId hiện tại
String? shopId = await service.getActiveShopId();

// Chuyển shop
bool success = await service.switchShop(newShopId);

// Lấy danh sách shops của owner
List<Map<String, dynamic>> shops = await service.getOwnedShops();

// Clear khi logout
await service.clear();
```

### EventBus Integration

```dart
// Lắng nghe khi shop thay đổi
EventBus.on(EventBus.shopChanged, (data) {
  // Reload UI data
});
```

## Test Checklist

### Chuẩn bị
- [ ] Có tài khoản owner với 2+ shops trong Firestore
- [ ] Mỗi shop có data riêng (repairs, products, etc.)

### Test Cases
1. **Login với single-shop owner** → ShopSwitcher KHÔNG hiển thị
2. **Login với multi-shop owner** → ShopSwitcher hiển thị trong Settings
3. **Chuyển shop** → Data reload đúng shop mới
4. **Tạo chi nhánh mới** → Shop tạo thành công, tự động switch
5. **Logout và login lại** → Nhớ shop đã chọn
6. **Shop indicator** → Hiển thị đúng tên shop trong AppBar

### Verify Data Isolation
- Repairs chỉ thuộc shop đang active
- Products chỉ thuộc shop đang active
- Sales chỉ thuộc shop đang active
- Không có data crossover giữa các shops

## Troubleshooting

### ShopSwitcher không hiển thị
1. Check role: phải là `owner`
2. Check ownedShops: phải có >= 2 shops với `ownerUid` matching

### Data không reload sau khi switch
1. Check EventBus listener trong HomeView
2. Check Console logs cho CurrentShopService messages

### Lỗi khi tạo chi nhánh
1. Check Firestore permissions
2. Check internet connection

## Phase 2 Roadmap (Tương lai)

- [ ] Staff assignment per shop
- [ ] Shop-level permissions
- [ ] Cross-shop reporting
- [ ] Shop transfer ownership
- [ ] Shop archiving

---
*Last updated: 2025*
