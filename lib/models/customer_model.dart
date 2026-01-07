class Customer {
  int? id;
  String? firestoreId;
  String name;
  String phone;
  String? email;
  String? address;
  String? notes;
  int createdAt;
  int? lastVisitAt;
  int? updatedAt;
  int totalSpent; // Tổng tiền đã mua
  int totalRepairs; // Tổng số lần sửa chữa
  int totalRepairCost; // Tổng tiền sửa chữa
  String? shopId;
  bool isSynced;
  bool deleted;

  Customer({
    this.id,
    this.firestoreId,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.notes,
    required this.createdAt,
    this.lastVisitAt,
    this.updatedAt,
    this.totalSpent = 0,
    this.totalRepairs = 0,
    this.totalRepairCost = 0,
    this.shopId,
    this.isSynced = false,
    this.deleted = false,
  });

  // Convert to Map for database
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'createdAt': createdAt,
      'lastVisitAt': lastVisitAt,
      'updatedAt': updatedAt,
      'totalSpent': totalSpent,
      'totalRepairs': totalRepairs,
      'totalRepairCost': totalRepairCost,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
    };
  }

  // Create from Map
  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      firestoreId: map['firestoreId'],
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      address: map['address'],
      notes: map['notes'],
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      lastVisitAt: map['lastVisitAt'],
      updatedAt: map['updatedAt'],
      totalSpent: map['totalSpent'] ?? 0,
      totalRepairs: map['totalRepairs'] ?? 0,
      totalRepairCost: map['totalRepairCost'] ?? 0,
      shopId: map['shopId'],
      isSynced: (map['isSynced'] ?? 0) == 1,
      deleted: (map['deleted'] ?? 0) == 1,
    );
  }

  // Convert to Firestore Map
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'createdAt': createdAt,
      'lastVisitAt': lastVisitAt,
      'totalSpent': totalSpent,
      'totalRepairs': totalRepairs,
      'totalRepairCost': totalRepairCost,
      'deleted': deleted,
    };
  }

  // Create from Firestore Map
  factory Customer.fromFirestoreMap(String firestoreId, Map<String, dynamic> map) {
    return Customer(
      firestoreId: firestoreId,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      address: map['address'],
      notes: map['notes'],
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      lastVisitAt: map['lastVisitAt'],
      totalSpent: map['totalSpent'] ?? 0,
      totalRepairs: map['totalRepairs'] ?? 0,
      totalRepairCost: map['totalRepairCost'] ?? 0,
      deleted: map['deleted'] ?? false,
      isSynced: true,
    );
  }

  // Copy with
  Customer copyWith({
    int? id,
    String? firestoreId,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    int? createdAt,
    int? lastVisitAt,
    int? updatedAt,
    int? totalSpent,
    int? totalRepairs,
    int? totalRepairCost,
    String? shopId,
    bool? isSynced,
    bool? deleted,
  }) {
    return Customer(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      updatedAt: updatedAt ?? this.updatedAt,
      totalSpent: totalSpent ?? this.totalSpent,
      totalRepairs: totalRepairs ?? this.totalRepairs,
      totalRepairCost: totalRepairCost ?? this.totalRepairCost,
      shopId: shopId ?? this.shopId,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }

  @override
  String toString() {
    return 'Customer(id: $id, name: $name, phone: $phone, totalSpent: $totalSpent)';
  }
}