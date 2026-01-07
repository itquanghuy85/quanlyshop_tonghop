import 'dart:convert';

class PurchaseItem {
  String? productName;
  String? imei;
  int quantity;
  int unitCost;
  int unitPrice;
  String? color;
  String? capacity;
  String condition;

  PurchaseItem({
    this.productName,
    this.imei,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    this.color,
    this.capacity,
    this.condition = 'Mới',
  });

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'imei': imei,
      'quantity': quantity,
      'unitCost': unitCost,
      'unitPrice': unitPrice,
      'color': color,
      'capacity': capacity,
      'condition': condition,
    };
  }

  factory PurchaseItem.fromMap(Map<String, dynamic> map) {
    return PurchaseItem(
      productName: map['productName'],
      imei: map['imei'],
      quantity: map['quantity'] ?? 0,
      unitCost: map['unitCost'] ?? 0,
      unitPrice: map['unitPrice'] ?? 0,
      color: map['color'],
      capacity: map['capacity'],
      condition: map['condition'] ?? 'Mới',
    );
  }

  PurchaseItem copyWith({
    String? productName,
    String? imei,
    int? quantity,
    int? unitCost,
    int? unitPrice,
    String? color,
    String? capacity,
    String? condition,
  }) {
    return PurchaseItem(
      productName: productName ?? this.productName,
      imei: imei ?? this.imei,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      unitPrice: unitPrice ?? this.unitPrice,
      color: color ?? this.color,
      capacity: capacity ?? this.capacity,
      condition: condition ?? this.condition,
    );
  }
}

class PurchaseOrder {
  String orderCode;
  String supplierName;
  String? supplierPhone;
  String? supplierAddress;
  List<PurchaseItem> items;
  int createdAt;
  String createdBy;
  String? notes;
  String status;
  String? paymentMethod;
  String? firestoreId;

  int get totalAmount => items.fold(0, (sum, item) => sum + item.quantity);
  int get totalCost => items.fold(0, (sum, item) => sum + (item.unitCost * item.quantity));

  PurchaseOrder({
    required this.orderCode,
    required this.supplierName,
    this.supplierPhone,
    this.supplierAddress,
    required this.items,
    required this.createdAt,
    required this.createdBy,
    this.notes,
    this.status = 'PENDING',
    this.paymentMethod,
    this.firestoreId,
  });

  void calculateTotals() {
    // Method to calculate totals if needed
  }

  Map<String, dynamic> toMap() {
    return {
      'orderCode': orderCode,
      'supplierName': supplierName,
      'supplierPhone': supplierPhone,
      'supplierAddress': supplierAddress,
      'itemsJson': jsonEncode(items.map((item) => item.toMap()).toList()),
      'totalAmount': totalAmount,
      'totalCost': totalCost,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'notes': notes,
      'status': status,
      'paymentMethod': paymentMethod,
      'firestoreId': firestoreId,
    };
  }

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      orderCode: map['orderCode'] ?? '',
      supplierName: map['supplierName'] ?? '',
      supplierPhone: map['supplierPhone'],
      supplierAddress: map['supplierAddress'],
      items: map['itemsJson'] != null
          ? (jsonDecode(map['itemsJson']) as List<dynamic>)
              .map((item) => PurchaseItem.fromMap(item as Map<String, dynamic>))
              .toList()
          : [],
      createdAt: map['createdAt'] ?? 0,
      createdBy: map['createdBy'] ?? '',
      notes: map['notes'],
      status: map['status'] ?? 'PENDING',
      paymentMethod: map['paymentMethod'],
      firestoreId: map['firestoreId'],
    );
  }
}
