import 'expansion_feature_flags.dart';
import 'expansion_module_services.dart';
import 'crm_loyalty_models.dart';
import 'crm_loyalty_repository.dart';

class LoyaltyService {
  ExpansionFeatureFlags flags;
  final LoyaltyModuleService _loyaltyLogic;
  final LoyaltyRepository _repository;

  LoyaltyService({
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
    LoyaltyModuleService? loyaltyLogic,
    LoyaltyRepository? repository,
  })  : _loyaltyLogic = loyaltyLogic ?? LoyaltyModuleService(),
        _repository = repository ?? LoyaltyRepository();

  // ─── Cộng điểm khi mua hàng ───────────────────────────────────────────────

  /// Tính và lưu điểm sau khi mua hàng.
  /// Không sửa flow bán hàng — caller tự quyết định khi nào gọi.
  Future<LoyaltyPoint> earnPointsForPurchase({
    required String customerId,
    required String customerName,
    required double orderAmount,
    String note = 'Mua hàng',
  }) async {
    _ensureCrmEnabled();

    final points = _loyaltyLogic.earnPoints(orderAmount);
    if (points <= 0) {
      final existing = await _repository.getPoints(customerId);
      return existing ??
          LoyaltyPoint(
            customerId: customerId,
            customerName: customerName,
            totalPoints: 0,
            updatedAt: DateTime.now(),
          );
    }

    return _repository.earnPoints(
      customerId: customerId,
      customerName: customerName,
      points: points,
      note: note,
    );
  }

  // ─── Đổi điểm lấy chiết khấu ──────────────────────────────────────────────

  /// Đổi [pointsToRedeem] điểm → trả về (điểm còn lại, chiết khấu VND).
  /// Ném [InsufficientPointsException] nếu không đủ điểm.
  Future<({LoyaltyPoint updatedPoint, int discountAmount})> redeemPoints({
    required String customerId,
    required String customerName,
    required int pointsToRedeem,
    String note = 'Đổi điểm',
  }) async {
    _ensureCrmEnabled();

    final discount = _loyaltyLogic.redeemToDiscount(pointsToRedeem);
    if (discount <= 0) {
      throw ArgumentError(
        'Cần tối thiểu 500 điểm để đổi. Hiện yêu cầu $pointsToRedeem điểm.',
      );
    }

    return _repository.redeemPoints(
      customerId: customerId,
      customerName: customerName,
      pointsToRedeem: pointsToRedeem,
      note: note,
    );
  }

  // ─── Đọc dữ liệu ──────────────────────────────────────────────────────────

  Future<LoyaltyPoint?> getCustomerPoints(
    String customerId, {
    String customerName = '',
  }) async {
    _ensureCrmEnabled();
    final point = await _repository.getPoints(customerId);
    if (point != null) return point;

    // Backward-compatible recovery: some old data only has transactions.
    return _repository.ensurePointsSnapshotFromTransactions(
      customerId: customerId,
      customerName: customerName,
    );
  }

  Future<LoyaltyPoint?> getCustomerPointsByAliases({
    required String primaryCustomerId,
    required List<String> aliases,
    String customerName = '',
  }) async {
    _ensureCrmEnabled();
    final ids = <String>{primaryCustomerId, ...aliases}
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final point = await _repository.getPoints(primaryCustomerId);
    if (point != null && point.totalPoints > 0) return point;

    return _repository.ensurePointsSnapshotFromTransactions(
      customerId: primaryCustomerId,
      customerName: customerName,
      customerIds: ids,
    );
  }

  Future<LoyaltyPoint> seedPointsIfMissing({
    required String customerId,
    required String customerName,
    required int initialPoints,
    String note = 'Khởi tạo điểm CRM từ dữ liệu mua hàng cũ',
  }) async {
    _ensureCrmEnabled();
    return _repository.seedPointsIfMissing(
      customerId: customerId,
      customerName: customerName,
      initialPoints: initialPoints,
      note: note,
    );
  }

  Future<CustomerLevel?> getCustomerLevel(String customerId) async {
    _ensureCrmEnabled();
    return _repository.getLevel(customerId);
  }

  Future<List<LoyaltyTransaction>> getTransactionHistory(
    String customerId, {
    int limit = 50,
  }) async {
    _ensureCrmEnabled();
    return _repository.getTransactions(customerId, limit: limit);
  }

  Future<List<LoyaltyTransaction>> getTransactionHistoryByAliases({
    required String primaryCustomerId,
    required List<String> aliases,
    int limit = 50,
  }) async {
    _ensureCrmEnabled();
    final ids = <String>{primaryCustomerId, ...aliases}
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return _repository.getTransactionsForCustomerIds(ids, limit: limit);
  }

  Future<List<LoyaltyPoint>> getAllCustomerPoints() async {
    _ensureCrmEnabled();
    return _repository.getAllPoints();
  }

  // ─── Tính điểm dự kiến (không lưu) ───────────────────────────────────────

  int previewEarnPoints(double orderAmount) {
    _ensureCrmEnabled();
    return _loyaltyLogic.earnPoints(orderAmount);
  }

  int previewRedeemDiscount(int points) {
    _ensureCrmEnabled();
    return _loyaltyLogic.redeemToDiscount(points);
  }

  Future<void> close() async {
    await _repository.close();
  }

  void _ensureCrmEnabled() {
    if (!flags.enableCRM) {
      throw ModuleDisabledException('CRM');
    }
  }
}
