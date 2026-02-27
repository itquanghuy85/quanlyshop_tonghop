class RepairService {
  int? id;
  String? firestoreId;
  String serviceName;
  int? partnerId; // Optional, if outsourced to partner
  int cost; // Cost for this service
  String? partnerName; // For display, not stored
  String?
  paymentMethod; // Phương thức thanh toán đối tác: TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ
  bool isSynced;
  bool deleted;

  RepairService({
    this.id,
    this.firestoreId,
    required this.serviceName,
    this.partnerId,
    this.cost = 0,
    this.partnerName,
    this.paymentMethod,
    this.isSynced = false,
    this.deleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'serviceName': serviceName,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'cost': cost,
      'paymentMethod': paymentMethod,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
    };
  }

  factory RepairService.fromMap(Map<String, dynamic> map) {
    return RepairService(
      id: map['id'],
      firestoreId: map['firestoreId'],
      serviceName: map['serviceName'] ?? '',
      partnerId: map['partnerId'],
      partnerName: map['partnerName'],
      cost: map['cost'] is int ? map['cost'] : 0,
      paymentMethod: map['paymentMethod'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] == 1 || map['deleted'] == true,
    );
  }

  RepairService copyWith({
    int? id,
    String? firestoreId,
    String? serviceName,
    int? partnerId,
    int? cost,
    String? partnerName,
    String? paymentMethod,
    bool? isSynced,
    bool? deleted,
  }) {
    return RepairService(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      serviceName: serviceName ?? this.serviceName,
      partnerId: partnerId ?? this.partnerId,
      cost: cost ?? this.cost,
      partnerName: partnerName ?? this.partnerName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }
}
