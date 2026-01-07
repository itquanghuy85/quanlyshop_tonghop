class PartnerRepairHistory {
  final int? id;
  final String repairOrderId;
  final int partnerId;
  final String customerName;
  final String deviceModel;
  final String issue;
  final int partnerCost;
  final String? repairContent;
  final int sentAt;
  final String shopId;

  PartnerRepairHistory({
    this.id,
    required this.repairOrderId,
    required this.partnerId,
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
      'repairOrderId': repairOrderId,
      'partnerId': partnerId,
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
      repairOrderId: map['repairOrderId'],
      partnerId: map['partnerId'],
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
    String? repairOrderId,
    int? partnerId,
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
      repairOrderId: repairOrderId ?? this.repairOrderId,
      partnerId: partnerId ?? this.partnerId,
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