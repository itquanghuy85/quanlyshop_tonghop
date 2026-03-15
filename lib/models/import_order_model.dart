/// Model cho phiếu nhập kho (Import Order)
class ImportOrder {
  final int? id;
  final String? firestoreId;
  final String shopId;
  final String orderCode; // NK-0001, NK-0002...
  final String? supplierId;
  final String? supplierName;
  final int totalQuantity;
  final int totalAmount;
  final String? paymentMethod; // TIỀN MẶT / CHUYỂN KHOẢN / CÔNG NỢ
  final String paymentStatus; // PAID / DEBT
  final int? paidAmount;
  final String status; // CONFIRMED / CANCELLED
  final int? importDate;
  final String? importedBy;
  final String? importedByUid;
  final String? stockEntryId; // FK to stock_entries firestoreId
  final String? notes;
  final int? createdAt;
  final int? updatedAt;
  final int isSynced;
  final int deleted;

  const ImportOrder({
    this.id,
    this.firestoreId,
    required this.shopId,
    required this.orderCode,
    this.supplierId,
    this.supplierName,
    this.totalQuantity = 0,
    this.totalAmount = 0,
    this.paymentMethod,
    this.paymentStatus = 'PAID',
    this.paidAmount,
    this.status = 'CONFIRMED',
    this.importDate,
    this.importedBy,
    this.importedByUid,
    this.stockEntryId,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.deleted = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'firestoreId': firestoreId,
      'shopId': shopId,
      'orderCode': orderCode,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'totalQuantity': totalQuantity,
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'paidAmount': paidAmount,
      'status': status,
      'importDate': importDate,
      'importedBy': importedBy,
      'importedByUid': importedByUid,
      'stockEntryId': stockEntryId,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isSynced': isSynced,
      'deleted': deleted,
    };
  }

  factory ImportOrder.fromMap(Map<String, dynamic> map) {
    return ImportOrder(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      shopId: (map['shopId'] ?? '') as String,
      orderCode: (map['orderCode'] ?? '') as String,
      supplierId: map['supplierId'] as String?,
      supplierName: map['supplierName'] as String?,
      totalQuantity: (map['totalQuantity'] as int?) ?? 0,
      totalAmount: (map['totalAmount'] as int?) ?? 0,
      paymentMethod: map['paymentMethod'] as String?,
      paymentStatus: (map['paymentStatus'] ?? 'PAID') as String,
      paidAmount: map['paidAmount'] as int?,
      status: (map['status'] ?? 'CONFIRMED') as String,
      importDate: map['importDate'] as int?,
      importedBy: map['importedBy'] as String?,
      importedByUid: map['importedByUid'] as String?,
      stockEntryId: map['stockEntryId'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] as int?,
      updatedAt: map['updatedAt'] as int?,
      isSynced: (map['isSynced'] as int?) ?? 0,
      deleted: (map['deleted'] as int?) ?? 0,
    );
  }

  ImportOrder copyWith({
    int? id,
    String? firestoreId,
    String? shopId,
    String? orderCode,
    String? supplierId,
    String? supplierName,
    int? totalQuantity,
    int? totalAmount,
    String? paymentMethod,
    String? paymentStatus,
    int? paidAmount,
    String? status,
    int? importDate,
    String? importedBy,
    String? importedByUid,
    String? stockEntryId,
    String? notes,
    int? createdAt,
    int? updatedAt,
    int? isSynced,
    int? deleted,
  }) {
    return ImportOrder(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      orderCode: orderCode ?? this.orderCode,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      importDate: importDate ?? this.importDate,
      importedBy: importedBy ?? this.importedBy,
      importedByUid: importedByUid ?? this.importedByUid,
      stockEntryId: stockEntryId ?? this.stockEntryId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }
}

/// Model cho chi tiết từng dòng trong phiếu nhập
class ImportOrderItem {
  final int? id;
  final String? firestoreId;
  final String? importOrderFirestoreId; // FK to import_orders
  final String productType; // DIEN_THOAI / PHU_KIEN / LINH_KIEN / QUAN_AO / GIAY_DEP / OTHER
  final String? categoryId;
  final String productName;
  final String? productBrand;
  final String? productModel;
  final String? imei;
  final String? sku;
  final int quantity;
  final String? unit;
  final int costPrice; // đơn giá
  final int totalAmount; // thành tiền
  final String? color;
  final String? size;
  final String? capacity;
  final String? condition; // Mới / Cũ
  final int? warranty; // months
  final String? compatibleModels; // linh kiện
  final String? notes;
  final String? shopId;
  final int isSynced;
  final int deleted;

  const ImportOrderItem({
    this.id,
    this.firestoreId,
    this.importOrderFirestoreId,
    this.productType = 'OTHER',
    this.categoryId,
    required this.productName,
    this.productBrand,
    this.productModel,
    this.imei,
    this.sku,
    this.quantity = 1,
    this.unit,
    required this.costPrice,
    required this.totalAmount,
    this.color,
    this.size,
    this.capacity,
    this.condition,
    this.warranty,
    this.compatibleModels,
    this.notes,
    this.shopId,
    this.isSynced = 0,
    this.deleted = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'firestoreId': firestoreId,
      'importOrderFirestoreId': importOrderFirestoreId,
      'productType': productType,
      'categoryId': categoryId,
      'productName': productName,
      'productBrand': productBrand,
      'productModel': productModel,
      'imei': imei,
      'sku': sku,
      'quantity': quantity,
      'unit': unit,
      'costPrice': costPrice,
      'totalAmount': totalAmount,
      'color': color,
      'size': size,
      'capacity': capacity,
      'condition': condition,
      'warranty': warranty,
      'compatibleModels': compatibleModels,
      'notes': notes,
      'shopId': shopId,
      'isSynced': isSynced,
      'deleted': deleted,
    };
  }

  factory ImportOrderItem.fromMap(Map<String, dynamic> map) {
    return ImportOrderItem(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      importOrderFirestoreId: map['importOrderFirestoreId'] as String?,
      productType: (map['productType'] ?? 'OTHER') as String,
      categoryId: map['categoryId'] as String?,
      productName: (map['productName'] ?? '') as String,
      productBrand: map['productBrand'] as String?,
      productModel: map['productModel'] as String?,
      imei: map['imei'] as String?,
      sku: map['sku'] as String?,
      quantity: (map['quantity'] as int?) ?? 1,
      unit: map['unit'] as String?,
      costPrice: (map['costPrice'] as int?) ?? 0,
      totalAmount: (map['totalAmount'] as int?) ?? 0,
      color: map['color'] as String?,
      size: map['size'] as String?,
      capacity: map['capacity'] as String?,
      condition: map['condition'] as String?,
      warranty: map['warranty'] as int?,
      compatibleModels: map['compatibleModels'] as String?,
      notes: map['notes'] as String?,
      shopId: map['shopId'] as String?,
      isSynced: (map['isSynced'] as int?) ?? 0,
      deleted: (map['deleted'] as int?) ?? 0,
    );
  }

  /// Tên hiển thị dựa theo loại sản phẩm
  String get displayName {
    final parts = <String>[productName];
    if (capacity != null && capacity!.isNotEmpty) parts.add(capacity!);
    if (color != null && color!.isNotEmpty) parts.add(color!);
    if (size != null && size!.isNotEmpty) parts.add('Size $size');
    return parts.join(' - ');
  }

  /// Icon theo loại SP
  String get typeIcon {
    switch (productType) {
      case 'DIEN_THOAI': return '📱';
      case 'PHU_KIEN': return '🎧';
      case 'LINH_KIEN': return '🔧';
      case 'QUAN_AO': return '👕';
      case 'GIAY_DEP': return '👟';
      default: return '📦';
    }
  }

  String get typeLabel {
    switch (productType) {
      case 'DIEN_THOAI': return 'Điện thoại';
      case 'PHU_KIEN': return 'Phụ kiện';
      case 'LINH_KIEN': return 'Linh kiện';
      case 'QUAN_AO': return 'Quần áo';
      case 'GIAY_DEP': return 'Giày dép';
      default: return 'Khác';
    }
  }
}
