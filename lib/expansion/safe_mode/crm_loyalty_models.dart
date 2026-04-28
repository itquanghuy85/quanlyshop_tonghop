/// Model lưu tổng điểm của một khách hàng trong CRM module.
/// Không liên kết với bảng customer cũ — chỉ dùng customerId làm khóa ngoài logic.
class LoyaltyPoint {
  /// ID của khách hàng trong hệ thống cũ (không thay đổi bảng customer).
  final String customerId;
  final String customerName;
  final int totalPoints;
  final DateTime updatedAt;

  const LoyaltyPoint({
    required this.customerId,
    required this.customerName,
    required this.totalPoints,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'totalPoints': totalPoints,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static LoyaltyPoint fromMap(Map<String, dynamic> map) {
    return LoyaltyPoint(
      customerId: (map['customerId'] ?? '').toString(),
      customerName: (map['customerName'] ?? '').toString(),
      totalPoints: (map['totalPoints'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  LoyaltyPoint copyWith({
    String? customerId,
    String? customerName,
    int? totalPoints,
    DateTime? updatedAt,
  }) {
    return LoyaltyPoint(
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      totalPoints: totalPoints ?? this.totalPoints,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum CustomerLevelTier { regular, silver, gold, platinum }

extension CustomerLevelTierX on CustomerLevelTier {
  String get displayName {
    switch (this) {
      case CustomerLevelTier.regular:
        return 'Thường';
      case CustomerLevelTier.silver:
        return 'Bạc';
      case CustomerLevelTier.gold:
        return 'Vàng';
      case CustomerLevelTier.platinum:
        return 'Kim cương';
    }
  }

  static CustomerLevelTier fromString(String value) {
    switch (value) {
      case 'silver':
        return CustomerLevelTier.silver;
      case 'gold':
        return CustomerLevelTier.gold;
      case 'platinum':
        return CustomerLevelTier.platinum;
      default:
        return CustomerLevelTier.regular;
    }
  }

  String toDbString() {
    switch (this) {
      case CustomerLevelTier.regular:
        return 'regular';
      case CustomerLevelTier.silver:
        return 'silver';
      case CustomerLevelTier.gold:
        return 'gold';
      case CustomerLevelTier.platinum:
        return 'platinum';
    }
  }
}

/// Model lưu hạng thành viên của khách hàng trong CRM module.
class CustomerLevel {
  final String customerId;
  final CustomerLevelTier tier;
  final int pointsAtLastUpdate;
  final DateTime updatedAt;

  const CustomerLevel({
    required this.customerId,
    required this.tier,
    required this.pointsAtLastUpdate,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'tier': tier.toDbString(),
      'pointsAtLastUpdate': pointsAtLastUpdate,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static CustomerLevel fromMap(Map<String, dynamic> map) {
    return CustomerLevel(
      customerId: (map['customerId'] ?? '').toString(),
      tier: CustomerLevelTierX.fromString((map['tier'] ?? '').toString()),
      pointsAtLastUpdate: (map['pointsAtLastUpdate'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

enum LoyaltyTransactionType { earn, redeem }

extension LoyaltyTransactionTypeX on LoyaltyTransactionType {
  String toDbString() => this == LoyaltyTransactionType.earn ? 'earn' : 'redeem';

  static LoyaltyTransactionType fromString(String value) {
    return value == 'earn' ? LoyaltyTransactionType.earn : LoyaltyTransactionType.redeem;
  }
}

/// Model lưu từng giao dịch điểm (cộng/trừ) trong lịch sử CRM module.
class LoyaltyTransaction {
  final int? id;
  final String customerId;
  final LoyaltyTransactionType type;
  final int points;
  final int discountAmount;
  final String note;
  final DateTime createdAt;

  const LoyaltyTransaction({
    this.id,
    required this.customerId,
    required this.type,
    required this.points,
    required this.discountAmount,
    required this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customerId': customerId,
      'type': type.toDbString(),
      'points': points,
      'discountAmount': discountAmount,
      'note': note,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  static LoyaltyTransaction fromMap(Map<String, dynamic> map) {
    return LoyaltyTransaction(
      id: (map['id'] as num?)?.toInt(),
      customerId: (map['customerId'] ?? '').toString(),
      type: LoyaltyTransactionTypeX.fromString((map['type'] ?? '').toString()),
      points: (map['points'] as num?)?.toInt() ?? 0,
      discountAmount: (map['discountAmount'] as num?)?.toInt() ?? 0,
      note: (map['note'] ?? '').toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
