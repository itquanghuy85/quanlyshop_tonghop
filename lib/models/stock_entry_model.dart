import 'package:cloud_firestore/cloud_firestore.dart';

/// Trạng thái phiếu nhập kho
enum StockEntryStatus {
  draft,      // Chờ xác nhận
  confirmed,  // Đã xác nhận - đã vào kho chính
  cancelled,  // Đã hủy
}

/// Loại nhập kho
enum StockEntryType {
  quick,    // Nhập nhanh (đủ thông tin ngay)
  staging,  // Nhập tạm (chờ bổ sung)
}

/// Item trong phiếu nhập kho
class StockEntryItem {
  final String? id;
  final String name;
  final int quantity;
  final double? cost;        // Giá vốn mỗi đơn vị
  final double? price;       // Giá bán (nếu có)
  
  // Chỉ điện thoại
  final String? imei;
  final String? brand;
  final String? model;
  final String? capacity;
  final String? color;
  final String? condition;
  
  // Chỉ phụ kiện/linh kiện
  final String? sku;
  final String? unit;
  
  // Loại sản phẩm
  final String productType;  // DIEN_THOAI, PHU_KIEN, LINH_KIEN
  
  StockEntryItem({
    this.id,
    required this.name,
    required this.quantity,
    this.cost,
    this.price,
    this.imei,
    this.brand,
    this.model,
    this.capacity,
    this.color,
    this.condition,
    this.sku,
    this.unit,
    required this.productType,
  });
  
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'quantity': quantity,
      if (cost != null) 'cost': cost,
      if (price != null) 'price': price,
      if (imei != null && imei!.isNotEmpty) 'imei': imei,
      if (brand != null && brand!.isNotEmpty) 'brand': brand,
      if (model != null && model!.isNotEmpty) 'model': model,
      if (capacity != null && capacity!.isNotEmpty) 'capacity': capacity,
      if (color != null && color!.isNotEmpty) 'color': color,
      if (condition != null && condition!.isNotEmpty) 'condition': condition,
      if (sku != null && sku!.isNotEmpty) 'sku': sku,
      if (unit != null && unit!.isNotEmpty) 'unit': unit,
      'productType': productType,
    };
  }
  
  factory StockEntryItem.fromMap(Map<String, dynamic> map) {
    return StockEntryItem(
      id: map['id'],
      name: map['name'] ?? '',
      quantity: (map['quantity'] ?? 1).toInt(),
      cost: map['cost']?.toDouble(),
      price: map['price']?.toDouble(),
      imei: map['imei'],
      brand: map['brand'],
      model: map['model'],
      capacity: map['capacity'],
      color: map['color'],
      condition: map['condition'],
      sku: map['sku'],
      unit: map['unit'],
      productType: map['productType'] ?? 'DIEN_THOAI',
    );
  }
  
  StockEntryItem copyWith({
    String? id,
    String? name,
    int? quantity,
    double? cost,
    double? price,
    String? imei,
    String? brand,
    String? model,
    String? capacity,
    String? color,
    String? condition,
    String? sku,
    String? unit,
    String? productType,
  }) {
    return StockEntryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      cost: cost ?? this.cost,
      price: price ?? this.price,
      imei: imei ?? this.imei,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      capacity: capacity ?? this.capacity,
      color: color ?? this.color,
      condition: condition ?? this.condition,
      sku: sku ?? this.sku,
      unit: unit ?? this.unit,
      productType: productType ?? this.productType,
    );
  }
  
  /// Tổng giá vốn của item
  double get totalCost => (cost ?? 0) * quantity;
  
  /// Kiểm tra đủ thông tin kế toán
  bool get hasAccountingInfo => cost != null && cost! > 0;
  
  /// Tên hiển thị đầy đủ
  String get displayName {
    if (productType == 'DIEN_THOAI') {
      final parts = <String>[name];
      if (capacity != null && capacity!.isNotEmpty) parts.add(capacity!);
      if (color != null && color!.isNotEmpty) parts.add(color!);
      return parts.join(' ');
    }
    return name;
  }
}

/// Phiếu nhập kho (Staging Entry)
class StockEntry {
  final String? id;
  final String? firestoreId;
  final String shopId;
  
  // Trạng thái
  final StockEntryStatus status;
  final StockEntryType entryType;
  final bool locked;
  
  // Danh sách sản phẩm
  final List<StockEntryItem> items;
  
  // Thông tin kế toán
  final String? supplierId;
  final String? supplierName;
  final double? totalCost;
  final String? paymentMethod;  // TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ
  
  // Metadata
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? confirmedAt;
  final String? confirmedBy;
  final DateTime? updatedAt;
  
  StockEntry({
    this.id,
    this.firestoreId,
    required this.shopId,
    this.status = StockEntryStatus.draft,
    this.entryType = StockEntryType.staging,
    this.locked = false,
    this.items = const [],
    this.supplierId,
    this.supplierName,
    this.totalCost,
    this.paymentMethod,
    this.notes,
    this.createdAt,
    this.createdBy,
    this.confirmedAt,
    this.confirmedBy,
    this.updatedAt,
  });
  
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      if (id != null) 'id': id,
      'shopId': shopId,
      'status': status.name.toLowerCase(), // phải lowercase để match Firestore rules
      'entryType': entryType.name.toLowerCase(),
      'locked': locked,
      'items': items.map((e) => e.toMap()).toList(),
      if (supplierId != null) 'supplierId': supplierId,
      if (supplierName != null) 'supplierName': supplierName,
      if (totalCost != null) 'totalCost': totalCost,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (createdBy != null) 'createdBy': createdBy,
      if (confirmedBy != null) 'confirmedBy': confirmedBy,
    };
    
    // Handle timestamps properly for Firestore
    if (createdAt != null) {
      map['createdAt'] = Timestamp.fromDate(createdAt!);
    } else {
      map['createdAt'] = FieldValue.serverTimestamp();
    }
    
    if (confirmedAt != null) {
      map['confirmedAt'] = Timestamp.fromDate(confirmedAt!);
    }
    
    map['updatedAt'] = FieldValue.serverTimestamp();
    
    return map;
  }
  
  factory StockEntry.fromMap(Map<String, dynamic> map, {String? docId}) {
    // Parse status
    StockEntryStatus status = StockEntryStatus.draft;
    final statusStr = (map['status'] ?? 'DRAFT').toString().toLowerCase();
    if (statusStr == 'confirmed') {
      status = StockEntryStatus.confirmed;
    } else if (statusStr == 'cancelled') {
      status = StockEntryStatus.cancelled;
    }
    
    // Parse entry type
    StockEntryType entryType = StockEntryType.staging;
    final typeStr = (map['entryType'] ?? 'STAGING').toString().toLowerCase();
    if (typeStr == 'quick') {
      entryType = StockEntryType.quick;
    }
    
    // Parse items
    List<StockEntryItem> items = [];
    if (map['items'] != null) {
      items = (map['items'] as List)
          .map((e) => StockEntryItem.fromMap(e as Map<String, dynamic>))
          .toList();
    }
    
    // Parse timestamps
    DateTime? createdAt;
    if (map['createdAt'] != null) {
      if (map['createdAt'] is Timestamp) {
        createdAt = (map['createdAt'] as Timestamp).toDate();
      } else if (map['createdAt'] is DateTime) {
        createdAt = map['createdAt'];
      }
    }
    
    DateTime? confirmedAt;
    if (map['confirmedAt'] != null) {
      if (map['confirmedAt'] is Timestamp) {
        confirmedAt = (map['confirmedAt'] as Timestamp).toDate();
      } else if (map['confirmedAt'] is DateTime) {
        confirmedAt = map['confirmedAt'];
      }
    }
    
    DateTime? updatedAt;
    if (map['updatedAt'] != null) {
      if (map['updatedAt'] is Timestamp) {
        updatedAt = (map['updatedAt'] as Timestamp).toDate();
      } else if (map['updatedAt'] is DateTime) {
        updatedAt = map['updatedAt'];
      }
    }
    
    return StockEntry(
      id: map['id'],
      firestoreId: docId ?? map['firestoreId'],
      shopId: map['shopId'] ?? '',
      status: status,
      entryType: entryType,
      locked: map['locked'] ?? false,
      items: items,
      supplierId: map['supplierId'],
      supplierName: map['supplierName'],
      totalCost: map['totalCost']?.toDouble(),
      paymentMethod: map['paymentMethod'],
      notes: map['notes'],
      createdAt: createdAt,
      createdBy: map['createdBy'],
      confirmedAt: confirmedAt,
      confirmedBy: map['confirmedBy'],
      updatedAt: updatedAt,
    );
  }
  
  StockEntry copyWith({
    String? id,
    String? firestoreId,
    String? shopId,
    StockEntryStatus? status,
    StockEntryType? entryType,
    bool? locked,
    List<StockEntryItem>? items,
    String? supplierId,
    String? supplierName,
    double? totalCost,
    String? paymentMethod,
    String? notes,
    DateTime? createdAt,
    String? createdBy,
    DateTime? confirmedAt,
    String? confirmedBy,
    DateTime? updatedAt,
  }) {
    return StockEntry(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      status: status ?? this.status,
      entryType: entryType ?? this.entryType,
      locked: locked ?? this.locked,
      items: items ?? this.items,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      totalCost: totalCost ?? this.totalCost,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  // === COMPUTED PROPERTIES ===
  
  /// Kiểm tra có phải draft không
  bool get isDraft => status == StockEntryStatus.draft;
  
  /// Kiểm tra đã xác nhận chưa
  bool get isConfirmed => status == StockEntryStatus.confirmed;
  
  /// Kiểm tra đã hủy chưa
  bool get isCancelled => status == StockEntryStatus.cancelled;
  
  /// Tổng số lượng sản phẩm
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
  
  /// Tổng số item
  int get itemCount => items.length;
  
  /// Tính tổng giá vốn từ items
  double get calculatedTotalCost => 
      items.fold(0.0, (sum, item) => sum + item.totalCost);
  
  /// Kiểm tra đủ thông tin để xác nhận
  bool get canConfirm {
    if (items.isEmpty) return false;
    if (supplierId == null || supplierId!.isEmpty) return false;
    if (paymentMethod == null || paymentMethod!.isEmpty) return false;
    // Tất cả items phải có giá vốn
    return items.every((item) => item.hasAccountingInfo);
  }
  
  /// Danh sách thông tin còn thiếu
  List<String> get missingInfo {
    final missing = <String>[];
    if (items.isEmpty) {
      missing.add('Chưa có sản phẩm');
    } else {
      final itemsWithoutCost = items.where((i) => !i.hasAccountingInfo).length;
      if (itemsWithoutCost > 0) {
        missing.add('$itemsWithoutCost sản phẩm chưa có giá vốn');
      }
    }
    if (supplierId == null || supplierId!.isEmpty) {
      missing.add('Chưa chọn nhà cung cấp');
    }
    if (paymentMethod == null || paymentMethod!.isEmpty) {
      missing.add('Chưa chọn thanh toán');
    }
    return missing;
  }
  
  /// Số ngày kể từ khi tạo
  int get daysSinceCreated {
    if (createdAt == null) return 0;
    return DateTime.now().difference(createdAt!).inDays;
  }
  
  /// Loại sản phẩm chính (lấy từ item đầu tiên)
  String get primaryProductType {
    if (items.isEmpty) return 'DIEN_THOAI';
    return items.first.productType;
  }
  
  /// Icon theo loại sản phẩm
  String get productTypeIcon {
    switch (primaryProductType) {
      case 'DIEN_THOAI':
        return '📱';
      case 'PHU_KIEN':
        return '🎧';
      case 'LINH_KIEN':
        return '🔧';
      default:
        return '📦';
    }
  }
}
