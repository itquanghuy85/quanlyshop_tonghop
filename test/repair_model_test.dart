import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/repair_model.dart';
import 'package:quanlyshop/models/repair_service_model.dart';

void main() {
  group('Repair Model Tests', () {
    test('totalCost should prefer stored canonical cost when present', () {
      final service1 = RepairService(serviceName: 'Service 1', cost: 100);
      final service2 = RepairService(serviceName: 'Service 2', cost: 200);
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        services: [service1, service2],
        cost: 450,
      );

      expect(repair.totalCost, 450);
      expect(repair.servicesCost, 300);
    });

    test('totalCost should fall back to services cost for legacy records', () {
      final service1 = RepairService(serviceName: 'Service 1', cost: 100);
      final service2 = RepairService(serviceName: 'Service 2', cost: 200);
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        services: [service1, service2],
        cost: 0,
      );

      expect(repair.totalCost, 300);
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

    test('toMap/fromMap should preserve attribution UIDs', () {
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        createdByUid: 'creator-1',
        repairedByUid: 'tech-1',
        deliveredByUid: 'manager-1',
      );

      final mapped = repair.toMap();
      final restored = Repair.fromMap(mapped);

      expect(restored.createdByUid, 'creator-1');
      expect(restored.repairedByUid, 'tech-1');
      expect(restored.deliveredByUid, 'manager-1');
    });
  });
}