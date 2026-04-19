import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftSwapRequest {
  final String firestoreId;
  final String shopId;
  final String requesterId;
  final String requesterName;
  final String requesterEmail;
  final String requestedDate; // yyyy-MM-dd
  final String currentShift;
  final String desiredShift;
  final String? targetUserId;
  final String? targetUserName;
  final String? note;
  final String status; // pending, approved, rejected, cancelled
  final String? reviewedBy;
  final String? reviewedByName;
  final int createdAt;
  final int updatedAt;
  final int? reviewedAt;
  final String? rejectReason;
  final bool deleted;

  const ShiftSwapRequest({
    required this.firestoreId,
    required this.shopId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterEmail,
    required this.requestedDate,
    required this.currentShift,
    required this.desiredShift,
    required this.targetUserId,
    required this.targetUserName,
    required this.note,
    required this.status,
    required this.reviewedBy,
    required this.reviewedByName,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedAt,
    required this.rejectReason,
    required this.deleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'firestoreId': firestoreId,
      'shopId': shopId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterEmail': requesterEmail,
      'requestedDate': requestedDate,
      'currentShift': currentShift,
      'desiredShift': desiredShift,
      'targetUserId': targetUserId,
      'targetUserName': targetUserName,
      'note': note,
      'status': status,
      'reviewedBy': reviewedBy,
      'reviewedByName': reviewedByName,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'reviewedAt': reviewedAt,
      'rejectReason': rejectReason,
      'deleted': deleted,
    };
  }

  factory ShiftSwapRequest.fromMap(Map<String, dynamic> map) {
    return ShiftSwapRequest(
      firestoreId: map['firestoreId']?.toString() ?? '',
      shopId: map['shopId']?.toString() ?? '',
      requesterId: map['requesterId']?.toString() ?? '',
      requesterName: map['requesterName']?.toString() ?? 'Nhân viên',
      requesterEmail: map['requesterEmail']?.toString() ?? '',
      requestedDate: map['requestedDate']?.toString() ?? '',
      currentShift: map['currentShift']?.toString() ?? 'Ca sáng',
      desiredShift: map['desiredShift']?.toString() ?? 'Ca chiều',
      targetUserId: map['targetUserId']?.toString(),
      targetUserName: map['targetUserName']?.toString(),
      note: map['note']?.toString(),
      status: map['status']?.toString() ?? 'pending',
      reviewedBy: map['reviewedBy']?.toString(),
      reviewedByName: map['reviewedByName']?.toString(),
      createdAt: _toInt(map['createdAt']),
      updatedAt: _toInt(map['updatedAt']),
      reviewedAt: _toNullableInt(map['reviewedAt']),
      rejectReason: map['rejectReason']?.toString(),
      deleted: map['deleted'] == true,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static int? _toNullableInt(dynamic value) {
    final v = _toInt(value);
    if (v <= 0) return null;
    return v;
  }

  ShiftSwapRequest copyWith({
    String? status,
    String? reviewedBy,
    String? reviewedByName,
    int? reviewedAt,
    String? rejectReason,
    int? updatedAt,
    bool? deleted,
  }) {
    return ShiftSwapRequest(
      firestoreId: firestoreId,
      shopId: shopId,
      requesterId: requesterId,
      requesterName: requesterName,
      requesterEmail: requesterEmail,
      requestedDate: requestedDate,
      currentShift: currentShift,
      desiredShift: desiredShift,
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      note: note,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectReason: rejectReason ?? this.rejectReason,
      deleted: deleted ?? this.deleted,
    );
  }
}
