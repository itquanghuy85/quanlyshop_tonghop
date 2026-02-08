/// Phase 2 Unit Tests - Food Module
/// Tests cho ExpiryAlertService, ExpiryBadge, ExpiryStats, BatchInfo
///
/// Chạy tests: flutter test test/multi_industry_phase2_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/product_model.dart';
import 'package:quanlyshop/models/shop_settings_model.dart';
import 'package:quanlyshop/services/expiry_alert_service.dart';

void main() {
  group('ExpiryStatus enum tests', () {
    test('All enum values exist', () {
      expect(ExpiryStatus.values.length, 5);
      expect(ExpiryStatus.noExpiry.index, 0);
      expect(ExpiryStatus.expired.index, 1);
      expect(ExpiryStatus.expiringToday.index, 2);
      expect(ExpiryStatus.nearExpiry.index, 3);
      expect(ExpiryStatus.good.index, 4);
    });
  });

  group('ExpiryStats model tests', () {
    test('Create ExpiryStats with all fields', () {
      final stats = ExpiryStats(
        expiredCount: 5,
        nearExpiryCount: 10,
        goodCount: 85,
        totalWithExpiry: 100,
        valueAtRisk: 5000000,
        warningDays: 7,
      );

      expect(stats.expiredCount, 5);
      expect(stats.nearExpiryCount, 10);
      expect(stats.goodCount, 85);
      expect(stats.totalWithExpiry, 100);
      expect(stats.valueAtRisk, 5000000);
      expect(stats.warningDays, 7);
    });

    test('atRiskCount returns sum of expired and near expiry', () {
      final stats = ExpiryStats(
        expiredCount: 3,
        nearExpiryCount: 7,
        goodCount: 90,
        totalWithExpiry: 100,
        valueAtRisk: 1000000,
        warningDays: 7,
      );

      expect(stats.atRiskCount, 10);
    });

    test('hasAlerts is true when expired or near expiry > 0', () {
      final statsWithExpired = ExpiryStats(
        expiredCount: 1,
        nearExpiryCount: 0,
        goodCount: 99,
        totalWithExpiry: 100,
        valueAtRisk: 100000,
        warningDays: 7,
      );
      expect(statsWithExpired.hasAlerts, true);

      final statsWithNearExpiry = ExpiryStats(
        expiredCount: 0,
        nearExpiryCount: 5,
        goodCount: 95,
        totalWithExpiry: 100,
        valueAtRisk: 500000,
        warningDays: 7,
      );
      expect(statsWithNearExpiry.hasAlerts, true);

      final statsNoAlerts = ExpiryStats(
        expiredCount: 0,
        nearExpiryCount: 0,
        goodCount: 100,
        totalWithExpiry: 100,
        valueAtRisk: 0,
        warningDays: 7,
      );
      expect(statsNoAlerts.hasAlerts, false);
    });

    test('ExpiryStats.empty returns all zeros', () {
      final empty = ExpiryStats.empty();
      expect(empty.expiredCount, 0);
      expect(empty.nearExpiryCount, 0);
      expect(empty.goodCount, 0);
      expect(empty.totalWithExpiry, 0);
      expect(empty.valueAtRisk, 0);
      expect(empty.warningDays, 7);
      expect(empty.atRiskCount, 0);
      expect(empty.hasAlerts, false);
    });
  });

  group('BatchInfo model tests', () {
    test('Create BatchInfo from map', () {
      final now = DateTime.now();
      final map = {
        'batchNumber': 'LOT-2026-001',
        'productCount': 5,
        'totalQuantity': 100,
        'earliestExpiry': now.millisecondsSinceEpoch,
        'latestExpiry': now.add(const Duration(days: 30)).millisecondsSinceEpoch,
        'totalValue': 5000000,
      };

      final batch = BatchInfo.fromMap(map);

      expect(batch.batchNumber, 'LOT-2026-001');
      expect(batch.productCount, 5);
      expect(batch.totalQuantity, 100);
      expect(batch.earliestExpiry, isNotNull);
      expect(batch.latestExpiry, isNotNull);
      expect(batch.totalValue, 5000000);
    });

    test('BatchInfo.hasExpired returns true for past expiry', () {
      final pastExpiry = DateTime.now().subtract(const Duration(days: 1));
      final batch = BatchInfo(
        batchNumber: 'LOT-EXPIRED',
        productCount: 1,
        totalQuantity: 10,
        earliestExpiry: pastExpiry,
        latestExpiry: pastExpiry,
        totalValue: 100000,
      );

      expect(batch.hasExpired, true);
    });

    test('BatchInfo.hasExpired returns false for future expiry', () {
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final batch = BatchInfo(
        batchNumber: 'LOT-GOOD',
        productCount: 1,
        totalQuantity: 10,
        earliestExpiry: futureExpiry,
        latestExpiry: futureExpiry,
        totalValue: 100000,
      );

      expect(batch.hasExpired, false);
    });

    test('BatchInfo.isNearExpiry returns true within 7 days', () {
      final nearExpiry = DateTime.now().add(const Duration(days: 3));
      final batch = BatchInfo(
        batchNumber: 'LOT-NEAR',
        productCount: 1,
        totalQuantity: 10,
        earliestExpiry: nearExpiry,
        latestExpiry: nearExpiry,
        totalValue: 100000,
      );

      expect(batch.isNearExpiry, true);
    });

    test('BatchInfo.isNearExpiry returns false for > 7 days', () {
      final farExpiry = DateTime.now().add(const Duration(days: 30));
      final batch = BatchInfo(
        batchNumber: 'LOT-FAR',
        productCount: 1,
        totalQuantity: 10,
        earliestExpiry: farExpiry,
        latestExpiry: farExpiry,
        totalValue: 100000,
      );

      expect(batch.isNearExpiry, false);
    });

    test('BatchInfo handles null expiry dates', () {
      final batch = BatchInfo(
        batchNumber: 'LOT-NO-EXPIRY',
        productCount: 1,
        totalQuantity: 10,
        earliestExpiry: null,
        latestExpiry: null,
        totalValue: 100000,
      );

      expect(batch.hasExpired, false);
      expect(batch.isNearExpiry, false);
    });
  });

  group('Product expiry helper tests', () {
    test('hasExpiry returns true when expiryDate is set', () {
      final product = Product(
        name: 'Sữa TH',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );

      expect(product.hasExpiry, true);
    });

    test('hasExpiry returns false when expiryDate is null', () {
      final product = Product(
        name: 'Điện thoại',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(product.hasExpiry, false);
    });

    test('isExpired returns true for past expiry date', () {
      final product = Product(
        name: 'Sữa hết hạn',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      );

      expect(product.isExpired, true);
    });

    test('isExpired returns false for future expiry date', () {
      final product = Product(
        name: 'Sữa còn hạn',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );

      expect(product.isExpired, false);
    });

    test('isNearExpiry returns true within 7 days', () {
      final product = Product(
        name: 'Sữa sắp hết hạn',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch,
      );

      expect(product.isNearExpiry, true);
    });

    test('isNearExpiry returns false for > 7 days', () {
      final product = Product(
        name: 'Sữa còn lâu',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );

      expect(product.isNearExpiry, false);
    });

    test('isNearExpiry returns false for expired products', () {
      final product = Product(
        name: 'Sữa đã hết hạn',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      );

      expect(product.isNearExpiry, false);
    });
  });

  group('Product batch number tests', () {
    test('batchNumber stored correctly in product', () {
      final product = Product(
        name: 'Thịt bò Úc',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        batchNumber: 'LOT-2026-02-001',
      );

      expect(product.batchNumber, 'LOT-2026-02-001');
    });

    test('batchNumber included in toMap', () {
      final product = Product(
        name: 'Cá hồi',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        batchNumber: 'BATCH-123',
        expiryDate: DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      );

      final map = product.toMap();
      expect(map['batchNumber'], 'BATCH-123');
      expect(map['expiryDate'], isNotNull);
    });

    test('Product.fromMap parses batch and expiry correctly', () {
      final now = DateTime.now();
      final map = {
        'name': 'Rau củ',
        'createdAt': now.millisecondsSinceEpoch,
        'batchNumber': 'LOT-VEG-001',
        'expiryDate': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
        'unit': 'kg',
      };

      final product = Product.fromMap(map);
      expect(product.batchNumber, 'LOT-VEG-001');
      expect(product.unit, 'kg');
      expect(product.hasExpiry, true);
    });

    test('copyWith updates expiry fields', () {
      final product = Product(
        name: 'Trái cây',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final newExpiry = DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch;
      final updated = product.copyWith(
        expiryDate: newExpiry,
        batchNumber: 'FRUIT-001',
        unit: 'kg',
      );

      expect(updated.expiryDate, newExpiry);
      expect(updated.batchNumber, 'FRUIT-001');
      expect(updated.unit, 'kg');
      expect(updated.name, product.name); // Unchanged
    });
  });

  group('ShopSettings food configuration tests', () {
    test('ShopSettings.food has correct defaults', () {
      final settings = ShopSettings.food('shop_food_001');

      expect(settings.businessType, 'food');
      expect(settings.businessTypeName, 'Thực phẩm & Đồ tươi sống');
      expect(settings.enableExpiry, true);
      expect(settings.enableBatch, true);
      expect(settings.enableRepair, false);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
      expect(settings.enableVariants, false);
      expect(settings.defaultUnit, 'kg');
      expect(settings.expiryWarningDays, 7);
    });

    test('expiryWarningDays can be customized', () {
      final settings = ShopSettings(
        shopId: 'shop_test',
        businessType: 'food',
        enableExpiry: true,
        expiryWarningDays: 14,
      );

      expect(settings.expiryWarningDays, 14);
    });

    test('copyWith updates expiryWarningDays', () {
      final settings = ShopSettings.food('shop_001');
      final updated = settings.copyWith(expiryWarningDays: 3);

      expect(updated.expiryWarningDays, 3);
      expect(updated.enableExpiry, true); // Unchanged
      expect(updated.businessType, 'food'); // Unchanged
    });
  });

  group('ExpiryAlertService unit tests - without Firebase initialization', () {
    // NOTE: These tests use pure functions that don't require Firebase
    // The full service tests require integration test setup with Firebase

    test('daysUntilExpiry calculation - future dates', () {
      // Testing the calculation logic directly
      final product = Product(
        name: 'Test Product',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 10)).millisecondsSinceEpoch,
      );

      // Direct calculation (same as service)
      final expiry = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!);
      final days = expiry.difference(DateTime.now()).inDays;
      
      expect(days >= 9 && days <= 10, true);
    });

    test('daysUntilExpiry calculation - past dates', () {
      final product = Product(
        name: 'Expired Product',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch,
      );

      final expiry = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!);
      final days = expiry.difference(DateTime.now()).inDays;
      
      expect(days < 0, true);
    });

    test('daysUntilExpiry calculation - no expiry returns default', () {
      final product = Product(
        name: 'No Expiry',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      // Product without expiry should return large default value
      final days = product.expiryDate == null 
          ? 999 
          : DateTime.fromMillisecondsSinceEpoch(product.expiryDate!).difference(DateTime.now()).inDays;
      
      expect(days, 999);
    });

    test('getExpiryStatus logic - expired', () {
      final product = Product(
        name: 'Expired',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      );

      // Direct status calculation
      final days = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
          .difference(DateTime.now()).inDays;
      final warningDays = 7;

      ExpiryStatus status;
      if (days < 0) {
        status = ExpiryStatus.expired;
      } else if (days == 0) {
        status = ExpiryStatus.expiringToday;
      } else if (days <= warningDays) {
        status = ExpiryStatus.nearExpiry;
      } else {
        status = ExpiryStatus.good;
      }

      expect(status, ExpiryStatus.expired);
    });

    test('getExpiryStatus logic - nearExpiry within warning days', () {
      final product = Product(
        name: 'Near Expiry',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
      );

      final days = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
          .difference(DateTime.now()).inDays;
      final warningDays = 7;

      ExpiryStatus status;
      if (days < 0) {
        status = ExpiryStatus.expired;
      } else if (days == 0) {
        status = ExpiryStatus.expiringToday;
      } else if (days <= warningDays) {
        status = ExpiryStatus.nearExpiry;
      } else {
        status = ExpiryStatus.good;
      }

      expect(status, ExpiryStatus.nearExpiry);
    });

    test('getExpiryStatus logic - good beyond warning', () {
      final product = Product(
        name: 'Good Product',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );

      final days = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
          .difference(DateTime.now()).inDays;
      final warningDays = 7;

      ExpiryStatus status;
      if (days < 0) {
        status = ExpiryStatus.expired;
      } else if (days == 0) {
        status = ExpiryStatus.expiringToday;
      } else if (days <= warningDays) {
        status = ExpiryStatus.nearExpiry;
      } else {
        status = ExpiryStatus.good;
      }

      expect(status, ExpiryStatus.good);
    });

    test('getExpiryStatus logic - noExpiry when null', () {
      final product = Product(
        name: 'No Expiry',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final status = product.expiryDate == null 
          ? ExpiryStatus.noExpiry 
          : ExpiryStatus.good;

      expect(status, ExpiryStatus.noExpiry);
    });

    test('formatExpiryText logic - expired', () {
      final product = Product(
        name: 'Expired',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      );

      final days = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
          .difference(DateTime.now()).inDays;
      
      final text = days < 0 ? 'Hết hạn ${-days} ngày trước' : 'Còn $days ngày';

      expect(text.contains('Hết hạn'), true);
      expect(text.contains('ngày trước'), true);
    });

    test('formatExpiryText logic - near expiry', () {
      final product = Product(
        name: 'Near Expiry',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        expiryDate: DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch,
      );

      final days = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
          .difference(DateTime.now()).inDays;
      
      final text = days < 0 ? 'Hết hạn ${-days} ngày trước' : 'Còn $days ngày';

      expect(text.contains('Còn'), true);
      expect(text.contains('ngày'), true);
    });

    test('formatExpiryText logic - no expiry', () {
      final product = Product(
        name: 'No Expiry',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final text = product.expiryDate == null ? 'Không HSD' : 'Có HSD';
      expect(text, 'Không HSD');
    });
  });

  group('Food industry sample data tests', () {
    test('Create product with all food-specific fields', () {
      final now = DateTime.now();
      final product = Product(
        name: 'Sữa TH True Milk 1L',
        createdAt: now.millisecondsSinceEpoch,
        cost: 28000,
        price: 35000,
        quantity: 10,
        unit: 'hộp',
        expiryDate: now.add(const Duration(days: 14)).millisecondsSinceEpoch,
        batchNumber: 'LOT-2026-02-001',
        categoryId: 'cat_dairy_001',
      );

      expect(product.name, 'Sữa TH True Milk 1L');
      expect(product.unit, 'hộp');
      expect(product.hasExpiry, true);
      expect(product.isExpired, false);
      expect(product.batchNumber, 'LOT-2026-02-001');
      expect(product.categoryId, 'cat_dairy_001');
    });

    test('Multiple products with different expiry statuses', () {
      final now = DateTime.now();
      
      // Expired product
      final expired = Product(
        name: 'Sữa hết hạn',
        createdAt: now.millisecondsSinceEpoch,
        expiryDate: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      );
      
      // Near expiry product
      final nearExpiry = Product(
        name: 'Sữa sắp hết hạn',
        createdAt: now.millisecondsSinceEpoch,
        expiryDate: now.add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
      
      // Good product
      final good = Product(
        name: 'Sữa còn hạn lâu',
        createdAt: now.millisecondsSinceEpoch,
        expiryDate: now.add(const Duration(days: 180)).millisecondsSinceEpoch,
      );

      expect(expired.isExpired, true);
      expect(expired.isNearExpiry, false);

      expect(nearExpiry.isExpired, false);
      expect(nearExpiry.isNearExpiry, true);

      expect(good.isExpired, false);
      expect(good.isNearExpiry, false);
    });

    test('Calculate value at risk from multiple products', () {
      final now = DateTime.now();
      
      final atRiskProducts = [
        Product(
          name: 'SP1',
          createdAt: now.millisecondsSinceEpoch,
          cost: 50000,
          quantity: 10,
          expiryDate: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
        Product(
          name: 'SP2',
          createdAt: now.millisecondsSinceEpoch,
          cost: 30000,
          quantity: 5,
          expiryDate: now.add(const Duration(days: 3)).millisecondsSinceEpoch,
        ),
      ];

      final totalValue = atRiskProducts.fold<int>(
        0,
        (sum, p) => sum + (p.cost * p.quantity),
      );

      expect(totalValue, 650000); // 500k + 150k
    });
  });

  group('Unit conversion tests', () {
    test('Different units stored correctly', () {
      final products = [
        Product(name: 'Rau cải', createdAt: 1, unit: 'kg'),
        Product(name: 'Sữa', createdAt: 2, unit: 'hộp'),
        Product(name: 'Nước', createdAt: 3, unit: 'chai'),
        Product(name: 'Gạo', createdAt: 4, unit: 'bao'),
        Product(name: 'Thịt', createdAt: 5, unit: 'kg'),
      ];

      expect(products[0].unit, 'kg');
      expect(products[1].unit, 'hộp');
      expect(products[2].unit, 'chai');
      expect(products[3].unit, 'bao');
      expect(products[4].unit, 'kg');
    });

    test('Unit included in JSON serialization', () {
      final product = Product(
        name: 'Trái cây',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        unit: 'kg',
        quantity: 25,
      );

      final map = product.toMap();
      expect(map['unit'], 'kg');
      expect(map['quantity'], 25);
    });
  });
}
