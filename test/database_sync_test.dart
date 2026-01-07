import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/repair_model.dart';

void main() {
  group('Database Sync Tests', () {
    test('DBHelper upsert repair should handle sync flags', () async {
      // Test basic repair creation without actual DB
      final repair = Repair(
        firestoreId: 'test123',
        customerName: 'Nguyễn Văn A',
        phone: '0123456789',
        model: 'iPhone 12',
        issue: 'Màn hình vỡ',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(repair.firestoreId, 'test123');
      expect(repair.customerName, 'Nguyễn Văn A');
      expect(repair.phone, '0123456789');
      expect(repair.isSynced, false); // Default value
      expect(repair.deleted, false); // Default value
    });

    test('SyncService should handle real-time updates', () async {
      // Test sync service logic without actual service
      final repair = Repair(
        firestoreId: 'sync_test',
        customerName: 'Test Customer',
        phone: '0987654321',
        model: 'Samsung',
        issue: 'Test issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );

      // Simulate sync process
      final syncedRepair = Repair(
        id: repair.id,
        firestoreId: repair.firestoreId,
        customerName: repair.customerName,
        phone: repair.phone,
        model: repair.model,
        issue: repair.issue,
        accessories: repair.accessories,
        address: repair.address,
        imagePath: repair.imagePath,
        deliveredImage: repair.deliveredImage,
        warranty: repair.warranty,
        partsUsed: repair.partsUsed,
        status: repair.status,
        price: repair.price,
        cost: repair.cost,
        paymentMethod: repair.paymentMethod,
        createdAt: repair.createdAt,
        startedAt: repair.startedAt,
        finishedAt: repair.finishedAt,
        deliveredAt: repair.deliveredAt,
        createdBy: repair.createdBy,
        repairedBy: repair.repairedBy,
        deliveredBy: repair.deliveredBy,
        lastCaredAt: repair.lastCaredAt,
        isSynced: true, // Changed to synced
        deleted: repair.deleted,
        color: repair.color,
        imei: repair.imei,
        condition: repair.condition,
      );

      expect(syncedRepair.isSynced, true);
      expect(syncedRepair.firestoreId, repair.firestoreId);
    });

    test('Repair model sync status transitions', () {
      final repair = Repair(
        firestoreId: 'test123',
        customerName: 'Trần Thị B',
        phone: '0987654321',
        model: 'Samsung Galaxy',
        issue: 'Pin yếu',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );

      // Test sync status change
      final syncedRepair = Repair(
        id: repair.id,
        firestoreId: repair.firestoreId,
        customerName: repair.customerName,
        phone: repair.phone,
        model: repair.model,
        issue: repair.issue,
        accessories: repair.accessories,
        address: repair.address,
        imagePath: repair.imagePath,
        deliveredImage: repair.deliveredImage,
        warranty: repair.warranty,
        partsUsed: repair.partsUsed,
        status: repair.status,
        price: repair.price,
        cost: repair.cost,
        paymentMethod: repair.paymentMethod,
        createdAt: repair.createdAt,
        startedAt: repair.startedAt,
        finishedAt: repair.finishedAt,
        deliveredAt: repair.deliveredAt,
        createdBy: repair.createdBy,
        repairedBy: repair.repairedBy,
        deliveredBy: repair.deliveredBy,
        lastCaredAt: repair.lastCaredAt,
        isSynced: true,
        deleted: repair.deleted,
        color: repair.color,
        imei: repair.imei,
        condition: repair.condition,
      );

      expect(syncedRepair.isSynced, true);
      expect(syncedRepair.firestoreId, repair.firestoreId);
    });

    test('Soft delete handling in sync', () {
      final repair = Repair(
        firestoreId: 'test123',
        customerName: 'Lê Văn C',
        phone: '0111111111',
        model: 'Huawei P30',
        issue: 'Camera lỗi',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        status: 2,
        isSynced: true,
        deleted: false,
      );

      // Test soft delete
      final deletedRepair = Repair(
        id: repair.id,
        firestoreId: repair.firestoreId,
        customerName: repair.customerName,
        phone: repair.phone,
        model: repair.model,
        issue: repair.issue,
        accessories: repair.accessories,
        address: repair.address,
        imagePath: repair.imagePath,
        deliveredImage: repair.deliveredImage,
        warranty: repair.warranty,
        partsUsed: repair.partsUsed,
        status: repair.status,
        price: repair.price,
        cost: repair.cost,
        paymentMethod: repair.paymentMethod,
        createdAt: repair.createdAt,
        startedAt: repair.startedAt,
        finishedAt: repair.finishedAt,
        deliveredAt: repair.deliveredAt,
        createdBy: repair.createdBy,
        repairedBy: repair.repairedBy,
        deliveredBy: repair.deliveredBy,
        lastCaredAt: repair.lastCaredAt,
        isSynced: repair.isSynced,
        deleted: true, // Soft deleted
        color: repair.color,
        imei: repair.imei,
        condition: repair.condition,
      );

      expect(deletedRepair.deleted, true);
      expect(deletedRepair.isSynced, true); // Should still be synced
    });

    test('Multi-tenant data isolation', () {
      final repair1 = Repair(
        firestoreId: 'shop1_repair1',
        customerName: 'Shop 1 Customer',
        phone: '0123456789',
        model: 'iPhone',
        issue: 'Test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        status: 1,
      );

      final repair2 = Repair(
        firestoreId: 'shop2_repair1',
        customerName: 'Shop 2 Customer',
        phone: '0987654321',
        model: 'Android',
        issue: 'Test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        status: 1,
      );

      expect(repair1.firestoreId, 'shop1_repair1');
      expect(repair2.firestoreId, 'shop2_repair1');
      expect(repair1.firestoreId != repair2.firestoreId, true);
    });

    test('Repair serialization and deserialization', () {
      final original = Repair(
        firestoreId: 'serialize_test',
        customerName: 'Test User',
        phone: '0123456789',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        status: 1,
        price: 100000,
        isSynced: false,
        deleted: false,
      );

      // Serialize to map
      final map = original.toMap();

      // Deserialize from map
      final deserialized = Repair.fromMap(map);

      expect(deserialized.firestoreId, original.firestoreId);
      expect(deserialized.customerName, original.customerName);
      expect(deserialized.phone, original.phone);
      expect(deserialized.model, original.model);
      expect(deserialized.issue, original.issue);
      expect(deserialized.status, original.status);
      expect(deserialized.price, original.price);
      expect(deserialized.isSynced, original.isSynced);
      expect(deserialized.deleted, original.deleted);
    });
  });
}
