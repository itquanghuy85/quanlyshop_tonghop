import 'package:flutter_test/flutter_test.dart';
import 'package:shop_new/models/repair_model.dart';
import 'package:shop_new/models/repair_service_model.dart';

void main() {
  group('Repair Model Tests', () {
    test('totalCost should return sum of services cost when services exist', () {
      final service1 = RepairService(serviceName: 'Service 1', cost: 100);
      final service2 = RepairService(serviceName: 'Service 2', cost: 200);
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        services: [service1, service2],
        cost: 50, // Old cost field
      );

      expect(repair.totalCost, 300); // Should be 100 + 200, not 50
    });

    test('totalCost should return old cost field when no services', () {
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        services: [], // Empty services
        cost: 150,
      );

      expect(repair.totalCost, 150);
    });

    test('toMap should include services as JSON string', () {
      final service = RepairService(serviceName: 'Test Service', cost: 100);
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        services: [service],
      );

      final map = repair.toMap();
      expect(map['services'], isNotNull);
      expect(map['services'], contains('Test Service'));
    });
  });
}