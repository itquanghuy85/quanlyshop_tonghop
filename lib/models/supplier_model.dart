class Supplier {
  final int? id;
  final String? avatarUrl;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? note;
  final bool active;
  final bool favorite;
  final String? type; // 'warehouse' for KHO TỔNG, null for regular suppliers
  final int createdAt;
  final int updatedAt;
  final String shopId;
  final String? firestoreId;

  /// Check if this is the built-in central warehouse supplier
  bool get isWarehouse => type == 'warehouse';

  Supplier({
    this.id,
    this.avatarUrl,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.note,
    this.active = true,
    this.favorite = false,
    this.type,
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
      'avatarUrl': avatarUrl,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'note': note,
      'active': active ? 1 : 0,
      'favorite': favorite ? 1 : 0,
      'type': type,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'shopId': shopId,
      'firestoreId': firestoreId,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'],
      avatarUrl: map['avatarUrl'],
      name: map['name'],
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      note: map['note'],
      active: map['active'] == 1,
      favorite: map['favorite'] == 1,
      type: map['type'] as String?,
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      shopId: map['shopId'],
      firestoreId: map['firestoreId'],
    );
  }

  Supplier copyWith({
    int? id,
    String? avatarUrl,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? note,
    bool? active,
    bool? favorite,
    String? type,
    int? createdAt,
    int? updatedAt,
    String? shopId,
    String? firestoreId,
  }) {
    return Supplier(
      id: id ?? this.id,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      note: note ?? this.note,
      active: active ?? this.active,
      favorite: favorite ?? this.favorite,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopId: shopId ?? this.shopId,
      firestoreId: firestoreId ?? this.firestoreId,
    );
  }
}
