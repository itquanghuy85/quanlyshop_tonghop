import 'expansion_feature_flags.dart';
import 'expansion_module_services.dart' show ModuleDisabledException, PricingTier;
import 'pricing_models.dart';
import 'pricing_repository.dart';

/// PricingService — service layer cho Pricing module.
/// Tất cả method đều kiểm tra feature flag trước khi thực thi.
/// DB file riêng: pricing_module_safe_mode.db — KHÔNG đụng salePrice gốc.
class PricingService {
  final ExpansionFeatureFlags flags;
  final PricingRepository _repository;

  PricingService({
    required this.flags,
    PricingRepository? repository,
  }) : _repository = repository ?? PricingRepository();

  void _assertEnabled() {
    if (!flags.enablePricing) {
      throw ModuleDisabledException('PricingModule');
    }
  }

  Future<void> close() => _repository.close();

  // ─── PriceRule management ──────────────────────────────────────────────

  /// Thêm rule giá mới cho sản phẩm.
  Future<int> addRule(PriceRule rule) async {
    _assertEnabled();
    return _repository.addRule(rule);
  }

  /// Cập nhật rule đã tồn tại.
  Future<void> updateRule(PriceRule rule) async {
    _assertEnabled();
    return _repository.updateRule(rule);
  }

  /// Xoá rule theo id.
  Future<void> deleteRule(int id) async {
    _assertEnabled();
    return _repository.deleteRule(id);
  }

  /// Lấy tất cả rule của 1 sản phẩm.
  Future<List<PriceRule>> getRulesForProduct(String productId) async {
    _assertEnabled();
    return _repository.getRulesForProduct(productId);
  }

  /// Lấy tất cả rule (admin view).
  Future<List<PriceRule>> getAllRules() async {
    _assertEnabled();
    return _repository.getAllRules();
  }

  // ─── CustomerPricing management ────────────────────────────────────────

  /// Cài loại giá cho 1 khách hàng (upsert).
  Future<void> setCustomerPricingType(String customerId, PricingRuleType type) async {
    _assertEnabled();
    await _repository.saveCustomerPricing(
      CustomerPricing(
        customerId: customerId,
        pricingType: type,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Lấy loại giá của 1 khách. Trả về [PricingRuleType.normal] nếu chưa cài.
  Future<PricingRuleType> getCustomerPricingType(String customerId) async {
    _assertEnabled();
    final cp = await _repository.getCustomerPricing(customerId);
    return cp?.pricingType ?? PricingRuleType.normal;
  }

  /// Xoá setting của 1 khách (reset về normal).
  Future<void> resetCustomerPricing(String customerId) async {
    _assertEnabled();
    return _repository.removeCustomerPricing(customerId);
  }

  /// Lấy tất cả khách có cài giá riêng.
  Future<List<CustomerPricing>> getAllCustomerPricings() async {
    _assertEnabled();
    return _repository.getAllCustomerPricings();
  }

  // ─── Price resolution ─────────────────────────────────────────────────

  /// Giải giá cho 1 sản phẩm + khách hàng cụ thể.
  ///
  /// Thứ tự ưu tiên:
  /// 1. Rule có minQty phù hợp (qty >= minQty) — ưu tiên minQty cao nhất
  /// 2. Rule theo loại khách (type match) không có minQty
  /// 3. Fallback về [basePrice] (không thay đổi giá gốc)
  ///
  /// QUAN TRỌNG: hàm này chỉ TƯ VẤN giá — caller quyết định có áp dụng không.
  /// Không bao giờ tự sửa salePrice gốc.
  Future<ResolvedPrice> resolvePrice({
    required String productId,
    required double basePrice,
    required int quantity,
    required String customerId,
  }) async {
    _assertEnabled();

    // Lấy loại khách
    final cp = await _repository.getCustomerPricing(customerId);
    final customerType = cp?.pricingType ?? PricingRuleType.normal;
    final pricingTier = customerType.toPricingTier();

    // Lấy rules của sản phẩm (sắp xếp minQty giảm dần)
    final rules = await _repository.getRulesForProduct(productId);

    // Bước 1: tìm rule theo số lượng (qty-based rule, bất kể type)
    final qtyRule = rules
        .where((r) => r.minQty > 0 && quantity >= r.minQty)
        .fold<PriceRule?>(null, (best, r) {
      if (best == null || r.minQty > best.minQty) return r;
      return best;
    });

    if (qtyRule != null) {
      return ResolvedPrice(
        productId: productId,
        resolvedPrice: qtyRule.price,
        basePrice: basePrice,
        appliedType: qtyRule.type,
        quantity: quantity,
        reason:
            'Rule số lượng: mua ≥${qtyRule.minQty} → ${qtyRule.type.displayName}',
      );
    }

    // Bước 2: tìm rule theo loại khách (type match, minQty = 0)
    final tierMatch = rules
        .where((r) => r.minQty == 0 && r.type == customerType)
        .toList();

    if (tierMatch.isNotEmpty) {
      final rule = tierMatch.first;
      return ResolvedPrice(
        productId: productId,
        resolvedPrice: rule.price,
        basePrice: basePrice,
        appliedType: rule.type,
        quantity: quantity,
        reason: 'Giá ${customerType.displayName}',
      );
    }

    // Bước 3: Fallback — giữ nguyên basePrice (không đụng giá gốc)
    return ResolvedPrice(
      productId: productId,
      resolvedPrice: basePrice,
      basePrice: basePrice,
      appliedType: PricingRuleType.normal,
      quantity: quantity,
      reason: pricingTier == PricingTier.normal
          ? 'Giá thường (mặc định)'
          : 'Chưa có rule ${customerType.displayName} — dùng giá thường',
    );
  }

  /// Xem trước giá cho 1 sản phẩm (không cần customerId — dùng loại tường minh).
  /// Không truy xuất DB customer. Dùng cho UI preview trước khi lưu rule.
  Future<ResolvedPrice> previewPrice({
    required String productId,
    required double basePrice,
    required int quantity,
    required PricingRuleType customerType,
  }) async {
    _assertEnabled();

    final rules = await _repository.getRulesForProduct(productId);

    final qtyRule = rules
        .where((r) => r.minQty > 0 && quantity >= r.minQty)
        .fold<PriceRule?>(null, (best, r) {
      if (best == null || r.minQty > best.minQty) return r;
      return best;
    });

    if (qtyRule != null) {
      return ResolvedPrice(
        productId: productId,
        resolvedPrice: qtyRule.price,
        basePrice: basePrice,
        appliedType: qtyRule.type,
        quantity: quantity,
        reason: 'Preview: Rule số lượng ≥${qtyRule.minQty}',
      );
    }

    final tierMatch =
        rules.where((r) => r.minQty == 0 && r.type == customerType).toList();

    if (tierMatch.isNotEmpty) {
      return ResolvedPrice(
        productId: productId,
        resolvedPrice: tierMatch.first.price,
        basePrice: basePrice,
        appliedType: customerType,
        quantity: quantity,
        reason: 'Preview: Giá ${customerType.displayName}',
      );
    }

    return ResolvedPrice(
      productId: productId,
      resolvedPrice: basePrice,
      basePrice: basePrice,
      appliedType: PricingRuleType.normal,
      quantity: quantity,
      reason: 'Preview: Không có rule — giá thường',
    );
  }
}
