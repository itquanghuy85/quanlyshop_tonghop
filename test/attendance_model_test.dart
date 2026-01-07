import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/attendance_model.dart';

void main() {
  group('Attendance Model', () {
    test('Attendance fromMap and toMap should be consistent', () {
      final attendance = Attendance(
        userId: 'test_user',
        email: 'test@example.com',
        name: 'Test User',
        dateKey: '2024-01-01',
        checkInAt: 1640995200000, // 2024-01-01 00:00:00
        checkOutAt: 1641081600000, // 2024-01-02 00:00:00
        overtimeOn: 2,
        photoIn: 'path/to/photo_in.jpg',
        photoOut: 'path/to/photo_out.jpg',
        note: 'Test note',
        status: 'approved',
        approvedBy: 'admin',
        approvedAt: 1641081600000,
        rejectReason: null,
        locked: 0,
        createdAt: 1640995200000,
        location: 'Office',
        isLate: 0,
        isEarlyLeave: 0,
        workSchedule: '08:00-17:00',
        updatedAt: 1641081600000,
      );

      final map = attendance.toMap();
      final reconstructed = Attendance.fromMap(map);

      expect(reconstructed.userId, attendance.userId);
      expect(reconstructed.email, attendance.email);
      expect(reconstructed.name, attendance.name);
      expect(reconstructed.dateKey, attendance.dateKey);
      expect(reconstructed.checkInAt, attendance.checkInAt);
      expect(reconstructed.checkOutAt, attendance.checkOutAt);
      expect(reconstructed.overtimeOn, attendance.overtimeOn);
      expect(reconstructed.photoIn, attendance.photoIn);
      expect(reconstructed.photoOut, attendance.photoOut);
      expect(reconstructed.note, attendance.note);
      expect(reconstructed.status, attendance.status);
      expect(reconstructed.approvedBy, attendance.approvedBy);
      expect(reconstructed.approvedAt, attendance.approvedAt);
      expect(reconstructed.rejectReason, attendance.rejectReason);
      expect(reconstructed.locked, attendance.locked);
      expect(reconstructed.createdAt, attendance.createdAt);
      expect(reconstructed.location, attendance.location);
      expect(reconstructed.isLate, attendance.isLate);
      expect(reconstructed.isEarlyLeave, attendance.isEarlyLeave);
      expect(reconstructed.workSchedule, attendance.workSchedule);
      expect(reconstructed.updatedAt, attendance.updatedAt);
    });

    test('Attendance with null values should handle correctly', () {
      final attendance = Attendance(
        userId: 'test_user',
        email: 'test@example.com',
        name: 'Test User',
        dateKey: '2024-01-01',
        createdAt: 1640995200000,
      );

      final map = attendance.toMap();
      final reconstructed = Attendance.fromMap(map);

      expect(reconstructed.checkInAt, isNull);
      expect(reconstructed.checkOutAt, isNull);
      expect(reconstructed.photoIn, isNull);
      expect(reconstructed.photoOut, isNull);
      expect(reconstructed.note, isNull);
      expect(reconstructed.approvedBy, isNull);
      expect(reconstructed.approvedAt, isNull);
      expect(reconstructed.rejectReason, isNull);
      expect(reconstructed.location, isNull);
      expect(reconstructed.workSchedule, isNull);
      expect(reconstructed.updatedAt, isNull);
    });
  });
}
