import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/expansion/safe_mode/expansion_feature_flags.dart';
import 'package:quanlyshop/expansion/safe_mode/expansion_module_services.dart';
import 'package:quanlyshop/expansion/safe_mode/crm_loyalty_models.dart';
import 'package:quanlyshop/expansion/safe_mode/crm_loyalty_repository.dart';
import 'package:quanlyshop/expansion/safe_mode/crm_loyalty_service.dart';

// Dùng in-memory DB bằng cách dùng repository với mock.
// Vì sqflite không mở được file thật trong flutter_test,
// ta test logic riêng của model + service (unit-level).

void main() {
  group('CRM Models', () {
    test('LoyaltyPoint toMap / fromMap round-trip', () {
      final now = DateTime(2026, 4, 26, 12);
      final point = LoyaltyPoint(
        customerId: 'cust_001',
        customerName: 'Nguyễn Văn A',
        totalPoints: 1200,
        updatedAt: now,
      );

      final map = point.toMap();
      final restored = LoyaltyPoint.fromMap(map);

      expect(restored.customerId, 'cust_001');
      expect(restored.customerName, 'Nguyễn Văn A');
      expect(restored.totalPoints, 1200);
      expect(restored.updatedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('LoyaltyPoint copyWith', () {
      final original = LoyaltyPoint(
        customerId: 'cust_001',
        customerName: 'Nguyễn Văn A',
        totalPoints: 100,
        updatedAt: DateTime(2026, 1, 1),
      );
      final updated = original.copyWith(totalPoints: 500);

      expect(updated.totalPoints, 500);
      expect(updated.customerId, 'cust_001');
      expect(updated.customerName, 'Nguyễn Văn A');
    });

    test('CustomerLevel toMap / fromMap round-trip', () {
      final level = CustomerLevel(
        customerId: 'cust_001',
        tier: CustomerLevelTier.gold,
        pointsAtLastUpdate: 2500,
        updatedAt: DateTime(2026, 4, 26),
      );

      final map = level.toMap();
      final restored = CustomerLevel.fromMap(map);

      expect(restored.customerId, 'cust_001');
      expect(restored.tier, CustomerLevelTier.gold);
      expect(restored.pointsAtLastUpdate, 2500);
    });

    test('CustomerLevelTier displayName', () {
      expect(CustomerLevelTier.regular.displayName, 'Thường');
      expect(CustomerLevelTier.silver.displayName, 'Bạc');
      expect(CustomerLevelTier.gold.displayName, 'Vàng');
      expect(CustomerLevelTier.platinum.displayName, 'Kim cương');
    });

    test('CustomerLevelTierX.fromString handles unknown', () {
      expect(CustomerLevelTierX.fromString('unknown'), CustomerLevelTier.regular);
      expect(CustomerLevelTierX.fromString('gold'), CustomerLevelTier.gold);
    });

    test('LoyaltyTransaction toMap / fromMap round-trip', () {
      final tx = LoyaltyTransaction(
        customerId: 'cust_001',
        type: LoyaltyTransactionType.redeem,
        points: 500,
        discountAmount: 50000,
        note: 'Đổi điểm',
        createdAt: DateTime(2026, 4, 26),
      );

      final map = tx.toMap();
      final restored = LoyaltyTransaction.fromMap(map);

      expect(restored.type, LoyaltyTransactionType.redeem);
      expect(restored.points, 500);
      expect(restored.discountAmount, 50000);
    });
  });

  group('LoyaltyModuleService (business logic không phụ thuộc DB)', () {
    final logic = LoyaltyModuleService();

    test('earnPoints tính đúng: 10.000 VND = 1 điểm', () {
      expect(logic.earnPoints(100000), 10);
      expect(logic.earnPoints(55000), 5);
      expect(logic.earnPoints(9999), 0);
    });

    test('redeemToDiscount: 500 điểm → 50.000 VND', () {
      expect(logic.redeemToDiscount(500), 50000);
      expect(logic.redeemToDiscount(1000), 100000);
      expect(logic.redeemToDiscount(499), 0);
    });

    test('levelFromPoints trả về đúng hạng', () {
      expect(logic.levelFromPoints(0), LoyaltyLevel.regular);
      expect(logic.levelFromPoints(800), LoyaltyLevel.silver);
      expect(logic.levelFromPoints(2000), LoyaltyLevel.gold);
      expect(logic.levelFromPoints(5000), LoyaltyLevel.platinum);
    });
  });

  group('LoyaltyService - feature flag guard', () {
    test('khi CRM tắt: earnPointsForPurchase ném ModuleDisabledException', () async {
      final service = LoyaltyService(
        flags: const ExpansionFeatureFlags.safeDefaults(), // enableCRM = false
      );

      expect(
        () => service.earnPointsForPurchase(
          customerId: 'cust_001',
          customerName: 'Nguyễn Văn A',
          orderAmount: 100000,
        ),
        throwsA(isA<ModuleDisabledException>()),
      );

      await service.close();
    });

    test('khi CRM tắt: redeemPoints ném ModuleDisabledException', () async {
      final service = LoyaltyService(
        flags: const ExpansionFeatureFlags.safeDefaults(),
      );

      expect(
        () => service.redeemPoints(
          customerId: 'cust_001',
          customerName: 'Nguyễn Văn A',
          pointsToRedeem: 500,
        ),
        throwsA(isA<ModuleDisabledException>()),
      );

      await service.close();
    });

    test('previewEarnPoints khi tắt ném ModuleDisabledException', () async {
      final service = LoyaltyService(
        flags: const ExpansionFeatureFlags.safeDefaults(),
      );
      expect(() => service.previewEarnPoints(100000), throwsA(isA<ModuleDisabledException>()));
      await service.close();
    });

    test('previewEarnPoints khi bật trả về đúng', () async {
      final service = LoyaltyService(
        flags: const ExpansionFeatureFlags(enableCRM: true),
      );
      expect(service.previewEarnPoints(100000), 10);
      await service.close();
    });

    test('previewRedeemDiscount khi bật: 500 điểm → 50.000', () async {
      final service = LoyaltyService(
        flags: const ExpansionFeatureFlags(enableCRM: true),
      );
      expect(service.previewRedeemDiscount(500), 50000);
      await service.close();
    });
  });

  group('InsufficientPointsException', () {
    test('toString mô tả đúng', () {
      const ex = InsufficientPointsException(available: 200, requested: 500);
      expect(ex.toString(), contains('200'));
      expect(ex.toString(), contains('500'));
    });
  });
}
