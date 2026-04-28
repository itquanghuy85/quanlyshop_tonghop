import 'expansion_module_services.dart' show PricingTier;

/// Enum PricingRuleType — loại giá áp dụng
enum PricingRuleType {
  vip,
  wholesale,
  normal;

  String toDbString() => name; // 'vip' / 'wholesale' / 'normal'

  static PricingRuleType fromString(String s) {
    return PricingRuleType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => PricingRuleType.normal,
    );
  }

  /// Chuyển sang PricingTier cho engine logic
  PricingTier toPricingTier() {
    switch (this) {
      case PricingRuleType.vip:
        return PricingTier.vip;
      case PricingRuleType.wholesale:
        return PricingTier.wholesale;
      case PricingRuleType.normal:
        return PricingTier.normal;
    }
  }

  String get displayName {
    switch (this) {
      case PricingRuleType.vip:
        return 'VIP';
      case PricingRuleType.wholesale:
        return 'Sỉ';
      case PricingRuleType.normal:
        return 'Thường';
    }
  }
}

/// PriceRule — quy tắc giá cho 1 sản phẩm theo loại khách / số lượng
class PriceRule {
  final int? id;
  final String productId;
  final PricingRuleType type;

  /// Số lượng tối thiểu để áp dụng rule này (0 = không giới hạn)
  final int minQty;

  /// Giá áp dụng (VND)
  final double price;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PriceRule({
    this.id,
    required this.productId,
    required this.type,
    required this.minQty,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'productId': productId,
      'type': type.toDbString(),
      'minQty': minQty,
      'price': price,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static PriceRule fromMap(Map<String, dynamic> map) {
    return PriceRule(
      id: map['id'] as int?,
      productId: map['productId'] as String,
      type: PricingRuleType.fromString(map['type'] as String),
      minQty: map['minQty'] as int,
      price: (map['price'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
    );
  }

  PriceRule copyWith({
    int? id,
    String? productId,
    PricingRuleType? type,
    int? minQty,
    double? price,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PriceRule(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      type: type ?? this.type,
      minQty: minQty ?? this.minQty,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// CustomerPricing — gắn loại giá cố định cho 1 khách hàng
class CustomerPricing {
  final String customerId;
  final PricingRuleType pricingType;
  final DateTime updatedAt;

  const CustomerPricing({
    required this.customerId,
    required this.pricingType,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'pricingType': pricingType.toDbString(),
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static CustomerPricing fromMap(Map<String, dynamic> map) {
    return CustomerPricing(
      customerId: map['customerId'] as String,
      pricingType: PricingRuleType.fromString(map['pricingType'] as String),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
    );
  }

  CustomerPricing copyWith({
    String? customerId,
    PricingRuleType? pricingType,
    DateTime? updatedAt,
  }) {
    return CustomerPricing(
      customerId: customerId ?? this.customerId,
      pricingType: pricingType ?? this.pricingType,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Kết quả giải giá — trả về giá đã chọn + lý do
class ResolvedPrice {
  final String productId;
  final double resolvedPrice;
  final double basePrice;
  final PricingRuleType appliedType;
  final int quantity;
  final String reason;

  const ResolvedPrice({
    required this.productId,
    required this.resolvedPrice,
    required this.basePrice,
    required this.appliedType,
    required this.quantity,
    required this.reason,
  });

  bool get hasDiscount => resolvedPrice < basePrice;
  double get savedAmount => basePrice - resolvedPrice;
}
