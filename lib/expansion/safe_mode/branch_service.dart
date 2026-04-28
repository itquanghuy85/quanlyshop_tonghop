import 'expansion_feature_flags.dart';
import 'expansion_module_services.dart' show ModuleDisabledException;
import 'branch_models.dart';
import 'branch_repository.dart';

/// Service layer cho Multi-Branch module.
///
/// - Tất cả method kiểm tra flag [enableMultiBranch] trước.
/// - Lưu [BranchContext] active trong bộ nhớ — tồn tại trong session.
/// - Không sửa UserService / shopId logic cũ.
class BranchService {
  final ExpansionFeatureFlags flags;
  final BranchRepository _repo;

  BranchContext? _activeContext;

  BranchService({
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
    BranchRepository? repository,
  }) : _repo = repository ?? BranchRepository();

  void close() => _repo.close();

  // ─── Guards ────────────────────────────────────────────────────────────────

  void _guard() {
    if (!flags.enableMultiBranch) {
      throw ModuleDisabledException('MultiiBranch');
    }
  }

  // ─── Branch CRUD ───────────────────────────────────────────────────────────

  /// Tạo chi nhánh mới. Trả về Branch đã có id.
  Future<Branch> createBranch({
    required String shopId,
    required String name,
    String? address,
  }) async {
    _guard();
    if (name.trim().isEmpty) throw ArgumentError('Tên chi nhánh không được trống');
    final branch = Branch(
      shopId: shopId,
      name: name.trim(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      createdAt: DateTime.now(),
    );
    final id = await _repo.addBranch(branch);
    return branch.copyWith(id: id);
  }

  /// Cập nhật thông tin chi nhánh.
  Future<void> updateBranch(Branch branch) async {
    _guard();
    assert(branch.id != null, 'Branch phải có id');
    await _repo.updateBranch(branch);
    // Cập nhật context nếu đang active branch này
    if (_activeContext?.branchId == branch.id) {
      _activeContext = BranchContext(branch: branch);
    }
  }

  /// Vô hiệu hoá chi nhánh (soft delete).
  Future<void> deactivateBranch(int branchId) async {
    _guard();
    await _repo.deactivateBranch(branchId);
    if (_activeContext?.branchId == branchId) {
      _activeContext = null;
    }
  }

  /// Lấy danh sách chi nhánh active của shop.
  Future<List<Branch>> getBranches(String shopId) async {
    _guard();
    return _repo.getBranchesForShop(shopId);
  }

  Future<Branch?> getBranchById(int id) async {
    _guard();
    return _repo.getBranchById(id);
  }

  // ─── Branch Context (session active branch) ────────────────────────────────

  /// Chi nhánh đang active trong session.
  BranchContext? get activeContext => _activeContext;

  /// Đặt chi nhánh active. Gọi khi user chọn/chuyển chi nhánh.
  Future<void> setActiveBranch(int branchId) async {
    _guard();
    final branch = await _repo.getBranchById(branchId);
    if (branch == null) throw StateError('Branch $branchId không tồn tại');
    _activeContext = BranchContext(branch: branch);
  }

  /// Xoá active context (ví dụ khi logout).
  void clearActiveBranch() => _activeContext = null;

  // ─── User Assignment ───────────────────────────────────────────────────────

  /// Gán user vào chi nhánh.
  Future<void> assignUserToBranch({
    required String userId,
    required int branchId,
    String role = 'staff',
  }) async {
    _guard();
    await _repo.assignUser(BranchUser(
      userId: userId,
      branchId: branchId,
      role: role,
      assignedAt: DateTime.now(),
    ));
  }

  /// Chuyển user sang chi nhánh mới.
  Future<void> switchUserBranch({
    required String userId,
    required int newBranchId,
    String role = 'staff',
  }) async {
    _guard();
    await _repo.reassignUser(
      userId: userId,
      newBranchId: newBranchId,
      role: role,
    );
    // Cập nhật active context nếu đang xem chi nhánh cũ
    await setActiveBranch(newBranchId);
  }

  /// Chi nhánh hiện tại của user (từ DB).
  Future<Branch?> getBranchForUser(String userId) async {
    _guard();
    return _repo.getBranchForUser(userId);
  }

  Future<List<BranchUser>> getUsersInBranch(int branchId) async {
    _guard();
    return _repo.getUsersInBranch(branchId);
  }

  // ─── Inventory (Branch-scoped) ─────────────────────────────────────────────

  /// Upsert tồn kho chi nhánh cho 1 sản phẩm.
  Future<void> setInventory({
    required String productId,
    required int branchId,
    required int quantity,
  }) async {
    _guard();
    await _repo.upsertInventory(BranchInventory(
      productId: productId,
      branchId: branchId,
      quantity: quantity,
      updatedAt: DateTime.now(),
    ));
  }

  /// Điều chỉnh tồn kho (cộng/trừ delta).
  Future<void> adjustInventory({
    required String productId,
    required int branchId,
    required int delta,
  }) async {
    _guard();
    await _repo.adjustInventory(
      productId: productId,
      branchId: branchId,
      delta: delta,
    );
  }

  /// Lấy tồn kho của active branch, hoặc branchId cụ thể.
  Future<List<BranchInventory>> getInventory({int? branchId}) async {
    _guard();
    final id = branchId ?? _activeContext?.branchId;
    if (id == null) return [];
    return _repo.getInventoryForBranch(id);
  }

  Future<int> getTotalQuantityForProduct(String productId) async {
    _guard();
    return _repo.getTotalQuantityForProduct(productId);
  }

  // ─── Filter helper ─────────────────────────────────────────────────────────

  /// Kiểm tra xem có nên filter theo branch không.
  /// Nếu module tắt → luôn trả false → dùng data như cũ.
  bool get shouldFilterByBranch =>
      flags.enableMultiBranch && _activeContext != null;

  /// branchId đang active (null nếu không filter).
  int? get activeBranchId =>
      shouldFilterByBranch ? _activeContext!.branchId : null;
}
