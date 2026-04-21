mimport 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';
import 'sync_service.dart';
import 'encryption_service.dart';
import 'event_bus.dart';
import 'category_service.dart';
import 'business_type_helper.dart';
import 'label_settings_service.dart';
import '../data/db_helper.dart';

/// CurrentShopService: Quản lý activeShopId cho owner có nhiều shop
///
/// PRODUCTION SAFETY:
/// - Backward compatible: Nếu user chỉ có 1 shop → hoạt động như cũ
/// - Fallback logic: activeShopId null → dùng shopId từ user profile
/// - Persistence: Lưu vào SharedPreferences để giữ sau restart
/// - Cache clear: Xóa SQLite khi switch shop
///
/// USAGE:
/// - Call init() sau khi login thành công
/// - Call getActiveShopId() thay vì UserService.getCurrentShopId() trong queries
/// - Call switchShop() khi owner chọn shop khác
class CurrentShopService {
  static final CurrentShopService _instance = CurrentShopService._internal();
  factory CurrentShopService() => _instance;
  CurrentShopService._internal();

  static const String _prefKey = 'active_shop_id';
  static const String _prefKeyUid = 'active_shop_uid';

  // Cache
  String? _activeShopId;
  String? _activeShopUid;
  List<Map<String, dynamic>>? _cachedShops;
  bool _initialized = false;

  final _db = FirebaseFirestore.instance;

  String _normalizeLegacyShopName(String? rawName) {
    final name = (rawName ?? '').trim();
    if (name.isEmpty) return '';
    final lower = name.toLowerCase();
    if (lower == 'shop new' || lower == 'shop_new' || lower == 'shopnew') {
      return 'QUAN LY SHOP';
    }
    return name;
  }

  Future<Map<String, dynamic>> _enrichShopDisplayName(
    Map<String, dynamic> shop,
  ) async {
    final data = Map<String, dynamic>.from(shop);
    final shopId = (data['id'] ?? '').toString().trim();
    if (shopId.isEmpty) return data;

    final currentName = _normalizeLegacyShopName(data['name']?.toString());
    if (currentName.isNotEmpty) {
      data['name'] = currentName;
      return data;
    }

    try {
      final profileDoc = await _db
          .collection('shops')
          .doc(shopId)
          .collection('settings')
          .doc('shop_profile')
          .get();
      final profileName = _normalizeLegacyShopName(
        profileDoc.data()?['name']?.toString(),
      );
      if (profileName.isNotEmpty) {
        data['name'] = profileName;
        return data;
      }
    } catch (e) {
      debugPrint('CurrentShopService: profile name fallback error for $shopId: $e');
    }

    data['name'] = 'Cửa hàng chưa đặt tên';
    return data;
  }

  /// Initialize service - call after successful login
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      // Load saved activeShopId (chỉ nếu cùng user)
      final savedUid = prefs.getString(_prefKeyUid);
      if (savedUid == currentUid) {
        _activeShopId = prefs.getString(_prefKey);
        _activeShopUid = savedUid;
        debugPrint(
          'CurrentShopService: Loaded activeShopId=$_activeShopId for uid=$currentUid',
        );

        // Validate saved active shop to avoid stale cache causing empty data.
        if (_activeShopId != null && _activeShopId!.isNotEmpty) {
          bool isValid = false;
          try {
            final shopDoc = await _db.collection('shops').doc(_activeShopId).get();
            if (shopDoc.exists && shopDoc.data()?['deleted'] != true) {
              final userShopId = await UserService.getCurrentShopId();
              final ownerUid = shopDoc.data()?['ownerUid']?.toString();
              isValid = ownerUid == currentUid || userShopId == _activeShopId;
            }
          } catch (e) {
            debugPrint('CurrentShopService: validate activeShopId error: $e');
          }

          if (!isValid) {
            debugPrint('CurrentShopService: stale activeShopId=$_activeShopId, clearing');
            _activeShopId = null;
            UserService.updateCachedShopId(null);
            await prefs.remove(_prefKey);
          }
        }

        // Update UserService cache for backward compatibility
        if (_activeShopId != null && _activeShopId!.isNotEmpty) {
          UserService.updateCachedShopId(_activeShopId);
          debugPrint(
            'CurrentShopService: Updated UserService cache with $_activeShopId',
          );
        }
      } else {
        // User khác → clear
        await prefs.remove(_prefKey);
        await prefs.remove(_prefKeyUid);
        _activeShopId = null;
        _activeShopUid = null;
        debugPrint('CurrentShopService: Different user, cleared saved shop');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('CurrentShopService init error: $e');
      _initialized = true; // Still mark as initialized to avoid retry loops
    }
  }

  /// Clear service state on logout
  void clear() {
    _activeShopId = null;
    _activeShopUid = null;
    _cachedShops = null;
    _initialized = false;
    debugPrint('CurrentShopService: Cleared');
  }

  /// Get active shop ID with fallback logic
  ///
  /// Priority:
  /// 1. Super admin selected shop
  /// 2. Owner's active shop (if has multiple)
  /// 3. User's default shopId from profile
  Future<String?> getActiveShopId() async {
    // Super admin: use their selected shop
    if (UserService.isCurrentUserSuperAdmin()) {
      return UserService.getAdminSelectedShop();
    }

    // If owner has set an active shop, use it
    if (_activeShopId != null && _activeShopId!.isNotEmpty) {
      return _activeShopId;
    }

    // Fallback to default shopId from user profile
    return await UserService.getCurrentShopId();
  }

  /// Synchronous version for quick access (may return null if not cached)
  String? getActiveShopIdSync() {
    // Super admin
    if (UserService.isCurrentUserSuperAdmin()) {
      return UserService.getAdminSelectedShop();
    }

    // Owner's active shop
    if (_activeShopId != null && _activeShopId!.isNotEmpty) {
      return _activeShopId;
    }

    // Fallback to cached shopId
    return UserService.getShopIdSync();
  }

  /// Check if current user is owner of multiple shops
  Future<bool> hasMultipleShops() async {
    final shops = await getOwnedShops();
    return shops.length > 1;
  }

  /// Get list of shops owned by current user
  /// Returns empty list if not owner or has only default shop
  Future<List<Map<String, dynamic>>> getOwnedShops() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    // Super admin: use getAllShops
    if (UserService.isCurrentUserSuperAdmin()) {
      return await UserService.getAllShops();
    }

    // Return cached if available
    if (_cachedShops != null && _cachedShops!.isNotEmpty) {
      return _cachedShops!;
    }

    try {
      // Query shops where current user is owner
      final snapshot = await _db
          .collection('shops')
          .where('ownerUid', isEqualTo: currentUser.uid)
          .get();

      final rawShops = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).where((shop) => shop['deleted'] != true).toList();

      _cachedShops = await Future.wait(
        rawShops.map(_enrichShopDisplayName),
      );

      debugPrint(
        'CurrentShopService: Found ${_cachedShops!.length} shops by ownerUid',
      );

      // Fallback: If no shops found by ownerUid, get current user's shop
      if (_cachedShops!.isEmpty) {
        final userShopId = await UserService.getCurrentShopId();
        if (userShopId != null && userShopId.isNotEmpty) {
          final shopDoc = await _db.collection('shops').doc(userShopId).get();
          if (shopDoc.exists) {
            final data = shopDoc.data() ?? {};
            data['id'] = shopDoc.id;
            final enriched = await _enrichShopDisplayName(data);
            _cachedShops = [enriched];
            debugPrint(
              'CurrentShopService: Fallback - got shop from user profile: $userShopId',
            );
          }
        }
      }

      return _cachedShops!;
    } catch (e) {
      debugPrint('CurrentShopService getOwnedShops error: $e');
      return [];
    }
  }

  /// Switch to a different shop (owner only)
  ///
  /// This will:
  /// 1. Validate ownership
  /// 2. Update activeShopId
  /// 3. Persist to SharedPreferences
  /// 4. Clear local SQLite cache
  /// 5. Update UserService cache
  Future<bool> switchShop(String newShopId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    // Validate: user must own this shop
    final shops = await getOwnedShops();
    final isOwner = shops.any((shop) => shop['id'] == newShopId);

    if (!isOwner && !UserService.isCurrentUserSuperAdmin()) {
      debugPrint('CurrentShopService: User does not own shop $newShopId');
      return false;
    }

    // Same shop - no action needed
    if (_activeShopId == newShopId) {
      debugPrint('CurrentShopService: Already on shop $newShopId');
      return true;
    }

    debugPrint(
      'CurrentShopService: Switching from $_activeShopId to $newShopId',
    );

    try {
      // 1. Update local cache
      _activeShopId = newShopId;
      _activeShopUid = currentUser.uid;

      // 2. Persist to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newShopId);
      await prefs.setString(_prefKeyUid, currentUser.uid);

      // 3. Update UserService cache (for backward compatibility)
      UserService.updateCachedShopId(newShopId);

      // 4. Cancel existing sync subscriptions
      await SyncService.cancelAllSubscriptions();
      debugPrint('CurrentShopService: Cancelled sync subscriptions');

      // 5. Clear local SQLite to prevent stale data
      await _clearLocalCache();
      
      // 5.1. Clear all caches (shop settings, business type, labels)
      CategoryService().clearCache();
      BusinessTypeHelper().clearCache();
      LabelSettingsService().clearCache();

      // 6. Re-initialize encryption for new shop
      EncryptionService.init(newShopId);
      debugPrint(
        'CurrentShopService: Re-initialized encryption for $newShopId',
      );

      // 7. Restart sync for new shop
      await _restartSync(newShopId);

      // 8. Emit event to notify all listeners
      EventBus().emit(EventBus.shopChanged);
      debugPrint('CurrentShopService: Emitted SHOP_CHANGED event');

      debugPrint('CurrentShopService: Successfully switched to $newShopId');
      return true;
    } catch (e) {
      debugPrint('CurrentShopService switchShop error: $e');
      return false;
    }
  }

  /// Clear local SQLite cache when switching shops
  Future<void> _clearLocalCache() async {
    try {
      final db = DBHelper();
      await db.clearAllData();
      debugPrint('CurrentShopService: Local cache cleared');
    } catch (e) {
      debugPrint('CurrentShopService _clearLocalCache error: $e');
    }
  }

  /// Restart sync service for new shop
  Future<void> _restartSync(String shopId) async {
    try {
      // Wait a bit for cache to settle
      await Future.delayed(const Duration(milliseconds: 500));

      // Initialize real-time sync for new shop
      await SyncService.initRealTimeSync(() {
        debugPrint('CurrentShopService: Sync data changed for $shopId');
      });

      debugPrint('CurrentShopService: Sync restarted for $shopId');
    } catch (e) {
      debugPrint('CurrentShopService _restartSync error: $e');
    }
  }

  /// Get current active shop info
  Future<Map<String, dynamic>?> getActiveShopInfo() async {
    final shopId = await getActiveShopId();
    if (shopId == null) return null;

    try {
      final doc = await _db.collection('shops').doc(shopId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        data['id'] = doc.id;
        return data;
      }
    } catch (e) {
      debugPrint('CurrentShopService getActiveShopInfo error: $e');
    }
    return null;
  }

  /// Refresh cached shops (call after creating new shop)
  void invalidateCache() {
    _cachedShops = null;
    debugPrint('CurrentShopService: Cache invalidated');
  }

  /// Clear active shop selection (dùng khi xóa shop cuối cùng hoặc logout)
  Future<void> clearActiveShop() async {
    try {
      // 1. Cancel sync subscriptions
      await SyncService.cancelAllSubscriptions();
      
      // 2. Clear in-memory cache
      _activeShopId = null;
      _activeShopUid = null;
      _cachedShops = null;
      
      // 3. Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      await prefs.remove(_prefKeyUid);
      
      // 4. Clear UserService cache
      UserService.updateCachedShopId(null);
      
      // 5. Clear local SQLite
      await _clearLocalCache();
      
      // 6. Clear other caches
      CategoryService().clearCache();
      BusinessTypeHelper().clearCache();
      LabelSettingsService().clearCache();
      
      debugPrint('CurrentShopService: Active shop cleared');
    } catch (e) {
      debugPrint('CurrentShopService clearActiveShop error: $e');
    }
  }
}
