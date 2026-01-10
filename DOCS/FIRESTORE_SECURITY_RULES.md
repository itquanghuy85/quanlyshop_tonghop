# Firestore Security Rules Documentation

## 📋 Tổng quan

**Version:** 3.0  
**Deploy Date:** 2026-01-10  
**Status:** Production Ready ✅

## 🆕 Version 3.0 Changes

### Custom Claims Support
- **Primary**: Sử dụng Custom Claims (`request.auth.token.shopId`, `request.auth.token.role`)
- **Fallback**: Đọc từ Firestore `/users/{uid}` nếu claims chưa được set
- **Performance**: Loại bỏ Firestore read mỗi request (tiết kiệm cost)

### Enhanced Role Functions
```javascript
// Role hierarchy checks with alias functions
function isOwner() { return isSuperAdmin() || getUserRole() == 'owner'; }
function isManagerOrAbove() { return isOwner() || getUserRole() == 'manager'; }
function isEmployeeOrAbove() { return isManagerOrAbove() || getUserRole() == 'employee'; }
function isTechnicianOrAbove() { return isManagerOrAbove() || getUserRole() == 'technician'; }

// Alias for readability
function isManager() { return isManagerOrAbove(); }
function isEmployee() { return isEmployeeOrAbove(); }
```

### Schema Validation
- Tất cả create/update đều validate schema
- Optional fields được handle đúng (không require nếu null)
- Protected fields không thể modified bởi client

---

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

### 2. Data Isolation (Custom Claims)
```javascript
// Primary: từ Custom Claims (fast, no read)
function getClaimShopId() {
  return request.auth.token.shopId;
}

// Fallback: từ Firestore (nếu claims chưa set)
function getFirestoreShopId() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.shopId;
}

// Auto-select best method
function getUserShopId() {
  return getClaimShopId() != null ? getClaimShopId() : getFirestoreShopId();
}

function docBelongsToUserShop() {
  return isSuperAdmin() || resource.data.shopId == getUserShopId();
}
```
**User chỉ đọc/ghi dữ liệu của shop mình.**

### 3. Schema Validation
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

### v3.0 (2026-01-10)
- ✨ Custom Claims support cho performance optimization
- ✨ Fallback mechanism: Claims → Firestore
- ✨ Enhanced RBAC với alias functions (`isManager()`, `isEmployee()`)
- ✨ Optional field validation improvements
- ✨ Reserved functions cho future use (`isAssignedTechnician`, `shopIdProtected`)
- 🔧 Fixed schema validation cho optional fields (price, cost, etc.)

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

---

## ⚡ Custom Claims Setup (Cloud Functions)

### Tại sao cần Custom Claims?
- **Performance**: Không cần Firestore read mỗi request
- **Cost**: Giảm số lượng reads đáng kể
- **Security**: Claims được Firebase verify, không thể giả mạo

### Cloud Function để set Custom Claims

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// Set claims when user joins a shop
exports.setUserClaims = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const userData = change.after.data();
    
    if (!userData) return; // User deleted
    
    const customClaims = {
      shopId: userData.shopId || null,
      role: userData.role || 'user',
    };
    
    try {
      await admin.auth().setCustomUserClaims(userId, customClaims);
      console.log(`Set claims for ${userId}:`, customClaims);
      
      // Mark claims as synced
      await change.after.ref.update({
        claimsSynced: true,
        claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('Error setting claims:', error);
    }
  });

// Manual claim refresh (callable)
exports.refreshClaims = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');
  }
  
  const userId = context.auth.uid;
  const userDoc = await admin.firestore().doc(`users/${userId}`).get();
  const userData = userDoc.data();
  
  if (!userData) {
    throw new functions.https.HttpsError('not-found', 'User not found');
  }
  
  const customClaims = {
    shopId: userData.shopId || null,
    role: userData.role || 'user',
  };
  
  await admin.auth().setCustomUserClaims(userId, customClaims);
  return { success: true, claims: customClaims };
});
```

### Deploy Cloud Function
```bash
cd functions
npm install
firebase deploy --only functions:setUserClaims,functions:refreshClaims
```

### Refresh Token trong Flutter App
```dart
// Sau khi user join shop hoặc role thay đổi
Future<void> refreshUserClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    // Force token refresh để lấy claims mới
    await user.getIdToken(true);
  }
}

// Hoặc gọi Cloud Function
Future<void> callRefreshClaims() async {
  final callable = FirebaseFunctions.instance.httpsCallable('refreshClaims');
  final result = await callable.call();
  print('Claims refreshed: ${result.data}');
  
  // Force token refresh
  await FirebaseAuth.instance.currentUser?.getIdToken(true);
}
```

---

## 🔗 Related Files
- [firestore.rules](../firestore.rules) - Rules file
- [firestore.indexes.json](../firestore.indexes.json) - Indexes
- [firebase.json](../firebase.json) - Firebase config
- [user_service.dart](../lib/services/user_service.dart) - Role logic
- [firestore_service.dart](../lib/services/firestore_service.dart) - CRUD operations
