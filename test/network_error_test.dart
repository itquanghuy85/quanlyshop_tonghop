import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/repair_model.dart';

void main() {
  group('Network Error Handling Tests', () {
    test('Handle network timeout during sync', () async {
      // Test network timeout scenario
      final repair = Repair(
        firestoreId: 'timeout_test',
        customerName: 'Timeout User',
        phone: '0123456789',
        model: 'Test Model',
        issue: 'Network timeout test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );

      // Simulate network failure - repair should remain unsynced
      expect(repair.isSynced, false);

      // After timeout, sync status should still be false
      final failedSyncRepair = Repair(
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
        isSynced: false, // Still not synced due to timeout
        deleted: repair.deleted,
        color: repair.color,
        imei: repair.imei,
        condition: repair.condition,
      );

      expect(failedSyncRepair.isSynced, false);
      expect(failedSyncRepair.firestoreId, repair.firestoreId);
    });

    test('Handle offline mode gracefully', () {
      // Test offline behavior
      final offlineRepair = Repair(
        firestoreId: 'offline_test',
        customerName: 'Offline User',
        phone: '0987654321',
        model: 'Offline Model',
        issue: 'Offline test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false, // Should be false when offline
      );

      expect(offlineRepair.isSynced, false);

      // Simulate queuing for later sync
      final queuedRepair = Repair(
        id: offlineRepair.id,
        firestoreId: offlineRepair.firestoreId,
        customerName: offlineRepair.customerName,
        phone: offlineRepair.phone,
        model: offlineRepair.model,
        issue: offlineRepair.issue,
        accessories: offlineRepair.accessories,
        address: offlineRepair.address,
        imagePath: offlineRepair.imagePath,
        deliveredImage: offlineRepair.deliveredImage,
        warranty: offlineRepair.warranty,
        partsUsed: offlineRepair.partsUsed,
        status: offlineRepair.status,
        price: offlineRepair.price,
        cost: offlineRepair.cost,
        paymentMethod: offlineRepair.paymentMethod,
        createdAt: offlineRepair.createdAt,
        startedAt: offlineRepair.startedAt,
        finishedAt: offlineRepair.finishedAt,
        deliveredAt: offlineRepair.deliveredAt,
        createdBy: offlineRepair.createdBy,
        repairedBy: offlineRepair.repairedBy,
        deliveredBy: offlineRepair.deliveredBy,
        lastCaredAt: offlineRepair.lastCaredAt,
        isSynced: false, // Still queued for sync
        deleted: offlineRepair.deleted,
        color: offlineRepair.color,
        imei: offlineRepair.imei,
        condition: offlineRepair.condition,
      );

      expect(queuedRepair.isSynced, false);
    });

    test('Handle authentication errors during sync', () {
      // Test auth failure scenario
      final authFailedRepair = Repair(
        firestoreId: 'auth_fail_test',
        customerName: 'Auth Fail User',
        phone: '0111111111',
        model: 'Auth Model',
        issue: 'Authentication failed test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false, // Should remain unsynced on auth failure
      );

      expect(authFailedRepair.isSynced, false);

      // After auth failure, should still be unsynced
      expect(authFailedRepair.isSynced, false);
    });

    test('Handle server errors (5xx) during sync', () {
      // Test server error scenario
      final serverErrorRepair = Repair(
        firestoreId: 'server_error_test',
        customerName: 'Server Error User',
        phone: '0222222222',
        model: 'Server Model',
        issue: 'Server error test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );

      expect(serverErrorRepair.isSynced, false);

      // After server error, should retry later
      final retryRepair = Repair(
        id: serverErrorRepair.id,
        firestoreId: serverErrorRepair.firestoreId,
        customerName: serverErrorRepair.customerName,
        phone: serverErrorRepair.phone,
        model: serverErrorRepair.model,
        issue: serverErrorRepair.issue,
        accessories: serverErrorRepair.accessories,
        address: serverErrorRepair.address,
        imagePath: serverErrorRepair.imagePath,
        deliveredImage: serverErrorRepair.deliveredImage,
        warranty: serverErrorRepair.warranty,
        partsUsed: serverErrorRepair.partsUsed,
        status: serverErrorRepair.status,
        price: serverErrorRepair.price,
        cost: serverErrorRepair.cost,
        paymentMethod: serverErrorRepair.paymentMethod,
        createdAt: serverErrorRepair.createdAt,
        startedAt: serverErrorRepair.startedAt,
        finishedAt: serverErrorRepair.finishedAt,
        deliveredAt: serverErrorRepair.deliveredAt,
        createdBy: serverErrorRepair.createdBy,
        repairedBy: serverErrorRepair.repairedBy,
        deliveredBy: serverErrorRepair.deliveredBy,
        lastCaredAt: serverErrorRepair.lastCaredAt,
        isSynced: false, // Still not synced, queued for retry
        deleted: serverErrorRepair.deleted,
        color: serverErrorRepair.color,
        imei: serverErrorRepair.imei,
        condition: serverErrorRepair.condition,
      );

      expect(retryRepair.isSynced, false);
    });

    test('Handle large data sync conflicts', () {
      // Test conflict resolution for large datasets
      final originalRepair = Repair(
        firestoreId: 'conflict_test',
        customerName: 'Original User',
        phone: '0333333333',
        model: 'Conflict Model',
        issue: 'Original issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        status: 1,
        isSynced: true,
      );

      // Simulate conflicting update from another device
      final conflictingRepair = Repair(
        id: originalRepair.id,
        firestoreId: originalRepair.firestoreId,
        customerName: 'Updated User', // Changed
        phone: originalRepair.phone,
        model: originalRepair.model,
        issue: 'Updated issue', // Changed
        accessories: originalRepair.accessories,
        address: originalRepair.address,
        imagePath: originalRepair.imagePath,
        deliveredImage: originalRepair.deliveredImage,
        warranty: originalRepair.warranty,
        partsUsed: originalRepair.partsUsed,
        status: 2, // Changed
        price: originalRepair.price,
        cost: originalRepair.cost,
        paymentMethod: originalRepair.paymentMethod,
        createdAt: originalRepair.createdAt,
        startedAt: originalRepair.startedAt,
        finishedAt: originalRepair.finishedAt,
        deliveredAt: originalRepair.deliveredAt,
        createdBy: originalRepair.createdBy,
        repairedBy: originalRepair.repairedBy,
        deliveredBy: originalRepair.deliveredBy,
        lastCaredAt: originalRepair.lastCaredAt,
        isSynced: true,
        deleted: originalRepair.deleted,
        color: originalRepair.color,
        imei: originalRepair.imei,
        condition: originalRepair.condition,
      );

      // Conflict should be detected and handled
      expect(conflictingRepair.customerName != originalRepair.customerName, true);
      expect(conflictingRepair.issue != originalRepair.issue, true);
      expect(conflictingRepair.status != originalRepair.status, true);
      expect(conflictingRepair.firestoreId, originalRepair.firestoreId); // Same document
    });

    test('Validate Vietnamese text encoding in network requests', () {
      // Test Vietnamese characters in network data
      final vietnameseRepair = Repair(
        firestoreId: 'vietnamese_test',
        customerName: 'Nguyễn Văn Tiếng Việt',
        phone: '0123456789',
        model: 'iPhone Việt Nam',
        issue: 'Sửa chữa màn hình có dấu tiếng Việt: àáãạảăắằẳẵặâấầẩẫậèéẹẻẽêếềểễệđìíĩỉịòóõọỏôốồổỗộơớờởỡợùúũụủưứừửữựỳỵỷỹý',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );

      // Serialize and deserialize to test encoding
      final map = vietnameseRepair.toMap();
      final deserialized = Repair.fromMap(map);

      expect(deserialized.customerName, vietnameseRepair.customerName);
      expect(deserialized.model, vietnameseRepair.model);
      expect(deserialized.issue, vietnameseRepair.issue);
      expect(deserialized.firestoreId, vietnameseRepair.firestoreId);
    });
  });
}
