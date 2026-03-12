import '../models/attendance_model.dart';
import '../models/attendance_monthly_summary_model.dart';

class AttendanceSummaryService {
  static bool isPendingLike(Attendance record) {
    return record.checkInAt != null &&
        record.status != 'approved' &&
        record.status != 'rejected';
  }

  static List<AttendanceMonthlySummary> buildMonthlySummaries({
    required List<Map<String, dynamic>> staffList,
    required Map<String, List<Attendance>> staffAttendance,
  }) {
    final summaries = staffList.map((staff) {
      final userId = staff['id'] as String? ?? '';
      final records = List<Attendance>.from(
        staffAttendance[userId] ?? const [],
      );
      records.sort((a, b) => a.dateKey.compareTo(b.dateKey));
      return _buildSummary(
        userId: userId,
        name: staff['name'] as String? ?? 'NV',
        email: staff['email'] as String? ?? '',
        role: staff['role'] as String? ?? 'employee',
        records: records,
      );
    }).toList();

    summaries.sort((a, b) {
      const order = {'owner': 0, 'manager': 1, 'technician': 2, 'employee': 3};
      final roleCompare = (order[a.role] ?? 99).compareTo(order[b.role] ?? 99);
      if (roleCompare != 0) return roleCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return summaries;
  }

  static AttendanceMonthlySummary _buildSummary({
    required String userId,
    required String name,
    required String email,
    required String role,
    required List<Attendance> records,
  }) {
    var workDays = 0;
    var approvedDays = 0;
    var pendingDays = 0;
    var rejectedDays = 0;
    var lateDays = 0;
    var earlyLeaveDays = 0;
    var incompleteDays = 0;
    var totalWorkMinutes = 0;
    var overtimeMinutes = 0;

    for (final record in records) {
      final hasCheckIn = record.checkInAt != null;
      final hasCheckOut = record.checkOutAt != null;

      if (hasCheckIn) {
        workDays++;
      }

      if (record.status == 'approved' && hasCheckIn) {
        approvedDays++;
      } else if (record.status == 'rejected' && hasCheckIn) {
        rejectedDays++;
      } else if (isPendingLike(record)) {
        pendingDays++;
      }

      if (record.isLate == 1) {
        lateDays++;
      }
      if (record.isEarlyLeave == 1) {
        earlyLeaveDays++;
      }
      if (hasCheckIn && !hasCheckOut) {
        incompleteDays++;
      }

      if (hasCheckIn && hasCheckOut) {
        final minutes = ((record.checkOutAt! - record.checkInAt!) / 60000)
            .round();
        if (minutes > 0) {
          totalWorkMinutes += minutes;
        }
      }

      if (record.overtimeOn > 0) {
        overtimeMinutes += record.overtimeOn;
      }
    }

    return AttendanceMonthlySummary(
      userId: userId,
      name: name,
      email: email,
      role: role,
      totalRecords: records.length,
      workDays: workDays,
      approvedDays: approvedDays,
      pendingDays: pendingDays,
      rejectedDays: rejectedDays,
      lateDays: lateDays,
      earlyLeaveDays: earlyLeaveDays,
      incompleteDays: incompleteDays,
      totalWorkMinutes: totalWorkMinutes,
      overtimeMinutes: overtimeMinutes,
    );
  }
}
