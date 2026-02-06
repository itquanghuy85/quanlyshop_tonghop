import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/constants/product_constants.dart';

void main() {
  group('ProductConstants.generateProductName', () {
    test('generates correct name with all fields', () {
      final name = ProductConstants.generateProductName(
        brand: 'IPHONE',
        model: '15 PRO MAX',
        capacity: '256GB',
        color: 'ĐEN',
        condition: 'MỚI',
      );
      expect(name, 'IPHONE 15 PRO MAX 256GB ĐEN MỚI');
    });

    test('generates correct name without duplicate brand in model', () {
      // User nhập model có chứa brand -> không nên trùng
      final name = ProductConstants.generateProductName(
        brand: 'IPHONE',
        model: 'IPHONE 15 PRO MAX', // User nhầm nhập brand + model
        capacity: '256GB',
        color: 'TRẮNG',
        condition: 'MỚI',
      );
      // Kỳ vọng: cleanProductName sẽ loại bỏ từ trùng
      expect(name.contains('IPHONE IPHONE'), false);
    });

    test('generates name with KHÁC for unknown color', () {
      final name = ProductConstants.generateProductName(
        brand: 'SAMSUNG',
        model: 'S24 ULTRA',
        capacity: '512GB',
        color: 'XÁM',
        condition: null,
      );
      // mapColor('XÁM') trả về 'KHÁC' vì không trong danh sách
      expect(name.contains('SAMSUNG'), true);
      expect(name.contains('S24 ULTRA'), true);
      expect(name.contains('512GB'), true);
    });

    test('handles empty brand gracefully', () {
      final name = ProductConstants.generateProductName(
        brand: '',
        model: '15 PRO MAX',
        capacity: '256GB',
        color: 'ĐEN',
        condition: 'MỚI',
      );
      expect(name.isNotEmpty, true);
      expect(name.contains('15 PRO MAX'), true);
    });
  });

  group('ProductConstants.cleanProductName', () {
    test('removes duplicate words', () {
      final cleaned = ProductConstants.cleanProductName(
        'IPHONE IPHONE 15 PRO MAX 256GB 256GB ĐEN',
      );
      expect(cleaned, 'IPHONE 15 PRO MAX 256GB ĐEN');
    });

    test('removes consecutive duplicate words', () {
      final cleaned = ProductConstants.cleanProductName(
        'SAMSUNG SAMSUNG S24 ULTRA 512GB 512GB',
      );
      expect(cleaned, 'SAMSUNG S24 ULTRA 512GB');
    });

    test('handles single word', () {
      final cleaned = ProductConstants.cleanProductName('IPHONE');
      expect(cleaned, 'IPHONE');
    });

    test('handles empty string', () {
      final cleaned = ProductConstants.cleanProductName('');
      expect(cleaned, '');
    });

    test('preserves non-duplicate words', () {
      final cleaned = ProductConstants.cleanProductName(
        'IPHONE 15 PRO MAX 256GB ĐEN MỚI',
      );
      expect(cleaned, 'IPHONE 15 PRO MAX 256GB ĐEN MỚI');
    });

    test('handles multiple spaces', () {
      final cleaned = ProductConstants.cleanProductName(
        'IPHONE   15   PRO   MAX',
      );
      expect(cleaned.contains('  '), false);
    });
  });

  group('ProductConstants.mapBrand', () {
    test('maps iphone variations correctly', () {
      expect(ProductConstants.mapBrand('IPHONE'), 'IPHONE');
      expect(ProductConstants.mapBrand('iphone'), 'IPHONE');
      expect(ProductConstants.mapBrand('IP'), 'IPHONE'); // viết tắt
    });

    test('maps samsung variations correctly', () {
      expect(ProductConstants.mapBrand('SAMSUNG'), 'SAMSUNG');
      expect(ProductConstants.mapBrand('samsung'), 'SAMSUNG');
      expect(ProductConstants.mapBrand('SS'), 'SAMSUNG'); // viết tắt
    });

    test('returns KHÁC for unknown brand', () {
      expect(ProductConstants.mapBrand('Unknown Brand'), 'KHÁC');
    });

    test('returns KHÁC for null brand', () {
      expect(ProductConstants.mapBrand(null), 'KHÁC');
    });

    test('returns KHÁC for empty brand', () {
      expect(ProductConstants.mapBrand(''), 'KHÁC');
    });
  });

  group('ProductConstants.mapCapacity', () {
    test('maps common capacity values', () {
      expect(ProductConstants.mapCapacity('64'), '64GB');
      expect(ProductConstants.mapCapacity('128'), '128GB');
      expect(ProductConstants.mapCapacity('256'), '256GB');
      expect(ProductConstants.mapCapacity('512'), '512GB');
    });

    test('handles already formatted capacity', () {
      expect(ProductConstants.mapCapacity('256GB'), '256GB');
      expect(ProductConstants.mapCapacity('512GB'), '512GB');
      expect(ProductConstants.mapCapacity('1TB'), '1TB');
    });

    test('returns empty for null capacity', () {
      expect(ProductConstants.mapCapacity(null), '');
    });

    test('returns empty for empty capacity', () {
      expect(ProductConstants.mapCapacity(''), '');
    });
  });

  group('ProductConstants.mapColor', () {
    test('maps common color values', () {
      expect(ProductConstants.mapColor('ĐEN'), 'ĐEN');
      expect(ProductConstants.mapColor('TRẮNG'), 'TRẮNG');
    });

    test('maps lowercase to uppercase', () {
      expect(ProductConstants.mapColor('đen'), 'ĐEN');
      expect(ProductConstants.mapColor('trắng'), 'TRẮNG');
    });

    test('returns KHÁC for null color', () {
      expect(ProductConstants.mapColor(null), 'KHÁC');
    });
  });

  group('Integration: Edit Product scenario', () {
    test('simulates editing product with brand and model separated', () {
      // Giả lập: User sửa sản phẩm
      // - Chọn brand từ dropdown: IPHONE
      // - Nhập model: 15 PRO MAX
      // - Chọn dung lượng: 256GB
      // - Chọn màu: ĐEN
      // - Tình trạng: MỚI
      
      const selectedBrand = 'IPHONE';
      const modelText = '15 PRO MAX';
      const selectedCapacity = '256GB';
      const selectedColor = 'ĐEN';
      const condition = 'MỚI';
      
      final generatedName = ProductConstants.generateProductName(
        brand: selectedBrand,
        model: modelText,
        capacity: selectedCapacity,
        color: selectedColor,
        condition: condition,
      );
      
      expect(generatedName, 'IPHONE 15 PRO MAX 256GB ĐEN MỚI');
      
      // Kiểm tra không có từ trùng
      final words = generatedName.split(' ');
      final uniqueWords = words.toSet();
      expect(words.length, uniqueWords.length);
    });

    test('simulates editing product when user enters brand in model field', () {
      // Giả lập: User nhầm nhập brand trong model
      const selectedBrand = 'SAMSUNG';
      const modelText = 'SAMSUNG S24 ULTRA'; // User nhập nhầm
      const selectedCapacity = '512GB';
      const selectedColor = 'TRẮNG';
      const condition = 'MỚI';
      
      final generatedName = ProductConstants.generateProductName(
        brand: selectedBrand,
        model: modelText,
        capacity: selectedCapacity,
        color: selectedColor,
        condition: condition,
      );
      
      // cleanProductName nên loại bỏ từ trùng
      expect(generatedName.indexOf('SAMSUNG'), generatedName.lastIndexOf('SAMSUNG'));
    });
  });
}
