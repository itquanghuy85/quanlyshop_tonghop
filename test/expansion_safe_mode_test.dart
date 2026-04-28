import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/expansion/safe_mode/expansion_feature_flags.dart';
import 'package:quanlyshop/expansion/safe_mode/expansion_module_models.dart';
import 'package:quanlyshop/expansion/safe_mode/expansion_module_services.dart';

void main() {
  group('Expansion Safe Mode - Feature Flags', () {
    test('safe defaults map to current rollout', () {
      const flags = ExpansionFeatureFlags.safeDefaults();

      expect(flags.enableVAT, isFalse);
      expect(flags.enablePricing, isFalse);
      expect(flags.enableCRM, isFalse);
      expect(flags.enableMultiBranch, isFalse);
    });

    test('module catalog provides isolated table ownership', () {
      expect(ExpansionModuleCatalog.all, hasLength(4));
      expect(ExpansionModuleCatalog.vat.isolatedTables, ['invoices', 'invoice_items']);
      expect(ExpansionModuleCatalog.pricing.isolatedTables, ['price_rules', 'customer_pricing']);
      expect(ExpansionModuleCatalog.crm.isolatedTables, ['loyalty_points', 'customer_level']);
      expect(ExpansionModuleCatalog.multiBranch.isolatedTables, ['branches', 'branch_inventory']);
    });
  });

  group('Expansion Safe Mode - VAT', () {
    test('toggle on -> use -> toggle off', () {
      final engine = SafeModeExpansionEngine();
      engine.flags = engine.flags.copyWith(enableVAT: false);

      expect(
        () => engine.issueVatInvoice(
          invoiceNo: 'INV-001',
          buyer: const VatBuyerInfo(
            companyName: 'ABC Co',
            taxCode: '0123456789',
            address: 'HCM',
            email: 'billing@abc.vn',
          ),
          items: const [
            VatItemDraft(productName: 'iPhone 11', quantity: 1, unitPrice: 5000000, taxPercent: 10),
          ],
        ),
        throwsA(isA<ModuleDisabledException>()),
      );

      engine.flags = engine.flags.copyWith(enableVAT: true);
      final invoice = engine.issueVatInvoice(
        invoiceNo: 'INV-001',
        buyer: const VatBuyerInfo(
          companyName: 'ABC Co',
          taxCode: '0123456789',
          address: 'HCM',
          email: 'billing@abc.vn',
        ),
        items: const [
          VatItemDraft(productName: 'iPhone 11', quantity: 1, unitPrice: 5000000, taxPercent: 10),
        ],
      );

      expect(invoice.locked, isTrue);
      expect(invoice.totalTax, 500000);
      expect(invoice.grandTotal, 5500000);

      engine.flags = engine.flags.copyWith(enableVAT: false);
      expect(
        () => engine.issueVatInvoice(
          invoiceNo: 'INV-002',
          buyer: const VatBuyerInfo(
            companyName: 'ABC Co',
            taxCode: '0123456789',
            address: 'HCM',
            email: 'billing@abc.vn',
          ),
          items: const [
            VatItemDraft(productName: 'iPhone 11', quantity: 1, unitPrice: 5000000, taxPercent: 10),
          ],
        ),
        throwsA(isA<ModuleDisabledException>()),
      );
    });
  });

  group('Expansion Safe Mode - Pricing', () {
    test('toggle on -> use -> toggle off', () {
      final engine = SafeModeExpansionEngine();
      engine.flags = engine.flags.copyWith(enablePricing: false);

      expect(
        () => engine.resolvePrice(
          prices: const ProductPricingSnapshot(basePrice: 5000000, vipPrice: 4500000, wholesalePrice: 4200000),
          context: const PricingContext(customerTier: PricingTier.vip, quantity: 1),
        ),
        throwsA(isA<ModuleDisabledException>()),
      );

      engine.flags = engine.flags.copyWith(enablePricing: true);
      final price = engine.resolvePrice(
        prices: const ProductPricingSnapshot(basePrice: 5000000, vipPrice: 4500000, wholesalePrice: 4200000),
        context: const PricingContext(customerTier: PricingTier.vip, quantity: 1),
      );
      expect(price, 4500000);

      engine.flags = engine.flags.copyWith(enablePricing: false);
      expect(
        () => engine.resolvePrice(
          prices: const ProductPricingSnapshot(basePrice: 5000000, vipPrice: 4500000, wholesalePrice: 4200000),
          context: const PricingContext(customerTier: PricingTier.vip, quantity: 1),
        ),
        throwsA(isA<ModuleDisabledException>()),
      );
    });
  });

  group('Expansion Safe Mode - CRM', () {
    test('toggle on -> use -> toggle off', () {
      final engine = SafeModeExpansionEngine();

      expect(() => engine.earnLoyaltyPoints(500000), throwsA(isA<ModuleDisabledException>()));

      engine.flags = engine.flags.copyWith(enableCRM: true);
      final points = engine.earnLoyaltyPoints(500000);
      expect(points, 50);

      engine.flags = engine.flags.copyWith(enableCRM: false);
      expect(() => engine.earnLoyaltyPoints(500000), throwsA(isA<ModuleDisabledException>()));
    });
  });

  group('Expansion Safe Mode - Multi-Branch', () {
    test('toggle on -> use -> toggle off', () {
      final engine = SafeModeExpansionEngine();
      engine.flags = engine.flags.copyWith(enableMultiBranch: false);
      final req = const StockTransferRequest(
        fromBranchId: 'hcm',
        toBranchId: 'hn',
        productId: 'iphone11',
        quantity: 2,
      );

      expect(() => engine.validateTransfer(req), throwsA(isA<ModuleDisabledException>()));

      engine.flags = engine.flags.copyWith(enableMultiBranch: true);
      final ok = engine.validateTransfer(req);
      expect(ok, isTrue);

      engine.flags = engine.flags.copyWith(enableMultiBranch: false);
      expect(() => engine.validateTransfer(req), throwsA(isA<ModuleDisabledException>()));
    });
  });
}
