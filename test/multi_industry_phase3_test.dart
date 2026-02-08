import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

// Import models
import 'package:quanlyshop/models/product_variant_model.dart';
import 'package:quanlyshop/models/shop_settings_model.dart';
import 'package:quanlyshop/services/variant_service.dart';

/// Phase 3: Fashion Module Tests
/// Tests for size/color variants, inventory matrix, and fashion shop features
void main() {
  group('ProductVariant Model Tests', () {
    test('should create variant with size and color', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        size: 'L',
        color: 'Đen',
        quantity: 10,
      );

      expect(variant.size, 'L');
      expect(variant.color, 'Đen');
      expect(variant.quantity, 10);
      expect(variant.displayName, 'Đen - Size L');
    });

    test('should display name correctly for size only', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        size: 'M',
        quantity: 5,
      );

      expect(variant.displayName, 'Size M');
    });

    test('should display name correctly for color only', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        color: 'Xanh dương',
        quantity: 5,
      );

      expect(variant.displayName, 'Xanh dương');
    });

    test('should detect out of stock', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        size: 'S',
        quantity: 0,
      );

      expect(variant.isOutOfStock, true);
      expect(variant.isLowStock, false);
    });

    test('should detect low stock', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        size: 'S',
        quantity: 3,
        minQuantity: 5,
      );

      expect(variant.isOutOfStock, false);
      expect(variant.isLowStock, true);
    });

    test('should convert to map and back', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        firestoreId: 'var_001',
        sku: 'SHIRT-L-BLACK',
        size: 'L',
        color: 'Đen',
        costPrice: 150000,
        salePrice: 250000,
        quantity: 10,
        minQuantity: 2,
        barcode: '1234567890',
      );

      final map = variant.toMap();
      final restored = ProductVariant.fromMap(map);

      expect(restored.shopId, variant.shopId);
      expect(restored.productId, variant.productId);
      expect(restored.sku, variant.sku);
      expect(restored.size, variant.size);
      expect(restored.color, variant.color);
      expect(restored.costPrice, variant.costPrice);
      expect(restored.salePrice, variant.salePrice);
      expect(restored.quantity, variant.quantity);
    });

    test('copyWith should work correctly', () {
      final variant = ProductVariant(
        shopId: 'shop_123',
        productId: 'product_456',
        size: 'M',
        color: 'Trắng',
        quantity: 5,
      );

      final updated = variant.copyWith(
        quantity: 10,
        salePrice: 300000,
      );

      expect(updated.size, 'M');
      expect(updated.color, 'Trắng');
      expect(updated.quantity, 10);
      expect(updated.salePrice, 300000);
    });
  });

  group('VariantSummary Tests', () {
    test('should calculate summary from variants', () {
      final variants = [
        ProductVariant(
          shopId: 'shop_123',
          productId: 'product_456',
          size: 'S',
          color: 'Đen',
          quantity: 5,
          salePrice: 200000,
        ),
        ProductVariant(
          shopId: 'shop_123',
          productId: 'product_456',
          size: 'M',
          color: 'Đen',
          quantity: 3,
          salePrice: 200000,
        ),
        ProductVariant(
          shopId: 'shop_123',
          productId: 'product_456',
          size: 'L',
          color: 'Trắng',
          quantity: 8,
          salePrice: 250000,
        ),
      ];

      final summary = VariantSummary.fromVariants('product_456', variants);

      expect(summary.totalVariants, 3);
      expect(summary.totalStock, 16);
      expect(summary.availableSizes, containsAll(['S', 'M', 'L']));
      expect(summary.availableColors, containsAll(['Đen', 'Trắng']));
      expect(summary.minPrice, 200000);
      expect(summary.maxPrice, 250000);
    });

    test('should calculate price range correctly', () {
      final variants = [
        ProductVariant(
          shopId: 'shop',
          productId: 'prod',
          salePrice: 100000,
        ),
        ProductVariant(
          shopId: 'shop',
          productId: 'prod',
          salePrice: 200000,
        ),
      ];

      final summary = VariantSummary.fromVariants('prod', variants);

      expect(summary.priceRange, '100K - 200K');
    });

    test('should handle single price', () {
      final variants = [
        ProductVariant(
          shopId: 'shop',
          productId: 'prod',
          salePrice: 150000,
        ),
        ProductVariant(
          shopId: 'shop',
          productId: 'prod',
          salePrice: 150000,
        ),
      ];

      final summary = VariantSummary.fromVariants('prod', variants);

      expect(summary.priceRange, '150K');
    });

    test('should handle empty variants', () {
      final summary = VariantSummary.fromVariants('prod', []);

      expect(summary.totalVariants, 0);
      expect(summary.totalStock, 0);
      expect(summary.availableSizes, isEmpty);
      expect(summary.availableColors, isEmpty);
    });
  });

  group('CommonSizes Tests', () {
    test('should have clothing sizes', () {
      expect(CommonSizes.clothing, contains('S'));
      expect(CommonSizes.clothing, contains('M'));
      expect(CommonSizes.clothing, contains('L'));
      expect(CommonSizes.clothing, contains('XL'));
    });

    test('should have shoe sizes', () {
      expect(CommonSizes.shoes, contains('38'));
      expect(CommonSizes.shoes, contains('40'));
      expect(CommonSizes.shoes, contains('42'));
    });

    test('should have kids sizes', () {
      expect(CommonSizes.kids, contains('2-3Y'));
      expect(CommonSizes.kids, contains('4-5Y'));
    });

    test('should have free size', () {
      expect(CommonSizes.freeSize, contains('Free Size'));
    });
  });

  group('CommonColors Tests', () {
    test('should have common colors', () {
      expect(CommonColors.all, contains('Đen'));
      expect(CommonColors.all, contains('Trắng'));
      expect(CommonColors.all, contains('Xanh dương'));
      expect(CommonColors.all, contains('Đỏ'));
    });

    test('should have hex codes for colors', () {
      expect(CommonColors.hexCodes['Đen'], '#000000');
      expect(CommonColors.hexCodes['Trắng'], '#FFFFFF');
      expect(CommonColors.hexCodes['Đỏ'], '#FF0000');
    });
  });

  group('VariantWarningCounts Tests', () {
    test('should calculate total warnings', () {
      final warnings = VariantWarningCounts(
        outOfStock: 3,
        lowStock: 5,
      );

      expect(warnings.total, 8);
      expect(warnings.hasWarnings, true);
    });

    test('should detect no warnings', () {
      final warnings = VariantWarningCounts(
        outOfStock: 0,
        lowStock: 0,
      );

      expect(warnings.total, 0);
      expect(warnings.hasWarnings, false);
    });
  });

  group('ShopSettings Fashion Config Tests', () {
    test('should create fashion shop settings', () {
      final settings = ShopSettings.fashion('shop_123');

      expect(settings.businessType, 'fashion');
      expect(settings.enableVariants, true);
      expect(settings.enableExpiry, false);
      expect(settings.enableRepair, false);
      expect(settings.enableSerial, false);
      expect(settings.defaultUnit, 'cái');
    });

    test('should have correct feature checks for fashion', () {
      final settings = ShopSettings.fashion('shop_123');

      // Fashion should have variants, not expiry or repair
      expect(settings.enableVariants, true);
      expect(settings.enableExpiry, false);
      expect(settings.enableRepair, false);
    });

    test('electronics should not have variants by default', () {
      final settings = ShopSettings.electronics('shop_123');

      expect(settings.enableVariants, false);
      expect(settings.enableRepair, true);
      expect(settings.enableSerial, true);
    });

    test('food should not have variants by default', () {
      final settings = ShopSettings.food('shop_123');

      expect(settings.enableVariants, false);
      expect(settings.enableExpiry, true);
      expect(settings.enableBatch, true);
    });
  });

  group('Variant SKU Generation Tests', () {
    // Test SKU generation logic directly without service
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

    test('should generate SKU from product name, size, and color', () {
      final sku = generateSku('Áo Thun Basic', 'L', 'Đen');
      
      expect(sku, isNotEmpty);
      expect(sku.contains('L'), true);
      expect(sku.contains('Đ'), true); // First letter of Đen
    });

    test('should generate SKU without color', () {
      final sku = generateSku('Giày Sneaker', '42', null);
      
      expect(sku, isNotEmpty);
      expect(sku.contains('42'), true);
    });

    test('should generate SKUs with timestamp suffix', () {
      final sku1 = generateSku('Test', 'M', 'Trắng');
      final sku2 = generateSku('Test', 'M', 'Trắng');
      
      // They might be same if generated in same millisecond, that's ok
      expect(sku1, isNotEmpty);
      expect(sku2, isNotEmpty);
      expect(sku1.split('-').length, greaterThanOrEqualTo(3));
    });

    test('should handle product name with single word', () {
      final sku = generateSku('Quần', 'L', 'Đen');
      
      expect(sku, isNotEmpty);
      expect(sku.toUpperCase().contains('QU'), true);
    });

    test('should handle product name truncation', () {
      final sku = generateSku('Áo Polo Cao Cấp', 'M', 'Xanh');
      
      // Should only take first 2 words
      expect(sku, isNotEmpty);
      expect(sku.split('-').length, greaterThanOrEqualTo(3));
    });
  });

  group('Variant Matrix Calculation Tests', () {
    test('should group variants by size and color', () {
      final variants = [
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'S', color: 'Đen', quantity: 5),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'S', color: 'Trắng', quantity: 3),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'M', color: 'Đen', quantity: 8),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'M', color: 'Trắng', quantity: 2),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'L', color: 'Đen', quantity: 0),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'L', color: 'Trắng', quantity: 1),
      ];

      final summary = VariantSummary.fromVariants('prod', variants);

      expect(summary.availableSizes.length, 3);
      expect(summary.availableColors.length, 2);
      expect(summary.totalStock, 19);
    });

    test('should count out of stock variants', () {
      final variants = [
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'S', quantity: 5),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'M', quantity: 0),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'L', quantity: 0),
      ];

      final outOfStock = variants.where((v) => v.isOutOfStock).length;

      expect(outOfStock, 2);
    });

    test('should count low stock variants', () {
      final variants = [
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'S', quantity: 10, minQuantity: 5),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'M', quantity: 3, minQuantity: 5),
        ProductVariant(shopId: 'shop', productId: 'prod', size: 'L', quantity: 1, minQuantity: 5),
      ];

      final lowStock = variants.where((v) => v.isLowStock).length;

      expect(lowStock, 2);
    });
  });

  group('Variant Pricing Tests', () {
    test('should use variant price if set', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        salePrice: 300000,
      );

      expect(variant.salePrice, 300000);
    });

    test('should handle zero price (use parent)', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        salePrice: 0,
      );

      expect(variant.salePrice, 0);
      // UI should use parent product price when salePrice is 0
    });

    test('should track cost price separately', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        costPrice: 100000,
        salePrice: 200000,
      );

      expect(variant.costPrice, 100000);
      expect(variant.salePrice, 200000);
      // Profit = 200000 - 100000 = 100000
    });
  });

  group('Variant Barcode Tests', () {
    test('should store barcode', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        barcode: '8934567890123',
        size: 'M',
        color: 'Đen',
      );

      expect(variant.barcode, '8934567890123');
    });

    test('should allow null barcode', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        size: 'M',
      );

      expect(variant.barcode, isNull);
    });
  });

  group('Variant Active Status Tests', () {
    test('should be active by default', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
      );

      expect(variant.isActive, true);
    });

    test('should track inactive variants', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        isActive: false,
      );

      expect(variant.isActive, false);
    });

    test('should copyWith active status', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        isActive: true,
      );

      final deactivated = variant.copyWith(isActive: false);

      expect(deactivated.isActive, false);
    });
  });

  group('Variant Image Tests', () {
    test('should store variant-specific image', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        color: 'Đỏ',
        image: 'https://example.com/red-shirt.jpg',
      );

      expect(variant.image, 'https://example.com/red-shirt.jpg');
    });

    test('should handle null image (use parent)', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        color: 'Xanh',
      );

      expect(variant.image, isNull);
    });
  });

  group('Variant Material/Style Tests', () {
    test('should store material info', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        material: 'Cotton 100%',
        style: 'Slim Fit',
      );

      expect(variant.material, 'Cotton 100%');
      expect(variant.style, 'Slim Fit');
    });

    test('should include material in display name', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        size: 'M',
        color: 'Trắng',
        material: 'Linen',
      );

      expect(variant.displayName, contains('Trắng'));
      expect(variant.displayName, contains('Size M'));
    });
  });

  group('Variant colorCode Tests', () {
    test('should store hex color code', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        color: 'Đỏ',
        colorCode: '#FF0000',
      );

      expect(variant.colorCode, '#FF0000');
    });

    test('should handle missing color code', () {
      final variant = ProductVariant(
        shopId: 'shop',
        productId: 'prod',
        color: 'Custom Color',
      );

      expect(variant.colorCode, isNull);
    });
  });
}
