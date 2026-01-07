class SupplierProductPrices {
  final int? id;
  final String supplierId;
  final String productId;
  final String batchId;
  final double costPrice;
  final double sellingPrice;
  final int importDate;
  final int quantity;
  final int remainingQuantity;
  final String? note;
  final int createdAt;
  final int updatedAt;
  final String shopId;

  SupplierProductPrices({
    this.id,
    required this.supplierId,
    required this.productId,
    required this.batchId,
    required this.costPrice,
    required this.sellingPrice,
    required this.importDate,
    required this.quantity,
    required this.remainingQuantity,
    this.note,
    int? createdAt,
    int? updatedAt,
    required this.shopId,
  }) :
    createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
    updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplierId': supplierId,
      'productId': productId,
      'batchId': batchId,
      'costPrice': costPrice,
      'sellingPrice': sellingPrice,
      'importDate': importDate,
      'quantity': quantity,
      'remainingQuantity': remainingQuantity,
      'note': note,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'shopId': shopId,
    };
  }

  factory SupplierProductPrices.fromMap(Map<String, dynamic> map) {
    return SupplierProductPrices(
      id: map['id'],
      supplierId: map['supplierId'],
      productId: map['productId'],
      batchId: map['batchId'],
      costPrice: map['costPrice'],
      sellingPrice: map['sellingPrice'],
      importDate: map['importDate'],
      quantity: map['quantity'],
      remainingQuantity: map['remainingQuantity'],
      note: map['note'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      shopId: map['shopId'],
    );
  }

  SupplierProductPrices copyWith({
    int? id,
    String? supplierId,
    String? productId,
    String? batchId,
    double? costPrice,
    double? sellingPrice,
    int? importDate,
    int? quantity,
    int? remainingQuantity,
    String? note,
    int? createdAt,
    int? updatedAt,
    String? shopId,
  }) {
    return SupplierProductPrices(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      productId: productId ?? this.productId,
      batchId: batchId ?? this.batchId,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      importDate: importDate ?? this.importDate,
      quantity: quantity ?? this.quantity,
      remainingQuantity: remainingQuantity ?? this.remainingQuantity,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopId: shopId ?? this.shopId,
    );
  }
}