import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'sync_service.dart';
import 'current_shop_service.dart';
import 'user_service.dart';
import 'event_bus.dart';
import '../data/db_helper.dart';

/// Service xử lý việc xóa shop an toàn
/// 
/// Đảm bảo:
/// 1. Cancel tất cả streams/subscriptions trước khi xóa
/// 2. Điều hướng khỏi màn hình shop trước khi xóa data
/// 3. Xóa cache local và Firestore data
/// 4. Emit events để UI cập nhật
class ShopDeletionService {
  static final _firestore = FirebaseFirestore.instance;
  
  /// Flag để đánh dấu shop đang bị xóa
  /// UI có thể check flag này để tránh query tiếp
  static final Set<String> _deletingShopIds = {};
  
  /// Stream controller để thông báo shop đang bị xóa
  static final _deletionController = StreamController<String>.broadcast();
  
  /// Stream để UI listen khi có shop bị xóa
  static Stream<String> get onShopDeleting => _deletionController.stream;
  
  /// Kiểm tra shop có đang bị xóa không
  static bool isShopBeingDeleted(String? shopId) {
    if (shopId == null) return false;
    return _deletingShopIds.contains(shopId);
  }
  
  /// Các subcollections cần xóa khi xóa shop
  static const _shopSubcollections = [
    'repairs',
    'products', 
    'sales',
    'expenses',
    'debts',
    'debt_payments',
    'customers',
    'suppliers',
    'attendance',
    'quick_input_codes',
    'repair_partners',
    'repair_parts',
    'supplier_payments',
    'repair_partner_payments',
    'supplier_import_history',
    'audit_logs',
    'notifications',
    'settings',
    'custom_salary_adjustments',
    'product_categories',
    'work_schedules',
  ];

  /// Xóa shop an toàn với các bước:
  /// 1. Đánh dấu shop đang xóa (local flag)
  /// 2. Cancel tất cả subscriptions
  /// 3. Navigate away
  /// 4. Xóa top-level Firestore data TRƯỚC KHI thay đổi shop
  ///    (giữ nguyên shop doc để Firestore rules vẫn cho phép delete)
  /// 5. Xóa subcollections có rules
  /// 6. Xóa shop document
  /// 7. Switch sang shop khác
  /// 8. Xóa local cache
  /// 9. Emit events
  /// 
  /// Returns: ShopDeletionResult
  static Future<ShopDeletionResult> deleteShopSafe({
    required String shopId,
    required String shopName,
    String? fallbackShopId,
    VoidCallback? onNavigateAway,
  }) async {
    debugPrint('🗑️ ShopDeletionService: Starting safe deletion of $shopId ($shopName)');
    
    try {
      // STEP 1: Đánh dấu shop đang bị xóa (local)
      _deletingShopIds.add(shopId);
      _deletionController.add(shopId);
      EventBus().emit('shop_deleting:$shopId');
      
      // Đợi UI có time react
      await Future.delayed(const Duration(milliseconds: 100));
      
      // STEP 2: Cancel tất cả Firestore subscriptions
      debugPrint('🔴 ShopDeletionService: Cancelling all subscriptions...');
      await SyncService.cancelAllSubscriptions();
      
      // STEP 3: Navigate away
      if (onNavigateAway != null) {
        debugPrint('🚀 ShopDeletionService: Calling onNavigateAway callback...');
        onNavigateAway();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // STEP 4: Xóa top-level Firestore data TRƯỚC KHI soft-delete shop
      // Shop doc vẫn tồn tại + chưa deleted => Firestore rules cho phép
      debugPrint('☁️ ShopDeletionService: Deleting top-level Firestore data for $shopId...');
      await _deleteTopLevelFirestoreData(shopId);
      
      // STEP 5: Xóa shop document (cuối cùng vì rules phụ thuộc nó)
      debugPrint('📄 ShopDeletionService: Deleting shop document $shopId...');
      try {
        await _firestore.collection('shops').doc(shopId).delete();
        debugPrint('✅ Shop document deleted');
      } catch (e) {
        // Nếu xóa doc thất bại, soft-delete thay thế
        debugPrint('⚠️ Shop doc hard-delete failed, soft-deleting: $e');
        try {
          await _firestore.collection('shops').doc(shopId).update({
            'deleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'deletedBy': FirebaseAuth.instance.currentUser?.uid,
          });
        } catch (_) {}
      }
      
      // STEP 6: Switch sang shop khác SAU KHI đã xóa data
      if (fallbackShopId != null) {
        debugPrint('🔄 ShopDeletionService: Switching to fallback shop $fallbackShopId...');
        await CurrentShopService().switchShop(fallbackShopId);
      } else {
        debugPrint('⚠️ ShopDeletionService: No fallback shop, clearing selection...');
        await CurrentShopService().clearActiveShop();
      }
      
      // STEP 7: Xóa local cache cho shop này
      debugPrint('🧹 ShopDeletionService: Clearing local cache for $shopId...');
      await _clearLocalCacheForShop(shopId);
      
      // STEP 8: Cleanup và emit events
      _deletingShopIds.remove(shopId);
      EventBus().emit('shop_deleted:$shopId');
      EventBus().emit(EventBus.shopChanged);
      
      // Reinitialize sync nếu có shop fallback
      if (fallbackShopId != null) {
        await SyncService.forceReinitializeSync();
      }
      
      debugPrint('✅ ShopDeletionService: Successfully deleted shop $shopId ($shopName)');
      return ShopDeletionResult.success();
      
    } catch (e, stack) {
      debugPrint('❌ ShopDeletionService: Error deleting shop: $e');
      debugPrint(stack.toString());
      
      // Cleanup flag
      _deletingShopIds.remove(shopId);
      
      return ShopDeletionResult.failure(e.toString());
    }
  }
  
  /// Xóa local cache cho shop cụ thể
  static Future<void> _clearLocalCacheForShop(String shopId) async {
    try {
      final db = DBHelper();
      
      // Xóa các bản ghi trong SQLite có shopId này
      // Gọi các method cleanup nếu có
      await db.deleteDataByShopId(shopId);
      
      debugPrint('✅ Cleared local cache for shop $shopId');
    } catch (e) {
      debugPrint('⚠️ Error clearing local cache: $e');
      // Không throw - continue with Firestore deletion
    }
  }
  
  /// Xóa data Firestore - chỉ top-level collections với shopId filter
  /// Subcollection cleanup nên dùng Cloud Functions vì client không có rules
  static Future<void> _deleteTopLevelFirestoreData(String shopId) async {
    // Chỉ xóa top-level collections có shopId field và có Firestore delete rules
    final topLevelCollections = [
      'repairs',
      'products',
      'sales',
      'expenses',
      'debts',
      'debt_payments',
      'customers',
      'suppliers',
      'attendance',
      'repair_partners',
      'repair_parts',
      'supplier_payments',
      'repair_partner_payments',
      'cash_closings',
      'audit_logs',
      'notifications',
      'purchase_orders',
      'quick_input_codes',
    ];
    
    for (final collection in topLevelCollections) {
      await _deleteCollectionByShopId(collection, shopId);
    }
    
    // Xóa subcollections CHỈ những có rules cho phép delete
    // settings, product_categories, custom_salary_adjustments
    for (final sub in ['settings', 'product_categories', 'custom_salary_adjustments']) {
      await _deleteSubcollection('shops', shopId, sub);
    }
  }
  
  /// Xóa documents trong collection có shopId
  static Future<void> _deleteCollectionByShopId(String collection, String shopId) async {
    try {
      // Batch delete - limit 500 per batch (Firestore limit)
      while (true) {
        final snapshot = await _firestore
            .collection(collection)
            .where('shopId', isEqualTo: shopId)
            .limit(500)
            .get();
        
        if (snapshot.docs.isEmpty) break;
        
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        
        debugPrint('  Deleted ${snapshot.docs.length} docs from $collection');
        
        // Đợi 1 chút để tránh rate limiting
        if (snapshot.docs.length == 500) {
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          break;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error deleting $collection for shop $shopId: $e');
    }
  }
  
  /// Xóa subcollection
  static Future<void> _deleteSubcollection(
    String parentCollection,
    String parentDocId,
    String subcollection,
  ) async {
    try {
      while (true) {
        final snapshot = await _firestore
            .collection(parentCollection)
            .doc(parentDocId)
            .collection(subcollection)
            .limit(500)
            .get();
        
        if (snapshot.docs.isEmpty) break;
        
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        
        debugPrint('  Deleted ${snapshot.docs.length} docs from $parentCollection/$parentDocId/$subcollection');
        
        if (snapshot.docs.length < 500) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('⚠️ Error deleting subcollection $subcollection: $e');
    }
  }

  /// Kiểm tra user có quyền xóa shop không
  static Future<bool> canDeleteShop(String shopId) async {
    // Chỉ owner hoặc super admin mới được xóa
    if (UserService.isCurrentUserSuperAdmin()) return true;
    
    try {
      final shopDoc = await _firestore.collection('shops').doc(shopId).get();
      if (!shopDoc.exists) return false;
      
      final ownerUid = shopDoc.data()?['ownerUid'];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      
      return currentUid != null && ownerUid == currentUid;
    } catch (e) {
      return false;
    }
  }
  
  /// Lấy danh sách shops có thể xóa (không phải shop đang dùng)
  static Future<List<Map<String, dynamic>>> getDeletableShops() async {
    try {
      final currentShopId = await CurrentShopService().getActiveShopId();
      final shops = await CurrentShopService().getOwnedShops();
      
      return shops.where((shop) => shop['id'] != currentShopId).toList();
    } catch (e) {
      return [];
    }
  }
}

/// Kết quả của việc xóa shop
class ShopDeletionResult {
  final bool success;
  final String? errorMessage;
  
  const ShopDeletionResult._({
    required this.success,
    this.errorMessage,
  });
  
  factory ShopDeletionResult.success() => const ShopDeletionResult._(success: true);
  
  factory ShopDeletionResult.failure(String message) => ShopDeletionResult._(
    success: false,
    errorMessage: message,
  );
}
