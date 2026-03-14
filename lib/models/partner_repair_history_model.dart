class PartnerRepairHistory {
  final int? id;
  final String? firestoreId;
  final String repairOrderId;
  final int partnerId;
  final String? partnerFirestoreId;
  final String customerName;
  final String deviceModel;
  final String issue;
  final int partnerCost;
  final String? repairContent;
  final int sentAt;
  final String shopId;

  PartnerRepairHistory({
    this.id,
    this.firestoreId,
    required this.repairOrderId,
    required this.partnerId,
    this.partnerFirestoreId,
    required this.customerName,
    required this.deviceModel,
    required this.issue,
    required this.partnerCost,
    this.repairContent,
    required this.sentAt,
    required this.shopId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'repairOrderId': repairOrderId,
      'partnerId': partnerId,
      'partnerFirestoreId': partnerFirestoreId,
      'customerName': customerName,
      'deviceModel': deviceModel,
      'issue': issue,
      'partnerCost': partnerCost,
      'repairContent': repairContent,
      'sentAt': sentAt,
      'shopId': shopId,
    };
  }

  factory PartnerRepairHistory.fromMap(Map<String, dynamic> map) {
    return PartnerRepairHistory(
      id: map['id'],
      firestoreId: map['firestoreId'],
      repairOrderId: map['repairOrderId'],
      partnerId: map['partnerId'],
      partnerFirestoreId: map['partnerFirestoreId'],
      customerName: map['customerName'],
      deviceModel: map['deviceModel'],
      issue: map['issue'],
      partnerCost: map['partnerCost'],
      repairContent: map['repairContent'],
      sentAt: map['sentAt'],
      shopId: map['shopId'],
    );
  }

  PartnerRepairHistory copyWith({
    int? id,
    String? firestoreId,
    String? repairOrderId,
    int? partnerId,
    String? partnerFirestoreId,
    String? customerName,
    String? deviceModel,
    String? issue,
    int? partnerCost,
    String? repairContent,
    int? sentAt,
    String? shopId,
  }) {
    return PartnerRepairHistory(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      repairOrderId: repairOrderId ?? this.repairOrderId,
      partnerId: partnerId ?? this.partnerId,
      partnerFirestoreId: partnerFirestoreId ?? this.partnerFirestoreId,
      customerName: customerName ?? this.customerName,
      deviceModel: deviceModel ?? this.deviceModel,
      issue: issue ?? this.issue,
      partnerCost: partnerCost ?? this.partnerCost,
      repairContent: repairContent ?? this.repairContent,
      sentAt: sentAt ?? this.sentAt,
      shopId: shopId ?? this.shopId,
    );
  }
}