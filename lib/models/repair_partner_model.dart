class RepairPartner {
  final int? id;
  final String name;
  final String? phone;
  final String? note;
  final bool active;
  final int createdAt;
  final int updatedAt;
  final String shopId;
  final String? firestoreId;

  RepairPartner({
    this.id,
    required this.name,
    this.phone,
    this.note,
    this.active = true,
    int? createdAt,
    int? updatedAt,
    required this.shopId,
    this.firestoreId,
  }) : 
    createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
    updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'note': note,
      'active': active ? 1 : 0,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'shopId': shopId,
      'firestoreId': firestoreId,
    };
  }

  factory RepairPartner.fromMap(Map<String, dynamic> map) {
    return RepairPartner(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      note: map['note'],
      active: map['active'] == 1,
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      shopId: map['shopId'],
      firestoreId: map['firestoreId'],
    );
  }

  RepairPartner copyWith({
    int? id,
    String? name,
    String? phone,
    String? note,
    bool? active,
    int? createdAt,
    int? updatedAt,
    String? shopId,
    String? firestoreId,
  }) {
    return RepairPartner(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopId: shopId ?? this.shopId,
      firestoreId: firestoreId ?? this.firestoreId,
    );
  }
}