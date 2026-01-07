import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../services/user_service.dart';

class WorkScheduleSettingsView extends StatefulWidget {
  const WorkScheduleSettingsView({super.key});

  @override
  State<WorkScheduleSettingsView> createState() => _WorkScheduleSettingsViewState();
}

class _WorkScheduleSettingsViewState extends State<WorkScheduleSettingsView> with TickerProviderStateMixin {
  late TabController _tabController;

  String _getShortRoleName(String role) {
    switch (role) {
      case 'owner':
        return 'CS';
      case 'manager':
        return 'QL';
      case 'employee':
        return 'NV';
      case 'technician':
        return 'KT';
      case 'admin':
        return 'AD';
      case 'user':
        return 'ND';
      default:
        return role.substring(0, 2).toUpperCase();
    }
  }

  // Work Schedule Settings
  final startTimeCtrl = TextEditingController(text: '08:00');
  final endTimeCtrl = TextEditingController(text: '17:00');
  final breakTimeCtrl = TextEditingController(text: '1');
  final maxOtHoursCtrl = TextEditingController(text: '4');

  // Work Days Settings
  List<bool> workDays = [false, true, true, true, true, true, false]; // Sun to Sat
  final holidayCtrl = TextEditingController();
  List<String> holidays = [];

  // Overtime Settings
  final weekdayOtRateCtrl = TextEditingController(text: '150');
  final weekendOtRateCtrl = TextEditingController(text: '200');
  final holidayOtRateCtrl = TextEditingController(text: '300');

  // Staff Salary Settings
  final staffSalaryCtrl = TextEditingController();
  String? selectedStaff;
  List<Map<String, dynamic>> staffList = [];
  Map<String, double> staffSalaries = {};

  // Attendance Settings
  List<Attendance> attendanceRecords = [];
  String? selectedStaffForAttendance;
  DateTime selectedDate = DateTime.now();
  bool _isSuperAdmin = false;
  String? _currentShopId;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    startTimeCtrl.dispose();
    endTimeCtrl.dispose();
    breakTimeCtrl.dispose();
    maxOtHoursCtrl.dispose();
    holidayCtrl.dispose();
    weekdayOtRateCtrl.dispose();
    weekendOtRateCtrl.dispose();
    holidayOtRateCtrl.dispose();
    staffSalaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUser = FirebaseAuth.instance.currentUser;

      // Check permissions
      _isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      _currentShopId = await UserService.getCurrentShopId();

      // Load work schedule
      startTimeCtrl.text = prefs.getString('work_start_time') ?? '08:00';
      endTimeCtrl.text = prefs.getString('work_end_time') ?? '17:00';
      breakTimeCtrl.text = (prefs.getInt('work_break_time') ?? 1).toString();
      maxOtHoursCtrl.text = (prefs.getInt('work_max_ot_hours') ?? 4).toString();

      // Load work days
      final workDaysStr = prefs.getString('work_days');
      if (workDaysStr != null) {
        final days = workDaysStr.split(',');
        for (int i = 0; i < workDays.length && i < days.length; i++) {
          workDays[i] = days[i] == '1';
        }
      }

      // Load holidays
      final holidaysStr = prefs.getString('work_holidays');
      if (holidaysStr != null) {
        holidays = holidaysStr.split(',');
      }

      // Load OT rates
      weekdayOtRateCtrl.text = (prefs.getInt('weekday_ot_rate') ?? 150).toString();
      weekendOtRateCtrl.text = (prefs.getInt('weekend_ot_rate') ?? 200).toString();
      holidayOtRateCtrl.text = (prefs.getInt('holiday_ot_rate') ?? 300).toString();

      // Load staff salaries
      final salariesStr = prefs.getString('staff_salaries');
      if (salariesStr != null) {
        final entries = salariesStr.split(';');
        for (final entry in entries) {
          if (entry.isNotEmpty) {
            final parts = entry.split(':');
            if (parts.length == 2) {
              staffSalaries[parts[0]] = double.tryParse(parts[1]) ?? 0;
            }
          }
        }
      }

      // Load staff list from shop
      await _loadStaffList();

      // Load attendance records for selected date
      await _loadAttendanceRecords();

    } catch (e) {
      // Handle error silently
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStaffList() async {
    try {
      final db = FirebaseFirestore.instance;
      Query query = db.collection('users');

      // Filter by shop if not super admin
      if (!_isSuperAdmin && _currentShopId != null) {
        query = query.where('shopId', isEqualTo: _currentShopId);
      }

      final snapshot = await query.get();
      staffList = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'] ?? data['email']?.split('@').first ?? 'Unknown',
          'email': data['email'] ?? '',
          'role': data['role'] ?? 'user',
        };
      }).toList();

      // Sort by name
      staffList.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    } catch (e) {
      // Fallback to sample data
      staffList = [
        {'id': 'staff1', 'name': 'Nguyễn Văn A', 'email': 'a@example.com', 'role': 'employee'},
        {'id': 'staff2', 'name': 'Trần Thị B', 'email': 'b@example.com', 'role': 'technician'},
        {'id': 'staff3', 'name': 'Lê Văn C', 'email': 'c@example.com', 'role': 'manager'},
      ];
    }
  }

  Future<void> _loadAttendanceRecords() async {
    if (selectedStaffForAttendance == null) return;

    try {
      final db = DBHelper();
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final record = await db.getAttendance(dateStr, selectedStaffForAttendance!);

      setState(() {
        attendanceRecords = record != null ? [record] : [];
      });
    } catch (e) {
      setState(() {
        attendanceRecords = [];
      });
    }
  }

  Future<void> _saveWorkSchedule() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('work_start_time', startTimeCtrl.text);
      await prefs.setString('work_end_time', endTimeCtrl.text);
      await prefs.setInt('work_break_time', int.tryParse(breakTimeCtrl.text) ?? 1);
      await prefs.setInt('work_max_ot_hours', int.tryParse(maxOtHoursCtrl.text) ?? 4);

      // Save work days
      final workDaysStr = workDays.map((d) => d ? '1' : '0').join(',');
      await prefs.setString('work_days', workDaysStr);

      // Save holidays
      final holidaysStr = holidays.join(',');
      await prefs.setString('work_holidays', holidaysStr);

      // Save OT rates
      await prefs.setInt('weekday_ot_rate', int.tryParse(weekdayOtRateCtrl.text) ?? 150);
      await prefs.setInt('weekend_ot_rate', int.tryParse(weekendOtRateCtrl.text) ?? 200);
      await prefs.setInt('holiday_ot_rate', int.tryParse(holidayOtRateCtrl.text) ?? 300);

      messenger.showSnackBar(
        const SnackBar(content: Text('Đã lưu cài đặt lịch làm việc')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu: $e')),
      );
    }
  }

  Future<void> _saveStaffSalary() async {
    if (selectedStaff == null || staffSalaryCtrl.text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final salary = double.tryParse(staffSalaryCtrl.text.replaceAll(',', ''));
      if (salary == null) return;

      staffSalaries[selectedStaff!] = salary;

      final prefs = await SharedPreferences.getInstance();
      final salariesStr = staffSalaries.entries.map((e) => '${e.key}:${e.value}').join(';');
      await prefs.setString('staff_salaries', salariesStr);

      staffSalaryCtrl.clear();
      selectedStaff = null;

      setState(() {});

      messenger.showSnackBar(
        const SnackBar(content: Text('Đã lưu lương nhân viên')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu: $e')),
      );
    }
  }

  Future<void> _selectTime(TextEditingController controller) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      controller.text = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _addHoliday() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      if (!holidays.contains(dateStr)) {
        setState(() {
          holidays.add(dateStr);
          holidays.sort();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt lịch làm việc'),
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Giờ làm việc'),
            Tab(text: 'Ngày nghỉ'),
            Tab(text: 'Tăng ca'),
            Tab(text: 'Lương NV'),
            Tab(text: 'Chấm công'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWorkScheduleTab(),
          _buildWorkDaysTab(),
          _buildOvertimeTab(),
          _buildStaffSalaryTab(),
          _buildAttendanceTab(),
        ],
      ),
    );
  }

  Widget _buildWorkScheduleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cài đặt giờ làm việc', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          _buildTimeCard('Giờ bắt đầu', startTimeCtrl),
          const SizedBox(height: 16),
          _buildTimeCard('Giờ kết thúc', endTimeCtrl),
          const SizedBox(height: 16),
          _buildNumberCard('Giờ nghỉ trưa (tiếng)', breakTimeCtrl, 'giờ'),
          const SizedBox(height: 16),
          _buildNumberCard('Giờ tăng ca tối đa/ngày', maxOtHoursCtrl, 'giờ'),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveWorkSchedule,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: const Text('Lưu cài đặt', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard(String label, TextEditingController controller) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              readOnly: true,
              onTap: () => _selectTime(controller),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.access_time),
                hintText: 'Chọn giờ',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberCard(String label, TextEditingController controller, String unit) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixText: unit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkDaysTab() {
    final dayNames = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cài đặt ngày làm việc', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          const Text('Ngày làm việc trong tuần:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(7, (index) {
              return FilterChip(
                label: Text(dayNames[index]),
                selected: workDays[index],
                onSelected: (selected) {
                  setState(() {
                    workDays[index] = selected ?? false;
                  });
                },
              );
            }),
          ),

          const SizedBox(height: 24),
          const Text('Ngày nghỉ lễ:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm ngày nghỉ'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          if (holidays.isNotEmpty) ...[
            const Text('Danh sách ngày nghỉ:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: holidays.map((holiday) {
                return Chip(
                  label: Text(holiday),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      holidays.remove(holiday);
                    });
                  },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveWorkSchedule,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: const Text('Lưu cài đặt', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOvertimeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cài đặt tăng ca', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          _buildNumberCard('Tăng ca ngày thường (% lương/giờ)', weekdayOtRateCtrl, '%'),
          const SizedBox(height: 16),
          _buildNumberCard('Tăng ca cuối tuần (% lương/giờ)', weekendOtRateCtrl, '%'),
          const SizedBox(height: 16),
          _buildNumberCard('Tăng ca ngày lễ (% lương/giờ)', holidayOtRateCtrl, '%'),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveWorkSchedule,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: const Text('Lưu cài đặt', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSalaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cài đặt lương nhân viên', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Thêm/Cập nhật lương', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: selectedStaff,
                    decoration: const InputDecoration(
                      labelText: 'Chọn nhân viên',
                      border: OutlineInputBorder(),
                    ),
                    items: staffList.map((staff) {
                      return DropdownMenuItem<String>(
                        value: staff['id'] as String,
                        child: Text(staff['name'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedStaff = value;
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: staffSalaryCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      NumberTextInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Lương cơ bản (VNĐ)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveStaffSalary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      child: const Text('Lưu lương', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (staffSalaries.isNotEmpty) ...[
            const Text('Danh sách lương hiện tại:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            ...staffSalaries.entries.map((entry) {
              final staff = staffList.firstWhere(
                (s) => s['id'] == entry.key,
                orElse: () => {'name': 'Unknown'},
              );
              return Card(
                child: ListTile(
                  title: Text(staff['name'] as String),
                  trailing: Text(
                    '${NumberFormat('#,###').format(entry.value)} đ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quản lý chấm công nhân viên', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Date picker
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chọn ngày', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) {
                        setState(() {
                          selectedDate = date;
                        });
                        await _loadAttendanceRecords();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Staff selector
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chọn nhân viên', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStaffForAttendance,
                    decoration: const InputDecoration(
                      labelText: 'Nhân viên',
                      border: OutlineInputBorder(),
                    ),
                    items: staffList.map((staff) {
                      return DropdownMenuItem<String>(
                        value: staff['id'] as String,
                        child: Text('${staff['name']} (${_getShortRoleName(staff['role'])})'),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      setState(() {
                        selectedStaffForAttendance = value;
                      });
                      await _loadAttendanceRecords();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Attendance records
          if (selectedStaffForAttendance != null) ...[
            const Text('Thông tin chấm công', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),

            if (attendanceRecords.isEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Không có dữ liệu chấm công cho ngày ${DateFormat('dd/MM/yyyy').format(selectedDate)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ] else ...[
              ...attendanceRecords.map((record) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nhân viên: ${staffList.firstWhere((s) => s['id'] == record.userId, orElse: () => {'name': 'Unknown'})['name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      if (record.checkInAt != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.login, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'Check-in: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!))}',
                            ),
                          ],
                        ),
                      ],

                      if (record.checkOutAt != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.logout, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(
                              'Check-out: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!))}',
                            ),
                          ],
                        ),
                      ],

                      if (record.status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(
                            record.status == 'approved' ? 'Đã duyệt' :
                            record.status == 'rejected' ? 'Từ chối' : 'Chờ duyệt',
                          ),
                          backgroundColor: record.status == 'approved' ? Colors.green :
                                         record.status == 'rejected' ? Colors.red : Colors.orange,
                        ),
                      ],
                    ],
                  ),
                ),
              )),
            ],
          ] else ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Vui lòng chọn nhân viên để xem thông tin chấm công',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NumberTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final number = int.tryParse(newValue.text.replaceAll(',', ''));
    if (number == null) return oldValue;

    final formatted = NumberFormat('#,###').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}