class RepairPartnerPayment {
  int? id;
  String? firestoreId;
  int partnerId;
  String? partnerName; // FIX: Thêm tên đối tác để hiển thị trong chốt quỹ
  int amount;
  int paidAt;
  String paymentMethod;
  String? note;
  String shopId;
  bool isSynced;
  bool deleted;
  int? updatedAt; // FIX: Thêm updatedAt để hỗ trợ sync

  RepairPartnerPayment({
    this.id,
    this.firestoreId,
    required this.partnerId,
    this.partnerName,
    required this.amount,
    required this.paidAt,
    required this.paymentMethod,
    this.note,
    required this.shopId,
    this.isSynced = false,
    this.deleted = false,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'amount': amount,
      'paidAt': paidAt,
      'paymentMethod': paymentMethod,
      'note': note,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'updatedAt': updatedAt,
    };
  }

  factory RepairPartnerPayment.fromMap(Map<String, dynamic> map) {
    return RepairPartnerPayment(
      id: map['id'],
      firestoreId: map['firestoreId'],
      partnerId: map['partnerId'],
      partnerName: map['partnerName'],
      amount: map['amount'],
      paidAt: map['paidAt'],
      paymentMethod: map['paymentMethod'],
      note: map['note'],
      shopId: map['shopId'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] == 1 || map['deleted'] == true,
      updatedAt: map['updatedAt'],
    );
  }
}