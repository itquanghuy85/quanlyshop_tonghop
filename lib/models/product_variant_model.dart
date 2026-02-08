/// Model biến thể sản phẩm - cho ngành thời trang và các sản phẩm có size/màu
/// Mỗi biến thể có thể có giá, tồn kho riêng
class ProductVariant {
  final String id;
  final String firestoreId;
  final String shopId;
  final String productId; // Tham chiếu đến sản phẩm cha

  // === THÔNG TIN BIẾN THỂ ===
  final String? sku; // Mã SKU riêng cho biến thể
  final String? size; // S, M, L, XL, 38, 39, 40...
  final String? color; // Đỏ, Xanh, Trắng...
  final String? colorCode; // Mã màu HEX cho UI
  final String? material; // Chất liệu (cotton, polyester...)
  final String? style; // Kiểu dáng

  // === GIÁ CẢ & TỒN KHO ===
  final int costPrice; // Giá vốn riêng (0 = dùng giá sản phẩm cha)
  final int salePrice; // Giá bán riêng (0 = dùng giá sản phẩm cha)
  final int quantity; // Tồn kho riêng
  final int minQuantity; // Mức tồn kho tối thiểu cảnh báo

  // === THÔNG TIN BỔ SUNG ===
  final String? barcode; // Mã vạch riêng
  final String? image; // Ảnh riêng cho biến thể
  final bool isActive; // Còn kinh doanh không

  // === METADATA ===
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedBy;
  final bool isSynced;

  ProductVariant({
    this.id = '',
    this.firestoreId = '',
    required this.shopId,
    required this.productId,
    this.sku,
    this.size,
    this.color,
    this.colorCode,
    this.material,
    this.style,
    this.costPrice = 0,
    this.salePrice = 0,
    this.quantity = 0,
    this.minQuantity = 0,
    this.barcode,
    this.image,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.updatedBy,
    this.isSynced = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Tên hiển thị của biến thể (VD: "Đỏ - Size M")
  String get displayName {
    final parts = <String>[];
    if (color != null && color!.isNotEmpty) parts.add(color!);
    if (size != null && size!.isNotEmpty) parts.add('Size $size');
    if (material != null && material!.isNotEmpty) parts.add(material!);
    return parts.isNotEmpty ? parts.join(' - ') : 'Biến thể';
  }

  /// Tạo từ Map (Firestore hoặc SQLite)
  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: (map['id'] ?? '').toString(),
      firestoreId: (map['firestoreId'] ?? map['id'] ?? '').toString(),
      shopId: map['shopId'] ?? '',
      productId: map['productId'] ?? '',
      sku: map['sku'],
      size: map['size'],
      color: map['color'],
      colorCode: map['colorCode'],
      material: map['material'],
      style: map['style'],
      costPrice: _parseInt(map['costPrice']),
      salePrice: _parseInt(map['salePrice']),
      quantity: _parseInt(map['quantity']),
      minQuantity: _parseInt(map['minQuantity']),
      barcode: map['barcode'],
      image: map['image'],
      isActive: map['isActive'] != false && map['isActive'] != 0,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      updatedBy: map['updatedBy'],
      isSynced: map['isSynced'] == true || map['isSynced'] == 1,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Chuyển sang Map cho Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'shopId': shopId,
      'productId': productId,
      'sku': sku,
      'size': size,
      'color': color,
      'colorCode': colorCode,
      'material': material,
      'style': style,
      'costPrice': costPrice,
      'salePrice': salePrice,
      'quantity': quantity,
      'minQuantity': minQuantity,
      'barcode': barcode,
      'image': image,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  /// Chuyển sang Map cho SQLite
  Map<String, dynamic> toMap() {
    return {
      'firestoreId': firestoreId.isNotEmpty ? firestoreId : null,
      'shopId': shopId,
      'productId': productId,
      'sku': sku,
      'size': size,
      'color': color,
      'colorCode': colorCode,
      'material': material,
      'style': style,
      'costPrice': costPrice,
      'salePrice': salePrice,
      'quantity': quantity,
      'minQuantity': minQuantity,
      'barcode': barcode,
      'image': image,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'updatedBy': updatedBy,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  /// Copy with để update
  ProductVariant copyWith({
    String? id,
    String? firestoreId,
    String? shopId,
    String? productId,
    String? sku,
    String? size,
    String? color,
    String? colorCode,
    String? material,
    String? style,
    int? costPrice,
    int? salePrice,
    int? quantity,
    int? minQuantity,
    String? barcode,
    String? image,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    bool? isSynced,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      size: size ?? this.size,
      color: color ?? this.color,
      colorCode: colorCode ?? this.colorCode,
      material: material ?? this.material,
      style: style ?? this.style,
      costPrice: costPrice ?? this.costPrice,
      salePrice: salePrice ?? this.salePrice,
      quantity: quantity ?? this.quantity,
      minQuantity: minQuantity ?? this.minQuantity,
      barcode: barcode ?? this.barcode,
      image: image ?? this.image,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      updatedBy: updatedBy ?? this.updatedBy,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Kiểm tra tồn kho thấp (còn hàng nhưng ít hơn ngưỡng)
  bool get isLowStock => quantity > 0 && quantity <= minQuantity;

  /// Kiểm tra hết hàng
  bool get isOutOfStock => quantity <= 0;

  @override
  String toString() =>
      'ProductVariant(productId: $productId, $displayName, qty: $quantity)';
}

/// Class chứa thông tin tổng hợp các biến thể của một sản phẩm
class VariantSummary {
  final String productId;
  final int totalVariants;
  final int totalStock;
  final int minPrice;
  final int maxPrice;
  final List<String> availableSizes;
  final List<String> availableColors;

  VariantSummary({
    required this.productId,
    this.totalVariants = 0,
    this.totalStock = 0,
    this.minPrice = 0,
    this.maxPrice = 0,
    this.availableSizes = const [],
    this.availableColors = const [],
  });

  /// Tạo từ danh sách variants
  factory VariantSummary.fromVariants(
      String productId, List<ProductVariant> variants) {
    if (variants.isEmpty) {
      return VariantSummary(productId: productId);
    }

    final sizes = <String>{};
    final colors = <String>{};
    int totalStock = 0;
    int minPrice = variants.first.salePrice;
    int maxPrice = variants.first.salePrice;

    for (final v in variants) {
      if (v.size != null && v.size!.isNotEmpty) sizes.add(v.size!);
      if (v.color != null && v.color!.isNotEmpty) colors.add(v.color!);
      totalStock += v.quantity;
      if (v.salePrice > 0 && v.salePrice < minPrice) minPrice = v.salePrice;
      if (v.salePrice > maxPrice) maxPrice = v.salePrice;
    }

    return VariantSummary(
      productId: productId,
      totalVariants: variants.length,
      totalStock: totalStock,
      minPrice: minPrice,
      maxPrice: maxPrice,
      availableSizes: sizes.toList()..sort(),
      availableColors: colors.toList()..sort(),
    );
  }

  /// Hiển thị range giá (VD: "100K - 200K")
  String get priceRange {
    if (minPrice == maxPrice) return '${minPrice ~/ 1000}K';
    return '${minPrice ~/ 1000}K - ${maxPrice ~/ 1000}K';
  }
}
