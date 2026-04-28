/// Models cho Multi-Branch module — SAFE MODE
/// Không đụng bảng shop, user, hay product cũ.

// ─── Branch ──────────────────────────────────────────────────────────────────

class Branch {
  final int? id;
  final String shopId;
  final String name;
  final String? address;
  final bool isActive;
  final DateTime createdAt;

  const Branch({
    this.id,
    required this.shopId,
    required this.name,
    this.address,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'shopId': shopId,
        'name': name,
        'address': address,
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Branch.fromMap(Map<String, dynamic> m) => Branch(
        id: m['id'] as int?,
        shopId: m['shopId'] as String,
        name: m['name'] as String,
        address: m['address'] as String?,
        isActive: (m['isActive'] as int? ?? 1) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      );

  Branch copyWith({
    int? id,
    String? shopId,
    String? name,
    String? address,
    bool? isActive,
    DateTime? createdAt,
  }) =>
      Branch(
        id: id ?? this.id,
        shopId: shopId ?? this.shopId,
        name: name ?? this.name,
        address: address ?? this.address,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
}

// ─── BranchUser ──────────────────────────────────────────────────────────────

class BranchUser {
  final String userId;
  final int branchId;
  final String role; // 'manager' | 'staff'
  final DateTime assignedAt;

  const BranchUser({
    required this.userId,
    required this.branchId,
    this.role = 'staff',
    required this.assignedAt,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'branchId': branchId,
        'role': role,
        'assignedAt': assignedAt.millisecondsSinceEpoch,
      };

  factory BranchUser.fromMap(Map<String, dynamic> m) => BranchUser(
        userId: m['userId'] as String,
        branchId: m['branchId'] as int,
        role: m['role'] as String? ?? 'staff',
        assignedAt:
            DateTime.fromMillisecondsSinceEpoch(m['assignedAt'] as int),
      );
}

// ─── BranchInventory ─────────────────────────────────────────────────────────

class BranchInventory {
  final int? id;
  final String productId; // firestoreId từ product
  final int branchId;
  final int quantity;
  final DateTime updatedAt;

  const BranchInventory({
    this.id,
    required this.productId,
    required this.branchId,
    required this.quantity,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'productId': productId,
        'branchId': branchId,
        'quantity': quantity,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory BranchInventory.fromMap(Map<String, dynamic> m) => BranchInventory(
        id: m['id'] as int?,
        productId: m['productId'] as String,
        branchId: m['branchId'] as int,
        quantity: m['quantity'] as int,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int),
      );
}

// ─── BranchContext ────────────────────────────────────────────────────────────
// Runtime state — lưu branch đang active; dùng trong service layer.

class BranchContext {
  final Branch branch;

  const BranchContext({required this.branch});

  int get branchId => branch.id!;
  String get branchName => branch.name;

  @override
  String toString() => 'BranchContext(branchId=$branchId, name=$branchName)';
}
