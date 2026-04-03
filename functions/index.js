const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2/options");

admin.initializeApp();
// Giới hạn region & timeout mặc định
setGlobalOptions({ region: "asia-southeast1", timeoutSeconds: 30 });

// ============================================================
// CUSTOM CLAIMS MANAGEMENT
// ============================================================
// Purpose: Auto-sync Custom Claims when user data changes
// Claims: shopId, role, isSuperAdmin
// ============================================================

const SUPER_ADMIN_EMAIL = "admin@huluca.com";
const VALID_ROLES = ["owner", "manager", "employee", "technician", "user"];

/**
 * Check if email is super admin
 */
function checkIsSuperAdmin(email) {
  return email && email.toLowerCase() === SUPER_ADMIN_EMAIL;
}

/**
 * Build custom claims object from user data
 */
function buildCustomClaims(userData, email) {
  const isSuperAdmin = checkIsSuperAdmin(email);
  return {
    shopId: userData?.shopId || null,
    role: isSuperAdmin ? "admin" : (userData?.role || "user"),
    isSuperAdmin: isSuperAdmin,
  };
}

/**
 * 🔑 AUTO-SYNC CUSTOM CLAIMS
 * Triggered when user document is created or updated
 * Sets: shopId, role, isSuperAdmin in JWT token
 */
exports.syncUserClaims = onDocumentWritten("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const afterData = event.data?.after?.data();
  
  // Skip if document was deleted
  if (!afterData) {
    console.log(`User ${userId} deleted, skipping claims sync`);
    return;
  }

  try {
    // Get user's email from Auth
    let userEmail = afterData.email;
    if (!userEmail) {
      try {
        const userRecord = await admin.auth().getUser(userId);
        userEmail = userRecord.email;
      } catch (e) {
        console.warn(`Cannot get email for user ${userId}:`, e.message);
      }
    }

    // Build and set claims
    const claims = buildCustomClaims(afterData, userEmail);
    
    // Check if claims actually changed
    const beforeData = event.data?.before?.data();
    const oldClaims = beforeData ? buildCustomClaims(beforeData, userEmail) : null;
    
    if (oldClaims && 
        oldClaims.shopId === claims.shopId && 
        oldClaims.role === claims.role && 
        oldClaims.isSuperAdmin === claims.isSuperAdmin) {
      console.log(`Claims unchanged for user ${userId}, skipping`);
      return;
    }

    await admin.auth().setCustomUserClaims(userId, claims);
    
    // Mark claims as synced in Firestore (for client to know when to refresh token)
    await event.data.after.ref.update({
      claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      _claimsVersion: admin.firestore.FieldValue.increment(1),
    });

    console.log(`✅ Claims synced for ${userId}:`, claims);
  } catch (error) {
    console.error(`❌ Error syncing claims for ${userId}:`, error);
  }
});

/**
 * 🔄 MANUAL REFRESH CLAIMS
 * Callable function to force refresh user's claims
 * Client should call this after joining shop or role change
 */
exports.refreshMyClaims = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const userId = auth.uid;
  const userEmail = auth.token.email;

  try {
    // Get fresh user data from Firestore
    const userDoc = await admin.firestore().doc(`users/${userId}`).get();
    const userData = userDoc.data();

    if (!userData) {
      throw new HttpsError("not-found", "Không tìm thấy thông tin người dùng");
    }

    // Build and set claims
    const claims = buildCustomClaims(userData, userEmail);
    await admin.auth().setCustomUserClaims(userId, claims);

    // Update sync timestamp
    await userDoc.ref.update({
      claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ Claims refreshed for ${userId}:`, claims);

    return {
      success: true,
      claims: claims,
      message: "Claims đã được cập nhật. Vui lòng refresh token.",
    };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error(`Error refreshing claims for ${userId}:`, error);
    throw new HttpsError("internal", "Lỗi cập nhật claims: " + error.message);
  }
});

/**
 * 👑 ADMIN: UPDATE USER ROLE
 * Only owner/admin can change roles
 * Cannot self-assign higher role
 */
exports.updateUserRole = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const data = request.data || {};
  const targetUserId = (data.userId || "").toString().trim();
  const newRole = (data.role || "").toString().trim().toLowerCase();

  // === VALIDATION ===
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "Thiếu userId");
  }

  if (!newRole || !VALID_ROLES.includes(newRole)) {
    throw new HttpsError("invalid-argument", `Role không hợp lệ. Chỉ chấp nhận: ${VALID_ROLES.join(", ")}`);
  }

  const callerUid = auth.uid;
  const callerEmail = auth.token.email || "";
  const callerIsSuperAdmin = checkIsSuperAdmin(callerEmail);

  // Get caller's data
  const callerDoc = await admin.firestore().doc(`users/${callerUid}`).get();
  const callerData = callerDoc.data() || {};
  const callerRole = callerIsSuperAdmin ? "admin" : (callerData.role || "user");
  const callerShopId = callerData.shopId;

  // Get target user's data
  const targetDoc = await admin.firestore().doc(`users/${targetUserId}`).get();
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "Không tìm thấy người dùng");
  }
  const targetData = targetDoc.data() || {};
  const targetShopId = targetData.shopId;

  // === PERMISSION CHECKS ===
  
  // 1. Super admin can do anything
  if (!callerIsSuperAdmin) {
    // 2. Must be in same shop (unless super admin)
    if (callerShopId !== targetShopId) {
      throw new HttpsError("permission-denied", "Không thể thay đổi role người dùng khác shop");
    }

    // 3. Only owner can assign owner role
    if (newRole === "owner" && callerRole !== "owner") {
      throw new HttpsError("permission-denied", "Chỉ owner mới có thể chỉ định owner mới");
    }

    // 4. Manager can only assign employee/technician/user
    if (callerRole === "manager" && !["employee", "technician", "user"].includes(newRole)) {
      throw new HttpsError("permission-denied", "Manager chỉ có thể gán role: employee, technician, user");
    }

    // 5. Employee and below cannot change roles
    if (!["admin", "owner", "manager"].includes(callerRole)) {
      throw new HttpsError("permission-denied", "Bạn không có quyền thay đổi role");
    }

    // 6. Cannot demote yourself
    if (callerUid === targetUserId && getRolePriority(newRole) < getRolePriority(callerRole)) {
      throw new HttpsError("permission-denied", "Không thể tự hạ role của mình");
    }
  }

  // === UPDATE ROLE ===
  try {
    await targetDoc.ref.update({
      role: newRole,
      roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      roleUpdatedBy: callerUid,
    });

    // Claims will be auto-synced by syncUserClaims trigger
    console.log(`✅ Role updated: ${targetUserId} -> ${newRole} (by ${callerUid})`);

    return {
      success: true,
      userId: targetUserId,
      newRole: newRole,
      message: `Đã cập nhật role thành ${newRole}`,
    };
  } catch (error) {
    console.error(`Error updating role for ${targetUserId}:`, error);
    throw new HttpsError("internal", "Lỗi cập nhật role: " + error.message);
  }
});

/**
 * Helper: Get role priority for comparison
 */
function getRolePriority(role) {
  const priorities = {
    "admin": 100,
    "owner": 90,
    "manager": 70,
    "employee": 50,
    "technician": 40,
    "user": 10,
  };
  return priorities[role] || 0;
}

/**
 * 🏪 ADMIN: ADD USER TO SHOP
 * Assigns user to a shop and sets initial role
 */
exports.addUserToShop = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const data = request.data || {};
  const targetUserId = (data.userId || "").toString().trim();
  const targetShopId = (data.shopId || "").toString().trim();
  const initialRole = (data.role || "employee").toString().trim().toLowerCase();

  // === VALIDATION ===
  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "Thiếu userId");
  }
  if (!targetShopId) {
    throw new HttpsError("invalid-argument", "Thiếu shopId");
  }
  if (!VALID_ROLES.includes(initialRole)) {
    throw new HttpsError("invalid-argument", `Role không hợp lệ: ${initialRole}`);
  }

  const callerEmail = auth.token.email || "";
  const callerIsSuperAdmin = checkIsSuperAdmin(callerEmail);

  // Get caller's data
  const callerDoc = await admin.firestore().doc(`users/${auth.uid}`).get();
  const callerData = callerDoc.data() || {};
  const callerRole = callerIsSuperAdmin ? "admin" : (callerData.role || "user");
  const callerShopId = callerData.shopId;

  // === PERMISSION CHECKS ===
  if (!callerIsSuperAdmin) {
    // Must be owner/manager of the target shop
    if (callerShopId !== targetShopId) {
      throw new HttpsError("permission-denied", "Bạn không thuộc shop này");
    }
    if (!["owner", "manager"].includes(callerRole)) {
      throw new HttpsError("permission-denied", "Chỉ owner/manager mới có thể thêm nhân viên");
    }
    // Manager cannot add owner
    if (callerRole === "manager" && initialRole === "owner") {
      throw new HttpsError("permission-denied", "Manager không thể thêm owner");
    }
  }

  // Check if target user exists
  const targetDoc = await admin.firestore().doc(`users/${targetUserId}`).get();
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "Không tìm thấy người dùng");
  }

  const targetData = targetDoc.data() || {};
  if (targetData.shopId && targetData.shopId !== targetShopId) {
    throw new HttpsError("failed-precondition", "Người dùng đã thuộc shop khác");
  }

  // === ADD TO SHOP ===
  try {
    await targetDoc.ref.update({
      shopId: targetShopId,
      role: initialRole,
      joinedShopAt: admin.firestore.FieldValue.serverTimestamp(),
      addedBy: auth.uid,
    });

    console.log(`✅ User ${targetUserId} added to shop ${targetShopId} as ${initialRole}`);

    return {
      success: true,
      userId: targetUserId,
      shopId: targetShopId,
      role: initialRole,
      message: `Đã thêm người dùng vào shop với role ${initialRole}`,
    };
  } catch (error) {
    console.error(`Error adding user to shop:`, error);
    throw new HttpsError("internal", "Lỗi thêm người dùng vào shop: " + error.message);
  }
});

/**
 * 🚪 ADMIN: REMOVE USER FROM SHOP
 * Removes user from shop (sets shopId to null)
 */
exports.removeUserFromShop = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const data = request.data || {};
  const targetUserId = (data.userId || "").toString().trim();

  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "Thiếu userId");
  }

  const callerEmail = auth.token.email || "";
  const callerIsSuperAdmin = checkIsSuperAdmin(callerEmail);

  // Get target user's data
  const targetDoc = await admin.firestore().doc(`users/${targetUserId}`).get();
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "Không tìm thấy người dùng");
  }
  const targetData = targetDoc.data() || {};
  const targetShopId = targetData.shopId;

  if (!targetShopId) {
    throw new HttpsError("failed-precondition", "Người dùng không thuộc shop nào");
  }

  // === PERMISSION CHECKS ===
  if (!callerIsSuperAdmin) {
    const callerDoc = await admin.firestore().doc(`users/${auth.uid}`).get();
    const callerData = callerDoc.data() || {};
    
    if (callerData.shopId !== targetShopId) {
      throw new HttpsError("permission-denied", "Không thể xóa người dùng khác shop");
    }
    if (!["owner", "manager"].includes(callerData.role)) {
      throw new HttpsError("permission-denied", "Chỉ owner/manager mới có thể xóa nhân viên");
    }
    // Cannot remove owner
    if (targetData.role === "owner") {
      throw new HttpsError("permission-denied", "Không thể xóa owner khỏi shop");
    }
    // Cannot remove yourself
    if (auth.uid === targetUserId) {
      throw new HttpsError("permission-denied", "Không thể tự xóa mình khỏi shop");
    }
  }

  // === REMOVE FROM SHOP ===
  try {
    await targetDoc.ref.update({
      shopId: null,
      role: "user",
      removedFromShopAt: admin.firestore.FieldValue.serverTimestamp(),
      removedBy: auth.uid,
    });

    console.log(`✅ User ${targetUserId} removed from shop ${targetShopId}`);

    return {
      success: true,
      userId: targetUserId,
      message: "Đã xóa người dùng khỏi shop",
    };
  } catch (error) {
    console.error(`Error removing user from shop:`, error);
    throw new HttpsError("internal", "Lỗi xóa người dùng: " + error.message);
  }
});

/**
 * 🔍 GET USER CLAIMS (for debugging)
 * Returns current claims of a user
 */
exports.getUserClaims = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const data = request.data || {};
  const targetUserId = data.userId || auth.uid;

  // Only super admin can view other users' claims
  if (targetUserId !== auth.uid && !checkIsSuperAdmin(auth.token.email)) {
    throw new HttpsError("permission-denied", "Không có quyền xem claims người khác");
  }

  try {
    const userRecord = await admin.auth().getUser(targetUserId);
    return {
      success: true,
      userId: targetUserId,
      email: userRecord.email,
      claims: userRecord.customClaims || {},
    };
  } catch (error) {
    console.error(`Error getting claims for ${targetUserId}:`, error);
    throw new HttpsError("internal", "Lỗi lấy thông tin claims");
  }
});

// ============================================================
// END CUSTOM CLAIMS MANAGEMENT
// ============================================================

// 🔔 Thông báo khi CÓ ĐƠN SỬA MỚI
exports.notifyNewRepair = onDocumentCreated("repairs/{repairId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const price = data.price ? Number(data.price).toLocaleString('vi-VN') : '0';
  const phone = data.phone || '';
  const time = data.createdAt ? new Date(data.createdAt.toDate()).toLocaleTimeString('vi-VN', {hour: '2-digit', minute: '2-digit'}) : '';
  let body = `👤 ${data.customerName || 'N/A'}`;
  if (phone) body += ` • 📞 ${phone}`;
  body += `\n📱 ${data.model || 'N/A'} • 💰 ${price}đ`;
  if (time) body += `\n🕐 ${time}`;

  const payload = {
    notification: {
      title: "🔧 ĐƠN SỬA MỚI",
      body: body,
    },
    data: {
      type: 'repair',
      repairId: event.params.repairId,
    },
  };

  try {
    await admin.messaging().sendToTopic("staff", payload);
    console.log("Đã gửi thông báo đơn mới");
  } catch (e) {
    console.error("Lỗi gửi thông báo:", e);
  }
});

// 🔔 Thông báo khi CÓ ĐƠN BÁN MỚI
exports.notifyNewSale = onDocumentCreated("sales/{saleId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const total = data.total ? Number(data.total).toLocaleString('vi-VN') : '0';
  const customerName = data.customerName || 'Khách lẻ';
  const productNames = data.productNames || '';
  const time = data.soldAt ? new Date(data.soldAt.toDate()).toLocaleTimeString('vi-VN', {hour: '2-digit', minute: '2-digit'}) : '';
  let body = `👤 ${customerName}`;
  if (productNames) body += `\n📦 ${productNames.substring(0, 80)}`;
  body += `\n💰 ${total}đ`;
  if (time) body += ` • 🕐 ${time}`;

  const payload = {
    notification: {
      title: "🛒 ĐƠN BÁN MỚI",
      body: body,
    },
    data: {
      type: 'sale',
      saleId: event.params.saleId,
    },
  };

  try {
    await admin.messaging().sendToTopic("staff", payload);
    console.log("Đã gửi thông báo đơn bán mới");
  } catch (e) {
    console.error("Lỗi gửi thông báo đơn bán:", e);
  }
});

// 🔔 Thông báo khi CÓ TIN NHẮN CHAT MỚI
exports.notifyNewChat = onDocumentCreated("chats/{chatId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const shopId = data.shopId;
  const senderId = data.senderId;
  const senderName = data.senderName;
  const message = data.message;

  try {
    // Get all users in the shop except sender
    const userDocs = await admin.firestore()
      .collection('users')
      .where('shopId', '==', shopId)
      .get();

    const tokens = [];
    for (const doc of userDocs.docs) {
      const userData = doc.data();
      // Don't send to sender
      if (doc.id !== senderId && userData.fcmToken) {
        tokens.push(userData.fcmToken);
      }
    }

    if (tokens.length === 0) {
      console.log('No FCM tokens found for shop chat:', shopId);
      return;
    }

    const payload = {
      notification: {
        title: `💬 ${senderName}`,
        body: message.length > 100 ? message.substring(0, 100) + '...' : message,
      },
      data: {
        type: 'chat',
        chatId: event.params.chatId,
        shopId: shopId,
        senderId: senderId,
      },
      android: {
        notification: {
          channelId: 'system_channel',
          priority: 'default',
          defaultSound: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
      tokens: tokens,
    };

    const response = await admin.messaging().sendMulticast(payload);
    console.log(`Sent ${response.successCount} chat notifications for shop ${shopId}`);

  } catch (error) {
    console.error('Error sending chat FCM notification:', error);
  }
});

// 🔔 Thông báo khi ĐỔI TRẠNG THÁI (đã sửa / đã giao)
exports.notifyStatusChange = onDocumentUpdated("repairs/{repairId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.status === after.status) return;

  let statusText = "Cập nhật đơn sửa";
  if (after.status === 2) statusText = "🛠️ Đã sửa xong";
  if (after.status === 3) statusText = "✅ Đã giao máy";

  const price = after.price ? Number(after.price).toLocaleString('vi-VN') : '0';
  const body = `👤 ${after.customerName || 'N/A'} • 📱 ${after.model || 'N/A'}\n💰 ${price}đ`;

  const payload = {
    notification: {
      title: statusText,
      body: body,
    },
    data: {
      type: 'repair_status',
      repairId: event.params.repairId,
    },
  };

  try {
    await admin.messaging().sendToTopic("staff", payload);
    console.log("Đã gửi thông báo đổi trạng thái");
  } catch (e) {
    console.error("Lỗi gửi thông báo:", e);
  }
});

// ✅ Chỉ quản lý/super admin được tạo tài khoản nhân viên qua callable
exports.createStaffAccount = onCall(async (request) => {
  const data = request.data || {};
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập để tạo tài khoản");
  }

  const requesterUid = auth.uid;
  const requesterEmail = auth.token.email || "";
  const isSuperAdmin = requesterEmail === "admin@huluca.com";

  const requesterDoc = await admin.firestore().collection("users").doc(requesterUid).get();
  const requesterData = requesterDoc.data() || {};
  const requesterRole = isSuperAdmin ? "admin" : requesterData.role || "user";
  const requesterShopId = requesterData.shopId || requesterUid;

  // Allow owner and admin to create staff accounts
  if (!isSuperAdmin && requesterRole !== "admin" && requesterRole !== "owner") {
    throw new HttpsError("permission-denied", "Chỉ chủ shop hoặc quản lý mới được tạo tài khoản nhân viên");
  }

  const email = (data.email || "").toString().trim().toLowerCase();
  const password = (data.password || "").toString();
  const displayName = (data.displayName || "").toString().trim();
  const phone = (data.phone || "").toString().trim();
  const address = (data.address || "").toString().trim();
  let role = (data.role || "user").toString();
  let shopId = (data.shopId || "").toString().trim();

  if (!email || !password || password.length < 6 || !displayName) {
    throw new HttpsError("invalid-argument", "Thiếu email/mật khẩu/tên hoặc mật khẩu quá ngắn");
  }

  // Admin bình thường chỉ tạo được trong shop của mình; super admin có thể chỉ định shopId khác
  if (!isSuperAdmin || shopId === "") {
    shopId = requesterShopId;
  }

  // Chỉ cho phép nâng lên admin khi chính caller là admin/super admin
  // Cho phép owner tạo nhân viên với role: employee, manager, technician
  const allowedRoles = ["employee", "manager", "technician", "owner"];
  if (role === "admin" && !isSuperAdmin && requesterRole !== "admin") {
    role = "employee"; // Không phải admin/superAdmin → fallback to employee
  } else if (!allowedRoles.includes(role) && role !== "admin") {
    role = "employee"; // Role không hợp lệ → fallback to employee
  }

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName,
    });

    const isManagerOrAbove = ["admin", "owner", "manager"].includes(role);
    const basePermissions = {
      allowViewSales: true,
      allowViewRepairs: true,
      allowViewInventory: true,
      allowViewParts: true,
      allowViewSuppliers: true,
      allowViewCustomers: true,
      allowViewWarranty: true,
      allowViewChat: true,
      allowViewPrinter: true,
      allowViewRevenue: isManagerOrAbove,
      allowViewExpenses: isManagerOrAbove,
      allowViewDebts: isManagerOrAbove,
    };

    await admin.firestore().collection("users").doc(userRecord.uid).set({
      email,
      displayName: displayName.toUpperCase(),
      phone,
      address: address.toUpperCase(),
      role,
      shopId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: requesterUid,
      ...basePermissions,
    }, { merge: true });

    await admin.firestore().collection("shops").doc(shopId).set({
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastStaffCreatedBy: requesterUid,
    }, { merge: true });

    return {
      uid: userRecord.uid,
      role,
      shopId,
    };
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Email đã tồn tại");
    }
    console.error("Lỗi tạo tài khoản nhân viên:", e);
    throw new HttpsError("internal", "Không thể tạo tài khoản mới");
  }
});

// --- CLEANUP (OPT-IN): XÓA HOÀN TOÀN NHỮNG REPAIR ĐÃ ĐÁNH DẤU deleted=true SAU N NGÀY ---
// Tính năng này là 'opt-in' — chỉ chạy nếu doc `settings/cleanup` tồn tại và có `enabled: true`.
// Để bật: tạo doc `settings/cleanup` với { enabled: true, repairRetentionDays: 30 }
exports.cleanupDeletedRepairs = onSchedule("every 24 hours", async (event) => {
  try {
    const cfgDoc = await admin.firestore().doc('settings/cleanup').get();
    const cfg = cfgDoc.exists ? (cfgDoc.data() || {}) : {};
    if (!cfg.enabled) {
      console.log('cleanupDeletedRepairs is disabled via settings/cleanup (or doc missing). Skipping.');
      return;
    }

    const days = Number(cfg.repairRetentionDays ?? 30);
    if (!(days > 0)) {
      console.log('cleanupDeletedRepairs: invalid repairRetentionDays, skipping.');
      return;
    }

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

    const q = admin.firestore().collection('repairs')
      .where('deleted', '==', true)
      .where('deletedAt', '<=', cutoffTs)
      .limit(500);

    const snaps = await q.get();
    console.log(`Found ${snaps.size} deleted repairs older than ${days} days`);
    for (const doc of snaps.docs) {
      try {
        await doc.ref.delete();
        console.log(`Permanently deleted repair ${doc.id}`);
      } catch (e) {
        console.error(`Failed to delete repair ${doc.id}:`, e);
      }
    }
  } catch (error) {
    console.error('Error in cleanupDeletedRepairs:', error);
  }
});


function getNotificationChannel(type) {
  switch (type) {
    case 'new_order':
      return 'new_order_channel';
    case 'payment':
      return 'payment_channel';
    case 'inventory':
      return 'inventory_channel';
    case 'staff':
      return 'staff_channel';
    case 'system':
    default:
      return 'system_channel';
  }
}

function getAndroidPriority(type) {
  switch (type) {
    case 'new_order':
    case 'payment':
    case 'chat':
      return 'high';
    case 'inventory':
    case 'staff':
      return 'default';
    case 'system':
    default:
      return 'default';
  }
}

function getChannelId(type) {
  switch (type) {
    case 'new_order':
      return 'new_order_channel';
    case 'payment':
      return 'payment_channel';
    case 'inventory':
      return 'inventory_channel';
    case 'staff':
      return 'staff_channel';
    case 'chat':
      return 'chat_channel';
    case 'system':
    default:
      return 'system_channel';
  }
}

// Role-based notification permissions
function getAllowedRolesForNotificationType(type) {
  switch (type) {
    case 'new_order':
      return ['admin', 'owner', 'manager', 'employee'];
    case 'payment':
      return ['admin', 'owner', 'manager', 'employee'];
    case 'inventory':
      return ['admin', 'owner', 'manager', 'technician'];
    case 'staff':
      return ['admin', 'owner', 'manager'];
    case 'chat':
      return ['admin', 'owner', 'manager', 'employee', 'technician', 'user'];
    case 'system':
    default:
      return ['admin', 'owner', 'manager', 'employee', 'technician', 'user'];
  }
}

// 📢 GỬI THÔNG BÁO PUSH CHO SHOP
exports.sendShopNotification = onCall(async (request) => {
  const data = request.data || {};
  
  // Re-enable auth - require authenticated users
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const title = (data.title || "Thông báo").toString();
  const body = (data.body || "").toString();
  const type = (data.type || "system").toString();
  const targetUserId = data.targetUserId; // optional, if null then broadcast to all shop users
  const notifId = data.id; // optional entity ID for navigation (repairId, saleId)

  // Get shopId from authenticated user's Firestore doc, fallback to data.shopId
  let shopId = data.shopId;
  if (!shopId) {
    const requesterDoc = await admin.firestore().collection("users").doc(auth.uid).get();
    const requesterData = requesterDoc.data() || {};
    shopId = requesterData.shopId;
  }

  if (!shopId) {
    throw new HttpsError("failed-precondition", "Không tìm thấy thông tin cửa hàng");
  }

  try {
    // Get FCM tokens for the shop with role-based filtering
    let query = admin.firestore()
      .collection('users')
      .where('shopId', '==', shopId);

    if (targetUserId) {
      query = query.where(admin.firestore.FieldPath.documentId(), '==', targetUserId);
    }

    const userDocs = await query.get();
    const tokens = [];
    const allowedRoles = getAllowedRolesForNotificationType(type);

    userDocs.forEach(doc => {
      const userData = doc.data();
      const userRole = userData.role || 'user';

      // Check if user has permission for this notification type
      if (allowedRoles.includes(userRole) || userRole === 'admin') { // Super admin always gets notifications
        if (userData.fcmToken && userData.fcmToken.trim() !== '') {
          tokens.push(userData.fcmToken);
        }
      }
    });

    if (tokens.length === 0) {
      console.log(`No FCM tokens found for shop ${shopId} with permission for notification type: ${type}`);
      return { success: true, sentCount: 0 };
    }

    // Send FCM messages
    const fcmData = {
      type: type,
      shopId: shopId,
      senderId: auth.uid,
    };
    if (notifId) fcmData.id = notifId.toString();

    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: fcmData,
      android: {
        priority: getAndroidPriority(type),
        notification: {
          channelId: getChannelId(type),
          priority: getAndroidPriority(type),
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body,
            },
            badge: 1,
            sound: 'default',
            'content-available': 1,
            'mutable-content': 1,
          },
        },
      },
    };

    const responses = await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      ...payload,
    });

    console.log(`Sent ${responses.successCount} notifications, ${responses.failureCount} failed`);

    return {
      success: true,
      sentCount: responses.successCount,
      failedCount: responses.failureCount
    };

  } catch (error) {
    console.error('Error sending notification:', error);
    throw new HttpsError("internal", "Lỗi gửi thông báo: " + error.message);
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// 🔐 CUSTOM CLAIMS MANAGEMENT - Quản lý quyền người dùng
// ══════════════════════════════════════════════════════════════════════════════

/**
 * BATCH SYNC ALL CLAIMS - Đồng bộ Custom Claims cho TOÀN BỘ user cũ
 * 
 * Chỉ Super Admin (admin@huluca.com) được quyền gọi.
 * Đọc từ Firestore users/{uid} và set custom claims.
 * 
 * @returns {Object} Thống kê: total, success, skipped, failed, errors
 */
exports.batchSyncAllClaims = onCall({ 
  timeoutSeconds: 540,  // 9 phút cho batch lớn
  memory: "512MiB"
}, async (request) => {
  const auth = request.auth;
  
  // 1. Verify authentication
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }
  
  // 2. ONLY Super Admin can call this function
  const callerEmail = auth.token.email || "";
  if (callerEmail !== "admin@huluca.com") {
    console.log(`DENIED: ${callerEmail} tried to call batchSyncAllClaims`);
    throw new HttpsError("permission-denied", "Chỉ Super Admin mới có quyền sync claims toàn bộ");
  }
  
  console.log(`✅ Super Admin ${callerEmail} started batchSyncAllClaims`);
  
  // 3. Statistics
  const stats = {
    total: 0,
    success: 0,
    skipped: 0,
    failed: 0,
    errors: [],
    details: []
  };
  
  try {
    // 4. Get ALL users from Firestore
    const usersSnapshot = await admin.firestore().collection('users').get();
    stats.total = usersSnapshot.size;
    
    console.log(`Found ${stats.total} users to process`);
    
    // 5. Process each user
    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;
      const userData = userDoc.data();
      
      try {
        // 5.1 Validate user data
        const email = (userData.email || "").toString().trim().toLowerCase();
        const role = (userData.role || "user").toString().trim();
        const shopId = (userData.shopId || "").toString().trim();
        
        // 5.2 Skip if no valid email (can't match with Auth)
        if (!email) {
          stats.skipped++;
          stats.details.push({ uid, status: 'skipped', reason: 'no_email' });
          continue;
        }
        
        // 5.3 Validate role
        const validRoles = ['owner', 'manager', 'employee', 'technician', 'user', 'admin'];
        const finalRole = validRoles.includes(role) ? role : 'user';
        
        // 5.4 Determine isSuperAdmin
        const isSuperAdmin = email === "admin@huluca.com";
        
        // 5.5 Build claims object
        const claims = {
          role: finalRole,
          shopId: shopId || uid, // Fallback to uid if no shopId
          isSuperAdmin: isSuperAdmin
        };
        
        // 5.6 Verify user exists in Firebase Auth
        try {
          await admin.auth().getUser(uid);
        } catch (authError) {
          // User doesn't exist in Auth, skip
          stats.skipped++;
          stats.details.push({ uid, email, status: 'skipped', reason: 'not_in_auth' });
          continue;
        }
        
        // 5.7 Set custom claims
        await admin.auth().setCustomUserClaims(uid, claims);
        
        // 5.8 Update Firestore with sync timestamp
        await admin.firestore().collection('users').doc(uid).update({
          claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
          claimsSyncedBy: 'batchSyncAllClaims'
        });
        
        stats.success++;
        stats.details.push({
          uid,
          email,
          status: 'success',
          claims
        });
        
        console.log(`✓ Synced claims for ${email}: role=${finalRole}, shopId=${claims.shopId}, isSuperAdmin=${isSuperAdmin}`);
        
      } catch (userError) {
        stats.failed++;
        const errorMsg = userError.message || userError.toString();
        stats.errors.push({ uid, error: errorMsg });
        stats.details.push({ uid, status: 'failed', error: errorMsg });
        console.error(`✗ Failed to sync claims for ${uid}: ${errorMsg}`);
      }
    }
    
    console.log(`\n=== BATCH SYNC COMPLETED ===`);
    console.log(`Total: ${stats.total}`);
    console.log(`Success: ${stats.success}`);
    console.log(`Skipped: ${stats.skipped}`);
    console.log(`Failed: ${stats.failed}`);
    
    return {
      success: true,
      message: `Đã sync claims cho ${stats.success}/${stats.total} users`,
      stats: {
        total: stats.total,
        success: stats.success,
        skipped: stats.skipped,
        failed: stats.failed
      },
      errors: stats.errors.length > 0 ? stats.errors.slice(0, 10) : [], // Limit errors in response
      details: stats.details.slice(0, 50) // Limit details in response
    };
    
  } catch (error) {
    console.error('Error in batchSyncAllClaims:', error);
    throw new HttpsError("internal", `Lỗi sync claims: ${error.message}`);
  }
});

/**
 * SYNC SINGLE USER CLAIMS - Sync claims cho 1 user cụ thể (v2)
 * Chỉ Super Admin hoặc Owner của shop được gọi.
 */
exports.syncUserClaimsV2 = onCall(async (request) => {
  const auth = request.auth;
  const data = request.data || {};
  
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }
  
  const targetUid = data.uid;
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "Thiếu uid của user cần sync");
  }
  
  const callerEmail = auth.token.email || "";
  const isSuperAdmin = callerEmail === "admin@huluca.com";
  
  // Get caller's data to check permissions
  const callerDoc = await admin.firestore().collection('users').doc(auth.uid).get();
  const callerData = callerDoc.data() || {};
  const callerRole = callerData.role || "user";
  const callerShopId = callerData.shopId;
  
  // Get target user's data
  const targetDoc = await admin.firestore().collection('users').doc(targetUid).get();
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "User không tồn tại");
  }
  
  const targetData = targetDoc.data();
  const targetShopId = targetData.shopId;
  
  // Permission check: Super Admin OR Owner of same shop
  if (!isSuperAdmin && (callerRole !== 'owner' || callerShopId !== targetShopId)) {
    throw new HttpsError("permission-denied", "Bạn không có quyền sync claims cho user này");
  }
  
  // Build claims
  const email = (targetData.email || "").toString().trim().toLowerCase();
  const role = (targetData.role || "user").toString();
  const shopId = targetData.shopId || targetUid;
  
  const claims = {
    role: role,
    shopId: shopId,
    isSuperAdmin: email === "admin@huluca.com"
  };
  
  // Set claims
  await admin.auth().setCustomUserClaims(targetUid, claims);
  
  // Update Firestore
  await admin.firestore().collection('users').doc(targetUid).update({
    claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    claimsSyncedBy: auth.uid
  });
  
  console.log(`✓ syncUserClaims: ${email} synced by ${callerEmail}`);
  
  return {
    success: true,
    uid: targetUid,
    claims: claims
  };
});

/**
 * REFRESH MY CLAIMS - User tự refresh claims của mình (v2)
 * Dùng sau khi role/shopId được thay đổi bởi admin
 */
exports.refreshMyClaimsV2 = onCall(async (request) => {
  const auth = request.auth;
  
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }
  
  const uid = auth.uid;
  
  // Get user data from Firestore
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  if (!userDoc.exists) {
    throw new HttpsError("not-found", "User không tồn tại trong Firestore");
  }
  
  const userData = userDoc.data();
  const email = (userData.email || auth.token.email || "").toString().trim().toLowerCase();
  const role = (userData.role || "user").toString();
  const shopId = userData.shopId || uid;
  
  const claims = {
    role: role,
    shopId: shopId,
    isSuperAdmin: email === "admin@huluca.com"
  };
  
  // Set claims
  await admin.auth().setCustomUserClaims(uid, claims);
  
  // Update Firestore
  await admin.firestore().collection('users').doc(uid).update({
    claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    claimsSyncedBy: 'self'
  });
  
  console.log(`✓ refreshMyClaims: ${email} refreshed own claims`);
  
  return {
    success: true,
    claims: claims,
    message: "Claims đã được refresh. Vui lòng logout và login lại để áp dụng."
  };
});

/**
 * GET MY CLAIMS - Xem claims hiện tại của user (v2)
 */
exports.getMyClaimsV2 = onCall(async (request) => {
  const auth = request.auth;
  
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }
  
  const uid = auth.uid;
  
  // Get current claims from Auth
  const userRecord = await admin.auth().getUser(uid);
  const currentClaims = userRecord.customClaims || {};
  
  // Get Firestore data for comparison
  const userDoc = await admin.firestore().collection('users').doc(uid).get();
  const firestoreData = userDoc.exists ? userDoc.data() : null;
  
  return {
    success: true,
    uid: uid,
    email: auth.token.email,
    currentClaims: currentClaims,
    firestoreData: firestoreData ? {
      role: firestoreData.role,
      shopId: firestoreData.shopId,
      claimsSyncedAt: firestoreData.claimsSyncedAt
    } : null,
    needsSync: firestoreData && (
      currentClaims.role !== firestoreData.role ||
      currentClaims.shopId !== firestoreData.shopId
    )
  };
});

// 🧹 CLEANUP FCM TOKENS - Xóa tokens cũ và không hợp lệ (mỗi Chủ nhật 3AM)
exports.cleanupFCMTokens = onSchedule("0 3 * * 0", async (event) => {
  try {
    console.log('Starting FCM token cleanup...');

    const batch = admin.firestore().batch();
    let cleanupCount = 0;
    const maxCleanup = 500; // Giới hạn số lượng cleanup mỗi lần

    // 1. Xóa tokens cũ hơn 30 ngày
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const oldTokensQuery = admin.firestore()
      .collection('users')
      .where('fcmTokenUpdatedAt', '<', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .limit(maxCleanup);

    const oldTokensSnapshot = await oldTokensQuery.get();
    console.log(`Found ${oldTokensSnapshot.size} old FCM tokens to clean up`);

    oldTokensSnapshot.forEach(doc => {
      const userData = doc.data();
      if (userData.fcmToken) {
        batch.update(doc.ref, {
          fcmToken: admin.firestore.FieldValue.delete(),
          fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        cleanupCount++;
      }
    });

    // 2. Xóa tokens trùng lặp (giữ lại token mới nhất cho mỗi user)
    if (cleanupCount < maxCleanup) {
      const allTokensQuery = admin.firestore()
        .collection('users')
        .where('fcmToken', '!=', null)
        .orderBy('fcmToken')
        .orderBy('fcmTokenUpdatedAt', 'desc')
        .limit(maxCleanup - cleanupCount);

      const allTokensSnapshot = await allTokensQuery.get();
      const seenTokens = new Set();

      allTokensSnapshot.forEach(doc => {
        const userData = doc.data();
        const token = userData.fcmToken;

        if (token && seenTokens.has(token)) {
          // Token này đã thấy trước đó, xóa
          batch.update(doc.ref, {
            fcmToken: admin.firestore.FieldValue.delete(),
            fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          cleanupCount++;
        } else if (token) {
          seenTokens.add(token);
        }
      });
    }

    if (cleanupCount > 0) {
      await batch.commit();
      console.log(`Cleaned up ${cleanupCount} FCM tokens`);
    } else {
      console.log('No FCM tokens to clean up');
    }

  } catch (error) {
    console.error('Error in FCM token cleanup:', error);
  }
});

/**
 * 🗑️ DELETE USER DATA (Super Admin only)
 * Deletes user Firestore doc + Auth account + related data in all collections
 */
exports.deleteUserData = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  }

  const callerEmail = (auth.token.email || "").toLowerCase().trim();
  if (!checkIsSuperAdmin(callerEmail)) {
    throw new HttpsError("permission-denied", "Chỉ Super Admin mới có quyền xóa dữ liệu");
  }

  const data = request.data || {};
  const targetUserId = (data.userId || "").toString().trim();
  const deleteAuth = data.deleteAuth !== false; // default true

  if (!targetUserId) {
    throw new HttpsError("invalid-argument", "Thiếu userId");
  }

  // Prevent deleting self
  if (auth.uid === targetUserId) {
    throw new HttpsError("permission-denied", "Không thể tự xóa tài khoản của mình");
  }

  const db = admin.firestore();
  const results = { deleted: [], errors: [] };

  // 1. Get user doc to find shopId
  const userDoc = await db.doc(`users/${targetUserId}`).get();
  const userData = userDoc.exists ? userDoc.data() : {};
  const shopId = userData.shopId || null;

  // 2. Delete related data in batched collections (filtered by shopId if available)
  const collectionsToClean = [
    { name: 'repairs', field: 'createdBy' },
    { name: 'sales', field: 'sellerId' },
    { name: 'expenses', field: 'createdBy' },
    { name: 'attendance', field: 'userId' },
    { name: 'notifications', field: 'userId' },
    { name: 'payment_requests', field: 'senderId' },
  ];

  for (const col of collectionsToClean) {
    try {
      const query = db.collection(col.name)
        .where(col.field, '==', targetUserId)
        .limit(500);
      const snap = await query.get();
      if (snap.size > 0) {
        const batch = db.batch();
        snap.docs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();
        results.deleted.push(`${col.name}: ${snap.size} docs`);
      }
    } catch (err) {
      results.errors.push(`${col.name}: ${err.message}`);
    }
  }

  // 3. Delete user Firestore document
  try {
    if (userDoc.exists) {
      await db.doc(`users/${targetUserId}`).delete();
      results.deleted.push('users: 1 doc');
    }
  } catch (err) {
    results.errors.push(`users: ${err.message}`);
  }

  // 4. Delete Firebase Auth account
  if (deleteAuth) {
    try {
      await admin.auth().deleteUser(targetUserId);
      results.deleted.push('auth: account deleted');
    } catch (err) {
      // User may not exist in Auth
      if (err.code !== 'auth/user-not-found') {
        results.errors.push(`auth: ${err.message}`);
      }
    }
  }

  console.log(`🗑️ deleteUserData for ${targetUserId}:`, JSON.stringify(results));

  return {
    success: true,
    userId: targetUserId,
    results: results,
    message: `Đã xóa user ${userData.email || targetUserId} và dữ liệu liên quan`,
  };
});
