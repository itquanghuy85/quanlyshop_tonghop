/// Leave request model for employee leave management
class LeaveRequest {
  int? id;
  String? firestoreId;
  String userId;
  String email;
  String name;
  String leaveType; // annual, sick, unpaid, personal, maternity
  String startDate; // yyyy-MM-dd
  String endDate; // yyyy-MM-dd
  double totalDays;
  String? reason;
  String status; // pending, approved, rejected
  String? approvedBy;
  int? approvedAt;
  String? rejectReason;
  int createdAt;
  int? updatedAt;
  bool isSynced;
  String? shopId;
  int deleted;

  LeaveRequest({
    this.id,
    this.firestoreId,
    required this.userId,
    required this.email,
    required this.name,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    this.reason,
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
    this.rejectReason,
    required this.createdAt,
    this.updatedAt,
    this.isSynced = false,
    this.shopId,
    this.deleted = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'userId': userId,
      'email': email,
      'name': name,
      'leaveType': leaveType,
      'startDate': startDate,
      'endDate': endDate,
      'totalDays': totalDays,
      'reason': reason,
      'status': status,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt,
      'rejectReason': rejectReason,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isSynced': isSynced ? 1 : 0,
      'shopId': shopId,
      'deleted': deleted,
    };
  }

  factory LeaveRequest.fromMap(Map<String, dynamic> map) {
    return LeaveRequest(
      id: map['id'],
      firestoreId: map['firestoreId'],
      userId: map['userId'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      leaveType: map['leaveType'] ?? 'unpaid',
      startDate: map['startDate'] ?? '',
      endDate: map['endDate'] ?? '',
      totalDays: (map['totalDays'] ?? 0).toDouble(),
      reason: map['reason'],
      status: map['status'] ?? 'pending',
      approvedBy: map['approvedBy'],
      approvedAt: map['approvedAt'],
      rejectReason: map['rejectReason'],
      createdAt: map['createdAt'] ?? 0,
      updatedAt: map['updatedAt'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      shopId: map['shopId'],
      deleted: map['deleted'] ?? 0,
    );
  }

  /// Vietnamese display name for leave type
  static String leaveTypeDisplayVi(String type) {
    switch (type) {
      case 'annual':
        return 'Nghỉ phép năm';
      case 'sick':
        return 'Nghỉ ốm';
      case 'unpaid':
        return 'Nghỉ không lương';
      case 'personal':
        return 'Nghỉ việc riêng';
      case 'maternity':
        return 'Nghỉ thai sản';
      default:
        return 'Khác';
    }
  }

  static String leaveTypeDisplayEn(String type) {
    switch (type) {
      case 'annual':
        return 'Annual Leave';
      case 'sick':
        return 'Sick Leave';
      case 'unpaid':
        return 'Unpaid Leave';
      case 'personal':
        return 'Personal Leave';
      case 'maternity':
        return 'Maternity Leave';
      default:
        return 'Other';
    }
  }
}
