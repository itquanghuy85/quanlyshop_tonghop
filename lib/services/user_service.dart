import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import 'encryption_service.dart';
import 'claims_service.dart';
import 'payment_intent_service.dart';

class UserService {
  // Validate input fields
  static String? validateName(String name, AppLocalizations loc) {
    if (name.trim().isEmpty) return loc.nameRequired;
    return null;
  }

  static String? validatePhone(String phone, AppLocalizations loc) {
    // Cho phép số điện thoại trống (optional)
    if (phone.trim().isEmpty) return null;
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length < 9 || cleaned.length > 12) {
      return loc.phoneLengthInvalid;
    }
    return null;
  }

  static String? validateAddress(String address, AppLocalizations loc) {
    // Cho phép địa chỉ trống (optional)
    if (address.trim().isEmpty) return null;
    return null;
  }

  static String? validateIMEI(String imei, AppLocalizations loc) {
    if (imei.isEmpty) return null; // IMEI có thể để trống cho phụ kiện
    // Chấp nhận: 4-5 số (mã ngắn nội bộ) hoặc 15 số (IMEI chuẩn)
    if (imei.length < 4) {
      return loc.imeiMinLength;
    }
    if (imei.length > 5 && imei.length != 15) {
      return loc.imeiLengthInvalid;
    }
    if (!RegExp(r'^\d+$').hasMatch(imei)) {
      return loc.imeiDigitsOnly;
    }
    return null;
  }

  static String? validateModel(String model, AppLocalizations loc) {
    if (model.trim().isEmpty) return loc.modelRequired;
    if (model.trim().length < 2) return loc.modelMinLength;
    if (model.trim().length > 50) return loc.modelMaxLength;
    return null;
  }

  static final _db = FirebaseFirestore.instance;
  static String? _cachedShopId;
  static String? _cachedUid; // Track which user's shopId is cached
  static String? _adminSelectedShopId; // Shop được super admin chọn để xem
  static bool? _cachedCanViewCostPrice; // Cache permission xem giá vốn
  static DateTime? _cachedCanViewCostPriceTime; // Thời điểm cache

  // Method để cập nhật cache shopId từ bên ngoài (dùng cho sync)
  static void updateCachedShopId(String? shopId) {
    _cachedShopId = shopId;
    _cachedUid = FirebaseAuth.instance.currentUser?.uid;
  }

  /// Check if shopId is currently valid and ready for data operations
  static bool isShopIdReady() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    if (_isSuperAdmin(currentUser)) {
      return _adminSelectedShopId != null && _adminSelectedShopId!.isNotEmpty;
    }
    return _cachedShopId != null &&
        _cachedShopId!.isNotEmpty &&
        _cachedUid == currentUser.uid;
  }

  /// Get shopId synchronously (returns cached value or null)
  /// Use this for quick checks, use getCurrentShopId() for guaranteed fetch
  static String? getShopIdSync() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;
    if (_isSuperAdmin(currentUser)) return _adminSelectedShopId;
    if (_cachedUid == currentUser.uid) return _cachedShopId;
    return null;
  }

  /// Ensure shopId is available, waiting if necessary
  /// Use this before critical data operations to ensure shopId is valid
  /// Returns the shopId or throws exception if cannot obtain after retries
  static Future<String> ensureShopId({int maxRetries = 5}) async {
    // First try cache
    final cachedId = getShopIdSync();
    if (cachedId != null && cachedId.isNotEmpty) return cachedId;

    // Try to get from Firestore/Claims
    for (int retry = 0; retry < maxRetries; retry++) {
      final shopId = await getCurrentShopId();
      if (shopId != null && shopId.isNotEmpty) {
        debugPrint(
          'ensureShopId: got shopId=$shopId after ${retry + 1} attempts',
        );
        return shopId;
      }
      debugPrint(
        'ensureShopId: retry ${retry + 1}/$maxRetries - no shopId yet',
      );
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception(
      'Không thể lấy shopId sau $maxRetries lần thử. Vui lòng đăng xuất và đăng nhập lại.',
    );
  }

  /// Lưu shopId + role vào SharedPreferences để lần đăng nhập sau
  /// không cần chờ Firestore/claims — dùng ngay từ local.
  static Future<void> saveAuthCache({String? role}) async {
    if (_cachedShopId == null || _cachedUid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_cache_shopId', _cachedShopId!);
      await prefs.setString('auth_cache_uid', _cachedUid!);
      if (role != null) {
        await prefs.setString('auth_cache_role', role);
      }
      debugPrint('💾 saveAuthCache: shopId=$_cachedShopId, uid=$_cachedUid, role=$role');
    } catch (e) {
      debugPrint('⚠️ saveAuthCache error: $e');
    }
  }

  /// Khôi phục cache từ SharedPreferences — gọi ĐẦU TIÊN khi app mở.
  /// Trả về true nếu cache hợp lệ (đúng uid), false nếu không có.
  static Future<bool> restoreAuthCache(String currentUid) async {
    // Đã có cache đúng user → không cần đọc prefs
    if (_cachedShopId != null && _cachedShopId!.isNotEmpty && _cachedUid == currentUid) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUid = prefs.getString('auth_cache_uid');
      final savedShopId = prefs.getString('auth_cache_shopId');
      if (savedUid == currentUid && savedShopId != null && savedShopId.isNotEmpty) {
        _cachedShopId = savedShopId;
        _cachedUid = currentUid;
        debugPrint('♻️ restoreAuthCache: restored shopId=$savedShopId for uid=$currentUid');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ restoreAuthCache error: $e');
    }
    return false;
  }

  /// Lấy role đã lưu từ SharedPreferences (fallback khi Firestore timeout)
  static Future<String?> getCachedRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_cache_role');
    } catch (_) {
      return null;
    }
  }

  /// Xóa cache khi logout để tránh lấy nhầm shopId của user khác
  static void clearCache() {
    debugPrint('UserService: Clearing cached shopId and uid');
    _cachedShopId = null;
    _cachedUid = null;
    _adminSelectedShopId = null;
    _cachedCanViewCostPrice = null;
    _cachedCanViewCostPriceTime = null;
    ClaimsService().stopClaimsSync(); // Stop claims listener on logout
    PaymentIntentService.clearCache(); // Clear payment intent cache
    // Xóa auth cache prefs
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('auth_cache_shopId');
      prefs.remove('auth_cache_uid');
      prefs.remove('auth_cache_role');
    }).catchError((_) {});
  }

  /// Initialize claims sync after login
  static void initClaimsSync() {
    ClaimsService().startClaimsSync();
    debugPrint('UserService: Started claims sync');
  }

  static bool _isSuperAdmin(User? user) {
    return user?.email?.toLowerCase() == 'admin@huluca.com';
  }

  static bool isCurrentUserSuperAdmin() {
    return _isSuperAdmin(FirebaseAuth.instance.currentUser);
  }

  /// Kiểm tra user hiện tại có phải admin (owner/manager/super admin)
  static Future<bool> isCurrentUserAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (_isSuperAdmin(user)) return true;

    final role = await getUserRole(user.uid);
    return role == 'admin' || role == 'owner' || role == 'manager';
  }

  /// Lấy tên hiển thị của user hiện tại
  static Future<String> getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    // 1. Thử lấy từ Firebase Auth displayName
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim();
    }

    // 2. Lấy từ Firestore (kiểm tra cả displayName và name, bỏ qua chuỗi rỗng)
    try {
      final info = await getUserInfo(user.uid);
      final displayName = (info['displayName'] ?? '').toString().trim();
      if (displayName.isNotEmpty) return displayName;
      final name = (info['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (e) {
      debugPrint('getCurrentUserName error: $e');
    }

    // 3. Fallback: capitalize phần trước @ của email
    if (user.email != null && user.email!.isNotEmpty) {
      final prefix = user.email!.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }

    return '';
  }

  /// Lấy danh sách tất cả shops (chỉ dùng cho super admin) kèm thông tin chi tiết
  static Future<List<Map<String, dynamic>>> getAllShops() async {
    if (!isCurrentUserSuperAdmin()) return [];
    try {
      final snap = await _db.collection('shops').get();
      final shops = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        // Đếm số nhân viên của shop
        try {
          final usersSnap = await _db
              .collection('users')
              .where('shopId', isEqualTo: doc.id)
              .get();
          data['userCount'] = usersSnap.docs.length;
        } catch (_) {
          data['userCount'] = 0;
        }
        shops.add(data);
      }
      // Sắp xếp: shop mới nhất lên trước
      shops.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return shops;
    } catch (e) {
      debugPrint('getAllShops error: $e');
      return [];
    }
  }

  /// Super admin chọn shop để xem
  static void setAdminSelectedShop(String? shopId) {
    if (!isCurrentUserSuperAdmin()) return;
    _adminSelectedShopId = shopId;
    _cachedShopId = shopId;
    _cachedUid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('Super admin selected shop: $shopId');
  }

  /// Lấy shop đang được super admin chọn
  static String? getAdminSelectedShop() {
    return _adminSelectedShopId;
  }

  static Map<String, bool> _defaultPermissionsForRole(String role) {
    final isOwner = role == 'owner';
    final isManager = role == 'manager';
    final isEmployee = role == 'employee';
    final isTechnician = role == 'technician';
    final isAdmin = role == 'admin'; // Super admin
    final isUser = role == 'user'; // Default fallback

    return {
      // Chủ shop: toàn quyền quản lý shop
      // Quản lý: xem được tất cả, quản lý nhân viên
      // Nhân viên: xem nghiệp vụ cơ bản, không xem tài chính
      // Kỹ thuật: chỉ xem sửa chữa, linh kiện, khách hàng
      // Admin: toàn quyền như owner (super admin)
      // User: quyền tối thiểu (fallback)
      'allowViewSales': isOwner || isManager || isEmployee || isAdmin,
      'allowViewRepairs':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser,
      'allowViewInventory': isOwner || isManager || isEmployee || isAdmin,
      'allowViewParts':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser, // Tất cả đều cần xem linh kiện
      'allowViewSuppliers': isOwner || isManager || isEmployee || isAdmin,
      'allowViewCustomers':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser, // Tất cả đều cần xem khách hàng
      'allowViewPurchaseOrders': isOwner || isManager || isAdmin,
      'allowCreatePurchaseOrders': isOwner || isManager || isAdmin,
      'allowViewWarranty':
          isOwner || isManager || isEmployee || isTechnician || isAdmin,
      'allowViewChat':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser,
      'allowViewAttendance':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser,
      'allowViewPrinter':
          isOwner ||
          isManager ||
          isEmployee ||
          isTechnician ||
          isAdmin ||
          isUser,
      'allowViewRevenue': isOwner, // Chỉ chủ shop được xem tài chính
      'allowViewExpenses': isOwner, // Chỉ chủ shop được xem chi phí
      'allowViewDebts': isOwner, // Chỉ chủ shop được xem công nợ
      'allowViewCostPrice': isOwner || isManager || isAdmin, // Xem giá vốn - mặc định chỉ owner/manager/admin
      'allowViewSettings': isOwner || isManager || isAdmin,
      'allowManageStaff': isOwner || isManager || isAdmin,
      'shopAppLocked': false,
      'shopAdminFinanceLocked': false,
    };
  }

  static Future<String?> getCurrentShopId() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint("getCurrentShopId: không có currentUser");
      clearCache(); // Clear cache nếu không có user
      return null;
    }

    // Super admin: trả về shop đã chọn (nếu có)
    if (_isSuperAdmin(currentUser)) {
      if (_adminSelectedShopId != null) {
        debugPrint(
          "getCurrentShopId: super admin đã chọn shop $_adminSelectedShopId",
        );
        return _adminSelectedShopId;
      }
      debugPrint("getCurrentShopId: super admin chưa chọn shop");
      return null;
    }

    // Nếu cache còn hiệu lực và đúng user thì trả về ngay
    // Shop validation sẽ được thực hiện khi load dữ liệu, không chặn login
    if (_cachedShopId != null && _cachedUid == currentUser.uid) {
      if (_cachedShopId!.isNotEmpty) {
        debugPrint(
          "getCurrentShopId: trả về cache $_cachedShopId cho user $_cachedUid",
        );
        return _cachedShopId;
      }
    }

    // Cache không hợp lệ hoặc user khác - cần load lại
    if (_cachedUid != null && _cachedUid != currentUser.uid) {
      debugPrint(
        "getCurrentShopId: User đã thay đổi ($_cachedUid -> ${currentUser.uid}), xóa cache",
      );
      clearCache();
    }

    try {
      debugPrint("getCurrentShopId: lấy dữ liệu user ${currentUser.uid}");
      final doc = await _db.collection('users').doc(currentUser.uid).get();
      final data = doc.data();
      String? shopId = data != null ? data['shopId'] as String? : null;

      // Auto-heal 1: nếu user doc thiếu shopId, ưu tiên lấy từ custom claims.
      if (shopId == null || shopId.trim().isEmpty) {
        final claimsShopId = await ClaimsService().getShopIdFromClaims();
        if (claimsShopId != null && claimsShopId.trim().isNotEmpty) {
          shopId = claimsShopId;
          try {
            await _db.collection('users').doc(currentUser.uid).set({
              'shopId': claimsShopId,
              'lastRecoveredAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint(
              'getCurrentShopId: recovered user.shopId from claims -> $claimsShopId',
            );
          } catch (e) {
            debugPrint('getCurrentShopId: failed to persist claims shopId: $e');
          }
        }
      }

      // Auto-heal 2: nếu vẫn thiếu shopId, thử tìm shop mà user đang là owner.
      if (shopId == null || shopId.trim().isEmpty) {
        final ownedShopId = await _findOwnedActiveShopId(currentUser.uid);
        if (ownedShopId != null && ownedShopId.isNotEmpty) {
          shopId = ownedShopId;
          try {
            await _db.collection('users').doc(currentUser.uid).set({
              'shopId': ownedShopId,
              'lastRecoveredAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint(
              'getCurrentShopId: recovered missing user.shopId -> $ownedShopId',
            );
          } catch (e) {
            debugPrint('getCurrentShopId: failed to persist recovered shopId: $e');
          }
        }
      }

      // Nếu shopId hiện tại trỏ tới shop đã bị xóa/không tồn tại, fallback sang shop owner đang active.
      if (shopId != null && shopId.trim().isNotEmpty) {
        try {
          final shopDoc = await _db.collection('shops').doc(shopId).get();
          final shopDeleted = shopDoc.data()?['deleted'] == true;
          final role = (data?['role'] ?? '').toString().trim().toLowerCase();
          final isOwnerRole = role == 'owner';
          final ownerUid = shopDoc.data()?['ownerUid']?.toString();
          final ownerMismatch = isOwnerRole && ownerUid != null && ownerUid != currentUser.uid;

          if (!shopDoc.exists || shopDeleted || ownerMismatch) {
            final ownedShopId = await _findOwnedActiveShopId(currentUser.uid);
            if (ownedShopId != null && ownedShopId.isNotEmpty && ownedShopId != shopId) {
              debugPrint(
                'getCurrentShopId: switching from invalid/mismatched shopId=$shopId to owned shop=$ownedShopId',
              );
              shopId = ownedShopId;
              await _db.collection('users').doc(currentUser.uid).set({
                'shopId': ownedShopId,
                'lastRecoveredAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        } catch (e) {
          debugPrint('getCurrentShopId: unable to validate shop document: $e');
        }
      }

      _cachedShopId = shopId;
      _cachedUid = currentUser.uid; // Lưu uid để verify cache
      debugPrint("getCurrentShopId: shopId = $shopId cho uid = $_cachedUid");
      return shopId;
    } catch (e) {
      debugPrint("getCurrentShopId: lỗi $e");
      return null;
    }
  }

  // Lấy quyền của người dùng (Có nhận diện Admin đặc biệt)
  // NOTE: Prefer using ClaimsService().getRoleFromClaims() for faster access
  static Future<String> getUserRole(String uid) async {
    // CAO KIẾN: Nhận diện Admin tối cao qua Email
    final currentUser = FirebaseAuth.instance.currentUser;
    debugPrint("getUserRole: currentUser email = ${currentUser?.email}");
    if (currentUser?.email == 'admin@huluca.com') {
      debugPrint("getUserRole: returning admin for super admin");
      return 'admin'; // Luôn là Admin nếu dùng email này
    }

    // Try to get role from Custom Claims first (faster, no Firestore read)
    if (uid == currentUser?.uid) {
      try {
        final role = await ClaimsService().getRoleFromClaims();
        if (role != 'user') {
          // user is default, might not be set yet
          debugPrint("getUserRole: role from claims = $role");
          return role;
        }
      } catch (e) {
        debugPrint("getUserRole: claims error $e, falling back to Firestore");
      }
    }

    // Fallback to Firestore
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final role = doc.data()?['role'] ?? 'user';
      debugPrint("getUserRole: role from firestore = $role");
      return role;
    } catch (e) {
      debugPrint("getUserRole: error $e, returning user");
      return 'user';
    }
  }

  /// Fast role check using Custom Claims (no Firestore read)
  static Future<String> getRoleFast() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.email == 'admin@huluca.com') {
      return 'admin';
    }
    return await ClaimsService().getRoleFromClaims();
  }

  /// Fast shopId check using Custom Claims (no Firestore read)
  static Future<String?> getShopIdFast() async {
    if (isCurrentUserSuperAdmin()) {
      return _adminSelectedShopId;
    }
    return await ClaimsService().getShopIdFromClaims();
  }

  static Future<Map<String, dynamic>> getUserInfo(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data() ?? {};
  }

  static Stream<QuerySnapshot> getAllUsersStream() {
    final currentUser = FirebaseAuth.instance.currentUser;

    // Super admin xem được toàn bộ
    if (currentUser != null && _isSuperAdmin(currentUser)) {
      // Nếu super admin đã chọn shop cụ thể, lọc theo shop đó
      if (_adminSelectedShopId != null &&
          _adminSelectedShopId!.trim().isNotEmpty) {
        return _db
            .collection('users')
            .where('shopId', isEqualTo: _adminSelectedShopId)
            .snapshots();
      }
      return _db.collection('users').snapshots();
    }

    // Người dùng thường: ưu tiên lọc theo shopId nếu đã có
    final shopId = _cachedShopId;
    if (shopId != null && shopId.trim().isNotEmpty) {
      return _db
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .snapshots();
    }

    // Trường hợp chưa đồng bộ shopId, tạm thời trả toàn bộ (sẽ thu hẹp sau khi syncUserInfo chạy)
    return _db.collection('users').snapshots();
  }

  /// Stream lấy users theo shopId cụ thể (dùng khi cần đảm bảo có shopId)
  static Stream<QuerySnapshot> getUsersStreamByShopId(String shopId) {
    return _db
        .collection('users')
        .where('shopId', isEqualTo: shopId)
        .snapshots();
  }

  static Future<void> updateUserInfo({
    required String uid,
    required String name,
    required String phone,
    required String address,
    required String role,
    required AppLocalizations loc,
    String? photoUrl,
    String? shopId,
  }) async {
    // Validate input
    final nameError = validateName(name, loc);
    final phoneError = validatePhone(phone, loc);
    final addressError = validateAddress(address, loc);
    if (nameError != null || phoneError != null || addressError != null) {
      throw Exception(
        [
          if (nameError != null) nameError,
          if (phoneError != null) phoneError,
          if (addressError != null) addressError,
        ].join(' | '),
      );
    }

    // Refresh token để đảm bảo custom claims được cập nhật
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (e) {
      debugPrint('Could not refresh token before updating user info: $e');
    }

    // Cập nhật dữ liệu người dùng
    // Role có thể được thay đổi bởi owner của shop (theo Firestore rules)
    final updateData = <String, dynamic>{
      'displayName': name.toUpperCase(),
      'name': name.toUpperCase(), // Thêm name field cho compatibility
      'phone': phone,
      'address': address.toUpperCase(),
      'role': role, // Owner có thể thay đổi role theo rules
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Chỉ SuperAdmin mới được cập nhật shopId
    final currentUser = FirebaseAuth.instance.currentUser;
    final isSuperAdmin = currentUser?.email == 'admin@huluca.com';
    if (shopId != null && isSuperAdmin) {
      updateData['shopId'] = shopId;
    }

    debugPrint(
      'UserService.updateUserInfo: updating uid=$uid with ${updateData.keys.toList()}',
    );
    try {
      await _db
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true));
      debugPrint('UserService.updateUserInfo: success for uid=$uid');
    } catch (e) {
      debugPrint('UserService.updateUserInfo: error for uid=$uid: $e');
      rethrow;
    }

    // Đồng bộ dữ liệu liên quan (ví dụ: cập nhật tên, số điện thoại ở các bảng khác nếu cần)
    // TODO: Nếu có bảng orders, repair_orders,... thì cập nhật thông tin liên quan ở đó
  }

  static Future<void> syncUserInfo(
    String uid,
    String email, {
    Map<String, dynamic>? extra,
  }) async {
    debugPrint('🔄 syncUserInfo: START for uid=$uid, email=$email');

    // Lấy thông tin hiện tại để đồng bộ
    final userRef = _db.collection('users').doc(uid);
    final userDoc = await userRef.get();
    final data = userDoc.data() ?? {};

    final bool isSuperAdmin = email == 'admin@huluca.com';
    String? shopId = data['shopId'];
    bool isNewShop = false;

    // Nếu chưa có shopId và không phải super admin:
    // 1) ưu tiên dùng shop đang sở hữu (nếu có) để tránh rơi vào shop mới rỗng,
    // 2) nếu không có mới tạo shop mới trùng uid.
    if (!isSuperAdmin && (shopId == null || shopId.trim().isEmpty)) {
      final claimsShopId = await ClaimsService().getShopIdFromClaims();
      if (claimsShopId != null && claimsShopId.trim().isNotEmpty) {
        shopId = claimsShopId;
        debugPrint('🔁 syncUserInfo: Reusing claims shopId=$shopId');
      } else {
        // Force refresh token/claims once before deciding to create a new shop.
        // This avoids creating an empty shop when claims sync is delayed.
        try {
          await ClaimsService().forceRefresh();
          final freshClaims = await ClaimsService().getClaimsFromToken(
            forceRefresh: true,
          );
          final freshClaimsShopId = freshClaims?['shopId']?.toString();
          if (freshClaimsShopId != null && freshClaimsShopId.trim().isNotEmpty) {
            shopId = freshClaimsShopId.trim();
            debugPrint('🔁 syncUserInfo: Reusing FRESH claims shopId=$shopId');
          }
        } catch (e) {
          debugPrint('⚠️ syncUserInfo: force refresh claims failed: $e');
        }

        if (shopId != null && shopId.trim().isNotEmpty) {
          // Persist recovered shopId for stable future logins.
          await userRef.set({
            'shopId': shopId,
            'lastRecoveredAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
        final ownedShopId = await _findOwnedActiveShopId(uid);
        if (ownedShopId != null && ownedShopId.isNotEmpty) {
          shopId = ownedShopId;
          debugPrint('🔁 syncUserInfo: Reusing existing owned shopId=$shopId');
        } else {
          shopId = uid;
          isNewShop = true;
          debugPrint(
            '🆕 syncUserInfo: Creating new shop with id=$shopId for user $email',
          );

          // CRITICAL: Tạo shop document trước và đợi hoàn thành
          try {
            await _db.collection('shops').doc(shopId).set({
              'shopId': shopId,
              'ownerUid': uid,
              'ownerEmail': email,
              'name': extra?['shopName'] ?? 'Cửa hàng mới',
              'businessType': 'electronics', // Default cho shop mới
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint('✅ syncUserInfo: Shop document created successfully');

            // Tạo shop_settings subcollection doc cho shop mới
            try {
              final settings = {
                'shopId': shopId,
                'businessType': 'electronics',
                'businessTypeName': 'Điện thoại & Điện tử',
                'enableRepair': true,
                'enableSerial': true,
                'enableWarranty': true,
                'enableExpiry': false,
                'enableVariants': false,
                'enableBatch': false,
                'defaultUnit': 'cái',
                'expiryWarningDays': 7,
                'lowStockWarning': 5,
                'createdAt': DateTime.now().toIso8601String(),
                'updatedAt': DateTime.now().toIso8601String(),
              };
              await _db.collection('shops').doc(shopId)
                  .collection('settings').doc('shop_settings')
                  .set(settings);
              debugPrint('✅ syncUserInfo: shop_settings created for new shop');
            } catch (e) {
              debugPrint('⚠️ syncUserInfo: Failed to create shop_settings: $e');
              // Non-critical, CategoryService will auto-create from shop doc businessType
            }
          } catch (e) {
            debugPrint('❌ syncUserInfo: Failed to create shop: $e');
            rethrow; // Không tiếp tục nếu không tạo được shop
          }
        }
        }
      }
    }

    // CRITICAL: Set cache NGAY SAU khi có shopId, trước khi làm gì khác
    _cachedShopId = shopId is String ? shopId : null;
    _cachedUid = uid;
    debugPrint(
      '✅ syncUserInfo: cached shopId=$_cachedShopId for uid=$uid (isNewShop=$isNewShop)',
    );

    // Lưu vào SharedPreferences để lần đăng nhập sau khôi phục ngay
    saveAuthCache();

    // Khởi tạo EncryptionService với shopId để mã hóa/giải mã dữ liệu
    if (_cachedShopId != null && _cachedShopId!.isNotEmpty) {
      EncryptionService.init(_cachedShopId!);
      debugPrint('EncryptionService initialized for shop: $_cachedShopId');
    }

    // Determine displayName with multiple fallbacks
    String resolvedDisplayName = '';
    if (data['displayName'] != null && data['displayName'].toString().trim().isNotEmpty) {
      resolvedDisplayName = data['displayName'].toString().trim();
    } else if (data['name'] != null && data['name'].toString().trim().isNotEmpty) {
      resolvedDisplayName = data['name'].toString().trim();
    } else if (FirebaseAuth.instance.currentUser?.displayName != null &&
               FirebaseAuth.instance.currentUser!.displayName!.trim().isNotEmpty) {
      resolvedDisplayName = FirebaseAuth.instance.currentUser!.displayName!.trim();
    } else if (email.isNotEmpty) {
      // Fallback: capitalize phần trước @ của email
      final emailPrefix = email.split('@').first;
      resolvedDisplayName = emailPrefix.isNotEmpty
          ? emailPrefix[0].toUpperCase() + emailPrefix.substring(1)
          : '';
    }

    final userData = {
      'email': email,
      'displayName': resolvedDisplayName,
      'phone': data['phone'] ?? '',
      'address': data['address'] ?? '',
      'role': isSuperAdmin
          ? 'admin'
          : (data['role'] ?? (shopId == uid ? 'owner' : 'user')),
      'shopId': shopId,
      'lastLogin': FieldValue.serverTimestamp(),
    };
    if (extra != null) {
      userData.addAll(extra);
    }
    await userRef.set(userData, SetOptions(merge: true));

    // Đợi Cloud Function syncUserClaims trigger và set claims
    // Cho shop mới, cần đợi lâu hơn vì Cloud Function trigger từ onCreate
    debugPrint(
      '🔄 syncUserInfo: waiting for claims sync (isNewShop=$isNewShop)...',
    );

    if (isNewShop) {
      // CHỈ shop mới cần đợi claims sync (để Cloud Function set shopId vào claims)
      try {
        debugPrint(
          '📡 syncUserInfo: Calling refreshMyClaims to trigger claims sync...',
        );
        await ClaimsService().refreshMyClaims();
      } catch (e) {
        debugPrint('⚠️ syncUserInfo: refreshMyClaims failed: $e');
      }

      bool claimsSynced = false;
      final maxRetries = 5;

      for (int retry = 0; retry < maxRetries; retry++) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          await ClaimsService().forceRefresh();

          final claims = await ClaimsService().getClaimsFromToken(
            forceRefresh: true,
          );
          final claimsShopId = claims?['shopId'];

          if (claimsShopId != null && claimsShopId == shopId) {
            debugPrint(
              '✅ syncUserInfo: claims synced successfully! shopId=$claimsShopId',
            );
            claimsSynced = true;
            break;
          } else {
            debugPrint(
              '🔄 syncUserInfo: retry ${retry + 1}/$maxRetries - claims shopId=$claimsShopId, expected=$shopId',
            );
            if (retry % 2 == 1) {
              await ClaimsService().refreshMyClaims();
            }
          }
        } catch (e) {
          debugPrint('⚠️ syncUserInfo: retry ${retry + 1}/$maxRetries error: $e');
        }
      }

      if (!claimsSynced) {
        debugPrint(
          '⚠️ syncUserInfo: claims not synced after $maxRetries retries (new shop)',
        );
        debugPrint(
          '📝 syncUserInfo: App sẽ sử dụng cached shopId=$_cachedShopId (claims sẽ sync sau)',
        );
      }
    } else {
      // EXISTING USER: Claims sync in background — không chặn login
      // _cachedShopId đã set từ Firestore user doc, app hoạt động bình thường
      debugPrint(
        '⚡ syncUserInfo: Existing user - skipping blocking claims wait. cached shopId=$_cachedShopId',
      );
      // Fire-and-forget: refresh claims in background
      Future.microtask(() async {
        try {
          await ClaimsService().refreshMyClaims();
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
          debugPrint('✅ syncUserInfo: background claims refresh done');
        } catch (e) {
          debugPrint('⚠️ syncUserInfo: background claims refresh failed: $e');
        }
      });
    }

    debugPrint('✅ syncUserInfo: COMPLETE for uid=$uid, shopId=$shopId');
  }

  /// GÁN một nhân viên vào cùng cửa hàng với user hiện tại
  static Future<void> assignUserToCurrentShop(String targetUid) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    if (_isSuperAdmin(currentUser)) {
      // Super admin cố tình gán shop nên vẫn cho phép, nhưng cần có shopId hiện tại
      // Nếu chưa có shopId cache thì không làm gì để tránh gán nhầm.
      final currentShop = _cachedShopId;
      if (currentShop == null || currentShop.trim().isEmpty) return;
      await _db.collection('users').doc(targetUid).set({
        'shopId': currentShop,
      }, SetOptions(merge: true));
      return;
    }

    final shopId = await getCurrentShopId();
    if (shopId == null || shopId.trim().isEmpty) return;

    await _db.collection('users').doc(targetUid).set({
      'shopId': shopId,
    }, SetOptions(merge: true));
  }

  /// Lấy quyền xem các màn hình nhạy cảm (doanh thu, chi phí, công nợ) của tài khoản hiện tại
  /// Trả về Map với các key:
  /// - allowView*: quyền xem từng chức năng
  /// - shopAppLocked, shopAdminFinanceLocked: cờ khóa từ Super Admin
  /// - lockedBy*: nguồn gốc khóa ('admin' = Super Admin, 'owner' = Chủ shop phân quyền)
  static Future<Map<String, dynamic>> getCurrentUserPermissions() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return _defaultPermissionsForRole('user');
    }

    // Admin tối cao luôn có toàn quyền
    if (_isSuperAdmin(currentUser)) {
      return _defaultPermissionsForRole('admin');
    }

    try {
      final snap = await _db.collection('users').doc(currentUser.uid).get();
      final data = snap.data() ?? {};
      final role = (data['role'] as String?) ?? 'user';
      debugPrint('getCurrentUserPermissions: role from firestore = $role');
      final defaults = _defaultPermissionsForRole(role);
      debugPrint('getCurrentUserPermissions: defaults = $defaults');
      // Debug: kiểm tra allowViewCostPrice từ Firestore vs force override
      final firestoreCostPrice = data['allowViewCostPrice'];
      final forceTrue = (role == 'owner' || role == 'manager' || role == 'admin');
      debugPrint('getCurrentUserPermissions: Firestore allowViewCostPrice=$firestoreCostPrice, forceTrue=$forceTrue');

      // Bắt đầu từ quyền riêng trên tài khoản (nếu chưa cấu hình thì dùng mặc định theo role)
      final perms = <String, dynamic>{
        'allowViewSales':
            (data['allowViewSales'] as bool?) ?? defaults['allowViewSales']!,
        'allowViewRepairs':
            (data['allowViewRepairs'] as bool?) ??
            defaults['allowViewRepairs']!,
        'allowViewInventory':
            (data['allowViewInventory'] as bool?) ??
            defaults['allowViewInventory']!,
        'allowViewParts':
            (data['allowViewParts'] as bool?) ?? defaults['allowViewParts']!,
        'allowViewSuppliers':
            (data['allowViewSuppliers'] as bool?) ??
            defaults['allowViewSuppliers']!,
        'allowViewCustomers':
            (data['allowViewCustomers'] as bool?) ??
            defaults['allowViewCustomers']!,
        'allowViewPurchaseOrders':
            (data['allowViewPurchaseOrders'] as bool?) ??
            defaults['allowViewPurchaseOrders']!,
        'allowCreatePurchaseOrders':
            (data['allowCreatePurchaseOrders'] as bool?) ??
            defaults['allowCreatePurchaseOrders']!,
        'allowViewWarranty':
            (data['allowViewWarranty'] as bool?) ??
            defaults['allowViewWarranty']!,
        'allowViewChat':
            (data['allowViewChat'] as bool?) ?? defaults['allowViewChat']!,
        'allowViewAttendance':
            (data['allowViewAttendance'] as bool?) ??
            defaults['allowViewAttendance']!,
        'allowViewPrinter':
            (data['allowViewPrinter'] as bool?) ??
            defaults['allowViewPrinter']!,
        'allowViewRevenue':
            (data['allowViewRevenue'] as bool?) ??
            defaults['allowViewRevenue']!,
        'allowViewExpenses':
            (data['allowViewExpenses'] as bool?) ??
            defaults['allowViewExpenses']!,
        'allowViewDebts':
            (data['allowViewDebts'] as bool?) ?? defaults['allowViewDebts']!,
        // Owner, Manager, Admin LUÔN được xem giá vốn, không bao giờ bị tắt
        'allowViewCostPrice':
            (role == 'owner' || role == 'manager' || role == 'admin')
              ? true
              : ((data['allowViewCostPrice'] as bool?) ?? defaults['allowViewCostPrice']!),
        'allowViewSettings':
            (data['allowViewSettings'] as bool?) ??
            defaults['allowViewSettings']!,
        'allowManageStaff':
            (data['allowManageStaff'] as bool?) ??
            defaults['allowManageStaff']!,
        'shopAppLocked': false,
        'shopAdminFinanceLocked': false,
        // Lưu nguồn gốc khóa để hiển thị thông báo phù hợp
        'lockedByAdmin': <String>[], // Danh sách các quyền bị Admin khóa
        'lockedByOwner': <String>[], // Danh sách các quyền bị Chủ shop khóa
      };

      // Kiểm tra xem user có được owner phân quyền riêng không (khác với default role)
      final ownerLockedList = <String>[];
      for (final key in [
        'allowViewSales',
        'allowViewRepairs',
        'allowViewInventory',
        'allowViewParts',
        'allowViewSuppliers',
        'allowViewCustomers',
        'allowViewPurchaseOrders',
        'allowViewWarranty',
        'allowViewRevenue',
        'allowViewExpenses',
        'allowViewDebts',
        'allowViewCostPrice',
        'allowViewSettings',
        'allowManageStaff',
      ]) {
        // Nếu user có quyền = false và khác với default role → bị chủ shop tắt
        final userPerm = data[key] as bool?;
        if (userPerm == false && defaults[key] == true) {
          ownerLockedList.add(key);
        }
      }
      perms['lockedByOwner'] = ownerLockedList;

      // Áp thêm luật điều khiển ở cấp shop (do Super Admin thiết lập)
      final adminLockedList = <String>[];
      final shopId = (data['shopId'] as String?) ?? _cachedShopId;
      if (shopId != null && shopId.trim().isNotEmpty) {
        try {
          final shopSnap = await _db.collection('shops').doc(shopId).get();
          final shopData = shopSnap.data() ?? {};
          final appLocked = shopData['appLocked'] == true;
          final adminFinanceLocked = shopData['adminFinanceLocked'] == true;
          final staffSalesLocked = shopData['staffSalesLocked'] == true;
          final staffInventoryLocked = shopData['staffInventoryLocked'] == true;
          final staffDebtLocked = shopData['staffDebtLocked'] == true;
          final staffSettingsLocked = shopData['staffSettingsLocked'] == true;
          debugPrint(
            'UserService: shop appLocked=$appLocked, adminFinanceLocked=$adminFinanceLocked',
          );

          if (appLocked) {
            // Khóa toàn bộ app cho shop này - bởi Admin
            for (final key in perms.keys.toList()) {
              if (key.startsWith('allowView') ||
                  key.startsWith('allowManage') ||
                  key.startsWith('allowCreate')) {
                perms[key] = false;
                adminLockedList.add(key);
              }
            }
            perms['shopAppLocked'] = true;
          }

          // Khóa tài chính cho quản lý - bởi Admin
          if (adminFinanceLocked && (role == 'manager')) {
            perms['allowViewRevenue'] = false;
            perms['allowViewExpenses'] = false;
            perms['allowViewDebts'] = false;
            perms['shopAdminFinanceLocked'] = true;
            adminLockedList.addAll([
              'allowViewRevenue',
              'allowViewExpenses',
              'allowViewDebts',
            ]);
          }

          // Khóa Cài đặt cho nhân viên và quản lý - bởi Admin
          final isStaffOrManager =
              role == 'employee' || role == 'technician' || role == 'manager';
          if (staffSettingsLocked && isStaffOrManager) {
            perms['allowViewSettings'] = false;
            adminLockedList.add('allowViewSettings');
          }

          // Khóa các chức năng cho nhân viên (employee, technician) - bởi Admin
          final isStaff = role == 'employee' || role == 'technician';
          if (isStaff) {
            if (staffSalesLocked) {
              perms['allowViewSales'] = false;
              adminLockedList.add('allowViewSales');
            }
            if (staffInventoryLocked) {
              perms['allowViewInventory'] = false;
              perms['allowViewParts'] = false;
              adminLockedList.addAll(['allowViewInventory', 'allowViewParts']);
            }
            if (staffDebtLocked) {
              perms['allowViewDebts'] = false;
              adminLockedList.add('allowViewDebts');
            }
          }
        } catch (_) {
          // Nếu lỗi đọc shop thì bỏ qua, chỉ dùng quyền theo tài khoản
        }
      }
      perms['lockedByAdmin'] = adminLockedList;

      debugPrint('UserService: final perms = $perms');
      return perms;
    } catch (_) {
      return _defaultPermissionsForRole('user');
    }
  }

  /// Kiểm tra xem một quyền bị khóa bởi ai: 'admin', 'owner', hoặc null nếu không bị khóa
  static String? getLockedBy(
    Map<String, dynamic> permissions,
    String permissionKey,
  ) {
    final lockedByAdmin = permissions['lockedByAdmin'] as List<dynamic>? ?? [];
    final lockedByOwner = permissions['lockedByOwner'] as List<dynamic>? ?? [];

    if (lockedByAdmin.contains(permissionKey)) {
      return 'admin';
    }
    if (lockedByOwner.contains(permissionKey)) {
      return 'owner';
    }
    return null;
  }

  /// Dành riêng cho Super Admin: xem danh sách tất cả shop
  static Stream<QuerySnapshot> getAllShopsStreamForSuperAdmin() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!_isSuperAdmin(currentUser)) {
      // Người thường không được xem, trả về stream rỗng
      return _db.collection('shops').limit(0).snapshots();
    }
    return _db
        .collection('shops')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Temporary function to update existing shops with shopId field
  static Future<void> updateExistingShopsWithShopId() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final shopId = await getCurrentShopId();
    if (shopId == null) return;

    // First check if shop exists
    final shopDoc = await _db.collection('shops').doc(shopId).get();
    if (!shopDoc.exists) {
      await _db.collection('shops').doc(shopId).set({
        'shopId': shopId,
        'ownerUid': currentUser.uid,
        'ownerEmail': currentUser.email ?? '',
        'name': 'Cửa hàng mới',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      final data = shopDoc.data() ?? {};
      if (!data.containsKey('shopId') || data['shopId'] != shopId) {
        // Update shop document to include shopId field
        await _db.collection('shops').doc(shopId).set({
          'shopId': shopId,
        }, SetOptions(merge: true));
      }
    }
  }

  /// Tìm shop active mà user là owner để phục hồi shopId khi user doc thiếu/sai.
  static Future<String?> _findOwnedActiveShopId(String uid) async {
    try {
      final snap = await _db
          .collection('shops')
          .where('ownerUid', isEqualTo: uid)
          .limit(10)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['deleted'] == true) {
          continue;
        }
        return doc.id;
      }
    } catch (e) {
      debugPrint('_findOwnedActiveShopId error for uid=$uid: $e');
    }
    return null;
  }

  /// Cập nhật phân quyền ẩn/hiện nội dung cho một nhân viên cụ thể
  static Future<void> updateUserPermissions({
    required String uid,
    required bool allowViewSales,
    required bool allowViewRepairs,
    required bool allowViewInventory,
    required bool allowViewParts,
    required bool allowViewSuppliers,
    required bool allowViewCustomers,
    required bool allowViewWarranty,
    required bool allowViewChat,
    required bool allowViewAttendance,
    required bool allowViewPrinter,
    required bool allowViewRevenue,
    required bool allowViewExpenses,
    required bool allowViewDebts,
    required bool allowViewCostPrice,
  }) async {
    // Refresh token để đảm bảo custom claims (role, shopId) được cập nhật
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (e) {
      debugPrint('Could not refresh token before updating permissions: $e');
    }

    try {
      await _db.collection('users').doc(uid).set({
        'allowViewSales': allowViewSales,
        'allowViewRepairs': allowViewRepairs,
        'allowViewInventory': allowViewInventory,
        'allowViewParts': allowViewParts,
        'allowViewSuppliers': allowViewSuppliers,
        'allowViewCustomers': allowViewCustomers,
        'allowViewWarranty': allowViewWarranty,
        'allowViewChat': allowViewChat,
        'allowViewAttendance': allowViewAttendance,
        'allowViewPrinter': allowViewPrinter,
        'allowViewRevenue': allowViewRevenue,
        'allowViewExpenses': allowViewExpenses,
        'allowViewDebts': allowViewDebts,
        'allowViewCostPrice': allowViewCostPrice,
        'permissionsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ Updated permissions for user $uid');
    } catch (e) {
      debugPrint('❌ Error updating permissions for user $uid: $e');
      rethrow;
    }
  }

  /// Cập nhật các flag điều khiển shop (dành cho super admin)
  static Future<void> updateShopControlFlags({
    required String shopId,
    bool? appLocked,
    bool? adminFinanceLocked,
    String? flagName,
    bool? flagValue,
  }) async {
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (appLocked != null) {
      updateData['appLocked'] = appLocked;
    }
    if (adminFinanceLocked != null) {
      updateData['adminFinanceLocked'] = adminFinanceLocked;
    }
    // Hỗ trợ cập nhật flag tùy ý theo tên
    if (flagName != null && flagValue != null) {
      updateData[flagName] = flagValue;
    }
    await _db
        .collection('shops')
        .doc(shopId)
        .set(updateData, SetOptions(merge: true));
  }

  // --- INVITE SYSTEM ---
  static Future<String> createInviteCode(String shopId) async {
    final code = _generateInviteCode();
    await _db.collection('invites').doc(code).set({
      'shopId': shopId,
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now()
          .add(const Duration(days: 7))
          .toIso8601String(), // 7 ngày
      'used': false,
    });
    return code;
  }

  static Future<Map<String, dynamic>?> getInvite(String code) async {
    final doc = await _db.collection('invites').doc(code).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    if (data['used'] == true) return null;
    final expiresAt = DateTime.tryParse(data['expiresAt']);
    if (expiresAt == null || expiresAt.isBefore(DateTime.now())) return null;
    return data;
  }

  static Future<bool> useInviteCode(String code, String uid) async {
    final invite = await getInvite(code);
    if (invite == null) return false;
    final shopId = invite['shopId'];
    // Update user shopId
    await _db.collection('users').doc(uid).set({
      'shopId': shopId,
    }, SetOptions(merge: true));
    // Mark invite as used
    await _db.collection('invites').doc(code).update({'used': true});
    // Update cache
    _cachedShopId = shopId;
    return true;
  }

  /// Dành riêng cho Super Admin: xóa một user (chỉ xóa từ Firestore, không xóa auth)
  static Future<int> getUnreadChatCount(String uid) async {
    try {
      final shopId = await getCurrentShopId();
      if (shopId == null) return 0;

      final userDoc = await _db.collection('users').doc(uid).get();
      final lastReadRaw = userDoc.data()?['lastReadChat'];

      // Chuyển đổi lastReadChat thành DateTime để so sánh
      DateTime? lastReadTime;
      if (lastReadRaw is Timestamp) {
        lastReadTime = lastReadRaw.toDate();
      } else if (lastReadRaw is int) {
        lastReadTime = DateTime.fromMillisecondsSinceEpoch(lastReadRaw);
      }

      // Query collection 'chats' - đúng collection name của ChatService
      final query = await _db
          .collection('chats')
          .where('shopId', isEqualTo: shopId)
          .get();

      // Đếm số tin nhắn có createdAt > lastRead (không tính tin của chính mình)
      int count = 0;
      for (var doc in query.docs) {
        final data = doc.data();
        final createdAtRaw = data['createdAt'];
        final senderId = data['senderId'];

        // Bỏ qua tin nhắn của chính mình
        if (senderId == uid) continue;

        // Chuyển đổi createdAt thành DateTime
        DateTime? createdAt;
        if (createdAtRaw is Timestamp) {
          createdAt = createdAtRaw.toDate();
        } else if (createdAtRaw is int) {
          createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw);
        }

        // So sánh thời gian
        if (createdAt != null) {
          if (lastReadTime == null || createdAt.isAfter(lastReadTime)) {
            count++;
          }
        }
      }
      return count;
    } catch (e) {
      debugPrint('Error getting unread chat count: $e');
      return 0; // Trả về 0 nếu có lỗi (bao gồm lỗi index)
    }
  }

  /// Lấy tin nhắn mới nhất trong shop (để hiển thị preview)
  static Future<Map<String, dynamic>?> getLatestChatMessage() async {
    try {
      final shopId = await getCurrentShopId();
      if (shopId == null) return null;

      // Query collection 'chats' - đúng collection name của ChatService
      final query = await _db
          .collection('chats')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final doc = query.docs.first;
      final data = doc.data();
      return {
        'message': data['message'] ?? '',
        'senderName': data['senderName'] ?? '',
        'createdAt': data['createdAt'],
      };
    } catch (e) {
      debugPrint('Error getting latest chat message: $e');
      return null;
    }
  }

  static Future<void> markChatAsRead(String uid) async {
    await _db.collection('users').doc(uid).update({
      'lastReadChat': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteUser(String uid) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!_isSuperAdmin(currentUser)) return;

    await _db.collection('users').doc(uid).delete();
  }

  static String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    for (int i = 0; i < 8; i++) {
      code += chars[random % chars.length];
      // Simple random, not crypto secure but ok for demo
    }
    return code;
  }

  // === PERMISSION HELPER METHODS ===

  /// Kiểm tra xem user hiện tại có quyền xem giá vốn không
  /// Sử dụng cache 5 phút để tránh gọi Firestore liên tục
  static Future<bool> canViewCostPrice() async {
    // Super admin luôn được xem
    if (isCurrentUserSuperAdmin()) return true;

    // Check cache (5 phút)
    if (_cachedCanViewCostPrice != null && _cachedCanViewCostPriceTime != null) {
      if (DateTime.now().difference(_cachedCanViewCostPriceTime!).inMinutes < 5) {
        return _cachedCanViewCostPrice!;
      }
    }

    // Lấy permissions từ Firestore
    final perms = await getCurrentUserPermissions();
    final canView = perms['allowViewCostPrice'] as bool? ?? false;
    
    // Cache kết quả
    _cachedCanViewCostPrice = canView;
    _cachedCanViewCostPriceTime = DateTime.now();
    
    return canView;
  }

  /// Xóa cache permission khi user logout hoặc đổi shop
  static void clearCostPricePermissionCache() {
    _cachedCanViewCostPrice = null;
    _cachedCanViewCostPriceTime = null;
  }
}
