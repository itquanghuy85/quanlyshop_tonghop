import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/attendance_model.dart';
import 'package:quanlyshop/services/attendance_summary_service.dart';

void main() {
  group('AttendanceSummaryService', () {
    test('buildMonthlySummaries aggregates attendance metrics per staff', () {
      final summaries = AttendanceSummaryService.buildMonthlySummaries(
        staffList: const [
          {
            'id': 'staff-1',
            'name': 'Nguyen Van A',
            'email': 'a@example.com',
            'role': 'technician',
          },
        ],
        staffAttendance: {
          'staff-1': [
            Attendance(
              userId: 'staff-1',
              email: 'a@example.com',
              name: 'Nguyen Van A',
              dateKey: '2025-03-01',
              checkInAt: DateTime(2025, 3, 1, 8, 0).millisecondsSinceEpoch,
              checkOutAt: DateTime(2025, 3, 1, 17, 30).millisecondsSinceEpoch,
              overtimeOn: 60,
              status: 'approved',
              isLate: 1,
              createdAt: DateTime(2025, 3, 1, 8, 0).millisecondsSinceEpoch,
            ),
            Attendance(
              userId: 'staff-1',
              email: 'a@example.com',
              name: 'Nguyen Van A',
              dateKey: '2025-03-02',
              checkInAt: DateTime(2025, 3, 2, 8, 15).millisecondsSinceEpoch,
              status: 'completed',
              isEarlyLeave: 1,
              createdAt: DateTime(2025, 3, 2, 8, 15).millisecondsSinceEpoch,
            ),
          ],
        },
      );

      expect(summaries, hasLength(1));
      final summary = summaries.first;
      expect(summary.workDays, 2);
      expect(summary.approvedDays, 1);
      expect(summary.pendingDays, 1);
      expect(summary.rejectedDays, 0);
      expect(summary.lateDays, 1);
      expect(summary.earlyLeaveDays, 1);
      expect(summary.incompleteDays, 1);
      expect(summary.totalWorkMinutes, 570);
      expect(summary.overtimeMinutes, 60);
    });

    test(
      'isPendingLike treats legacy completed records as waiting approval',
      () {
        final record = Attendance(
          userId: 'staff-1',
          email: 'a@example.com',
          name: 'Nguyen Van A',
          dateKey: '2025-03-03',
          checkInAt: DateTime(2025, 3, 3, 8, 0).millisecondsSinceEpoch,
          status: 'completed',
          createdAt: DateTime(2025, 3, 3, 8, 0).millisecondsSinceEpoch,
        );

        expect(AttendanceSummaryService.isPendingLike(record), isTrue);
      },
    );
  });
}
