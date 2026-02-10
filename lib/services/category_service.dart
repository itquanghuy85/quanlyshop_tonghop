import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/product_category_model.dart';
import '../models/shop_settings_model.dart';
import '../data/db_helper.dart';
import 'user_service.dart';

/// Service quản lý danh mục sản phẩm và cài đặt shop
/// Hỗ trợ multi-industry expansion
class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DBHelper _dbHelper = DBHelper();

  // === CACHED DATA ===
  ShopSettings? _cachedSettings;
  List<ProductCategory>? _cachedCategories;

  // === SHOP SETTINGS ===

  /// Lấy ShopSettings từ cache hoặc tạo mới
  Future<ShopSettings?> getShopSettings() async {
    // Skip cache to ensure fresh data
    // if (_cachedSettings != null) return _cachedSettings;

    final shopId = await UserService.getCurrentShopId();
    debugPrint('📦 CategoryService.getShopSettings: shopId=$shopId');
    if (shopId == null) {
      debugPrint('📦 CategoryService: No shopId, returning null');
      return null;
    }

    // Try local DB first
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'shop_settings',
        where: 'shopId = ?',
        whereArgs: [shopId],
        limit: 1,
      );
      if (results.isNotEmpty) {
        _cachedSettings = ShopSettings.fromMap(results.first);
        debugPrint('📦 CategoryService: Found in local DB - businessType=${_cachedSettings?.businessType}, enableRepair=${_cachedSettings?.enableRepair}');
        return _cachedSettings;
      }
      debugPrint('📦 CategoryService: Not found in local DB');
    } catch (e) {
      debugPrint('Error getting shop settings locally: $e');
    }

    // Try Firestore
    try {
      final doc = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('settings')
          .doc('shop_settings')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        data['firestoreId'] = doc.id;
        data['shopId'] = shopId;
        _cachedSettings = ShopSettings.fromMap(data);
        debugPrint('📦 CategoryService: Found in Firestore - businessType=${_cachedSettings?.businessType}, enableRepair=${_cachedSettings?.enableRepair}');
        // Cache locally
        await _saveSettingsLocally(_cachedSettings!);
        return _cachedSettings;
      }
      debugPrint('📦 CategoryService: Not found in Firestore');
    } catch (e) {
      debugPrint('Error getting shop settings from Firestore: $e');
    }

    // KHÔNG auto-create electronics - trả về null để home_view hiện wizard
    // Chỉ shop owner mới có quyền chọn loại hình kinh doanh
    debugPrint('📦 CategoryService: Settings not found - returning null (new shop needs wizard)');
    return null;
  }

  /// Lưu ShopSettings
  Future<bool> saveShopSettings(ShopSettings settings) async {
    // Nếu settings đã có shopId thì dùng đó, nếu không thì lấy từ UserService
    String? shopId = settings.shopId;
    if (shopId == null || shopId.isEmpty) {
      shopId = await UserService.getCurrentShopId();
    }
    if (shopId == null) return false;

    final settingsWithShop = settings.copyWith(shopId: shopId);
    
    debugPrint('💾 CategoryService.saveShopSettings: businessType=${settingsWithShop.businessType}, enableRepair=${settingsWithShop.enableRepair}, shopId=$shopId');

    // Clear existing local cache for this shop first
    try {
      final db = await _dbHelper.database;
      await db.delete('shop_settings', where: 'shopId = ?', whereArgs: [shopId]);
      debugPrint('💾 CategoryService: Cleared old local settings for shopId=$shopId');
    } catch (e) {
      debugPrint('Error clearing old shop settings: $e');
    }

    // Save to Firestore
    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('settings')
          .doc('shop_settings')
          .set(settingsWithShop.toFirestoreMap(), SetOptions(merge: true));
      debugPrint('💾 CategoryService: Saved to Firestore successfully');
    } catch (e) {
      debugPrint('Error saving shop settings to Firestore: $e');
    }

    // Save locally
    await _saveSettingsLocally(settingsWithShop);

    // Update cache
    _cachedSettings = settingsWithShop;
    debugPrint('💾 CategoryService: Cache updated with businessType=${_cachedSettings?.businessType}');
    return true;
  }
  
  /// Clear cache - gọi khi đổi shop hoặc logout
  void clearCache() {
    _cachedSettings = null;
    _cachedCategories = null;
    debugPrint('🗑️ CategoryService: Cache cleared');
  }

  Future<void> _saveSettingsLocally(ShopSettings settings) async {
    try {
      final db = await _dbHelper.database;
      final map = settings.toMap();

      // Check if exists
      final existing = await db.query(
        'shop_settings',
        where: 'shopId = ?',
        whereArgs: [settings.shopId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('shop_settings', map);
      } else {
        await db.update(
          'shop_settings',
          map,
          where: 'shopId = ?',
          whereArgs: [settings.shopId],
        );
      }
    } catch (e) {
      debugPrint('Error saving shop settings locally: $e');
    }
  }

  // === PRODUCT CATEGORIES ===

  /// Lấy danh sách categories cho shop hiện tại
  Future<List<ProductCategory>> getCategories({bool forceRefresh = false}) async {
    if (_cachedCategories != null && !forceRefresh) {
      return _cachedCategories!;
    }

    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    // Try local DB first
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_categories',
        where: 'shopId = ? AND isActive = 1',
        whereArgs: [shopId],
        orderBy: 'sortOrder ASC, name ASC',
      );
      if (results.isNotEmpty) {
        _cachedCategories =
            results.map((e) => ProductCategory.fromMap(e)).toList();
        return _cachedCategories!;
      }
    } catch (e) {
      debugPrint('Error getting categories locally: $e');
    }

    // Try Firestore
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_categories')
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .get();

      if (snapshot.docs.isNotEmpty) {
        _cachedCategories = snapshot.docs.map((doc) {
          final data = doc.data();
          data['firestoreId'] = doc.id;
          data['shopId'] = shopId;
          return ProductCategory.fromMap(data);
        }).toList();

        // Cache locally
        for (final cat in _cachedCategories!) {
          await _saveCategoryLocally(cat);
        }
        return _cachedCategories!;
      }
    } catch (e) {
      debugPrint('Error getting categories from Firestore: $e');
    }

    // Return default categories if none exist
    return _getDefaultCategories(shopId);
  }

  /// Lấy categories mặc định dựa theo businessType
  Future<List<ProductCategory>> _getDefaultCategories(String shopId) async {
    final settings = await getShopSettings();
    final businessType = settings?.businessType ?? 'electronics';

    switch (businessType) {
      case 'electronics':
        return [
          ProductCategory.defaultPhoneCategory(shopId),
          ProductCategory.defaultAccessoryCategory(shopId),
          ProductCategory.defaultPartCategory(shopId),
        ];
      case 'food':
        return [
          ProductCategory.foodCategory(shopId, 'Rau củ'),
          ProductCategory.foodCategory(shopId, 'Trái cây'),
          ProductCategory.foodCategory(shopId, 'Thịt cá'),
          ProductCategory.foodCategory(shopId, 'Đồ khô'),
        ];
      case 'fashion':
        return [
          ProductCategory.fashionCategory(shopId, 'Áo'),
          ProductCategory.fashionCategory(shopId, 'Quần'),
          ProductCategory.fashionCategory(shopId, 'Giày dép'),
          ProductCategory.fashionCategory(shopId, 'Phụ kiện'),
        ];
      default:
        return [
          ProductCategory(shopId: shopId, name: 'Sản phẩm chung', icon: '📦'),
        ];
    }
  }

  /// Thêm danh mục mới
  Future<String?> addCategory(ProductCategory category) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return null;

    final categoryWithShop = category.copyWith(shopId: shopId);

    try {
      // Save to Firestore
      final docRef = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_categories')
          .add(categoryWithShop.toFirestoreMap());

      final savedCategory =
          categoryWithShop.copyWith(firestoreId: docRef.id, isSynced: true);

      // Save locally
      await _saveCategoryLocally(savedCategory);

      // Clear cache
      _cachedCategories = null;

      return docRef.id;
    } catch (e) {
      debugPrint('Error adding category: $e');
      return null;
    }
  }

  /// Cập nhật danh mục
  Future<bool> updateCategory(ProductCategory category) async {
    if (category.firestoreId.isEmpty) return false;

    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_categories')
          .doc(category.firestoreId)
          .update(category.toFirestoreMap());

      await _saveCategoryLocally(category.copyWith(isSynced: true));
      _cachedCategories = null;
      return true;
    } catch (e) {
      debugPrint('Error updating category: $e');
      return false;
    }
  }

  /// Xóa danh mục (soft delete)
  Future<bool> deleteCategory(String firestoreId) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_categories')
          .doc(firestoreId)
          .update({
        'isActive': false,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Update locally
      final db = await _dbHelper.database;
      await db.update(
        'product_categories',
        {'isActive': 0},
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );

      _cachedCategories = null;
      return true;
    } catch (e) {
      debugPrint('Error deleting category: $e');
      return false;
    }
  }

  Future<void> _saveCategoryLocally(ProductCategory category) async {
    try {
      final db = await _dbHelper.database;
      final map = category.toMap();

      // Check if exists
      final existing = await db.query(
        'product_categories',
        where: 'firestoreId = ?',
        whereArgs: [category.firestoreId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('product_categories', map);
      } else {
        await db.update(
          'product_categories',
          map,
          where: 'firestoreId = ?',
          whereArgs: [category.firestoreId],
        );
      }
    } catch (e) {
      debugPrint('Error saving category locally: $e');
    }
  }

  /// Tạo default categories cho shop mới
  Future<void> initializeDefaultCategories(String shopId, String businessType) async {
    final defaultCategories = await _getDefaultCategoriesForType(shopId, businessType);
    
    for (final category in defaultCategories) {
      await addCategory(category);
    }
  }

  Future<List<ProductCategory>> _getDefaultCategoriesForType(String shopId, String businessType) async {
    switch (businessType) {
      case 'electronics':
        return [
          ProductCategory.defaultPhoneCategory(shopId),
          ProductCategory.defaultAccessoryCategory(shopId),
          ProductCategory.defaultPartCategory(shopId),
        ];
      case 'food':
        return [
          ProductCategory.foodCategory(shopId, 'Rau củ'),
          ProductCategory.foodCategory(shopId, 'Trái cây'),
          ProductCategory.foodCategory(shopId, 'Thịt cá'),
          ProductCategory.foodCategory(shopId, 'Đồ khô'),
        ];
      case 'fashion':
        return [
          ProductCategory.fashionCategory(shopId, 'Áo'),
          ProductCategory.fashionCategory(shopId, 'Quần'),
          ProductCategory.fashionCategory(shopId, 'Giày dép'),
          ProductCategory.fashionCategory(shopId, 'Phụ kiện'),
        ];
      default:
        return [
          ProductCategory(shopId: shopId, name: 'Sản phẩm chung', icon: '📦'),
        ];
    }
  }

  // === HELPER METHODS ===

  /// Lấy category theo ID
  Future<ProductCategory?> getCategoryById(String firestoreId) async {
    final categories = await getCategories();
    return categories.where((c) => c.firestoreId == firestoreId).firstOrNull;
  }

  /// Lấy root categories (không có parent)
  Future<List<ProductCategory>> getRootCategories() async {
    final categories = await getCategories();
    return categories.where((c) => c.isRoot).toList();
  }

  /// Lấy subcategories của một category
  Future<List<ProductCategory>> getSubcategories(String parentId) async {
    final categories = await getCategories();
    return categories.where((c) => c.parentId == parentId).toList();
  }

  /// Check if current shop supports repair
  Future<bool> get supportsRepair async {
    final settings = await getShopSettings();
    return settings?.enableRepair ?? true;
  }

  /// Check if current shop supports variants
  Future<bool> get supportsVariants async {
    final settings = await getShopSettings();
    return settings?.enableVariants ?? false;
  }

  /// Check if current shop supports expiry tracking
  Future<bool> get supportsExpiry async {
    final settings = await getShopSettings();
    return settings?.enableExpiry ?? false;
  }

  /// Check if current shop supports serial tracking
  Future<bool> get supportsSerial async {
    final settings = await getShopSettings();
    return settings?.enableSerial ?? true;
  }
}
