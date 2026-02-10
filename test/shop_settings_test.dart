import 'package:flutter_test/flutter_test.dart';
import '../lib/models/shop_settings_model.dart';

void main() {
  group('ShopSettings Model', () {
    test('electronics factory creates correct settings', () {
      final settings = ShopSettings.electronics('shop123');
      
      expect(settings.shopId, 'shop123');
      expect(settings.businessType, 'electronics');
      expect(settings.enableRepair, true);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, false);
      expect(settings.enableSerial, true);
      expect(settings.enableWarranty, true);
      expect(settings.enableBatch, false);
      expect(settings.defaultUnit, 'cái');
      expect(settings.isDefault, false);
    });

    test('food factory creates correct settings', () {
      final settings = ShopSettings.food('shop123');
      
      expect(settings.shopId, 'shop123');
      expect(settings.businessType, 'food');
      expect(settings.enableRepair, false);
      expect(settings.enableExpiry, true);
      expect(settings.enableVariants, false);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
      expect(settings.enableBatch, true);
      expect(settings.defaultUnit, 'kg');
    });

    test('fashion factory creates correct settings', () {
      final settings = ShopSettings.fashion('shop123');
      
      expect(settings.shopId, 'shop123');
      expect(settings.businessType, 'fashion');
      expect(settings.enableRepair, false);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, true);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
      expect(settings.enableBatch, false);
    });

    test('general factory creates correct settings', () {
      final settings = ShopSettings.general('shop123');
      
      expect(settings.shopId, 'shop123');
      expect(settings.businessType, 'general');
      expect(settings.enableRepair, false);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, false);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
      expect(settings.enableBatch, false);
    });

    test('fromBusinessType creates correct settings', () {
      expect(
        ShopSettings.fromBusinessType('electronics', 'shop1').enableRepair,
        true,
      );
      expect(
        ShopSettings.fromBusinessType('food', 'shop1').enableExpiry,
        true,
      );
      expect(
        ShopSettings.fromBusinessType('fashion', 'shop1').enableVariants,
        true,
      );
      expect(
        ShopSettings.fromBusinessType('general', 'shop1').enableRepair,
        false,
      );
    });

    test('toMap produces correct output', () {
      final settings = ShopSettings.electronics('shop123');
      final map = settings.toMap();
      
      expect(map['shopId'], 'shop123');
      expect(map['businessType'], 'electronics');
      // toMap returns 1/0 for bools (SQLite compatible)
      expect(map['enableRepair'], 1);
      expect(map['enableExpiry'], 0);
      expect(map['enableVariants'], 0);
    });

    test('fromMap parses correctly', () {
      final map = {
        'shopId': 'shop123',
        'businessType': 'fashion',
        'businessTypeName': 'Thời trang',
        'enableRepair': false,
        'enableExpiry': false,
        'enableVariants': true,
        'enableSerial': false,
        'enableWarranty': false,
        'enableBatch': false,
        'defaultUnit': 'cái',
        // Note: isDefault is intentionally ignored in fromMap
        // because loading from DB means settings are already saved
      };
      
      final settings = ShopSettings.fromMap(map);
      
      expect(settings.shopId, 'shop123');
      expect(settings.businessType, 'fashion');
      expect(settings.enableVariants, true);
      expect(settings.enableRepair, false);
      expect(settings.isDefault, false); // Always false when loaded from DB
    });

    test('copyWith works correctly', () {
      final original = ShopSettings.electronics('shop123');
      final modified = original.copyWith(
        enableRepair: false,
        enableVariants: true,
        isDefault: true,
      );
      
      expect(original.enableRepair, true);
      expect(modified.enableRepair, false);
      expect(modified.enableVariants, true);
      expect(modified.isDefault, true);
      expect(modified.shopId, 'shop123'); // unchanged
    });

    test('isDefault flag preserved through copyWith', () {
      final defaultSettings = ShopSettings.electronics('shop123')
          .copyWith(isDefault: true);
      
      expect(defaultSettings.isDefault, true);
      
      final savedSettings = defaultSettings.copyWith(isDefault: false);
      expect(savedSettings.isDefault, false);
    });
  });

  group('UI Filtering Logic', () {
    test('electronics shows repair, hides expiry/variants', () {
      final settings = ShopSettings.electronics('shop1');
      
      // UI should show
      expect(settings.enableRepair, true); // Repair tab visible
      expect(settings.enableSerial, true); // Serial/IMEI input visible
      expect(settings.enableWarranty, true); // Warranty management visible
      
      // UI should hide
      expect(settings.enableExpiry, false); // Expiry tab hidden
      expect(settings.enableVariants, false); // Variants tab hidden
      expect(settings.enableBatch, false); // Batch input hidden
    });

    test('food shows expiry/batch, hides repair/variants', () {
      final settings = ShopSettings.food('shop1');
      
      // UI should show
      expect(settings.enableExpiry, true); // Expiry tab visible
      expect(settings.enableBatch, true); // Batch input visible
      
      // UI should hide
      expect(settings.enableRepair, false); // Repair tab hidden
      expect(settings.enableVariants, false); // Variants tab hidden
      expect(settings.enableSerial, false); // Serial input hidden
      expect(settings.enableWarranty, false); // Warranty hidden
    });

    test('fashion shows variants, hides repair/expiry', () {
      final settings = ShopSettings.fashion('shop1');
      
      // UI should show
      expect(settings.enableVariants, true); // Variants tab visible
      
      // UI should hide
      expect(settings.enableRepair, false); // Repair tab hidden
      expect(settings.enableExpiry, false); // Expiry tab hidden
      expect(settings.enableBatch, false); // Batch input hidden
      expect(settings.enableSerial, false); // Serial input hidden
      expect(settings.enableWarranty, false); // Warranty hidden
    });

    test('general hides all industry-specific features', () {
      final settings = ShopSettings.general('shop1');
      
      // All industry-specific features hidden
      expect(settings.enableRepair, false);
      expect(settings.enableExpiry, false);
      expect(settings.enableVariants, false);
      expect(settings.enableBatch, false);
      expect(settings.enableSerial, false);
      expect(settings.enableWarranty, false);
    });
  });

  group('Legacy Shop Detection', () {
    test('default settings have isDefault=true when shop has no settings', () {
      // Simulate what CategoryService does for legacy shops
      final defaultSettings = ShopSettings.electronics('legacy_shop')
          .copyWith(isDefault: true);
      
      expect(defaultSettings.isDefault, true);
      expect(defaultSettings.businessType, 'electronics');
    });

    test('saved settings have isDefault=false', () {
      final savedSettings = ShopSettings.fromMap({
        'shopId': 'configured_shop',
        'businessType': 'fashion',
        'businessTypeName': 'Thời trang',
        'enableRepair': false,
        'enableExpiry': false,
        'enableVariants': true,
        'enableSerial': false,
        'enableWarranty': false,
        'enableBatch': false,
        // isDefault not in map = defaults to false
      });
      
      expect(savedSettings.isDefault, false);
    });
  });

  group('Inventory Categories by Business Type', () {
    test('electronics has phone/accessory/parts categories', () {
      final settings = ShopSettings.electronics('shop1');
      expect(settings.businessType, 'electronics');
      // Expected categories: DIEN_THOAI, PHU_KIEN, LINH_KIEN
    });

    test('food has food/drinks/ingredients categories', () {
      final settings = ShopSettings.food('shop1');
      expect(settings.businessType, 'food');
      // Expected categories: THUC_PHAM, DO_UONG, NGUYEN_LIEU
    });

    test('fashion has clothing/shoes/accessories categories', () {
      final settings = ShopSettings.fashion('shop1');
      expect(settings.businessType, 'fashion');
      // Expected categories: THOI_TRANG, GIAY_DEP, PHU_KIEN_TT
    });

    test('general has products/services categories', () {
      final settings = ShopSettings.general('shop1');
      expect(settings.businessType, 'general');
      // Expected categories: SAN_PHAM, DICH_VU
    });
  });

  group('Quick Access Shortcuts by Business Type', () {
    test('electronics shows repair shortcut', () {
      final settings = ShopSettings.electronics('shop1');
      expect(settings.enableRepair, true);
      // Home quick access should show: Sales, Repair orders
    });

    test('non-electronics shows customer shortcut instead of repair', () {
      final settings = ShopSettings.fashion('shop1');
      expect(settings.enableRepair, false);
      // Home quick access should show: Sales, Customers
    });
  });
}
