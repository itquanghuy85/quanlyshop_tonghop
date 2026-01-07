class QuickInputCode {
  int? id;
  String? firestoreId;
  String? shopId; // Shop ID để đồng bộ giữa các thiết bị
  String? code; // Mã code (có thể là firestoreId hoặc custom)
  String name; // Tên template
  String type; // 'PHONE' hoặc 'linh-phụ kiện'
  String? brand; // Thương hiệu (cho phone)
  String? model; // Model (cho phone)
  String? capacity; // Dung lượng (cho phone)
  String? color; // Màu sắc (cho phone)
  String? condition; // Tình trạng (cho phone)
  int? cost; // Giá nhập
  int? price; // Giá bán
  String? description; // Mô tả/ghi chú
  String? supplier; // Nhà cung cấp
  String? paymentMethod; // Phương thức thanh toán
  bool isActive; // Có đang active không
  int createdAt;
  bool isSynced;

  QuickInputCode({
    this.id,
    this.firestoreId,
    this.shopId,
    this.code,
    required this.name,
    required this.type,
    this.brand,
    this.model,
    this.capacity,
    this.color,
    this.condition,
    this.cost,
    this.price,
    this.description,
    this.supplier,
    this.paymentMethod,
    this.isActive = true,
    required this.createdAt,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'shopId': shopId,
      'code': code,
      'name': name,
      'type': type,
      'brand': brand,
      'model': model,
      'capacity': capacity,
      'color': color,
      'condition': condition,
      'cost': cost,
      'price': price,
      'description': description,
      'supplier': supplier,
      'paymentMethod': paymentMethod,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory QuickInputCode.fromMap(Map<String, dynamic> map) {
    return QuickInputCode(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? ''),
      firestoreId: map['firestoreId'],
      shopId: map['shopId'],
      code: map['code'],
      name: map['name'] ?? '',
      type: map['type'] ?? 'PHONE',
      brand: map['brand'],
      model: map['model'],
      capacity: map['capacity'],
      color: map['color'],
      condition: map['condition'],
      cost: map['cost'] is int ? map['cost'] : int.tryParse(map['cost']?.toString() ?? '0'),
      price: map['price'] is int ? map['price'] : int.tryParse(map['price']?.toString() ?? '0'),
      description: map['description'],
      supplier: map['supplier'],
      paymentMethod: map['paymentMethod'],
      isActive: map['isActive'] is int ? map['isActive'] == 1 : (map['isActive'] == true || map['isActive'] == 1),
      createdAt: map['createdAt'] is int ? map['createdAt'] : int.tryParse(map['createdAt']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString()) ?? DateTime.now().millisecondsSinceEpoch,
      isSynced: map['isSynced'] is int ? map['isSynced'] == 1 : (map['isSynced'] == true || map['isSynced'] == 1),
    );
  }

  QuickInputCode copyWith({
    int? id,
    String? firestoreId,
    String? code,
    String? name,
    String? type,
    String? brand,
    String? model,
    String? capacity,
    String? color,
    String? condition,
    int? cost,
    int? price,
    String? description,
    String? supplier,
    String? paymentMethod,
    bool? isActive,
    int? createdAt,
    bool? isSynced,
  }) {
    return QuickInputCode(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      capacity: capacity ?? this.capacity,
      color: color ?? this.color,
      condition: condition ?? this.condition,
      cost: cost ?? this.cost,
      price: price ?? this.price,
      description: description ?? this.description,
      supplier: supplier ?? this.supplier,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}