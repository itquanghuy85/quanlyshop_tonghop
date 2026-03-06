/// Model for sales return header
class SalesReturn {
  int? id;
  String? firestoreId;
  int? salesOrderId;
  String? salesOrderFirestoreId;
  String customerName;
  String customerPhone;
  int returnDate;
  int totalReturnAmount;
  int totalReturnCost;
  String refundMethod; // TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ
  String? note;
  int createdAt;
  String? createdBy;
  String? approvedBy;
  int? approvedAt;
  String status; // APPROVED, PENDING, REJECTED
  String? shopId;
  bool isSynced;

  SalesReturn({
    this.id,
    this.firestoreId,
    this.salesOrderId,
    this.salesOrderFirestoreId,
    required this.customerName,
    required this.customerPhone,
    required this.returnDate,
    this.totalReturnAmount = 0,
    this.totalReturnCost = 0,
    this.refundMethod = 'TIỀN MẶT',
    this.note,
    required this.createdAt,
    this.createdBy,
    this.approvedBy,
    this.approvedAt,
    this.status = 'APPROVED',
    this.shopId,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'firestoreId': firestoreId,
      'salesOrderId': salesOrderId,
      'salesOrderFirestoreId': salesOrderFirestoreId,
      'customerName': customerName.toUpperCase(),
      'customerPhone': customerPhone,
      'returnDate': returnDate,
      'totalReturnAmount': totalReturnAmount,
      'totalReturnCost': totalReturnCost,
      'refundMethod': refundMethod.toUpperCase(),
      'note': note,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt,
      'status': status,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory SalesReturn.fromMap(Map<String, dynamic> m) {
    return SalesReturn(
      id: m['id'] as int?,
      firestoreId: m['firestoreId'] as String?,
      salesOrderId: m['salesOrderId'] as int?,
      salesOrderFirestoreId: m['salesOrderFirestoreId'] as String?,
      customerName: (m['customerName'] ?? '') as String,
      customerPhone: (m['customerPhone'] ?? '') as String,
      returnDate: (m['returnDate'] ?? 0) as int,
      totalReturnAmount: (m['totalReturnAmount'] ?? 0) as int,
      totalReturnCost: (m['totalReturnCost'] ?? 0) as int,
      refundMethod: (m['refundMethod'] ?? 'TIỀN MẶT') as String,
      note: m['note'] as String?,
      createdAt: (m['createdAt'] ?? 0) as int,
      createdBy: m['createdBy'] as String?,
      approvedBy: m['approvedBy'] as String?,
      approvedAt: m['approvedAt'] as int?,
      status: (m['status'] ?? 'APPROVED') as String,
      shopId: m['shopId'] as String?,
      isSynced: m['isSynced'] == 1 || m['isSynced'] == true,
    );
  }
}

/// Model for individual items in a sales return
class SalesReturnItem {
  int? id;
  String? firestoreId;
  int? salesReturnId;
  String? salesReturnFirestoreId;
  int? productId;
  String? productFirestoreId;
  String productName;
  String? productImei;
  int quantity;
  int price; // sale price per unit
  int cost;  // cost price per unit
  int amount; // total return amount = price * quantity
  String? shopId;
  bool isSynced;

  SalesReturnItem({
    this.id,
    this.firestoreId,
    this.salesReturnId,
    this.salesReturnFirestoreId,
    this.productId,
    this.productFirestoreId,
    required this.productName,
    this.productImei,
    this.quantity = 1,
    this.price = 0,
    this.cost = 0,
    this.amount = 0,
    this.shopId,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'firestoreId': firestoreId,
      'salesReturnId': salesReturnId,
      'salesReturnFirestoreId': salesReturnFirestoreId,
      'productId': productId,
      'productFirestoreId': productFirestoreId,
      'productName': productName.toUpperCase(),
      'productImei': productImei,
      'quantity': quantity,
      'price': price,
      'cost': cost,
      'amount': amount,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory SalesReturnItem.fromMap(Map<String, dynamic> m) {
    return SalesReturnItem(
      id: m['id'] as int?,
      firestoreId: m['firestoreId'] as String?,
      salesReturnId: m['salesReturnId'] as int?,
      salesReturnFirestoreId: m['salesReturnFirestoreId'] as String?,
      productId: m['productId'] as int?,
      productFirestoreId: m['productFirestoreId'] as String?,
      productName: (m['productName'] ?? '') as String,
      productImei: m['productImei'] as String?,
      quantity: (m['quantity'] ?? 1) as int,
      price: (m['price'] ?? 0) as int,
      cost: (m['cost'] ?? 0) as int,
      amount: (m['amount'] ?? 0) as int,
      shopId: m['shopId'] as String?,
      isSynced: m['isSynced'] == 1 || m['isSynced'] == true,
    );
  }
}
