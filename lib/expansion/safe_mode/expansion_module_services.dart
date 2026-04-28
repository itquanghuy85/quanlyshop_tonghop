import 'expansion_feature_flags.dart';

class ModuleDisabledException implements Exception {
  final String moduleName;

  ModuleDisabledException(this.moduleName);

  @override
  String toString() => 'ModuleDisabledException: $moduleName is disabled';
}

class VatBuyerInfo {
  final String companyName;
  final String taxCode;
  final String address;
  final String email;

  const VatBuyerInfo({
    required this.companyName,
    required this.taxCode,
    required this.address,
    required this.email,
  });
}

class VatItemDraft {
  final String productName;
  final int quantity;
  final double unitPrice;
  final int taxPercent;

  const VatItemDraft({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxPercent,
  });

  double get subTotal => quantity * unitPrice;
  double get taxAmount => subTotal * taxPercent / 100;
}

class VatIssuedInvoice {
  final String invoiceNo;
  final VatBuyerInfo buyer;
  final List<VatItemDraft> items;
  final double subTotal;
  final double totalTax;
  final double grandTotal;
  final DateTime issuedAt;
  final bool locked;

  const VatIssuedInvoice({
    required this.invoiceNo,
    required this.buyer,
    required this.items,
    required this.subTotal,
    required this.totalTax,
    required this.grandTotal,
    required this.issuedAt,
    required this.locked,
  });
}

class VatModuleService {
  static final RegExp _taxCodePattern = RegExp(r'^\d{10}(?:-\d{3})?$');

  bool isValidTaxCode(String taxCode) {
    return _taxCodePattern.hasMatch(taxCode.trim());
  }

  VatIssuedInvoice issueInvoice({
    required String invoiceNo,
    required VatBuyerInfo buyer,
    required List<VatItemDraft> items,
  }) {
    if (!isValidTaxCode(buyer.taxCode)) {
      throw ArgumentError('Invalid tax code format');
    }
    if (items.isEmpty) {
      throw ArgumentError('Invoice must contain at least one item');
    }

    final subTotal = items.fold<double>(0, (sum, item) => sum + item.subTotal);
    final totalTax = items.fold<double>(0, (sum, item) => sum + item.taxAmount);

    return VatIssuedInvoice(
      invoiceNo: invoiceNo,
      buyer: buyer,
      items: List<VatItemDraft>.unmodifiable(items),
      subTotal: subTotal,
      totalTax: totalTax,
      grandTotal: subTotal + totalTax,
      issuedAt: DateTime.now(),
      locked: true,
    );
  }
}

enum PricingTier { normal, vip, wholesale }

class PricingContext {
  final PricingTier customerTier;
  final int quantity;

  const PricingContext({required this.customerTier, required this.quantity});
}

class ProductPricingSnapshot {
  final double basePrice;
  final double vipPrice;
  final double wholesalePrice;

  const ProductPricingSnapshot({
    required this.basePrice,
    required this.vipPrice,
    required this.wholesalePrice,
  });
}

class PricingModuleService {
  double resolvePrice({
    required ProductPricingSnapshot prices,
    required PricingContext context,
  }) {
    if (context.quantity >= 20) {
      return prices.wholesalePrice;
    }

    switch (context.customerTier) {
      case PricingTier.vip:
        return prices.vipPrice;
      case PricingTier.wholesale:
        return prices.wholesalePrice;
      case PricingTier.normal:
        return prices.basePrice;
    }
  }
}

enum LoyaltyLevel { regular, silver, gold, platinum }

class LoyaltyPointLedger {
  final int currentPoints;
  final LoyaltyLevel currentLevel;

  const LoyaltyPointLedger({
    required this.currentPoints,
    required this.currentLevel,
  });
}

class LoyaltyModuleService {
  int earnPoints(double orderAmount) {
    return (orderAmount / 10000).floor();
  }

  int redeemToDiscount(int points) {
    if (points < 500) return 0;
    return (points ~/ 500) * 50000;
  }

  LoyaltyLevel levelFromPoints(int points) {
    if (points >= 5000) return LoyaltyLevel.platinum;
    if (points >= 2000) return LoyaltyLevel.gold;
    if (points >= 800) return LoyaltyLevel.silver;
    return LoyaltyLevel.regular;
  }
}

class Branch {
  final String branchId;
  final String name;

  const Branch({required this.branchId, required this.name});
}

class BranchRevenue {
  final String branchId;
  final double revenue;

  const BranchRevenue({required this.branchId, required this.revenue});
}

class StockTransferRequest {
  final String fromBranchId;
  final String toBranchId;
  final String productId;
  final int quantity;

  const StockTransferRequest({
    required this.fromBranchId,
    required this.toBranchId,
    required this.productId,
    required this.quantity,
  });
}

class MultiBranchService {
  List<T> filterByBranch<T>({
    required List<T> records,
    required String userBranchId,
    required String Function(T) branchResolver,
  }) {
    return records.where((row) => branchResolver(row) == userBranchId).toList();
  }

  double aggregateRevenue(List<BranchRevenue> branchRevenues) {
    return branchRevenues.fold<double>(0, (sum, row) => sum + row.revenue);
  }

  bool canTransfer(StockTransferRequest req) {
    return req.fromBranchId != req.toBranchId && req.quantity > 0;
  }
}

class SafeModeExpansionEngine {
  ExpansionFeatureFlags flags;

  final VatModuleService _vatService;
  final PricingModuleService _pricingService;
  final LoyaltyModuleService _crmService;
  final MultiBranchService _branchService;

  SafeModeExpansionEngine({
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
    VatModuleService? vatService,
    PricingModuleService? pricingService,
    LoyaltyModuleService? crmService,
    MultiBranchService? branchService,
  })  : _vatService = vatService ?? VatModuleService(),
        _pricingService = pricingService ?? PricingModuleService(),
        _crmService = crmService ?? LoyaltyModuleService(),
        _branchService = branchService ?? MultiBranchService();

  VatIssuedInvoice issueVatInvoice({
    required String invoiceNo,
    required VatBuyerInfo buyer,
    required List<VatItemDraft> items,
  }) {
    if (!flags.enableVAT) {
      throw ModuleDisabledException('VAT');
    }
    return _vatService.issueInvoice(invoiceNo: invoiceNo, buyer: buyer, items: items);
  }

  double resolvePrice({
    required ProductPricingSnapshot prices,
    required PricingContext context,
  }) {
    if (!flags.enablePricing) {
      throw ModuleDisabledException('Pricing');
    }
    return _pricingService.resolvePrice(prices: prices, context: context);
  }

  int earnLoyaltyPoints(double orderAmount) {
    if (!flags.enableCRM) {
      throw ModuleDisabledException('CRM');
    }
    return _crmService.earnPoints(orderAmount);
  }

  bool validateTransfer(StockTransferRequest req) {
    if (!flags.enableMultiBranch) {
      throw ModuleDisabledException('Multi-Branch');
    }
    return _branchService.canTransfer(req);
  }
}
