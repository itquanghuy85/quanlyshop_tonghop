import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/shop_settings_model.dart';
import 'package:quanlyshop/models/product_category_model.dart';
import 'package:quanlyshop/models/product_variant_model.dart';
import 'package:quanlyshop/models/product_model.dart';

/// Test Phase 1: Multi-Industry Expansion
/// Kiểm tra tất cả các model, fields, và logic chuyển đổi dữ liệu
void main() {
  group('ShopSettings Model Tests', () {
    test('Default constructor creates electronics shop', () {
      final settings = ShopSettings(shopId: 'shop_001');
      
      expect(settings.businessType, 'electronics');
      expect(settings.enableRepair, true);
      expect(settings.enableSerial, true);
      expect(settings.enableWarranty, true);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, false);
      expect(settings.enableBatch, false);
      expect(settings.defaultUnit, 'cái');
    });

    test('Electronics factory creates correct settings', () {
      final settings = ShopSettings.electronics('shop_elec_001');
      
      expect(settings.shopId, 'shop_elec_001');
      expect(settings.businessType, 'electronics');
      expect(settings.businessTypeName, 'Điện thoại & Điện tử');
      expect(settings.enableRepair, true);
      expect(settings.enableSerial, true);
      expect(settings.enableWarranty, true);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, false);
      expect(settings.isElectronics, true);
      expect(settings.isFood, false);
      expect(settings.isFashion, false);
    });

    test('Food factory creates correct settings', () {
      final settings = ShopSettings.food('shop_food_001');
      
      expect(settings.shopId, 'shop_food_001');
      expect(settings.businessType, 'food');
      expect(settings.businessTypeName, 'Thực phẩm & Đồ tươi sống');
      expect(settings.enableRepair, false);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
      expect(settings.enableExpiry, true);
      expect(settings.enableBatch, true);
      expect(settings.defaultUnit, 'kg');
      expect(settings.expiryWarningDays, 7);
      expect(settings.isFood, true);
    });

    test('Fashion factory creates correct settings', () {
      final settings = ShopSettings.fashion('shop_fashion_001');
      
      expect(settings.shopId, 'shop_fashion_001');
      expect(settings.businessType, 'fashion');
      expect(settings.businessTypeName, 'Thời trang & May mặc');
      expect(settings.enableRepair, false);
      expect(settings.enableVariants, true);
      expect(settings.enableSerial, false);
      expect(settings.isFashion, true);
    });

    test('General factory creates correct settings', () {
      final settings = ShopSettings.general('shop_general_001');
      
      expect(settings.businessType, 'general');
      expect(settings.businessTypeName, 'Tổng hợp');
      expect(settings.enableRepair, false);
      expect(settings.enableVariants, false);
      expect(settings.enableExpiry, false);
      expect(settings.isGeneral, true);
    });

    test('toMap and fromMap roundtrip for SQLite', () {
      final original = ShopSettings.food('shop_test');
      final map = original.toMap();
      final restored = ShopSettings.fromMap(map);
      
      expect(restored.shopId, original.shopId);
      expect(restored.businessType, original.businessType);
      expect(restored.enableExpiry, original.enableExpiry);
      expect(restored.enableBatch, original.enableBatch);
      expect(restored.defaultUnit, original.defaultUnit);
      expect(restored.expiryWarningDays, original.expiryWarningDays);
    });

    test('toFirestoreMap creates valid Firestore document', () {
      final settings = ShopSettings.electronics('shop_fs_001');
      final map = settings.toFirestoreMap();
      
      expect(map['shopId'], 'shop_fs_001');
      expect(map['businessType'], 'electronics');
      expect(map['enableRepair'], true);
      expect(map['enableSerial'], true);
      expect(map.containsKey('createdAt'), true);
      expect(map.containsKey('updatedAt'), true);
    });

    test('copyWith updates fields correctly', () {
      final original = ShopSettings.electronics('shop_001');
      final updated = original.copyWith(
        enableVariants: true,
        expiryWarningDays: 14,
      );
      
      expect(updated.enableVariants, true);
      expect(updated.expiryWarningDays, 14);
      // Original fields preserved
      expect(updated.shopId, 'shop_001');
      expect(updated.businessType, 'electronics');
      expect(updated.enableRepair, true);
    });

    test('BusinessType enum works correctly', () {
      expect(BusinessType.electronics.code, 'electronics');
      expect(BusinessType.electronics.displayName, 'Điện thoại & Điện tử');
      expect(BusinessType.electronics.icon, '📱');
      
      expect(BusinessType.food.code, 'food');
      expect(BusinessType.food.icon, '🍎');
      
      expect(BusinessType.fashion.code, 'fashion');
      expect(BusinessType.fashion.icon, '👕');
      
      expect(BusinessType.fromCode('food'), BusinessType.food);
      expect(BusinessType.fromCode('invalid'), BusinessType.electronics); // default
    });
  });

  group('ProductCategory Model Tests', () {
    test('Default phone category has correct properties', () {
      final category = ProductCategory.defaultPhoneCategory('shop_001');
      
      expect(category.name, 'Điện thoại');
      expect(category.icon, '📱');
      expect(category.trackSerial, true);
      expect(category.hasWarranty, true);
      expect(category.defaultWarrantyDays, 365);
      expect(category.trackExpiry, false);
      expect(category.hasVariants, false);
      expect(category.customFields['imei'], 'IMEI');
      expect(category.customFields['color'], 'Màu sắc');
    });

    test('Default accessory category has correct properties', () {
      final category = ProductCategory.defaultAccessoryCategory('shop_001');
      
      expect(category.name, 'Phụ kiện');
      expect(category.icon, '🎧');
      expect(category.trackSerial, false);
      expect(category.hasWarranty, true);
      expect(category.defaultWarrantyDays, 30);
    });

    test('Default part category has correct properties', () {
      final category = ProductCategory.defaultPartCategory('shop_001');
      
      expect(category.name, 'Linh kiện');
      expect(category.icon, '🔧');
      expect(category.trackSerial, false);
      expect(category.hasWarranty, false);
    });

    test('Food category has expiry tracking enabled', () {
      final category = ProductCategory.foodCategory('shop_001', 'Rau củ');
      
      expect(category.name, 'Rau củ');
      expect(category.icon, '🍎');
      expect(category.trackExpiry, true);
      expect(category.trackSerial, false);
      expect(category.hasVariants, false);
    });

    test('Fashion category has variants enabled', () {
      final category = ProductCategory.fashionCategory('shop_001', 'Áo');
      
      expect(category.name, 'Áo');
      expect(category.icon, '👕');
      expect(category.hasVariants, true);
      expect(category.trackExpiry, false);
      expect(category.trackSerial, false);
      expect(category.customFields['size'], 'Kích cỡ');
      expect(category.customFields['color'], 'Màu sắc');
      expect(category.customFields['material'], 'Chất liệu');
    });

    test('Category with parent is not root', () {
      final parent = ProductCategory(
        shopId: 'shop_001',
        name: 'Điện thoại',
        firestoreId: 'cat_parent',
      );
      
      final child = ProductCategory(
        shopId: 'shop_001',
        name: 'iPhone',
        parentId: 'cat_parent',
      );
      
      expect(parent.isRoot, true);
      expect(child.isRoot, false);
      expect(child.parentId, 'cat_parent');
    });

    test('toMap and fromMap roundtrip with customFields', () {
      final original = ProductCategory(
        shopId: 'shop_001',
        name: 'Test Category',
        icon: '📦',
        trackExpiry: true,
        hasVariants: true,
        customFields: {'field1': 'Value 1', 'field2': 'Value 2'},
      );
      
      final map = original.toMap();
      final restored = ProductCategory.fromMap(map);
      
      expect(restored.shopId, original.shopId);
      expect(restored.name, original.name);
      expect(restored.icon, original.icon);
      expect(restored.trackExpiry, original.trackExpiry);
      expect(restored.hasVariants, original.hasVariants);
      expect(restored.customFields['field1'], 'Value 1');
      expect(restored.customFields['field2'], 'Value 2');
    });

    test('toFirestoreMap creates valid document', () {
      final category = ProductCategory.defaultPhoneCategory('shop_001');
      final map = category.toFirestoreMap();
      
      expect(map['shopId'], 'shop_001');
      expect(map['name'], 'Điện thoại');
      expect(map['trackSerial'], true);
      expect(map['hasWarranty'], true);
      expect(map['customFields'] is Map, true);
    });

    test('copyWith preserves original values', () {
      final original = ProductCategory.fashionCategory('shop_001', 'Áo');
      final updated = original.copyWith(
        name: 'Áo sơ mi',
        sortOrder: 10,
      );
      
      expect(updated.name, 'Áo sơ mi');
      expect(updated.sortOrder, 10);
      expect(updated.hasVariants, true); // preserved
      expect(updated.shopId, 'shop_001'); // preserved
    });
  });

  group('ProductVariant Model Tests', () {
    test('Variant with size and color has correct displayName', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        size: 'L',
        color: 'Đỏ',
        quantity: 10,
        salePrice: 350000,
      );
      
      expect(variant.displayName, 'Đỏ - Size L');
      expect(variant.quantity, 10);
      expect(variant.salePrice, 350000);
    });

    test('Variant with only color has correct displayName', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        color: 'Xanh dương',
        quantity: 5,
      );
      
      expect(variant.displayName, 'Xanh dương');
    });

    test('Variant with only size has correct displayName', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        size: 'M',
        quantity: 3,
      );
      
      expect(variant.displayName, 'Size M');
    });

    test('Low stock detection works', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        quantity: 2,
        minQuantity: 5,
      );
      
      expect(variant.isLowStock, true);
      expect(variant.isOutOfStock, false);
    });

    test('Out of stock detection works', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        quantity: 0,
        minQuantity: 5,
      );
      
      expect(variant.isOutOfStock, true);
      expect(variant.isLowStock, true);
    });

    test('toMap and fromMap roundtrip', () {
      final original = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        sku: 'SKU-001-L-RED',
        size: 'L',
        color: 'Đỏ',
        colorCode: '#FF0000',
        material: 'Cotton',
        costPrice: 200000,
        salePrice: 350000,
        quantity: 10,
        minQuantity: 3,
        barcode: '1234567890123',
      );
      
      final map = original.toMap();
      final restored = ProductVariant.fromMap(map);
      
      expect(restored.shopId, original.shopId);
      expect(restored.productId, original.productId);
      expect(restored.sku, original.sku);
      expect(restored.size, original.size);
      expect(restored.color, original.color);
      expect(restored.colorCode, original.colorCode);
      expect(restored.material, original.material);
      expect(restored.costPrice, original.costPrice);
      expect(restored.salePrice, original.salePrice);
      expect(restored.quantity, original.quantity);
      expect(restored.minQuantity, original.minQuantity);
      expect(restored.barcode, original.barcode);
    });

    test('VariantSummary calculates correctly', () {
      final variants = [
        ProductVariant(
          shopId: 'shop_001',
          productId: 'prod_001',
          size: 'S',
          color: 'Đỏ',
          quantity: 5,
          salePrice: 300000,
        ),
        ProductVariant(
          shopId: 'shop_001',
          productId: 'prod_001',
          size: 'M',
          color: 'Đỏ',
          quantity: 10,
          salePrice: 350000,
        ),
        ProductVariant(
          shopId: 'shop_001',
          productId: 'prod_001',
          size: 'L',
          color: 'Xanh',
          quantity: 8,
          salePrice: 400000,
        ),
      ];
      
      final summary = VariantSummary.fromVariants('prod_001', variants);
      
      expect(summary.productId, 'prod_001');
      expect(summary.totalVariants, 3);
      expect(summary.totalStock, 23); // 5 + 10 + 8
      expect(summary.minPrice, 300000);
      expect(summary.maxPrice, 400000);
      expect(summary.availableSizes, containsAll(['S', 'M', 'L']));
      expect(summary.availableColors, containsAll(['Đỏ', 'Xanh']));
      expect(summary.priceRange, '300K - 400K');
    });

    test('VariantSummary empty list returns defaults', () {
      final summary = VariantSummary.fromVariants('prod_001', []);
      
      expect(summary.totalVariants, 0);
      expect(summary.totalStock, 0);
      expect(summary.availableSizes, isEmpty);
      expect(summary.availableColors, isEmpty);
    });
  });

  group('Product Model Multi-Industry Fields Tests', () {
    test('Product with categoryId works', () {
      final product = Product(
        name: 'iPhone 15 Pro',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_phone_001',
        unit: 'cái',
      );
      
      expect(product.categoryId, 'cat_phone_001');
      expect(product.unit, 'cái');
      expect(product.type, 'DIEN_THOAI'); // default backward compat
    });

    test('Product with expiryDate detects expiry correctly', () {
      // Expired product
      final expiredProduct = Product(
        name: 'Sữa tươi',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_dairy_001',
        unit: 'hộp',
        expiryDate: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      
      expect(expiredProduct.hasExpiry, true);
      expect(expiredProduct.isExpired, true);
      expect(expiredProduct.isNearExpiry, false);
    });

    test('Product near expiry detects correctly', () {
      // Product expiring in 3 days
      final nearExpiryProduct = Product(
        name: 'Bánh mì',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_bakery_001',
        unit: 'cái',
        expiryDate: DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
      
      expect(nearExpiryProduct.hasExpiry, true);
      expect(nearExpiryProduct.isExpired, false);
      expect(nearExpiryProduct.isNearExpiry, true);
    });

    test('Product not near expiry returns false', () {
      // Product expiring in 30 days
      final product = Product(
        name: 'Nước ngọt',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );
      
      expect(product.isNearExpiry, false);
      expect(product.isExpired, false);
    });

    test('Product without expiryDate has no expiry', () {
      final product = Product(
        name: 'Điện thoại Samsung',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      
      expect(product.hasExpiry, false);
      expect(product.isExpired, false);
      expect(product.isNearExpiry, false);
    });

    test('Product with variantParentId is a variant', () {
      final parentProduct = Product(
        name: 'Áo sơ mi Veston',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_shirt_001',
      );
      
      final variantProduct = Product(
        name: 'Áo sơ mi Veston - Size L - Trắng',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_shirt_001',
        variantParentId: 'prod_parent_001',
      );
      
      expect(parentProduct.isVariant, false);
      expect(variantProduct.isVariant, true);
      expect(variantProduct.variantParentId, 'prod_parent_001');
    });

    test('Product with batchNumber works', () {
      final product = Product(
        name: 'Sữa TH True Milk',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        batchNumber: 'LOT-2026-02-001',
        expiryDate: DateTime.now().add(const Duration(days: 60)).millisecondsSinceEpoch,
      );
      
      expect(product.batchNumber, 'LOT-2026-02-001');
    });

    test('Product with customData stores JSON', () {
      final product = Product(
        name: 'iPhone 15 Pro Max',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        customData: '{"screen_size":"6.7 inch","ram":"8GB","storage":"256GB"}',
      );
      
      expect(product.customData, contains('screen_size'));
      expect(product.customData, contains('6.7 inch'));
    });

    test('Product toMap includes multi-industry fields', () {
      final product = Product(
        name: 'Test Product',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        categoryId: 'cat_001',
        unit: 'kg',
        expiryDate: 1707350400000, // Some future date
        batchNumber: 'BATCH001',
        variantParentId: 'parent_001',
        customData: '{"key":"value"}',
      );
      
      final map = product.toMap();
      
      expect(map['categoryId'], 'cat_001');
      expect(map['unit'], 'kg');
      expect(map['expiryDate'], 1707350400000);
      expect(map['batchNumber'], 'BATCH001');
      expect(map['variantParentId'], 'parent_001');
      expect(map['customData'], '{"key":"value"}');
    });

    test('Product fromMap parses multi-industry fields', () {
      final map = {
        'name': 'Restored Product',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'categoryId': 'cat_restored',
        'unit': 'lít',
        'expiryDate': 1707350400000,
        'batchNumber': 'BATCH_RESTORED',
        'variantParentId': 'parent_restored',
        'customData': '{"restored":"true"}',
      };
      
      final product = Product.fromMap(map);
      
      expect(product.categoryId, 'cat_restored');
      expect(product.unit, 'lít');
      expect(product.expiryDate, 1707350400000);
      expect(product.batchNumber, 'BATCH_RESTORED');
      expect(product.variantParentId, 'parent_restored');
      expect(product.customData, '{"restored":"true"}');
    });

    test('Product copyWith updates multi-industry fields', () {
      final original = Product(
        name: 'Original',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      
      final updated = original.copyWith(
        categoryId: 'cat_new',
        unit: 'cái',
        expiryDate: 1707350400000,
        batchNumber: 'NEW_BATCH',
      );
      
      expect(updated.name, 'Original'); // preserved
      expect(updated.categoryId, 'cat_new');
      expect(updated.unit, 'cái');
      expect(updated.expiryDate, 1707350400000);
      expect(updated.batchNumber, 'NEW_BATCH');
    });
  });

  group('Data Integrity Tests - Prices and Quantities', () {
    test('Product prices are non-negative', () {
      final product = Product(
        name: 'Test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        cost: 100000,
        price: 150000,
        quantity: 10,
      );
      
      expect(product.cost, greaterThanOrEqualTo(0));
      expect(product.price, greaterThanOrEqualTo(0));
      expect(product.quantity, greaterThanOrEqualTo(0));
    });

    test('ProductVariant prices are non-negative', () {
      final variant = ProductVariant(
        shopId: 'shop_001',
        productId: 'prod_001',
        costPrice: 200000,
        salePrice: 350000,
        quantity: 5,
      );
      
      expect(variant.costPrice, greaterThanOrEqualTo(0));
      expect(variant.salePrice, greaterThanOrEqualTo(0));
      expect(variant.quantity, greaterThanOrEqualTo(0));
    });

    test('VariantSummary price range is correct', () {
      final variants = [
        ProductVariant(shopId: 's', productId: 'p', salePrice: 100000, quantity: 1),
        ProductVariant(shopId: 's', productId: 'p', salePrice: 500000, quantity: 1),
        ProductVariant(shopId: 's', productId: 'p', salePrice: 250000, quantity: 1),
      ];
      
      final summary = VariantSummary.fromVariants('p', variants);
      
      expect(summary.minPrice, 100000);
      expect(summary.maxPrice, 500000);
    });
  });

  group('Industry-Specific Feature Tests', () {
    test('Electronics shop has repair and serial features', () {
      final settings = ShopSettings.electronics('shop_001');
      final phoneCategory = ProductCategory.defaultPhoneCategory('shop_001');
      
      // Shop supports repair
      expect(settings.enableRepair, true);
      expect(settings.enableSerial, true);
      
      // Category tracks serial
      expect(phoneCategory.trackSerial, true);
      expect(phoneCategory.hasWarranty, true);
    });

    test('Food shop has expiry and batch features', () {
      final settings = ShopSettings.food('shop_001');
      final foodCategory = ProductCategory.foodCategory('shop_001', 'Thịt');
      
      // Shop supports expiry
      expect(settings.enableExpiry, true);
      expect(settings.enableBatch, true);
      
      // Category tracks expiry
      expect(foodCategory.trackExpiry, true);
    });

    test('Fashion shop has variant features', () {
      final settings = ShopSettings.fashion('shop_001');
      final category = ProductCategory.fashionCategory('shop_001', 'Quần jean');
      
      // Shop supports variants
      expect(settings.enableVariants, true);
      
      // Category has variants
      expect(category.hasVariants, true);
      expect(category.customFields.containsKey('size'), true);
      expect(category.customFields.containsKey('color'), true);
    });
  });

  group('Timestamp Parsing Tests', () {
    test('ShopSettings parses various timestamp formats', () {
      // Integer timestamp
      final map1 = {
        'shopId': 'shop_001',
        'createdAt': 1707350400000,
        'updatedAt': 1707350400000,
      };
      final s1 = ShopSettings.fromMap(map1);
      expect(s1.createdAt.millisecondsSinceEpoch, 1707350400000);
      
      // ISO String timestamp
      final map2 = {
        'shopId': 'shop_002',
        'createdAt': '2026-02-08T12:00:00.000Z',
        'updatedAt': '2026-02-08T12:00:00.000Z',
      };
      final s2 = ShopSettings.fromMap(map2);
      expect(s2.createdAt.year, 2026);
    });

    test('ProductCategory parses various timestamp formats', () {
      final map = {
        'shopId': 'shop_001',
        'name': 'Test',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      
      final category = ProductCategory.fromMap(map);
      expect(category.createdAt, isNotNull);
      expect(category.updatedAt, isNotNull);
    });

    test('Product expiryDate parsing', () {
      final map = {
        'name': 'Test',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiryDate': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      };
      
      final product = Product.fromMap(map);
      expect(product.expiryDate, isNotNull);
      expect(product.hasExpiry, true);
    });
  });
}
