class SupplierPayment {
  int? id;
  String? firestoreId;
  int supplierId;
  int amount;
  int paidAt;
  String paymentMethod;
  String? note;
  String shopId;
  bool isSynced;
  bool deleted;

  SupplierPayment({
    this.id,
    this.firestoreId,
    required this.supplierId,
    required this.amount,
    required this.paidAt,
    required this.paymentMethod,
    this.note,
    required this.shopId,
    this.isSynced = false,
    this.deleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'supplierId': supplierId,
      'amount': amount,
      'paidAt': paidAt,
      'paymentMethod': paymentMethod,
      'note': note,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
    };
  }

  factory SupplierPayment.fromMap(Map<String, dynamic> map) {
    return SupplierPayment(
      id: map['id'],
      firestoreId: map['firestoreId'],
      supplierId: map['supplierId'],
      amount: map['amount'],
      paidAt: map['paidAt'],
      paymentMethod: map['paymentMethod'],
      note: map['note'],
      shopId: map['shopId'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] == 1 || map['deleted'] == true,
    );
  }
}