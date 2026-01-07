import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/sale_order_model.dart';

void main() {
  group('SaleOrder.fromMap', () {
    test('fromMap with invalid totalPrice string', () {
      final map = {'totalPrice': 'abc', 'totalCost': 100, 'customerName': 'Test', 'phone': '123', 'productNames': 'Phone', 'productImeis': 'IMEI', 'sellerName': 'Seller', 'soldAt': 1234567890};
      final sale = SaleOrder.fromMap(map);
      expect(sale.totalPrice, 0);
    });

    test('fromMap with negative totalPrice - should normalize to 0', () {
      final map = {'totalPrice': -100, 'totalCost': 50, 'customerName': 'Test', 'phone': '123', 'productNames': 'Phone', 'productImeis': 'IMEI', 'sellerName': 'Seller', 'soldAt': 1234567890};
      final sale = SaleOrder.fromMap(map);
      expect(sale.totalPrice, 0); // Normalized from negative
    });

    test('fromMap with null soldAt', () {
      final map = {'totalPrice': 100, 'totalCost': 50, 'customerName': 'Test', 'phone': '123', 'productNames': 'Phone', 'productImeis': 'IMEI', 'sellerName': 'Seller', 'soldAt': null};
      final sale = SaleOrder.fromMap(map);
      expect(sale.soldAt, 0);
    });

    test('fromMap with invalid isInstallment', () {
      final map = {'totalPrice': 100, 'totalCost': 50, 'customerName': 'Test', 'phone': '123', 'productNames': 'Phone', 'productImeis': 'IMEI', 'sellerName': 'Seller', 'soldAt': 1234567890, 'isInstallment': 'true'};
      final sale = SaleOrder.fromMap(map);
      expect(sale.isInstallment, false);
    });
  });
}
