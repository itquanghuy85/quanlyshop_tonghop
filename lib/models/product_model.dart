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
  bool isPending; // Kho tạm - chưa có giá vốn
  String? pendingSupplier; // NCC tạm khi chưa xác nhận giá

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
    this.type = 'DIEN_THOAI',
    this.quantity = 1,
    this.color,
    this.capacity,
    this.paymentMethod,
    this.isSynced = false,
    this.isPending = false,
    this.pendingSupplier,
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
      'isPending': isPending ? 1 : 0,
      'pendingSupplier': pendingSupplier,
    };
  }

  /// Helper: parse int từ dynamic (hỗ trợ int, double, num, String)
  static int _parseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value < 0 ? 0 : value;
    if (value is double) return value < 0 ? 0 : value.toInt();
    if (value is num) return value < 0 ? 0 : value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return (parsed != null && parsed >= 0) ? parsed : defaultValue;
    }
    return defaultValue;
  }
  
  /// Helper: parse timestamp từ dynamic (hỗ trợ int, Timestamp, DateTime)
  static int _parseTimestamp(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value > 0 ? value : defaultValue;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    // Handle Firestore Timestamp
    if (value.runtimeType.toString().contains('Timestamp')) {
      try {
        // Firestore Timestamp has toDate() method
        final date = (value as dynamic).toDate() as DateTime;
        return date.millisecondsSinceEpoch;
      } catch (_) {}
    }
    return defaultValue;
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] is int ? map['id'] : null,
      firestoreId: map['firestoreId'],
      name: map['name'] ?? "",
      brand: map['brand'] ?? "KHÁC",
      model: map['model'],
      imei: map['imei'],
      cost: _parseInt(map['cost']),
      price: _parseInt(map['price']),
      condition: map['condition'] ?? "Mới",
      status: map['status'] is int ? map['status'] : 1,
      description: map['description'] ?? "",
      images: map['images'],
      warranty: map['warranty'],
      createdAt: _parseTimestamp(map['createdAt'], DateTime.now().millisecondsSinceEpoch),
      updatedAt: map['updatedAt'] != null ? _parseTimestamp(map['updatedAt']) : null,
      supplier: map['supplier'],
      type: map['type'] ?? 'DIEN_THOAI',
      quantity: _parseInt(map['quantity'], 1),
      color: map['color'],
      capacity: map['capacity'],
      paymentMethod: map['paymentMethod'],
      isSynced: map['isSynced'] == 1,
      isPending: map['isPending'] == 1,
      pendingSupplier: map['pendingSupplier'],
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
    bool? isPending,
    String? pendingSupplier,
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
      isPending: isPending ?? this.isPending,
      pendingSupplier: pendingSupplier ?? this.pendingSupplier,
    );
  }
}
