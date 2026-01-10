# Firestore Security Rules Documentation

## 📋 Tổng quan

**Version:** 2.0  
**Deploy Date:** 2026-01-10  
**Status:** Production Ready ✅

## 🏗️ Kiến trúc bảo mật

### Multi-tenant Architecture
- Mỗi shop được cách ly bởi `shopId`
- User chỉ truy cập được dữ liệu của shop mình
- Super Admin (`admin@huluca.com`) có quyền truy cập toàn hệ thống

### Role Hierarchy
```
admin (Super Admin) → Toàn quyền
    ↓
owner → Chủ shop, quản lý toàn bộ shop
    ↓
manager → Quản lý, xem tài chính, quản lý nhân viên
    ↓
employee → Nhân viên, nghiệp vụ cơ bản
    ↓
technician → Kỹ thuật, chỉ sửa chữa
    ↓
user → Mặc định, quyền tối thiểu
```

## 🔐 Security Principles

### 1. Authentication Required
```javascript
function isAuthenticated() {
  return request.auth != null;
}
```
**Tất cả operations đều yêu cầu đăng nhập.**

### 2. Data Isolation
```javascript
function docBelongsToUserShop() {
  return isSuperAdmin() || resource.data.shopId == getUserShopId();
}
```
**User chỉ đọc/ghi dữ liệu của shop mình.**

### 3. Schema Validation
```javascript
// Validate string
isValidString('customerName', 1, 100)

// Validate integer không âm
isNonNegativeInt('totalPrice')

// Validate range
isValidInt('status', 1, 4)
```

### 4. Protected Fields
Các field không thể bị ghi đè:
- `role` - Chỉ super admin có thể thay đổi
- `isAdmin` / `isSuperAdmin`
- `balance`
- `ownerUid`
- `shopId` - Không thể thay đổi sau khi tạo

### 5. Soft Deletes
```javascript
allow delete: if false; // Không cho phép xóa cứng
```
**Tất cả xóa phải dùng `deleted: true`.**

## 📚 Collections & Permissions

| Collection | Read | Create | Update | Delete |
|------------|------|--------|--------|--------|
| `users` | Auth | Own profile | Own/Manager | Super Admin |
| `shops` | Shop members | Auth | Owner | Super Admin |
| `repairs` | Shop | Shop | Shop | ❌ (soft) |
| `sales` | Shop | Employee+ | Shop | ❌ (soft) |
| `products` | Shop | Employee+ | Shop | ❌ (soft) |
| `expenses` | Manager+ | Manager+ | Manager+ | ❌ (soft) |
| `attendance` | Own/Manager | Own/Manager | Own/Manager | ❌ (soft) |
| `debts` | Manager+ | Manager+ | Manager+ | ❌ (soft) |
| `debt_payments` | Manager+ | Manager+ | Manager+ | ❌ (soft) |
| `suppliers` | Shop | Employee+ | Shop | Manager+ |
| `customers` | Shop | Shop | Shop | Manager+ |
| `repair_partners` | Shop | Employee+ | Shop | Manager+ |
| `purchase_orders` | Manager+ | Manager+ | Manager+ | ❌ (soft) |
| `audit_logs` | Manager+ | Auth | ❌ | ❌ |
| `chats` | Shop | Shop | Shop | ❌ |
| `notifications` | Own/Shop | Shop | Own/Shop | ❌ |
| `invites` | Auth | Manager+ | Auth (used only) | Owner |

## ⚠️ Lưu ý khi thay đổi Schema

### Thêm collection mới
1. Copy template từ collection tương tự
2. Xác định role access (ai đọc, ai ghi)
3. Thêm validation cho required fields
4. Test với Firebase Emulator trước

### Thêm field mới vào collection
1. Nếu là required field → thêm vào `hasAll([...])`
2. Nếu là số → thêm validation `isNonNegativeInt()` hoặc `isValidInt()`
3. Nếu là string → thêm `isValidString()` với min/max length

### Thay đổi role permissions
1. Cập nhật helper function: `isOwner()`, `isManager()`, etc.
2. Review tất cả rules dùng function đó
3. Test kỹ với các role khác nhau

## 🧪 Testing

### Firebase Emulator
```bash
firebase emulators:start --only firestore
```

### Test Cases quan trọng
1. ✅ User không đăng nhập → Denied tất cả
2. ✅ User shop A đọc dữ liệu shop B → Denied
3. ✅ Employee tạo expense → Denied (cần Manager+)
4. ✅ Ghi số âm vào totalPrice → Denied
5. ✅ Thay đổi shopId sau khi tạo → Denied
6. ✅ User tự nâng role thành admin → Denied
7. ✅ Super admin đọc tất cả shops → Allowed

## 🚀 Deploy Commands

```bash
# Deploy rules only
firebase deploy --only firestore:rules

# Deploy rules + indexes
firebase deploy --only firestore

# Check compilation
firebase firestore:rules:compile firestore.rules
```

## 📝 Changelog

### v2.0 (2026-01-10)
- Chuyển từ Test Mode sang Production Mode
- Thêm multi-tenant isolation với shopId
- Thêm role-based access control
- Schema validation cho tất cả collections
- Protected sensitive fields
- Soft delete enforcement
- Documentation đầy đủ

### v1.0 (Legacy)
- Test mode: `allow read, write: if request.auth != null`

## 🔗 Related Files
- [firestore.rules](../firestore.rules) - Rules file
- [firestore.indexes.json](../firestore.indexes.json) - Indexes
- [firebase.json](../firebase.json) - Firebase config
- [user_service.dart](../lib/services/user_service.dart) - Role logic
- [firestore_service.dart](../lib/services/firestore_service.dart) - CRUD operations
