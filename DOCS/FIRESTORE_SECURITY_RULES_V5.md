# Firestore Security Rules v5.0 - Production Ready

## 📋 Tổng quan

**Version:** 5.0 (Grouped by Functional Areas)  
**Deploy Date:** 2026-01-10  
**Status:** Production Ready ✅

## 🆕 Version 5.0 - Major Restructure

### Highlights
- **100% Custom Claims**: Không fallback, không Firestore read cho auth checks
- **Grouped by Function**: 11 sections được tổ chức theo nghiệp vụ
- **30+ Collections**: Phủ đầy đủ tất cả collections trong hệ thống
- **Role Hierarchy**: SuperAdmin > Owner > Manager > Employee/Technician

---

## 📁 Cấu trúc Sections

| Section | Collections | Access Level |
|---------|------------|--------------|
| **1. Core Functions** | Helper functions | N/A |
| **2. Auth & Users** | users, shops, invites | Varies |
| **3. Core Business** | repairs, sales, products, customers | Staff+ |
| **4. Finance** | expenses, debts, debt_payments, cash_closings | Manager+ |
| **5. Suppliers** | suppliers, supplier_payments, purchase_orders, supplier_import_history, supplier_product_prices | Employee+/Manager+ |
| **6. Partners** | repair_partners, repair_partner_payments, partner_repair_history | Employee+/Manager+ |
| **7. HR** | attendance | Self or Manager+ |
| **8. Chat** | chats, chat_messages | Shop members |
| **9. Notifications** | notifications, shop_notifications | Shop members |
| **10. System** | audit_logs (IMMUTABLE), quick_input_codes, repair_parts | Varies |
| **11. Catch-All** | `{document=**}` | DENIED |

---

## 🔐 Custom Claims Structure

```json
{
  "isSuperAdmin": true,      // Only admin@huluca.com
  "shopId": "shop123",       // User's assigned shop
  "role": "owner"            // owner | manager | employee | technician | user
}
```

### Setting Claims (Cloud Functions only)
```javascript
// functions/index.js
await admin.auth().setCustomUserClaims(uid, {
  isSuperAdmin: email === 'admin@huluca.com',
  shopId: userData.shopId,
  role: userData.role
});
```

---

## 🎯 Core Helper Functions

### 1. Authentication
```javascript
function isAuth() {
  return request.auth != null;
}

function uid() {
  return request.auth.uid;
}
```

### 2. Super Admin Check
```javascript
function isSuperAdmin() {
  return isAuth() && request.auth.token.isSuperAdmin == true;
}
```

### 3. Multi-Tenant Isolation
```javascript
function myShopId() {
  return request.auth.token.shopId;
}

function belongsTo(shopId) {
  return isSuperAdmin() || myShopId() == shopId;
}

function docInMyShop() {
  return isSuperAdmin() || 
         ('shopId' in resource.data && resource.data.shopId == myShopId());
}

function newDocInMyShop() {
  return isSuperAdmin() || request.resource.data.shopId == myShopId();
}
```

### 4. Role-Based Access
```javascript
function myRole() {
  return request.auth.token.role;
}

function isOwner()     { return isSuperAdmin() || myRole() == 'owner'; }
function isManager()   { return isOwner() || myRole() == 'manager'; }
function isEmployee()  { return isManager() || myRole() == 'employee'; }
function isTechnician(){ return isManager() || myRole() == 'technician'; }
function isStaff()     { return isEmployee() || isTechnician(); }
```

### 5. Protected Fields
```javascript
function changed(field) {
  return field in resource.data && 
         field in request.resource.data &&
         request.resource.data[field] != resource.data[field];
}

function protectedOK() {
  return isSuperAdmin() || (
    !changed('role') &&
    !changed('shopId') &&
    !changed('isAdmin') &&
    !changed('isSuperAdmin') &&
    !changed('balance') &&
    !changed('ownerUid') &&
    !changed('claimsSyncedAt')
  );
}
```

---

## 📊 Collection Rules Detail

### Section 2: Auth & Users

#### users
| Action | Rule | Description |
|--------|------|-------------|
| READ | `isAuth()` | Any authenticated user |
| CREATE | `uid() == userId` + schema | Own profile only |
| UPDATE | `uid() == userId OR manager of same shop` + `protectedOK()` | Own or manager can edit |
| DELETE | `false` | Soft delete only |

#### shops
| Action | Rule |
|--------|------|
| READ | `belongsTo(shopId)` |
| CREATE | `ownerUid == uid()` |
| UPDATE | `ownerUid == uid() OR isSuperAdmin()` |
| DELETE | `false` |

#### invites
| Action | Rule |
|--------|------|
| READ | `isAuth()` |
| CREATE | `isManager()` |
| UPDATE | Only `used`, `usedBy`, `usedAt` fields |
| DELETE | `isOwner()` |

### Section 3: Core Business

#### repairs
| Action | Rule |
|--------|------|
| READ | `docInMyShop()` |
| CREATE | `isStaff() && newDocInMyShop()` + schema |
| UPDATE | `docInMyShop() && shopIdLocked()` |
| DELETE | `false` |

**Required Fields:** customerName, phone, model, issue, createdAt, status, shopId  
**Validation:** status 1-4, price/cost >= 0

#### sales
| Action | Rule |
|--------|------|
| READ | `docInMyShop()` |
| CREATE | `isEmployee() && newDocInMyShop()` |
| UPDATE | `docInMyShop()` |
| DELETE | `false` |

#### products
| Action | Rule |
|--------|------|
| READ | `docInMyShop()` |
| CREATE | `isEmployee()` |
| UPDATE | `docInMyShop()` |
| DELETE | `false` |

#### customers
| Action | Rule |
|--------|------|
| READ | `docInMyShop()` |
| CREATE | Any staff |
| UPDATE | `docInMyShop()` |
| DELETE | `false` |

### Section 4: Finance (Manager+ only)

#### expenses, debts, debt_payments, cash_closings
- **READ:** `docInMyShop() && isManager()`
- **CREATE:** `isManager() && newDocInMyShop()`
- **UPDATE:** `docInMyShop() && isManager()`
- **DELETE:** `false`

### Section 5: Suppliers

| Collection | Create | Read | Update | Delete |
|------------|--------|------|--------|--------|
| suppliers | Employee+ | Staff | Staff | ❌ |
| supplier_payments | Manager+ | Manager+ | Manager+ | ❌ |
| purchase_orders | Manager+ | Manager+ | Manager+ | ❌ |
| supplier_import_history | Employee+ | Staff | Staff | ❌ |
| supplier_product_prices | Employee+ | Staff | Staff | Manager+ |

### Section 6: Repair Partners

| Collection | Create | Read | Update | Delete |
|------------|--------|------|--------|--------|
| repair_partners | Employee+ | Staff | Staff | ❌ |
| repair_partner_payments | Manager+ | Manager+ | Manager+ | ❌ |
| partner_repair_history | Employee+ | Staff | Staff | ❌ |

### Section 7: HR (Attendance)

| Action | Rule |
|--------|------|
| READ | Own records OR Manager sees all |
| CREATE | Own OR Manager creates for anyone |
| UPDATE | Manager: full access / Employee: limited (no status/locked/approval changes) |
| DELETE | `false` |

### Section 8: Chat

- **chats, chat_messages**
  - READ/UPDATE: Shop members
  - CREATE: Must be sender
  - DELETE: `false`

### Section 9: Notifications

| Collection | Special Rules |
|------------|--------------|
| notifications | Read own or broadcast (userId=null) |
| shop_notifications | Manager+ can delete old ones |

### Section 10: System

| Collection | Special Rules |
|------------|--------------|
| audit_logs | **IMMUTABLE** - No update, no delete |
| quick_input_codes | Delete allowed for cleanup |
| repair_parts | Standard rules |

### Section 11: Catch-All

```javascript
match /{document=**} {
  allow read, write: if false;
}
```

---

## 🧪 Testing

### Test Super Admin Access
```javascript
// Firebase console - Rules Playground
// Auth: admin@huluca.com with claims {isSuperAdmin: true}

// Should ALLOW: read any collection
firestore.doc('repairs/any-doc').get()

// Should ALLOW: write to any shop
firestore.doc('repairs/any-doc').set({shopId: 'any-shop', ...})
```

### Test Multi-Tenant Isolation
```javascript
// Auth: user@shop1.com with claims {shopId: 'shop1', role: 'employee'}

// Should ALLOW: read own shop
firestore.doc('repairs/doc-in-shop1').get()

// Should DENY: read other shop
firestore.doc('repairs/doc-in-shop2').get()  // ❌ DENIED

// Should DENY: write to other shop
firestore.doc('repairs/new').set({shopId: 'shop2'})  // ❌ DENIED
```

### Test Role-Based Access
```javascript
// Auth: employee with claims {role: 'employee', shopId: 'shop1'}

// Should ALLOW: create repair
firestore.collection('repairs').add({...})  // ✅

// Should DENY: read expenses (Manager+ only)
firestore.doc('expenses/any').get()  // ❌ DENIED
```

### Test Protected Fields
```javascript
// Any non-SuperAdmin user

// Should DENY: change role
firestore.doc('users/me').update({role: 'owner'})  // ❌ DENIED

// Should DENY: change shopId
firestore.doc('users/me').update({shopId: 'other-shop'})  // ❌ DENIED
```

### Test Audit Logs Immutability
```javascript
// Should ALLOW: create audit log
firestore.collection('audit_logs').add({action: 'test', ...})  // ✅

// Should DENY: update audit log
firestore.doc('audit_logs/any').update({action: 'hack'})  // ❌ DENIED

// Should DENY: delete audit log
firestore.doc('audit_logs/any').delete()  // ❌ DENIED
```

---

## 🔄 Migration from v4.0

### What Changed
1. **No Fallback**: v4.0 had Firestore fallback, v5.0 is claims-only
2. **Functional Grouping**: Rules organized by business domain
3. **More Validations**: Enhanced schema checks
4. **Finance Isolation**: Financial data now Manager+ only

### Migration Steps
1. Ensure all users have Custom Claims synced
2. Deploy v5.0 rules: `firebase deploy --only firestore:rules`
3. Test all user roles

---

## 📞 Support

Questions? Check:
- [firestore.rules](../firestore.rules) - Source code
- [functions/index.js](../functions/index.js) - Claims management
- [lib/services/claims_service.dart](../lib/services/claims_service.dart) - Flutter integration
