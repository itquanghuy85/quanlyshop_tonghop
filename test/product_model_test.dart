import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/product_model.dart';

void main() {
  group('Product.fromMap', () {
    test('fromMap with negative quantity', () {
      final map = {'name': 'Phone', 'cost': 100, 'price': 200, 'condition': 'New', 'createdAt': 1234567890, 'quantity': -5};
      final product = Product.fromMap(map);
      expect(product.quantity, 0);
    });

    test('fromMap with invalid price', () {
      final map = {'name': 'Phone', 'cost': 100, 'price': 'invalid', 'condition': 'New', 'createdAt': 1234567890, 'quantity': 1};
      final product = Product.fromMap(map);
      expect(product.price, 0);
    });

    test('fromMap with invalid createdAt', () {
      final map = {'name': 'Phone', 'cost': 100, 'price': 200, 'condition': 'New', 'createdAt': 'timestamp', 'quantity': 1};
      final product = Product.fromMap(map);
      expect(product.createdAt, 0);
    });
  });

  group('Product model field', () {
    test('Product with model field', () {
      final product = Product(
        name: 'iPhone 12',
        model: 'A2172',
        imei: '12345',
        brand: 'Apple',
        cost: 1000,
        price: 1200,
        condition: 'New',
        quantity: 1,
        createdAt: 1234567890,
      );
      expect(product.model, 'A2172');
      expect(product.imei, '12345');
    });

    test('Product toMap includes model field', () {
      final product = Product(
        name: 'iPhone 12',
        model: 'A2172',
        imei: '12345',
        brand: 'Apple',
        cost: 1000,
        price: 1200,
        condition: 'New',
        quantity: 1,
        createdAt: 1234567890,
      );
      final map = product.toMap();
      expect(map['model'], 'A2172');
      expect(map['imei'], '12345');
    });

    test('Product fromMap with model field', () {
      final map = {
        'name': 'iPhone 12',
        'model': 'A2172',
        'imei': '12345',
        'brand': 'Apple',
        'cost': 1000,
        'price': 1200,
        'condition': 'New',
        'quantity': 1,
        'createdAt': 1234567890,
      };
      final product = Product.fromMap(map);
      expect(product.model, 'A2172');
      expect(product.imei, '12345');
    });
  });
}
