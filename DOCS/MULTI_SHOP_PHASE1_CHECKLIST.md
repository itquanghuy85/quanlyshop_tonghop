# Multi-Shop Phase 1 - Production Test Checklist

## 📋 Files Created/Modified

### New Files
- `lib/services/current_shop_service.dart` - Manages activeShopId with persistence
- `lib/widgets/shop_switcher_widget.dart` - UI dropdown for shop selection

### Modified Files
- `lib/main.dart` - Added CurrentShopService import and init
- `lib/views/settings_view.dart` - Integrated ShopSwitcherWidget
- `lib/l10n/app_en.arb` - Added localization keys
- `lib/l10n/app_vi.arb` - Added Vietnamese translations

---

## ✅ Pre-Release Test Cases

### Case 1: Single Shop User (NO CHANGE EXPECTED)
- [ ] Login with employee/technician account
- [ ] Verify NO shop switcher appears in Settings
- [ ] Verify all data loads normally
- [ ] Verify can create repairs, sales, expenses
- [ ] Verify sync works correctly

### Case 2: Owner with ONE Shop
- [ ] Login with owner account (single shop)
- [ ] Verify NO shop switcher appears (only shows with 2+ shops)
- [ ] Verify all owner features work normally
- [ ] Verify can manage staff, view financials

### Case 3: Owner with MULTIPLE Shops
- [ ] Create second shop in Firestore for test owner:
  ```javascript
  // Firebase Console > Firestore > shops collection
  {
    "ownerUid": "OWNER_UID_HERE",
    "ownerEmail": "owner@example.com",
    "name": "Chi Nhánh 2",
    "createdAt": Timestamp.now()
  }
  ```
- [ ] Login with owner account
- [ ] Verify ShopSwitcherWidget appears in Settings
- [ ] Verify dropdown shows both shops
- [ ] Switch to second shop
- [ ] Verify snackbar shows "Đã chuyển sang: Chi Nhánh 2"
- [ ] Verify data reloads for new shop
- [ ] Verify can create data in new shop

### Case 4: App Restart Persistence
- [ ] Switch to Shop B
- [ ] Kill app completely
- [ ] Reopen app
- [ ] Verify still on Shop B (not reset to Shop A)
- [ ] Verify activeShopId persisted correctly

### Case 5: Cache Clear on Switch
- [ ] Have data in Shop A (repairs, sales)
- [ ] Switch to Shop B
- [ ] Verify old data NOT visible
- [ ] Verify new shop data loads
- [ ] Switch back to Shop A
- [ ] Verify Shop A data reloads correctly

### Case 6: Firestore Security Rules
- [ ] Try to read Shop B data while logged into Shop A
- [ ] Verify Firestore rules block access
- [ ] Check Firebase Console for any permission denied errors

### Case 7: Super Admin (admin@huluca.com)
- [ ] Login as super admin
- [ ] Verify can still select any shop from ShopSelectorView
- [ ] Verify ShopSwitcherWidget also works if has owned shops

### Case 8: Logout/Login Cycle
- [ ] Login as owner, switch to Shop B
- [ ] Logout
- [ ] Login with different user
- [ ] Verify NOT on Shop B (cleared on logout)
- [ ] Login as original owner
- [ ] Verify still on Shop B (persisted)

---

## 🔧 Rollback Plan

If issues found, revert by:
1. Remove ShopSwitcherWidget from settings_view.dart
2. Remove CurrentShopService.init() from main.dart
3. Remove CurrentShopService.clear() calls
4. Keep services files (no harm if unused)

---

## 📊 Monitoring Post-Release

1. Check Crashlytics for any new crashes
2. Monitor Firestore permission denied errors
3. Check user feedback for data visibility issues
4. Verify sync health in production

---

## 🚀 Deployment Steps

1. Run `flutter test` - ensure all tests pass
2. Run `flutter build apk --release`
3. Test APK on physical device
4. Upload to Play Console internal testing
5. Promote to production after 24h testing
