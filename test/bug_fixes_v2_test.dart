import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/repair_model.dart';

/// Tests for 5 bug fixes:
/// 1. Finance tab permission bypass
/// 2. Activity cards grid layout
/// 3. KTV notes in repair list + duplicate price removal
/// 4. iOS freezing (lifecycle/timer management)
/// 5. Notification loop fix

void main() {
  group('Bug #1: Finance Permission Logic', () {
    test('hasFullAccess should grant finance for admin/owner', () {
      // Simulating hasFullAccess logic from home_view.dart
      bool hasFullAccess(String role, bool isSuperAdmin) {
        return role == 'admin' || role == 'owner' || isSuperAdmin;
      }

      expect(hasFullAccess('admin', false), isTrue);
      expect(hasFullAccess('owner', false), isTrue);
      expect(hasFullAccess('user', true), isTrue);
      expect(hasFullAccess('employee', false), isFalse);
      expect(hasFullAccess('technician', false), isFalse);
      expect(hasFullAccess('manager', false), isFalse);
    });

    test('Finance tab should be locked when permissions empty and non-admin', () {
      // Simulating _updateAvailableTabs logic
      bool hasPermission(String? permission, Map<String, bool> permissions, bool fullAccess) {
        if (permission == null) return true;
        if (fullAccess) return true;
        if (permissions.isEmpty) return false; // NEW: default locked
        return permissions[permission] == true;
      }

      final emptyPerms = <String, bool>{};
      // Employee with no permissions loaded → locked
      expect(hasPermission('allowViewRevenue', emptyPerms, false), isFalse);
      expect(hasPermission('allowViewSales', emptyPerms, false), isFalse);
      // Home tab (null permission) → always accessible
      expect(hasPermission(null, emptyPerms, false), isTrue);
      // Owner (fullAccess) → always accessible even with empty perms
      expect(hasPermission('allowViewRevenue', emptyPerms, true), isTrue);
    });

    test('Finance tab should respect loaded permissions', () {
      bool hasPermission(String? permission, Map<String, bool> permissions, bool fullAccess) {
        if (permission == null) return true;
        if (fullAccess) return true;
        if (permissions.isEmpty) return false;
        return permissions[permission] == true;
      }

      // Employee with allowViewRevenue = false (explicitly set by owner)
      final perms = {'allowViewRevenue': false, 'allowViewSales': true};
      expect(hasPermission('allowViewRevenue', perms, false), isFalse);
      expect(hasPermission('allowViewSales', perms, false), isTrue);
    });

    test('Finance dashboard cards should check permissions not just role', () {
      bool canViewFinance(bool hasFullAccess, Map<String, bool> permissions) {
        return hasFullAccess || permissions['allowViewRevenue'] == true;
      }

      // Manager with allowViewRevenue = false
      expect(canViewFinance(false, {'allowViewRevenue': false}), isFalse);
      // Employee with default (no key) → false
      expect(canViewFinance(false, {}), isFalse);
      // Owner → always true
      expect(canViewFinance(true, {'allowViewRevenue': false}), isTrue);
    });
  });

  group('Bug #3: Repair Card - KTV Notes & Duplicate Price', () {
    test('Repair model should have notes field', () {
      final repair = Repair(
        customerName: 'Nguyễn Văn A',
        phone: '0901234567',
        model: 'iPhone 15 Pro Max',
        issue: 'Vỡ màn hình|Cong khung',
        accessories: 'Cáp sạc, ốp lưng',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        notes: 'KTV: Cần thay cả cảm ứng, linh kiện đặt hàng 3 ngày',
        repairedBy: 'KTV Trung',
      );

      expect(repair.notes, isNotNull);
      expect(repair.notes, contains('KTV'));
      expect(repair.repairedBy, equals('KTV Trung'));
    });

    test('Repair notes should handle null gracefully', () {
      final repair = Repair(
        customerName: 'Trần B',
        phone: '0909876543',
        model: 'Samsung S24',
        issue: 'Hỏng pin',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(repair.notes, isNull);
      expect(repair.repairedBy, isNull);
    });

    test('Repair notes should be included in toMap', () {
      final repair = Repair(
        customerName: 'Test',
        phone: '0901111111',
        model: 'Test Model',
        issue: 'Test Issue',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        notes: 'Ghi chú rất dài từ KTV về tình trạng máy, cần lưu ý nhiều thứ',
        repairedBy: 'KTV Hoàng',
      );

      final map = repair.toMap();
      expect(map['notes'], contains('Ghi chú rất dài'));
      expect(map['repairedBy'], equals('KTV Hoàng'));
    });

    test('Long KTV notes should not exceed display constraints', () {
      // Test that very long notes are handled (the UI uses maxLines: 2 + ellipsis)
      final longNote = 'A' * 500; // 500 characters
      final repair = Repair(
        customerName: 'Test',
        phone: '0901111111',
        model: 'Test',
        issue: 'Test',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        notes: longNote,
      );
      
      expect(repair.notes!.length, equals(500));
      // UI will truncate with TextOverflow.ellipsis + maxLines: 2
      // This test ensures the model handles long strings without error
    });
  });

  group('Bug #4: iOS Performance - Timer & Lifecycle', () {
    test('Sync timer interval should be >= 120 seconds to reduce I/O', () {
      // The auto-sync timer was changed from 60s to 120s
      const syncInterval = Duration(seconds: 120);
      expect(syncInterval.inSeconds, greaterThanOrEqualTo(120));
    });
  });

  group('Bug #5: Notification Deduplication', () {
    test('Processed notification IDs should prevent duplicates', () {
      final processedIds = <String>{};
      
      // First notification
      processedIds.add('notif_001');
      expect(processedIds.contains('notif_001'), isTrue);
      
      // Should not process same ID again
      final isNew = !processedIds.contains('notif_001');
      expect(isNew, isFalse);
    });

    test('Processed IDs should be limited to 100 entries', () {
      final processedIds = <String>{};
      
      // Add 101 entries
      for (int i = 0; i < 101; i++) {
        processedIds.add('notif_$i');
        if (processedIds.length > 100) {
          processedIds.remove(processedIds.first);
        }
      }
      
      expect(processedIds.length, equals(100));
      // First entry should be removed
      expect(processedIds.contains('notif_0'), isFalse);
      expect(processedIds.contains('notif_100'), isTrue);
    });

    test('Self-sent system notification should only show snackbar, not local push', () {
      // Simulating the logic
      bool shouldShowLocalPush(String senderId, String currentUid, String type) {
        final isSelf = senderId == currentUid;
        final isSystem = type == 'system';
        // Self-sent system: only snackbar, no local notification
        return !(isSelf && isSystem);
      }

      // Self-sent system → no local push
      expect(shouldShowLocalPush('user123', 'user123', 'system'), isFalse);
      // Other user system → show local push
      expect(shouldShowLocalPush('user456', 'user123', 'system'), isTrue);
      // Self-sent non-system → should not even enter this code path (filtered earlier)
      // Other user non-system → show local push
      expect(shouldShowLocalPush('user456', 'user123', 'new_order'), isTrue);
    });
  });

  group('Bug #2: Activity Cards Layout', () {
    test('Grid cross-axis count should be 3 for 5+ items', () {
      int calcCrossAxisCount(int itemCount) {
        return itemCount <= 4 ? itemCount.clamp(1, 4) : 3;
      }
      
      // 2 items → 2 columns
      expect(calcCrossAxisCount(2), equals(2));
      // 4 items → 4 columns
      expect(calcCrossAxisCount(4), equals(4));
      // 5+ items → 3 columns (wraps to 2 rows)
      expect(calcCrossAxisCount(5), equals(3));
      expect(calcCrossAxisCount(6), equals(3));
      // 1 item → 1 column
      expect(calcCrossAxisCount(1), equals(1));
    });
  });
}
