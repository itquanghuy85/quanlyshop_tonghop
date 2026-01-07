class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? note;
  final bool active;
  final bool favorite;
  final int createdAt;
  final int updatedAt;
  final String shopId;
  final String? firestoreId;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.note,
    this.active = true,
    this.favorite = false,
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
      'email': email,
      'address': address,
      'note': note,
      'active': active ? 1 : 0,
      'favorite': favorite ? 1 : 0,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'shopId': shopId,
      'firestoreId': firestoreId,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      email: map['email'],
      address: map['address'],
      note: map['note'],
      active: map['active'] == 1,
      favorite: map['favorite'] == 1,
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      shopId: map['shopId'],
      firestoreId: map['firestoreId'],
    );
  }

  Supplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? note,
    bool? active,
    bool? favorite,
    int? createdAt,
    int? updatedAt,
    String? shopId,
    String? firestoreId,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      note: note ?? this.note,
      active: active ?? this.active,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopId: shopId ?? this.shopId,
      firestoreId: firestoreId ?? this.firestoreId,
    );
  }
}