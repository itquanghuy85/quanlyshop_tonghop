import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../widgets/validated_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class PayrollView extends StatefulWidget {
  const PayrollView({super.key});

  @override
  State<PayrollView> createState() => _PayrollViewState();
}

class _PayrollViewState extends State<PayrollView> {
  final db = DBHelper();
  bool _loading = true;
  List<Attendance> _att = [];
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String? _selectedStaff;
  final TextEditingController _customStaff = TextEditingController();
  String _role = 'user';
  bool _monthLocked = false;
  bool _hasPermission = false;

  Map<String, double> _basePerDay = {}; // staff -> base per day
  Map<String, double> _hoursPerDay = {}; // staff -> expected hours
  Map<String, double> _otRate = {}; // staff -> percent e.g. 150

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadRole();
    _load();
    _loadPrefs();
    _refreshLockState();
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewAttendance'] ?? false);
  }

  @override
  void dispose() {
    _customStaff.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await db.getAttendanceByDateRange(
      DateFormat('yyyy-MM-dd').format(_from),
      DateFormat('yyyy-MM-dd').format(_to)
    );
    setState(() {
      _att = data;
      _loading = false;
    });
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final r = await UserService.getUserRole(uid);
    if (mounted) setState(() => _role = r);
  }

  Future<void> _refreshLockState() async {
    final locked = await db.isPayrollMonthLocked(DateFormat('yyyy-MM').format(_from));
    if (mounted) setState(() => _monthLocked = locked);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final a = prefs.getString('payroll_base');
      final b = prefs.getString('payroll_hours');
      final c = prefs.getString('payroll_ot');
      if (a != null) _basePerDay = Map<String, double>.from(jsonDecode(a).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      if (b != null) _hoursPerDay = Map<String, double>.from(jsonDecode(b).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      if (c != null) _otRate = Map<String, double>.from(jsonDecode(c).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
    });
  }

  List<String> get _staffList {
    final s = <String>{};
    for (final a in _att) {
      final name = (a.name ?? '').toString();
      if (name.isNotEmpty) s.add(name);
    }
    final list = s.toList()..sort();
    return list;
  }

  Iterable<Attendance> get _filteredAtt {
    final filter = (_selectedStaff ?? _customStaff.text).trim().toUpperCase();
    if (filter.isEmpty) return _att;
    return _att.where((a) => (a.name ?? '').toString().toUpperCase().contains(filter));
  }

  double _getBase(String staff) => _basePerDay[staff] ?? 0;
  double _getHours(String staff) => _hoursPerDay[staff] ?? 8;
  double _getOt(String staff) => _otRate[staff] ?? 150;

  Map<String, dynamic> _calc() {
    final staffKey = (_selectedStaff ?? _customStaff.text).trim().toUpperCase();
    final base = _getBase(staffKey);
    final otRate = _getOt(staffKey);

    double totalHours = 0;
    double otHours = 0;
    int days = 0;
    double hoursStd = 8.0; // default

    // Get work schedule from first attendance record of this staff
    final staffAtt = _filteredAtt.where((a) => (a.name ?? '').toString().toUpperCase() == staffKey).toList();
    if (staffAtt.isNotEmpty) {
      final firstAtt = staffAtt.first;
      if (firstAtt.workSchedule != null && firstAtt.workSchedule!.isNotEmpty) {
        try {
          final schedule = firstAtt.workSchedule!.split('-');
          if (schedule.length == 2) {
            final start = schedule[0].split(':');
            final end = schedule[1].split(':');
            final startHour = int.tryParse(start[0]) ?? 8;
            final startMin = int.tryParse(start[1]) ?? 0;
            final endHour = int.tryParse(end[0]) ?? 17;
            final endMin = int.tryParse(end[1]) ?? 0;
            final duration = (endHour * 60 + endMin) - (startHour * 60 + startMin);
            hoursStd = duration / 60.0;
          }
        } catch (e) {
          // fallback to default 8 hours
          hoursStd = 8.0;
        }
      }
    }

    for (final a in _filteredAtt) {
      final inMs = a.checkInAt;
      final outMs = a.checkOutAt;
      if (inMs == null || outMs == null || outMs <= inMs) continue;
      final hrs = (outMs - inMs) / (1000 * 60 * 60);
      totalHours += hrs;
      days += 1;
      if ((a.overtimeOn ?? 0) == 1 && hrs > hoursStd) {
        otHours += (hrs - hoursStd);
      }
    }

    final regularHours = totalHours - otHours;
    final payPerHour = hoursStd > 0 ? base / hoursStd : 0;
    final salary = (regularHours * payPerHour) + (otHours * payPerHour * (otRate / 100));

    return {
      'staff': staffKey,
      'days': days,
      'regularHours': regularHours,
      'otHours': otHours,
      'salary': salary,
      'basePerDay': base,
      'hoursStd': hoursStd,
      'otRate': otRate,
    };
  }

  bool _isValidPayrollInput(String base, String hours, String ot) {
    final baseVal = double.tryParse(base);
    final hoursVal = double.tryParse(hours);
    final otVal = double.tryParse(ot);
    return baseVal != null && baseVal > 0 &&
           hoursVal != null && hoursVal > 0 &&
           otVal != null && otVal >= 0;
  }

  void _openRuleDialog() async {
    final staff = (_selectedStaff ?? _customStaff.text).trim().toUpperCase();
    if (staff.isEmpty) return;
    if (!_isManager) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chỉ quản lý mới chỉnh công thức')));
      return;
    }
    if (_monthLocked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tháng đã khóa, không sửa công thức')));
      return;
    }
    final baseCtrl = TextEditingController(text: _getBase(staff).toStringAsFixed(0));
    final hourCtrl = TextEditingController(text: _getHours(staff).toStringAsFixed(1));
    final otCtrl = TextEditingController(text: _getOt(staff).toStringAsFixed(0));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          baseCtrl.addListener(() => setS(() {}));
          otCtrl.addListener(() => setS(() {}));
          return AlertDialog(
            title: Text('Cài công thức: $staff'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValidatedTextField(controller: baseCtrl, label: 'Lương ngày (đ)', icon: Icons.attach_money, keyboardType: TextInputType.number, required: true),
                Text('Giờ chuẩn/ngày: ${_getHours(staff).toStringAsFixed(1)} (từ lịch làm việc)', style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6))),
                ValidatedTextField(controller: otCtrl, label: 'Hệ số OT (%)', icon: Icons.trending_up, keyboardType: TextInputType.number, required: true), 
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
              ElevatedButton(
                onPressed: _isValidPayrollInput(baseCtrl.text, hourCtrl.text, otCtrl.text) ? () => Navigator.pop(ctx, true) : null,
                child: const Text('LƯU'),
              ),
            ],
          );
        }
      ),
    );

    if (ok == true) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _basePerDay[staff] = double.tryParse(baseCtrl.text) ?? 0;
        // _hoursPerDay[staff] = double.tryParse(hourCtrl.text) ?? 8; // Now calculated from workSchedule
        _otRate[staff] = double.tryParse(otCtrl.text) ?? 150;
      });
      await prefs.setString('payroll_base', jsonEncode(_basePerDay));
      await prefs.setString('payroll_hours', jsonEncode(_hoursPerDay));
      await prefs.setString('payroll_ot', jsonEncode(_otRate));
    }
  }

  Future<void> _pickFrom() async {
    final p = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2022), lastDate: DateTime.now());
    if (p != null) setState(() => _from = p);
    await _load();
    await _refreshLockState();
  }

  Future<void> _pickTo() async {
    final p = await showDatePicker(context: context, initialDate: _to, firstDate: DateTime(2022), lastDate: DateTime.now());
    if (p != null) setState(() => _to = p);
    await _load();
  }

  bool get _isManager => _role == 'admin';

  Future<void> _toggleLock() async {
    if (!_isManager) return;
    final email = FirebaseAuth.instance.currentUser?.email ?? 'manager';
    final newLock = !_monthLocked;
    await db.setPayrollMonthLock(DateFormat('yyyy-MM').format(_from), locked: newLock, lockedBy: email, note: 'payroll_view');
    await _refreshLockState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(newLock ? 'Đã khóa tháng' : 'Đã mở khóa tháng')));
  }

  Future<void> _exportCsv(Map<String, dynamic> summary) async {
    final buffer = StringBuffer();
    buffer.writeln('Date,Name,CheckIn,CheckOut,Hours,OT,Status');
    for (final a in _filteredAtt) {
      final inMs = a.checkInAt;
      final outMs = a.checkOutAt;
      final hrs = (inMs != null && outMs != null && outMs > inMs)
          ? ((outMs - inMs) / (1000 * 60 * 60))
          : 0.0;
      buffer.writeln([
        a.dateKey ?? '',
        a.name ?? '',
        inMs == null ? '' : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(inMs)),
        outMs == null ? '' : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(outMs)),
        hrs.toStringAsFixed(2),
        (a.overtimeOn ?? 0) == 1 ? 'OT' : '',
        (a.status ?? 'pending').toString(),
      ].join(','));
    }
    buffer.writeln('');
    buffer.writeln('Summary,,Days,RegularHours,OTHours,Salary');
    buffer.writeln(',,'
      '${summary['days']},'
      '${summary['regularHours'].toStringAsFixed(2)},'
      '${summary['otHours'].toStringAsFixed(2)},'
      '${summary['salary'].round()}');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã copy CSV vào clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('BẢNG LƯƠNG')),
        body: const Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: AppTextStyles.body1.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }

    final summary = _calc();
    return Scaffold(
      appBar: AppBar(title: const Text('BẢNG LƯƠNG'), automaticallyImplyLeading: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.calendar_today), label: Text(DateFormat('dd/MM/yyyy').format(_from)))),
                          const SizedBox(width: 8),
                          Expanded(child: OutlinedButton.icon(onPressed: _pickTo, icon: const Icon(Icons.calendar_today), label: Text(DateFormat('dd/MM/yyyy').format(_to)))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedStaff,
                              decoration: const InputDecoration(labelText: 'Chọn nhân viên', border: OutlineInputBorder()),
                              items: _staffList.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (v) => setState(() => _selectedStaff = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _customStaff,
                              decoration: const InputDecoration(labelText: 'Hoặc gõ tên', border: OutlineInputBorder()),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton.icon(onPressed: (!_isManager || _monthLocked) ? null : _openRuleDialog, icon: const Icon(Icons.rule), label: const Text('Cài công thức')),
                            ElevatedButton.icon(onPressed: () => _exportCsv(summary), icon: const Icon(Icons.file_download), label: const Text('Xuất CSV')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius), boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 6)]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TỔNG HỢP', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold, color: AppColors.onSurface)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Chip(label: Text(_monthLocked ? 'THÁNG ĐÃ KHÓA' : 'THÁNG CHƯA KHÓA'), backgroundColor: _monthLocked ? AppColors.warning.withOpacity(0.2) : AppColors.success.withOpacity(0.2)),
                          const SizedBox(width: 8),
                          if (_isManager)
                            TextButton.icon(onPressed: _toggleLock, icon: Icon(_monthLocked ? Icons.lock_open : Icons.lock), label: Text(_monthLocked ? 'Mở khóa' : 'Khóa tháng')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Ngày công: ${summary['days']}'),
                      Text('Giờ chuẩn: ${summary['regularHours'].toStringAsFixed(2)}h'),
                      Text('Giờ OT: ${summary['otHours'].toStringAsFixed(2)}h (hệ số ${summary['otRate']})'),
                      const Divider(),
                      Text('Lương tạm tính: ${NumberFormat('#,###').format(summary['salary'].round())} đ', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold, color: AppColors.success)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: _filteredAtt.map((a) {
                      final inMs = a.checkInAt;
                      final outMs = a.checkOutAt;
                      final hrs = (inMs != null && outMs != null && outMs > inMs)
                          ? ((outMs - inMs) / (1000 * 60 * 60))
                          : 0.0;
                      return ListTile(
                        leading: const Icon(Icons.calendar_today, size: 18),
                        title: Text(a.dateKey ?? ''),
                        subtitle: Text('In: ${inMs == null ? '--' : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(inMs))} • Out: ${outMs == null ? '--' : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(outMs))} • ${hrs.toStringAsFixed(2)}h'),
                        trailing: Text((a.overtimeOn ?? 0) == 1 ? 'OT' : ''),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
