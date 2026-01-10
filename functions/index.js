const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2/options");

admin.initializeApp();
// Giới hạn region & timeout mặc định
setGlobalOptions({ region: "asia-southeast1", timeoutSeconds: 30 });

// 🔔 Thông báo khi CÓ ĐƠN SỬA MỚI
exports.notifyNewRepair = onDocumentCreated("repairs/{repairId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const payload = {
    notification: {
      title: "🔧 Có đơn sửa mới",
      body: `${data.customerName} - ${data.model}`,
    },
    data: {
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

  const payload = {
    notification: {
      title: statusText,
      body: `${after.customerName} - ${after.model}`,
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
  if (role !== "admin" || (!isSuperAdmin && requesterRole !== "admin")) {
    role = "user";
  }

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName,
    });

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
      allowViewRevenue: role === "admin",
      allowViewExpenses: role === "admin",
      allowViewDebts: role === "admin",
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
    case 'system':
    default:
      return ['admin', 'owner', 'manager', 'employee', 'technician', 'user'];
  }
}

// 📢 GỬI THÔNG BÁO PUSH CHO SHOP
exports.sendShopNotification = onCall(async (request) => {
  const data = request.data || {};
  // Temporarily disable auth for testing
  // const auth = request.auth;
  // if (!auth) {
  //   throw new HttpsError("unauthenticated", "Vui lòng đăng nhập");
  // }

  const title = (data.title || "Thông báo").toString();
  const body = (data.body || "").toString();
  const type = (data.type || "system").toString();
  const targetUserId = data.targetUserId; // optional, if null then broadcast to all shop users

  // Temporarily use hardcoded shopId for testing
  const shopId = data.shopId || "honC8KnKhOUG19wcYOFDTGVdKWP2"; // Use the shopId from logs

  // const requesterDoc = await admin.firestore().collection("users").doc(auth.uid).get();
  // const requesterData = requesterDoc.data() || {};
  // const shopId = requesterData.shopId;

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
    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: type,
        shopId: shopId,
        senderId: "system", // Temporarily hardcoded for testing
      },
      android: {
        priority: getAndroidPriority(type),
        notification: {
          channelId: getChannelId(type),
          priority: getAndroidPriority(type),
        },
      },
      apns: {
        payload: {
          aps: {
            sound: getChannelId(type) === 'new_order_channel' || getChannelId(type) === 'payment_channel' ? 'default' : null,
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
