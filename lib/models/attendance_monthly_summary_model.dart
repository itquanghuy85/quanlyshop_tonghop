class AttendanceMonthlySummary {
  final String userId;
  final String name;
  final String email;
  final String role;
  final int totalRecords;
  final int workDays;
  final int approvedDays;
  final int pendingDays;
  final int rejectedDays;
  final int lateDays;
  final int earlyLeaveDays;
  final int incompleteDays;
  final int totalWorkMinutes;
  final int overtimeMinutes;

  const AttendanceMonthlySummary({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.totalRecords,
    required this.workDays,
    required this.approvedDays,
    required this.pendingDays,
    required this.rejectedDays,
    required this.lateDays,
    required this.earlyLeaveDays,
    required this.incompleteDays,
    required this.totalWorkMinutes,
    required this.overtimeMinutes,
  });

  double get approvalRate => workDays == 0 ? 0 : approvedDays / workDays;

  String get totalWorkLabel => formatMinutes(totalWorkMinutes);

  String get overtimeLabel => formatMinutes(overtimeMinutes);

  static String formatMinutes(int totalMinutes) {
    if (totalMinutes <= 0) return '0h';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}p';
  }
}