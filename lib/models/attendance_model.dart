class Attendance {
  int? id;
  String? firestoreId;
  String userId;
  String email;
  String name;
  String dateKey; // yyyy-MM-dd
  int? checkInAt;
  int? checkOutAt;
  int overtimeOn;
  int? overtimeStartAt; // Overtime window start (ms epoch)
  int? overtimeEndAt; // Overtime window end (ms epoch)
  String? photoIn;
  String? photoOut;
  String? note;
  String status; // pending, approved, rejected
  String? approvedBy;
  int? approvedAt;
  String? rejectReason;
  String? requestType; // normal, forgot_checkin, forgot_checkout, overtime_edit
  int locked;
  int createdAt;
  String? location;
  int isLate;
  int isEarlyLeave;
  String? workSchedule;
  int? updatedAt;
  bool isSynced;

  Attendance({
    this.id,
    this.firestoreId,
    required this.userId,
    required this.email,
    required this.name,
    required this.dateKey,
    this.checkInAt,
    this.checkOutAt,
    this.overtimeOn = 0,
    this.overtimeStartAt,
    this.overtimeEndAt,
    this.photoIn,
    this.photoOut,
    this.note,
    this.status = 'pending',
    this.approvedBy,
    this.approvedAt,
    this.rejectReason,
    this.requestType,
    this.locked = 0,
    required this.createdAt,
    this.location,
    this.isLate = 0,
    this.isEarlyLeave = 0,
    this.workSchedule,
    this.updatedAt,
    this.isSynced = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'userId': userId,
      'email': email,
      'name': name,
      'dateKey': dateKey,
      'checkInAt': checkInAt,
      'checkOutAt': checkOutAt,
      'overtimeOn': overtimeOn,
      'overtimeStartAt': overtimeStartAt,
      'overtimeEndAt': overtimeEndAt,
      'photoIn': photoIn,
      'photoOut': photoOut,
      'note': note,
      'status': status,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt,
      'rejectReason': rejectReason,
      'requestType': requestType,
      'locked': locked,
      'createdAt': createdAt,
      'location': location,
      'isLate': isLate,
      'isEarlyLeave': isEarlyLeave,
      'workSchedule': workSchedule,
      'updatedAt': updatedAt,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'],
      firestoreId: map['firestoreId'],
      userId: map['userId'],
      email: map['email'],
      name: map['name'],
      dateKey: map['dateKey'],
      checkInAt: map['checkInAt'],
      checkOutAt: map['checkOutAt'],
      overtimeOn: map['overtimeOn'] ?? 0,
      overtimeStartAt: map['overtimeStartAt'],
      overtimeEndAt: map['overtimeEndAt'],
      photoIn: map['photoIn'],
      photoOut: map['photoOut'],
      note: map['note'],
      status: map['status'] ?? 'pending',
      approvedBy: map['approvedBy'],
      approvedAt: map['approvedAt'],
      rejectReason: map['rejectReason'],
      requestType: map['requestType'],
      locked: map['locked'] ?? 0,
      createdAt: map['createdAt'],
      location: map['location'],
      isLate: map['isLate'] ?? 0,
      isEarlyLeave: map['isEarlyLeave'] ?? 0,
      workSchedule: map['workSchedule'],
      updatedAt: map['updatedAt'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
    );
  }
}