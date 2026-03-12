class Product {
  int? id;
  String? firestoreId;
  String? shopId;
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
  String type; // DEPRECATED - giữ lại để tương thích ngược
  int quantity;
  String? color;
  String? capacity; // Dung lượng (ví dụ: 64GB, 128GB, etc.)
  String? size; // Size quần áo/giày: XS, S, M, L, XL, 28, 29, 30...
  String? paymentMethod; // Phương thức thanh toán
  String? labelInfo; // Thông tin in trên tem
  bool isSynced;
  bool isPending; // Kho tạm - chưa có giá vốn
  String? pendingSupplier; // NCC tạm khi chưa xác nhận giá
  String? labelNote; // Nội dung in trên tem

  // === MULTI-INDUSTRY FIELDS (Phase 1) ===
  String? categoryId; // Tham chiếu đến ProductCategory (thay thế type)
  String? unit; // Đơn vị tính: cái, kg, lít, hộp...
  int? expiryDate; // Ngày hết hạn (milliseconds) - cho thực phẩm
  String? batchNumber; // Số lô hàng - cho thực phẩm
  String? variantParentId; // ID sản phẩm cha (nếu là biến thể)
  String? customData; // JSON string cho dữ liệu tùy chỉnh theo ngành
  String? sku; // Mã SKU tự động sinh: [NHOM]-[MODEL]-[INFO]-[STT]

  Product({
    this.id,
    this.firestoreId,
    this.shopId,
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
    this.size,
    this.paymentMethod,
    this.labelInfo,
    this.isSynced = false,
    this.isPending = false,
    this.pendingSupplier,
    this.labelNote,
    // Multi-industry fields
    this.categoryId,
    this.unit,
    this.expiryDate,
    this.batchNumber,
    this.variantParentId,
    this.customData,
    this.sku,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId ?? "prod_${createdAt}_$name",
      'shopId': shopId,
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
      'size': size,
      'paymentMethod': paymentMethod,
      'labelInfo': labelInfo,
      'isSynced': isSynced ? 1 : 0,
      'isPending': isPending ? 1 : 0,
      'pendingSupplier': pendingSupplier,
      'labelNote': labelNote,
      // Multi-industry fields
      'categoryId': categoryId,
      'unit': unit,
      'expiryDate': expiryDate,
      'batchNumber': batchNumber,
      'variantParentId': variantParentId,
      'customData': customData,
      'sku': sku,
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
  
  /// Normalize product type to consistent format (ASCII underscore)
  /// Handles old Vietnamese format: 'LINH KIỆN' → 'LINH_KIEN', 'PHỤ KIỆN' → 'PHU_KIEN'
  static String _normalizeType(String type) {
    switch (type) {
      case 'LINH KIỆN':
        return 'LINH_KIEN';
      case 'PHỤ KIỆN':
        return 'PHU_KIEN';
      default:
        return type;
    }
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
      shopId: map['shopId'],
      name: map['name'] ?? "",
      brand: map['brand'] ?? "KHÁC",
      model: map['model'],
      imei: map['imei'],
      cost: _parseInt(map['cost']),
      price: _parseInt(map['price']),
      condition: map['condition'] ?? "Mới",
      status: map['status'] is int ? map['status'] : 1,
      description: map['description'] ?? map['detail'] ?? "",
      images: map['images'],
      warranty: map['warranty'],
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? _parseTimestamp(map['updatedAt']) : null,
      supplier: map['supplier'],
      type: _normalizeType(map['type'] ?? 'DIEN_THOAI'),
      quantity: _parseInt(map['quantity'], 1),
      color: map['color'],
      capacity: map['capacity'],
      size: map['size'],
      paymentMethod: map['paymentMethod'],
      labelInfo: map['labelInfo'],
      isSynced: map['isSynced'] == 1,
      isPending: map['isPending'] == 1,
      pendingSupplier: map['pendingSupplier'],
      labelNote: map['labelNote'],
      // Multi-industry fields
      categoryId: map['categoryId'],
      unit: map['unit'],
      expiryDate: map['expiryDate'] != null ? _parseTimestamp(map['expiryDate']) : null,
      batchNumber: map['batchNumber'],
      variantParentId: map['variantParentId'],
      customData: map['customData'],
      sku: map['sku'],
    );
  }

  Product copyWith({
    int? id,
    String? firestoreId,
    String? shopId,
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
    String? size,
    String? paymentMethod,
    String? labelInfo,
    bool? isSynced,
    int? updatedAt,
    bool? isPending,
    String? pendingSupplier,
    String? labelNote,
    // Multi-industry fields
    String? categoryId,
    String? unit,
    int? expiryDate,
    String? batchNumber,
    String? variantParentId,
    String? customData,
    String? sku,
  }) {
    return Product(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
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
      size: size ?? this.size,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      labelInfo: labelInfo ?? this.labelInfo,
      isSynced: isSynced ?? this.isSynced,
      isPending: isPending ?? this.isPending,
      pendingSupplier: pendingSupplier ?? this.pendingSupplier,
      labelNote: labelNote ?? this.labelNote,
      // Multi-industry fields
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      expiryDate: expiryDate ?? this.expiryDate,
      batchNumber: batchNumber ?? this.batchNumber,
      variantParentId: variantParentId ?? this.variantParentId,
      customData: customData ?? this.customData,
      sku: sku ?? this.sku,
    );
  }

  // === HELPER GETTERS ===
  
  /// Kiểm tra sản phẩm có hạn sử dụng không
  bool get hasExpiry => expiryDate != null;
  
  /// Kiểm tra sản phẩm đã hết hạn chưa
  bool get isExpired => 
      expiryDate != null && 
      DateTime.fromMillisecondsSinceEpoch(expiryDate!).isBefore(DateTime.now());
  
  /// Kiểm tra sản phẩm sắp hết hạn (trong 7 ngày)
  bool get isNearExpiry {
    if (expiryDate == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiryDate!);
    final now = DateTime.now();
    return expiry.isAfter(now) && expiry.difference(now).inDays <= 7;
  }
  
  /// Kiểm tra đây có phải sản phẩm biến thể không
  bool get isVariant => variantParentId != null && variantParentId!.isNotEmpty;
}
