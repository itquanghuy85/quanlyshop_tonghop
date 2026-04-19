import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:flutter/foundation.dart';
import '../models/product_variant_model.dart';
import '../models/product_model.dart';
import '../data/db_helper.dart';
import 'user_service.dart';

/// Service quản lý biến thể sản phẩm (size, color) cho ngành thời trang
/// Hỗ trợ CRUD variants, tính toán tồn kho theo variant
class VariantService {
  static final VariantService _instance = VariantService._internal();
  factory VariantService() => _instance;
  VariantService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DBHelper _dbHelper = DBHelper();

  // === CACHED DATA ===
  Map<String, List<ProductVariant>> _variantCache = {};

  /// Clear cache khi chuyển shop
  void clearCache() {
    _variantCache.clear();
  }

  // === CRUD OPERATIONS ===

  /// Tạo biến thể mới
  Future<String?> createVariant(ProductVariant variant) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return null;

    final variantWithShop = variant.copyWith(
      shopId: shopId,
      updatedAt: DateTime.now(),
    );

    try {
      // Save to Firestore
      final docRef = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_variants')
          .add(variantWithShop.toFirestoreMap());

      final firestoreId = docRef.id;

      // Save to local DB
      final localVariant = variantWithShop.copyWith(
        firestoreId: firestoreId,
        isSynced: true,
      );
      await _saveVariantLocally(localVariant);

      // Invalidate cache
      _variantCache.remove(variant.productId);

      return firestoreId;
    } catch (e) {
      debugPrint('Error creating variant: $e');

      // Save offline
      try {
        final localVariant = variantWithShop.copyWith(
          firestoreId: 'local_${DateTime.now().millisecondsSinceEpoch}',
          isSynced: false,
        );
        await _saveVariantLocally(localVariant);
        return localVariant.firestoreId;
      } catch (localError) {
        debugPrint('Error saving variant locally: $localError');
        return null;
      }
    }
  }

  /// Cập nhật biến thể
  Future<bool> updateVariant(ProductVariant variant) async {
    if (variant.firestoreId.isEmpty) return false;

    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    final updated = variant.copyWith(
      updatedAt: DateTime.now(),
    );

    try {
      // Update Firestore
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_variants')
          .doc(variant.firestoreId)
          .set(updated.toFirestoreMap(), SetOptions(merge: true));

      // Update local DB
      await _saveVariantLocally(updated.copyWith(isSynced: true));

      // Invalidate cache
      _variantCache.remove(variant.productId);

      return true;
    } catch (e) {
      debugPrint('Error updating variant: $e');

      // Update locally
      try {
        await _saveVariantLocally(updated.copyWith(isSynced: false));
        return true;
      } catch (localError) {
        debugPrint('Error updating variant locally: $localError');
        return false;
      }
    }
  }

  /// Xóa biến thể (soft delete)
  Future<bool> deleteVariant(String firestoreId, String productId) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      // Soft delete in Firestore
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_variants')
          .doc(firestoreId)
          .set({
        'isActive': false,
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      }, SetOptions(merge: true));

      // Delete from local DB
      final db = await _dbHelper.database;
      await db.delete(
        'product_variants',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );

      // Invalidate cache
      _variantCache.remove(productId);

      return true;
    } catch (e) {
      debugPrint('Error deleting variant: $e');
      return false;
    }
  }

  /// Lấy tất cả variants của một sản phẩm
  Future<List<ProductVariant>> getVariantsByProduct(String productId) async {
    // Check cache first
    if (_variantCache.containsKey(productId)) {
      return _variantCache[productId]!;
    }

    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    // Try local DB first
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'productId = ? AND shopId = ?',
        whereArgs: [productId, shopId],
        orderBy: 'size ASC, color ASC',
      );

      if (results.isNotEmpty) {
        final variants =
            results.map((r) => ProductVariant.fromMap(r)).toList();
        _variantCache[productId] = variants;
        return variants;
      }
    } catch (e) {
      debugPrint('Error getting variants locally: $e');
    }

    // Try Firestore
    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_variants')
          .where('productId', isEqualTo: productId)
          .where('isActive', isEqualTo: true)
          .get();

      final variants = snapshot.docs.map((doc) {
        final data = doc.data();
        data['firestoreId'] = doc.id;
        return ProductVariant.fromMap(data);
      }).toList();

      // Sort by size then color
      variants.sort((a, b) {
        final sizeCompare = (a.size ?? '').compareTo(b.size ?? '');
        if (sizeCompare != 0) return sizeCompare;
        return (a.color ?? '').compareTo(b.color ?? '');
      });

      // Cache and save locally
      _variantCache[productId] = variants;
      for (final v in variants) {
        await _saveVariantLocally(v.copyWith(isSynced: true));
      }

      return variants;
    } catch (e) {
      debugPrint('Error getting variants from Firestore: $e');
      return [];
    }
  }

  /// Lấy variant summary cho một sản phẩm
  Future<VariantSummary> getVariantSummary(String productId) async {
    final variants = await getVariantsByProduct(productId);
    return VariantSummary.fromVariants(productId, variants);
  }

  /// Lấy tất cả variants của shop (cho báo cáo)
  Future<List<ProductVariant>> getAllVariants({bool lowStockOnly = false}) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      String where = 'shopId = ? AND isActive = 1';
      if (lowStockOnly) {
        where += ' AND quantity <= minQuantity';
      }
      final results = await db.query(
        'product_variants',
        where: where,
        whereArgs: [shopId],
        orderBy: 'productId, size ASC, color ASC',
      );

      return results.map((r) => ProductVariant.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error getting all variants: $e');
      return [];
    }
  }

  /// Lấy variant theo barcode
  Future<ProductVariant?> getVariantByBarcode(String barcode) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return null;

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'barcode = ? AND shopId = ? AND isActive = 1',
        whereArgs: [barcode, shopId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return ProductVariant.fromMap(results.first);
      }
    } catch (e) {
      debugPrint('Error getting variant by barcode: $e');
    }

    return null;
  }

  /// Lấy variant theo SKU
  Future<ProductVariant?> getVariantBySku(String sku) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return null;

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'sku = ? AND shopId = ? AND isActive = 1',
        whereArgs: [sku, shopId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return ProductVariant.fromMap(results.first);
      }
    } catch (e) {
      debugPrint('Error getting variant by sku: $e');
    }

    return null;
  }

  // === INVENTORY OPERATIONS ===

  /// Cập nhật số lượng tồn kho variant
  Future<bool> updateQuantity(String firestoreId, int quantity) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      // Update Firestore
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('product_variants')
          .doc(firestoreId)
          .update({
        'quantity': quantity,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });

      // Update local
      final db = await _dbHelper.database;
      await db.update(
        'product_variants',
        {
          'quantity': quantity,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'isSynced': 1,
        },
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );

      // Invalidate all cache (variant might be in cache)
      _variantCache.clear();

      return true;
    } catch (e) {
      debugPrint('Error updating variant quantity: $e');
      return false;
    }
  }

  /// Giảm số lượng khi bán (dùng trong sale flow)
  Future<bool> decreaseQuantity(String firestoreId, int amount) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      // Get current quantity first
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );

      if (results.isEmpty) return false;

      final current = results.first['quantity'] as int? ?? 0;
      final newQty = (current - amount).clamp(0, 999999);

      return await updateQuantity(firestoreId, newQty);
    } catch (e) {
      debugPrint('Error decreasing variant quantity: $e');
      return false;
    }
  }

  /// Tăng số lượng khi nhập hàng
  Future<bool> increaseQuantity(String firestoreId, int amount) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
        limit: 1,
      );

      if (results.isEmpty) return false;

      final current = results.first['quantity'] as int? ?? 0;
      final newQty = current + amount;

      return await updateQuantity(firestoreId, newQty);
    } catch (e) {
      debugPrint('Error increasing variant quantity: $e');
      return false;
    }
  }

  // === REPORTING ===

  /// Thống kê tồn kho theo variant (inventory matrix)
  Future<Map<String, VariantSummary>> getInventoryMatrix() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return {};

    try {
      final allVariants = await getAllVariants();

      // Group by productId
      final grouped = <String, List<ProductVariant>>{};
      for (final v in allVariants) {
        grouped.putIfAbsent(v.productId, () => []).add(v);
      }

      // Create summaries
      final matrix = <String, VariantSummary>{};
      for (final entry in grouped.entries) {
        matrix[entry.key] = VariantSummary.fromVariants(entry.key, entry.value);
      }

      return matrix;
    } catch (e) {
      debugPrint('Error getting inventory matrix: $e');
      return {};
    }
  }

  /// Lấy variants hết hàng
  Future<List<ProductVariant>> getOutOfStockVariants() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'shopId = ? AND isActive = 1 AND quantity <= 0',
        whereArgs: [shopId],
      );

      return results.map((r) => ProductVariant.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error getting out of stock variants: $e');
      return [];
    }
  }

  /// Lấy variants sắp hết (low stock)
  Future<List<ProductVariant>> getLowStockVariants() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'product_variants',
        where: 'shopId = ? AND isActive = 1 AND quantity > 0 AND quantity <= minQuantity',
        whereArgs: [shopId],
      );

      return results.map((r) => ProductVariant.fromMap(r)).toList();
    } catch (e) {
      debugPrint('Error getting low stock variants: $e');
      return [];
    }
  }

  /// Đếm số variants cần cảnh báo
  Future<VariantWarningCounts> getWarningCounts() async {
    final outOfStock = await getOutOfStockVariants();
    final lowStock = await getLowStockVariants();

    return VariantWarningCounts(
      outOfStock: outOfStock.length,
      lowStock: lowStock.length,
    );
  }

  // === BULK OPERATIONS ===

  /// Tạo nhiều variants cùng lúc (cho product mới)
  Future<List<String>> createVariants(List<ProductVariant> variants) async {
    final ids = <String>[];
    for (final v in variants) {
      final id = await createVariant(v);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Xóa tất cả variants của một sản phẩm (khi xóa sản phẩm)
  Future<bool> deleteVariantsByProduct(String productId) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return false;

    try {
      // Get all variants
      final variants = await getVariantsByProduct(productId);

      // Delete each one
      for (final v in variants) {
        await deleteVariant(v.firestoreId, productId);
      }

      // Clear cache
      _variantCache.remove(productId);

      return true;
    } catch (e) {
      debugPrint('Error deleting variants by product: $e');
      return false;
    }
  }

  // === HELPER ===

  Future<void> _saveVariantLocally(ProductVariant variant) async {
    try {
      final db = await _dbHelper.database;
      
      // Check if exists
      final existing = await db.query(
        'product_variants',
        where: 'firestoreId = ?',
        whereArgs: [variant.firestoreId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Update
        await db.update(
          'product_variants',
          variant.toMap(),
          where: 'firestoreId = ?',
          whereArgs: [variant.firestoreId],
        );
      } else {
        // Insert
        await db.insert('product_variants', variant.toMap());
      }
    } catch (e) {
      debugPrint('Error saving variant locally: $e');
      rethrow;
    }
  }

  /// Generate SKU từ productId, size, color
  String generateSku(String productName, String? size, String? color) {
    final parts = <String>[];
    
    // Tên sản phẩm rút gọn
    final nameCode = productName
        .split(' ')
        .take(2)
        .map((w) => w.length > 2 ? w.substring(0, 2).toUpperCase() : w.toUpperCase())
        .join('');
    parts.add(nameCode);
    
    // Size
    if (size != null && size.isNotEmpty) {
      parts.add(size.toUpperCase());
    }
    
    // Color (lấy ký tự đầu)
    if (color != null && color.isNotEmpty) {
      parts.add(color.split(' ').map((w) => w[0].toUpperCase()).join(''));
    }
    
    // Random suffix
    parts.add(DateTime.now().millisecondsSinceEpoch.toString().substring(9));
    
    return parts.join('-');
  }

  /// Lấy danh sách sizes có sẵn trong shop
  Future<List<String>> getAvailableSizes() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return CommonSizes.clothing;

    try {
      final db = await _dbHelper.database;
      final results = await db.rawQuery('''
        SELECT DISTINCT size FROM product_variants 
        WHERE shopId = ? AND size IS NOT NULL AND size != ''
        ORDER BY size
      ''', [shopId]);

      final sizes = results.map((r) => r['size'] as String).toList();
      if (sizes.isEmpty) return CommonSizes.clothing;
      return sizes;
    } catch (e) {
      debugPrint('Error getting available sizes: $e');
      return CommonSizes.clothing;
    }
  }

  /// Lấy danh sách màu có sẵn trong shop
  Future<List<String>> getAvailableColors() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return CommonColors.all;

    try {
      final db = await _dbHelper.database;
      final results = await db.rawQuery('''
        SELECT DISTINCT color FROM product_variants 
        WHERE shopId = ? AND color IS NOT NULL AND color != ''
        ORDER BY color
      ''', [shopId]);

      final colors = results.map((r) => r['color'] as String).toList();
      if (colors.isEmpty) return CommonColors.all;
      return colors;
    } catch (e) {
      debugPrint('Error getting available colors: $e');
      return CommonColors.all;
    }
  }
}

/// Số lượng cảnh báo variants
class VariantWarningCounts {
  final int outOfStock;
  final int lowStock;

  VariantWarningCounts({
    this.outOfStock = 0,
    this.lowStock = 0,
  });

  int get total => outOfStock + lowStock;

  bool get hasWarnings => total > 0;
}

/// Danh sách sizes phổ biến
class CommonSizes {
  static const List<String> clothing = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL'];
  static const List<String> shoes = ['35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45'];
  static const List<String> kids = ['1-2Y', '2-3Y', '3-4Y', '4-5Y', '5-6Y', '6-7Y', '7-8Y', '8-9Y', '9-10Y'];
  static const List<String> freeSize = ['Free Size'];
}

/// Danh sách màu phổ biến
class CommonColors {
  static const List<String> all = [
    'Đen', 'Trắng', 'Xám', 'Xanh navy', 'Xanh dương',
    'Xanh lá', 'Đỏ', 'Hồng', 'Vàng', 'Cam',
    'Nâu', 'Be', 'Tím', 'Kem', 'Bạc',
  ];

  static const Map<String, String> hexCodes = {
    'Đen': '#000000',
    'Trắng': '#FFFFFF',
    'Xám': '#808080',
    'Xanh navy': '#000080',
    'Xanh dương': '#0000FF',
    'Xanh lá': '#008000',
    'Đỏ': '#FF0000',
    'Hồng': '#FFC0CB',
    'Vàng': '#FFFF00',
    'Cam': '#FFA500',
    'Nâu': '#8B4513',
    'Be': '#F5F5DC',
    'Tím': '#800080',
    'Kem': '#FFFDD0',
    'Bạc': '#C0C0C0',
  };
}

