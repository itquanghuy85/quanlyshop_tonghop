class SupplierImportHistory {
  final int? id;
  final String supplierId;
  final String batchId;
  final int importDate;
  final int totalQuantity;
  final double totalCost;
  final String? note;
  final int createdAt;
  final int updatedAt;
  final String shopId;

  SupplierImportHistory({
    this.id,
    required this.supplierId,
    required this.batchId,
    required this.importDate,
    required this.totalQuantity,
    required this.totalCost,
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
      'batchId': batchId,
      'importDate': importDate,
      'totalQuantity': totalQuantity,
      'totalCost': totalCost,
      'note': note,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'shopId': shopId,
    };
  }

  factory SupplierImportHistory.fromMap(Map<String, dynamic> map) {
    return SupplierImportHistory(
      id: map['id'],
      supplierId: map['supplierId'],
      batchId: map['batchId'],
      importDate: map['importDate'],
      totalQuantity: map['totalQuantity'],
      totalCost: map['totalCost'],
      note: map['note'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      shopId: map['shopId'],
    );
  }

  SupplierImportHistory copyWith({
    int? id,
    String? supplierId,
    String? batchId,
    int? importDate,
    int? totalQuantity,
    double? totalCost,
    String? note,
    int? createdAt,
    int? updatedAt,
    String? shopId,
  }) {
    return SupplierImportHistory(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      batchId: batchId ?? this.batchId,
      importDate: importDate ?? this.importDate,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      totalCost: totalCost ?? this.totalCost,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shopId: shopId ?? this.shopId,
    );
  }
}