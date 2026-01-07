class Product {
  int? id;
  String? firestoreId;
  String name;
  String brand; // Trường bắt buộc
  String? model; // Model máy (ví dụ: iPhone 15 Pro, Galaxy S24, etc.)
  String? imei;
  int cost;
  int price;
  String condition;
  int status;
  String description;
  String? images;
  String? warranty;
  int createdAt;
  int? updatedAt;
  String? supplier;
  String type;
  int quantity;
  String? color;
  String? capacity; // Dung lượng (ví dụ: 64GB, 128GB, etc.)
  String? paymentMethod; // Phương thức thanh toán
  bool isSynced;

  Product({
    this.id,
    this.firestoreId,
    required this.name,
    this.brand = "KHÁC",
    this.model,
    this.imei,
    this.cost = 0,
    this.price = 0,
    this.condition = "Mới",
    this.status = 1,
    this.description = "",
    this.images,
    this.warranty,
    required this.createdAt,
    this.updatedAt,
    this.supplier,
    this.type = 'PHONE',
    this.quantity = 1,
    this.color,
    this.capacity,
    this.paymentMethod,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId ?? "prod_${createdAt}_$name",
      'name': name,
      'brand': brand,
      'model': model,
      'imei': imei,
      'cost': cost,
      'price': price,
      'condition': condition,
      'status': status,
      'description': description,
      'images': images,
      'warranty': warranty,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'supplier': supplier,
      'type': type,
      'quantity': quantity,
      'color': color,
      'capacity': capacity,
      'paymentMethod': paymentMethod,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      firestoreId: map['firestoreId'],
      name: map['name'] ?? "",
      brand: map['brand'] ?? "KHÁC",
      model: map['model'],
      imei: map['imei'],
      cost: (map['cost'] is int ? map['cost'] : 0) < 0 ? 0 : (map['cost'] is int ? map['cost'] : 0),
      price: (map['price'] is int ? map['price'] : 0) < 0 ? 0 : (map['price'] is int ? map['price'] : 0),
      condition: map['condition'] ?? "Mới",
      status: map['status'] is int ? map['status'] : 1,
      description: map['description'] ?? "",
      images: map['images'],
      warranty: map['warranty'],
      createdAt: map['createdAt'] is int ? map['createdAt'] : 0,
      updatedAt: map['updatedAt'] is int ? map['updatedAt'] : null,
      supplier: map['supplier'],
      type: map['type'] ?? 'PHONE',
      quantity: (map['quantity'] is int ? map['quantity'] : 1) < 0 ? 0 : (map['quantity'] is int ? map['quantity'] : 1),
      color: map['color'],
      capacity: map['capacity'],
      paymentMethod: map['paymentMethod'],
      isSynced: map['isSynced'] == 1,
    );
  }

  Product copyWith({
    int? id,
    String? firestoreId,
    String? name,
    String? brand,
    String? model,
    String? imei,
    int? cost,
    int? price,
    String? condition,
    int? status,
    String? description,
    String? images,
    String? warranty,
    int? createdAt,
    String? supplier,
    String? type,
    int? quantity,
    String? color,
    String? capacity,
    String? paymentMethod,
    bool? isSynced,
    int? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      imei: imei ?? this.imei,
      cost: cost ?? this.cost,
      price: price ?? this.price,
      condition: condition ?? this.condition,
      status: status ?? this.status,
      description: description ?? this.description,
      images: images ?? this.images,
      warranty: warranty ?? this.warranty,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      supplier: supplier ?? this.supplier,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      color: color ?? this.color,
      capacity: capacity ?? this.capacity,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
