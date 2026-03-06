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
      id: m['id'] is int ? m['id'] as int : int.tryParse('${m['id'] ?? ''}'),
      firestoreId: m['firestoreId'] as String?,
      salesOrderId: m['salesOrderId'] is int ? m['salesOrderId'] as int : int.tryParse('${m['salesOrderId'] ?? ''}'),
      salesOrderFirestoreId: m['salesOrderFirestoreId'] as String?,
      customerName: '${m['customerName'] ?? ''}',
      customerPhone: '${m['customerPhone'] ?? ''}',
      returnDate: m['returnDate'] is int ? m['returnDate'] as int : int.tryParse('${m['returnDate'] ?? '0'}') ?? 0,
      totalReturnAmount: m['totalReturnAmount'] is int ? m['totalReturnAmount'] as int : int.tryParse('${m['totalReturnAmount'] ?? '0'}') ?? 0,
      totalReturnCost: m['totalReturnCost'] is int ? m['totalReturnCost'] as int : int.tryParse('${m['totalReturnCost'] ?? '0'}') ?? 0,
      refundMethod: '${m['refundMethod'] ?? 'TIỀN MẶT'}',
      note: m['note']?.toString(),
      createdAt: m['createdAt'] is int ? m['createdAt'] as int : int.tryParse('${m['createdAt'] ?? '0'}') ?? 0,
      createdBy: m['createdBy']?.toString(),
      approvedBy: m['approvedBy']?.toString(),
      approvedAt: m['approvedAt'] is int ? m['approvedAt'] as int : int.tryParse('${m['approvedAt'] ?? ''}'),
      status: '${m['status'] ?? 'APPROVED'}',
      shopId: m['shopId']?.toString(),
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
      id: m['id'] is int ? m['id'] as int : int.tryParse('${m['id'] ?? ''}'),
      firestoreId: m['firestoreId']?.toString(),
      salesReturnId: m['salesReturnId'] is int ? m['salesReturnId'] as int : int.tryParse('${m['salesReturnId'] ?? ''}'),
      salesReturnFirestoreId: m['salesReturnFirestoreId']?.toString(),
      productId: m['productId'] is int ? m['productId'] as int : int.tryParse('${m['productId'] ?? ''}'),
      productFirestoreId: m['productFirestoreId']?.toString(),
      productName: '${m['productName'] ?? ''}',
      productImei: m['productImei']?.toString(),
      quantity: m['quantity'] is int ? m['quantity'] as int : int.tryParse('${m['quantity'] ?? '1'}') ?? 1,
      price: m['price'] is int ? m['price'] as int : int.tryParse('${m['price'] ?? '0'}') ?? 0,
      cost: m['cost'] is int ? m['cost'] as int : int.tryParse('${m['cost'] ?? '0'}') ?? 0,
      amount: m['amount'] is int ? m['amount'] as int : int.tryParse('${m['amount'] ?? '0'}') ?? 0,
      shopId: m['shopId']?.toString(),
      isSynced: m['isSynced'] == 1 || m['isSynced'] == true,
    );
  }
}
