/// Shift swap request model for employee schedule exchange
/// Flow: requester creates → target accepts/declines → manager approves/rejects
class ShiftSwap {
  int? id;
  String? firestoreId;
  String shopId;

  // Requester (người yêu cầu đổi ca)
  String requesterId;
  String requesterName;
  String requesterEmail;

  // Target (người được yêu cầu đổi ca)
  String targetId;
  String targetName;
  String targetEmail;

  // Swap details
  String swapDate; // yyyy-MM-dd — ngày muốn đổi
  String? returnDate; // yyyy-MM-dd — ngày trả ca (optional, if different day)
  String? reason;

  // Status flow: pending_target → pending_manager → approved / rejected / cancelled
  // pending_target: chờ người được yêu cầu chấp nhận
  // pending_manager: người được yêu cầu đã đồng ý, chờ quản lý duyệt
  // approved: quản lý đã duyệt
  // rejected: bị từ chối (bởi target hoặc manager)
  // cancelled: bị huỷ bởi requester
  String status;

  // Target response
  int? targetRespondedAt;

  // Manager response
  String? approvedBy;
  int? approvedAt;
  String? rejectReason;
  String? rejectedBy; // 'target' or manager uid

  int createdAt;
  int? updatedAt;
  bool isSynced;
  int deleted;

  ShiftSwap({
    this.id,
    this.firestoreId,
    required this.shopId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterEmail,
    required this.targetId,
    required this.targetName,
    required this.targetEmail,
    required this.swapDate,
    this.returnDate,
    this.reason,
    this.status = 'pending_target',
    this.targetRespondedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectReason,
    this.rejectedBy,
    required this.createdAt,
    this.updatedAt,
    this.isSynced = false,
    this.deleted = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'shopId': shopId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
      'targetId': targetId,
      'targetName': targetName,
      'targetEmail': targetEmail,
      'swapDate': swapDate,
      'returnDate': returnDate,
      'reason': reason,
      'status': status,
      'targetRespondedAt': targetRespondedAt,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt,
      'rejectReason': rejectReason,
      'rejectedBy': rejectedBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted,
    };
  }

  factory ShiftSwap.fromMap(Map<String, dynamic> map) {
    return ShiftSwap(
      id: map['id'],
      firestoreId: map['firestoreId'],
      shopId: map['shopId'] ?? '',
      requesterId: map['requesterId'] ?? '',
      requesterName: map['requesterName'] ?? '',
      requesterEmail: map['requesterEmail'] ?? '',
      targetId: map['targetId'] ?? '',
      targetName: map['targetName'] ?? '',
      targetEmail: map['targetEmail'] ?? '',
      swapDate: map['swapDate'] ?? '',
      returnDate: map['returnDate'],
      reason: map['reason'],
      status: map['status'] ?? 'pending_target',
      targetRespondedAt: map['targetRespondedAt'],
      approvedBy: map['approvedBy'],
      approvedAt: map['approvedAt'],
      rejectReason: map['rejectReason'],
      rejectedBy: map['rejectedBy'],
      createdAt: map['createdAt'] ?? 0,
      updatedAt: map['updatedAt'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] ?? 0,
    );
  }

  /// Vietnamese display name for status
  static String statusDisplayVi(String status) {
    switch (status) {
      case 'pending_target':
        return 'Chờ đồng nghiệp';
      case 'pending_manager':
        return 'Chờ quản lý';
      case 'approved':
        return 'Đã duyệt';
      case 'rejected':
        return 'Từ chối';
      case 'cancelled':
        return 'Đã huỷ';
      default:
        return status;
    }
  }

  /// Whether the swap can still be cancelled by requester
  bool get canCancel =>
      status == 'pending_target' || status == 'pending_manager';

  /// Whether target can still respond
  bool get canTargetRespond => status == 'pending_target';

  /// Whether manager can still approve/reject
  bool get canManagerApprove => status == 'pending_manager';
}
