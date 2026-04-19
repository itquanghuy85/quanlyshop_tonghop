import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/leave_request_model.dart';
import '../services/user_service.dart';
import '../services/encryption_service.dart';

/// Service for managing attendance approval, leave requests, overtime editing.
/// Only owner/manager roles can approve/reject.
class AttendanceApprovalService {
  static final _db = FirebaseFirestore.instance;
  static final _dbHelper = DBHelper();

  // ========================
  // ATTENDANCE APPROVAL
  // ========================

  /// Approve an attendance record (confirm it counts toward salary)
  static Future<bool> approveAttendance(Attendance record) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      record.status = 'approved';
      record.approvedBy = uid;
      record.approvedAt = DateTime.now().millisecondsSinceEpoch;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      record.isSynced = false;

      await _dbHelper.upsertAttendance(record);
      await _syncAttendanceToCloud(record);
      return true;
    } catch (e) {
      debugPrint('Error approving attendance: $e');
      return false;
    }
  }

  /// Reject an attendance record
  static Future<bool> rejectAttendance(Attendance record, String reason) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      record.status = 'rejected';
      record.approvedBy = uid;
      record.approvedAt = DateTime.now().millisecondsSinceEpoch;
      record.rejectReason = reason;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      record.isSynced = false;

      await _dbHelper.upsertAttendance(record);
      await _syncAttendanceToCloud(record);
      return true;
    } catch (e) {
      debugPrint('Error rejecting attendance: $e');
      return false;
    }
  }

  /// Bulk approve all pending attendance for a date
  static Future<int> bulkApproveByDate(String dateKey, List<Attendance> records) async {
    int count = 0;
    for (final record in records) {
      if (record.status == 'pending' && record.checkInAt != null) {
        final ok = await approveAttendance(record);
        if (ok) count++;
      }
    }
    return count;
  }

  // ========================
  // FORGOT CHECK-IN/OUT
  // ========================

  /// Create a "forgot check-in" request (employee submits, manager approves)
  static Future<bool> createForgotCheckinRequest({
    required String userId,
    required String email,
    required String name,
    required String dateKey,
    required int checkInAt,
    int? checkOutAt,
    String? note,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final record = Attendance(
        userId: userId,
        email: email,
        name: name,
        dateKey: dateKey,
        checkInAt: checkInAt,
        checkOutAt: checkOutAt,
        status: 'pending',
        requestType: 'forgot_checkin',
        note: note ?? 'Quên chấm công',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        isSynced: false,
      );
      record.firestoreId = "att_${dateKey}_$userId";

      // Check if record already exists for this date/user
      final existing = await _dbHelper.getAttendance(dateKey, userId);
      if (existing != null) {
        // Update existing with forgot_checkin request type
        existing.checkInAt = checkInAt;
        if (checkOutAt != null) existing.checkOutAt = checkOutAt;
        existing.requestType = 'forgot_checkin';
        existing.status = 'pending';
        existing.note = note ?? 'Quên chấm công';
        existing.updatedAt = DateTime.now().millisecondsSinceEpoch;
        existing.isSynced = false;
        await _dbHelper.upsertAttendance(existing);
        await _syncAttendanceToCloud(existing);
      } else {
        final map = record.toMap();
        map['shopId'] = shopId;
        await _dbHelper.upsertAttendance(Attendance.fromMap(map));
        await _syncAttendanceToCloud(record);
      }
      return true;
    } catch (e) {
      debugPrint('Error creating forgot checkin request: $e');
      return false;
    }
  }

  // ========================
  // OVERTIME EDITING
  // ========================

  /// Edit overtime for an attendance record (set specific overtime window)
  static Future<bool> editOvertime({
    required Attendance record,
    required int overtimeMinutes,
    int? overtimeStartAt,
    int? overtimeEndAt,
    String? note,
  }) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      record.overtimeOn = overtimeMinutes;
      record.overtimeStartAt = overtimeStartAt;
      record.overtimeEndAt = overtimeEndAt;
      if (note != null) record.note = note;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      record.isSynced = false;

      await _dbHelper.upsertAttendance(record);
      await _syncAttendanceToCloud(record);
      return true;
    } catch (e) {
      debugPrint('Error editing overtime: $e');
      return false;
    }
  }

  /// Edit check-in/check-out times for an attendance record
  static Future<bool> editAttendanceTimes({
    required Attendance record,
    int? checkInAt,
    int? checkOutAt,
    String? note,
  }) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      if (checkInAt != null) record.checkInAt = checkInAt;
      if (checkOutAt != null) record.checkOutAt = checkOutAt;
      if (note != null) record.note = note;
      record.updatedAt = DateTime.now().millisecondsSinceEpoch;
      record.isSynced = false;

      await _dbHelper.upsertAttendance(record);
      await _syncAttendanceToCloud(record);
      return true;
    } catch (e) {
      debugPrint('Error editing attendance times: $e');
      return false;
    }
  }

  // ========================
  // LEAVE REQUESTS
  // ========================

  /// Create a leave request
  static Future<bool> createLeaveRequest(LeaveRequest request) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      request.shopId = shopId;
      request.firestoreId ??= "lr_${request.userId}_${request.startDate}_${request.createdAt}";
      await _dbHelper.upsertLeaveRequest(request);
      await _syncLeaveRequestToCloud(request);
      return true;
    } catch (e) {
      debugPrint('Error creating leave request: $e');
      return false;
    }
  }

  /// Approve a leave request
  static Future<bool> approveLeaveRequest(LeaveRequest request) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      request.status = 'approved';
      request.approvedBy = uid;
      request.approvedAt = DateTime.now().millisecondsSinceEpoch;
      request.updatedAt = DateTime.now().millisecondsSinceEpoch;
      request.isSynced = false;

      await _dbHelper.upsertLeaveRequest(request);
      await _syncLeaveRequestToCloud(request);
      return true;
    } catch (e) {
      debugPrint('Error approving leave request: $e');
      return false;
    }
  }

  /// Reject a leave request
  static Future<bool> rejectLeaveRequest(LeaveRequest request, String reason) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      request.status = 'rejected';
      request.approvedBy = uid;
      request.approvedAt = DateTime.now().millisecondsSinceEpoch;
      request.rejectReason = reason;
      request.updatedAt = DateTime.now().millisecondsSinceEpoch;
      request.isSynced = false;

      await _dbHelper.upsertLeaveRequest(request);
      await _syncLeaveRequestToCloud(request);
      return true;
    } catch (e) {
      debugPrint('Error rejecting leave request: $e');
      return false;
    }
  }

  /// Get pending leave requests for current shop
  static Future<List<LeaveRequest>> getPendingLeaveRequests() async {
    return _dbHelper.getLeaveRequestsByStatus('pending');
  }

  /// Get leave requests by date range
  static Future<List<LeaveRequest>> getLeaveRequestsByDateRange(String start, String end) async {
    return _dbHelper.getLeaveRequestsByDateRange(start, end);
  }

  /// Get all leave requests for a user
  static Future<List<LeaveRequest>> getLeaveRequestsByUser(String userId) async {
    return _dbHelper.getLeaveRequestsByUser(userId);
  }

  // ========================
  // HELPERS
  // ========================

  static String? _getCurrentUid() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static Future<void> _syncAttendanceToCloud(Attendance record) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = record.firestoreId ?? "att_${record.dateKey}_${record.userId}";
      Map<String, dynamic> data = record.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db.collection('attendance').doc(docId).set(
        encryptedData,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error syncing attendance to cloud: $e');
    }
  }

  static Future<void> _syncLeaveRequestToCloud(LeaveRequest request) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = request.firestoreId ?? "lr_${request.userId}_${request.startDate}_${request.createdAt}";
      Map<String, dynamic> data = request.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db.collection('leave_requests').doc(docId).set(
        encryptedData,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error syncing leave request to cloud: $e');
    }
  }
}

