import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/repair_model.dart';

void main() {
  group('Network Sync Model Tests', () {
    test('Repair model should serialize correctly', () {
      final repair = Repair(
        customerName: 'Test Customer',
        phone: '0123456789',
        model: 'iPhone 12',
        issue: 'Màn hình vỡ',
        status: 1,
        price: 1000000,
        cost: 500000,
        createdAt: 1640995200000, // 2022-01-01
      );

      final map = repair.toMap();
      final restored = Repair.fromMap(map);

      expect(restored.customerName, 'Test Customer');
      expect(restored.phone, '0123456789');
      expect(restored.status, 1);
      expect(restored.price, 1000000);
      expect(restored.cost, 500000);
      expect(restored.createdAt, 1640995200000);
    });

    test('Repair model should handle sync status', () {
      final unsyncedRepair = Repair(
        customerName: 'Unsynced',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        isSynced: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final syncedRepair = Repair(
        id: unsyncedRepair.id,
        firestoreId: 'test_id',
        customerName: unsyncedRepair.customerName,
        phone: unsyncedRepair.phone,
        model: unsyncedRepair.model,
        issue: unsyncedRepair.issue,
        accessories: unsyncedRepair.accessories,
        address: unsyncedRepair.address,
        imagePath: unsyncedRepair.imagePath,
        deliveredImage: unsyncedRepair.deliveredImage,
        warranty: unsyncedRepair.warranty,
        partsUsed: unsyncedRepair.partsUsed,
        status: unsyncedRepair.status,
        price: unsyncedRepair.price,
        cost: unsyncedRepair.cost,
        paymentMethod: unsyncedRepair.paymentMethod,
        createdAt: unsyncedRepair.createdAt,
        startedAt: unsyncedRepair.startedAt,
        finishedAt: unsyncedRepair.finishedAt,
        deliveredAt: unsyncedRepair.deliveredAt,
        createdBy: unsyncedRepair.createdBy,
        repairedBy: unsyncedRepair.repairedBy,
        deliveredBy: unsyncedRepair.deliveredBy,
        lastCaredAt: unsyncedRepair.lastCaredAt,
        isSynced: true, // Now synced
        deleted: unsyncedRepair.deleted,
        color: unsyncedRepair.color,
        imei: unsyncedRepair.imei,
        condition: unsyncedRepair.condition,
      );

      expect(unsyncedRepair.isSynced, false);
      expect(syncedRepair.isSynced, true);
      expect(syncedRepair.firestoreId, 'test_id');
    });

    test('Repair status should follow correct workflow', () {
      // Test status transitions
      final statuses = [1, 2, 3, 4]; // Nhận -> Sửa -> Xong -> Giao

      for (final status in statuses) {
        final repair = Repair(
          customerName: 'Status Test',
          phone: '0123456789',
          model: 'Test Phone',
          issue: 'Test issue',
          status: status,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        expect(repair.status, status);
        expect(repair.status, isA<int>());
        expect(repair.status, greaterThanOrEqualTo(1));
        expect(repair.status, lessThanOrEqualTo(4));
      }
    });

    test('Repair should handle Vietnamese text correctly', () {
      final repair = Repair(
        customerName: 'Khách hàng Việt Nam',
        phone: '0123456789',
        model: 'Điện thoại Samsung',
        issue: 'Màn hình bị vỡ, cần thay thế',
        accessories: 'Ốp lưng, kính cường lực',
        address: '123 Đường ABC, Quận 1, TP.HCM',
        warranty: 'Bảo hành 12 tháng',
        partsUsed: 'Màn hình OLED, kính cường lực',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final map = repair.toMap();
      final restored = Repair.fromMap(map);

      expect(restored.customerName, 'Khách hàng Việt Nam');
      expect(restored.issue, 'Màn hình bị vỡ, cần thay thế');
      expect(restored.accessories, 'Ốp lưng, kính cường lực');
      expect(restored.address, '123 Đường ABC, Quận 1, TP.HCM');
    });

    test('Repair should handle special characters', () {
      final repair = Repair(
        customerName: 'Customer @#\$%^&*()',
        phone: '0123456789',
        model: 'Phone !@#\$%^&*()',
        issue: 'Issue with special chars: @#\$%^&*()',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final map = repair.toMap();
      final restored = Repair.fromMap(map);

      expect(restored.customerName, 'Customer @#\$%^&*()');
      expect(restored.model, 'Phone !@#\$%^&*()');
      expect(restored.issue, 'Issue with special chars: @#\$%^&*()');
    });

    test('Multiple repairs should be independent', () {
      final repair1 = Repair(
        customerName: 'Customer 1',
        phone: '0111111111',
        model: 'Phone 1',
        issue: 'Issue 1',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final repair2 = Repair(
        customerName: 'Customer 2',
        phone: '0222222222',
        model: 'Phone 2',
        issue: 'Issue 2',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(repair1.customerName, isNot(repair2.customerName));
      expect(repair1.phone, isNot(repair2.phone));
      expect(repair1.model, isNot(repair2.model));
      expect(repair1.issue, isNot(repair2.issue));
    });

    test('Repair timestamps should be valid', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final repair = Repair(
        customerName: 'Timestamp Test',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        createdAt: now,
      );

      expect(repair.createdAt, now);
      expect(repair.createdAt, greaterThan(0));
      expect(repair.createdAt, lessThan(DateTime.now().millisecondsSinceEpoch + 1000));
    });
  });

  group('Sync Logic Tests', () {
    test('Sync status should be properly tracked', () {
      // Test sync flag transitions
      final states = [false, true];

      for (final isSynced in states) {
        final repair = Repair(
          customerName: 'Sync Test',
          phone: '0123456789',
          model: 'Test Phone',
          issue: 'Test issue',
          isSynced: isSynced,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        expect(repair.isSynced, isSynced);
      }
    });

    test('Firestore ID should be handled correctly', () {
      final repairWithoutId = Repair(
        customerName: 'No ID',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final repairWithId = Repair(
        firestoreId: 'test_firestore_id',
        customerName: 'With ID',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(repairWithoutId.firestoreId, isNull);
      expect(repairWithId.firestoreId, 'test_firestore_id');
    });

    test('Deleted flag should work correctly', () {
      final activeRepair = Repair(
        customerName: 'Active',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        deleted: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final deletedRepair = Repair(
        customerName: 'Deleted',
        phone: '0123456789',
        model: 'Test Phone',
        issue: 'Test issue',
        deleted: true,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(activeRepair.deleted, false);
      expect(deletedRepair.deleted, true);
    });
  });
}
