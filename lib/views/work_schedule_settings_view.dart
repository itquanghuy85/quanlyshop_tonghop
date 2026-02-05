import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';

class WorkScheduleSettingsView extends StatefulWidget {
  const WorkScheduleSettingsView({super.key});

  @override
  State<WorkScheduleSettingsView> createState() =>
      _WorkScheduleSettingsViewState();
}

class _WorkScheduleSettingsViewState extends State<WorkScheduleSettingsView> {
  AppLocalizations get loc => AppLocalizations.of(context)!;
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
  List<bool> workDays = [
    false,
    true,
    true,
    true,
    true,
    true,
    false,
  ]; // Sun to Sat
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

  // Staff Work Schedules (loaded into state to avoid FutureBuilder issues)
  Map<String, Map<String, dynamic>> _staffWorkSchedules = {};

  // Attendance Settings
  List<Attendance> attendanceRecords = [];
  String? selectedStaffForAttendance;
  DateTime selectedDate = DateTime.now();
  bool _isSuperAdmin = false;
  String? _currentShopId;

  bool _loading = true;
  bool _refreshingStaff =
      false; // For refreshing staff list without resetting tabs

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
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

      // Load work schedule from Firestore first (sync source), fallback to local
      Map<String, dynamic>? firestoreSchedule;
      if (_currentShopId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('work_schedules')
            .doc('shop_general_$_currentShopId')
            .get();
        if (doc.exists) {
          firestoreSchedule = doc.data();
          debugPrint(
            '📋 Loaded work schedule from Firestore: $firestoreSchedule',
          );
        }
      }

      // Use Firestore data if available, otherwise use SharedPreferences
      if (firestoreSchedule != null) {
        startTimeCtrl.text = firestoreSchedule['startTime'] ?? '08:00';
        endTimeCtrl.text = firestoreSchedule['endTime'] ?? '17:00';
        breakTimeCtrl.text = (firestoreSchedule['breakTime'] ?? 1).toString();
        maxOtHoursCtrl.text = (firestoreSchedule['maxOtHours'] ?? 4).toString();

        // Load work days from Firestore
        final workDaysStr = firestoreSchedule['workDays'] as String?;
        if (workDaysStr != null) {
          final days = workDaysStr.split(',');
          for (int i = 0; i < workDays.length && i < days.length; i++) {
            workDays[i] = days[i] == '1';
          }
        }

        // Load holidays from Firestore
        final holidaysStr = firestoreSchedule['holidays'] as String?;
        if (holidaysStr != null && holidaysStr.isNotEmpty) {
          holidays = holidaysStr.split(',').where((h) => h.isNotEmpty).toList();
        }

        // Load OT rates from Firestore
        weekdayOtRateCtrl.text = (firestoreSchedule['weekdayOtRate'] ?? 150)
            .toString();
        weekendOtRateCtrl.text = (firestoreSchedule['weekendOtRate'] ?? 200)
            .toString();
        holidayOtRateCtrl.text = (firestoreSchedule['holidayOtRate'] ?? 300)
            .toString();

        // Also update SharedPreferences for local cache
        await prefs.setString('work_start_time', startTimeCtrl.text);
        await prefs.setString('work_end_time', endTimeCtrl.text);
        await prefs.setInt(
          'work_break_time',
          int.tryParse(breakTimeCtrl.text) ?? 1,
        );
        await prefs.setInt(
          'work_max_ot_hours',
          int.tryParse(maxOtHoursCtrl.text) ?? 4,
        );
        await prefs.setString('work_days', workDaysStr ?? '0,1,1,1,1,1,0');
        await prefs.setString('work_holidays', holidaysStr ?? '');
        await prefs.setInt(
          'weekday_ot_rate',
          int.tryParse(weekdayOtRateCtrl.text) ?? 150,
        );
        await prefs.setInt(
          'weekend_ot_rate',
          int.tryParse(weekendOtRateCtrl.text) ?? 200,
        );
        await prefs.setInt(
          'holiday_ot_rate',
          int.tryParse(holidayOtRateCtrl.text) ?? 300,
        );
      } else {
        // Fallback to SharedPreferences
        startTimeCtrl.text = prefs.getString('work_start_time') ?? '08:00';
        endTimeCtrl.text = prefs.getString('work_end_time') ?? '17:00';
        breakTimeCtrl.text = (prefs.getInt('work_break_time') ?? 1).toString();
        maxOtHoursCtrl.text = (prefs.getInt('work_max_ot_hours') ?? 4)
            .toString();

        // Load work days from SharedPreferences
        final workDaysStr = prefs.getString('work_days');
        if (workDaysStr != null) {
          final days = workDaysStr.split(',');
          for (int i = 0; i < workDays.length && i < days.length; i++) {
            workDays[i] = days[i] == '1';
          }
        }

        // Load holidays from SharedPreferences
        final holidaysStr = prefs.getString('work_holidays');
        if (holidaysStr != null && holidaysStr.isNotEmpty) {
          holidays = holidaysStr.split(',').where((h) => h.isNotEmpty).toList();
        }

        // Load OT rates from SharedPreferences
        weekdayOtRateCtrl.text = (prefs.getInt('weekday_ot_rate') ?? 150)
            .toString();
        weekendOtRateCtrl.text = (prefs.getInt('weekend_ot_rate') ?? 200)
            .toString();
        holidayOtRateCtrl.text = (prefs.getInt('holiday_ot_rate') ?? 300)
            .toString();
      }

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

      // Load work schedules for all staff
      await _loadStaffWorkSchedules();

      // Load attendance records for selected date
      await _loadAttendanceRecords();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStaffList() async {
    try {
      final db = FirebaseFirestore.instance;
      final currentUser = FirebaseAuth.instance.currentUser;

      debugPrint(
        '📋 _loadStaffList: isSuperAdmin=$_isSuperAdmin, shopId=$_currentShopId',
      );

      // Nếu chưa có shopId, thử lấy từ nhiều nguồn
      if (_currentShopId == null || _currentShopId!.isEmpty) {
        // 1. Thử từ UserService cache
        _currentShopId = await UserService.getCurrentShopId();
        debugPrint('📋 Got shopId from UserService: $_currentShopId');

        // 2. Thử từ Firestore user doc
        if ((_currentShopId == null || _currentShopId!.isEmpty) &&
            currentUser != null) {
          final userDoc = await db
              .collection('users')
              .doc(currentUser.uid)
              .get();
          final shopIdFromDoc = userDoc.data()?['shopId'] as String?;
          if (shopIdFromDoc != null && shopIdFromDoc.isNotEmpty) {
            _currentShopId = shopIdFromDoc;
            debugPrint('📋 Got shopId from Firestore doc: $_currentShopId');
          }
        }

        // 3. Với non-super-admin, dùng uid làm shopId (owner mặc định)
        if ((_currentShopId == null || _currentShopId!.isEmpty) &&
            !_isSuperAdmin &&
            currentUser != null) {
          _currentShopId = currentUser.uid;
          debugPrint('📋 Using uid as shopId fallback: $_currentShopId');
        }
      }

      // Vẫn không có shopId = trả về rỗng
      if (_currentShopId == null || _currentShopId!.isEmpty) {
        debugPrint(
          '⚠️ No shopId found after all attempts, returning empty staffList',
        );
        staffList = [];
        return;
      }

      // Query users với shopId filter
      debugPrint('📋 Querying users with shopId: $_currentShopId');

      // Thực hiện queries:
      // 1. Users có shopId trùng với _currentShopId
      // 2. Users có shopId trùng uid của owner (nếu khác _currentShopId)
      // 3. User hiện tại (owner case)
      final List<Map<String, dynamic>> allStaff = [];
      final Set<String> addedIds = {};

      // Query 1: Users có shopId == _currentShopId
      try {
        final snapshot = await db
            .collection('users')
            .where('shopId', isEqualTo: _currentShopId)
            .get();
        debugPrint(
          '📋 Found ${snapshot.docs.length} staff with shopId=$_currentShopId',
        );

        for (var doc in snapshot.docs) {
          if (!addedIds.contains(doc.id)) {
            final data = doc.data();
            allStaff.add({
              'id': doc.id,
              'name':
                  data['name'] ??
                  data['displayName'] ??
                  data['email']?.toString().split('@').first ??
                  'Unknown',
              'email': data['email'] ?? '',
              'role': data['role'] ?? 'user',
            });
            addedIds.add(doc.id);
          }
        }
      } catch (e) {
        debugPrint('❌ Query users with shopId failed: $e');
      }

      // Query 2: Nếu shopId khác uid, thử query thêm với uid làm shopId (owner's employees)
      if (currentUser != null && _currentShopId != currentUser.uid) {
        try {
          final snapshot2 = await db
              .collection('users')
              .where('shopId', isEqualTo: currentUser.uid)
              .get();
          debugPrint(
            '📋 Found ${snapshot2.docs.length} staff with shopId=${currentUser.uid} (owner uid)',
          );

          for (var doc in snapshot2.docs) {
            if (!addedIds.contains(doc.id)) {
              final data = doc.data();
              allStaff.add({
                'id': doc.id,
                'name':
                    data['name'] ??
                    data['displayName'] ??
                    data['email']?.toString().split('@').first ??
                    'Unknown',
                'email': data['email'] ?? '',
                'role': data['role'] ?? 'user',
              });
              addedIds.add(doc.id);
            }
          }
        } catch (e) {
          debugPrint('❌ Query users with owner uid failed: $e');
        }
      }

      // Query 3: LUÔN thêm current user vào danh sách nếu chưa có
      // (Đảm bảo owner/chủ shop luôn xuất hiện trong danh sách)
      if (currentUser != null && !addedIds.contains(currentUser.uid)) {
        try {
          final ownerDoc = await db
              .collection('users')
              .doc(currentUser.uid)
              .get();
          if (ownerDoc.exists) {
            final data = ownerDoc.data()!;
            allStaff.add({
              'id': currentUser.uid,
              'name':
                  data['name'] ??
                  data['displayName'] ??
                  currentUser.email?.split('@').first ??
                  'Owner',
              'email': data['email'] ?? currentUser.email ?? '',
              'role': data['role'] ?? 'owner',
            });
            addedIds.add(currentUser.uid);
            debugPrint(
              '📋 Added owner/current user to staff list: ${currentUser.uid}',
            );
          } else {
            // User doc không tồn tại, tạo entry từ auth info
            allStaff.add({
              'id': currentUser.uid,
              'name':
                  currentUser.displayName ??
                  currentUser.email?.split('@').first ??
                  'Owner',
              'email': currentUser.email ?? '',
              'role': 'owner',
            });
            addedIds.add(currentUser.uid);
            debugPrint(
              '📋 Added current user from auth info: ${currentUser.uid}',
            );
          }
        } catch (e) {
          debugPrint('❌ Query owner doc failed: $e');
          // Fallback: thêm từ auth info
          allStaff.add({
            'id': currentUser.uid,
            'name':
                currentUser.displayName ??
                currentUser.email?.split('@').first ??
                'Owner',
            'email': currentUser.email ?? '',
            'role': 'owner',
          });
          addedIds.add(currentUser.uid);
        }
      }

      debugPrint('📋 Total staff loaded: ${allStaff.length}');

      staffList = allStaff;

      // Sort by name
      staffList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
    } catch (e) {
      debugPrint('❌ _loadStaffList error: $e');
      // Fallback to empty list instead of sample data
      staffList = [];
    }
  }

  /// Load work schedules cho tất cả nhân viên vào state (từ Firestore hoặc local DB)
  Future<void> _loadStaffWorkSchedules() async {
    final db = DBHelper();
    final Map<String, Map<String, dynamic>> schedules = {};

    for (final staff in staffList) {
      final userId = staff['id'] as String;
      try {
        // Thử load từ Firestore trước (để sync giữa các thiết bị)
        Map<String, dynamic>? schedule;
        if (_currentShopId != null) {
          final doc = await FirebaseFirestore.instance
              .collection('work_schedules')
              .doc('staff_${userId}_$_currentShopId')
              .get();
          if (doc.exists) {
            schedule = doc.data();
            debugPrint('📋 Loaded schedule from Firestore for $userId');
            // Cập nhật local DB
            await db.upsertWorkSchedule(userId, schedule!);
          }
        }

        // Nếu không có trên Firestore, dùng local DB
        schedule ??= await db.getWorkSchedule(userId);

        if (schedule != null) {
          schedules[userId] = schedule;
        }
      } catch (e) {
        debugPrint('❌ Error loading schedule for $userId: $e');
        // Fallback to local DB
        final localSchedule = await db.getWorkSchedule(userId);
        if (localSchedule != null) {
          schedules[userId] = localSchedule;
        }
      }
    }

    setState(() {
      _staffWorkSchedules = schedules;
    });
    debugPrint(
      '📋 Loaded ${schedules.length} work schedules for ${staffList.length} staff',
    );
  }

  /// Auto load staff list khi vào tab Nhân viên
  Future<void> _autoLoadStaff() async {
    if (_refreshingStaff) return;
    setState(() => _refreshingStaff = true);
    try {
      // Đảm bảo có shopId trước
      if (_currentShopId == null || _currentShopId!.isEmpty) {
        _currentShopId = await UserService.getCurrentShopId();
        final currentUser = FirebaseAuth.instance.currentUser;
        if ((_currentShopId == null || _currentShopId!.isEmpty) &&
            currentUser != null) {
          _currentShopId = currentUser.uid;
        }
      }
      await _loadStaffList();
      await _loadStaffWorkSchedules();
    } catch (e) {
      debugPrint('❌ _autoLoadStaff error: $e');
    } finally {
      if (mounted) setState(() => _refreshingStaff = false);
    }
  }

  Future<void> _loadAttendanceRecords() async {
    if (selectedStaffForAttendance == null) return;

    try {
      final db = DBHelper();
      final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
      final record = await db.getAttendance(
        dateStr,
        selectedStaffForAttendance!,
      );

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
      final shopId = _currentShopId;

      // Prepare data for sync
      final workDaysStr = workDays.map((d) => d ? '1' : '0').join(',');
      final holidaysStr = holidays.join(',');
      final scheduleData = {
        'startTime': startTimeCtrl.text,
        'endTime': endTimeCtrl.text,
        'breakTime': int.tryParse(breakTimeCtrl.text) ?? 1,
        'maxOtHours': int.tryParse(maxOtHoursCtrl.text) ?? 4,
        'workDays': workDaysStr,
        'holidays': holidaysStr,
        'weekdayOtRate': int.tryParse(weekdayOtRateCtrl.text) ?? 150,
        'weekendOtRate': int.tryParse(weekendOtRateCtrl.text) ?? 200,
        'holidayOtRate': int.tryParse(holidayOtRateCtrl.text) ?? 300,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'shopId': shopId,
      };

      // Save to SharedPreferences (for local cache)
      await prefs.setString('work_start_time', startTimeCtrl.text);
      await prefs.setString('work_end_time', endTimeCtrl.text);
      await prefs.setInt(
        'work_break_time',
        int.tryParse(breakTimeCtrl.text) ?? 1,
      );
      await prefs.setInt(
        'work_max_ot_hours',
        int.tryParse(maxOtHoursCtrl.text) ?? 4,
      );
      await prefs.setString('work_days', workDaysStr);
      await prefs.setString('work_holidays', holidaysStr);
      await prefs.setInt(
        'weekday_ot_rate',
        int.tryParse(weekdayOtRateCtrl.text) ?? 150,
      );
      await prefs.setInt(
        'weekend_ot_rate',
        int.tryParse(weekendOtRateCtrl.text) ?? 200,
      );
      await prefs.setInt(
        'holiday_ot_rate',
        int.tryParse(holidayOtRateCtrl.text) ?? 300,
      );

      // Save to local DB
      await DBHelper().upsertWorkSchedule('shop_general', scheduleData);

      // Sync to Firestore (với shopId)
      if (shopId != null) {
        await FirebaseFirestore.instance
            .collection('work_schedules')
            .doc('shop_general_$shopId')
            .set(scheduleData, SetOptions(merge: true));
      }

      messenger.showSnackBar(
        SnackBar(content: Text(loc.workScheduleSaved)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loc.saveErrorMsg(e.toString()))));
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
      final salariesStr = staffSalaries.entries
          .map((e) => '${e.key}:${e.value}')
          .join(';');
      await prefs.setString('staff_salaries', salariesStr);

      staffSalaryCtrl.clear();
      selectedStaff = null;

      setState(() {});

      messenger.showSnackBar(
        SnackBar(content: Text(loc.staffSalarySaved)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(loc.saveErrorMsg(e.toString()))));
    }
  }

  Future<void> _selectTime(TextEditingController controller) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      controller.text =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loc.workScheduleSettingsTitle),
          automaticallyImplyLeading: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            tabs: [
              Tab(text: loc.generalSettingsTab),
              Tab(text: loc.staffTab),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            _buildGeneralSettingsTab(),
            _buildStaffManagementTabSimple(),
          ],
        ),
      ),
    );
  }

  /// Simplified Staff Management Tab - không dùng Builder hay try-catch
  Widget _buildStaffManagementTabSimple() {
    debugPrint(
      '🟢 _buildStaffManagementTabSimple called, staffList=${staffList.length}',
    );

    if (staffList.isEmpty) {
      // Tự động load lại nếu chưa có data và không đang loading
      if (!_refreshingStaff && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && staffList.isEmpty && !_refreshingStaff) {
            _autoLoadStaff();
          }
        });
      }

      return Container(
        color: Colors.grey.shade100,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_refreshingStaff) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  loc.loadingStaffList,
                  style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                ),
              ] else ...[
                const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  loc.noStaffData,
                  style: TextStyle(fontSize: AppTextStyles.headline2.fontSize),
                ),
                const SizedBox(height: 8),
                Text(
                  loc.tapToRefresh,
                  style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(loc.reload),
                  onPressed: _autoLoadStaff,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: staffList.length + 2, // +2 for headers
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              color: Colors.blue.shade50,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text(
                      loc.staffCountLabel(staffList.length),
                      style: TextStyle(
                        fontSize: AppTextStyles.headline3.fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    loc.staffWorkSchedule,
                    style: TextStyle(
                      fontSize: AppTextStyles.headline3.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            );
          }

          final staffIndex = index - 2;
          final staff = staffList[staffIndex];
          final staffId = staff['id'] as String;
          final schedule = _staffWorkSchedules[staffId];
          final hasSchedule = schedule != null;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: hasSchedule
                    ? Colors.green.shade100
                    : Colors.grey.shade200,
                child: Icon(
                  hasSchedule ? Icons.check : Icons.schedule,
                  color: hasSchedule ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ),
              title: Text(
                '${staff['name']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: hasSchedule
                  ? Text(
                      '${schedule['startTime'] ?? '08:00'} - ${schedule['endTime'] ?? '17:00'}',
                      style: TextStyle(
                        fontSize: AppTextStyles.subtitle1.fontSize,
                        color: Colors.grey.shade700,
                      ),
                    )
                  : Text(
                      loc.scheduleNotSet,
                      style: TextStyle(
                        fontSize: AppTextStyles.subtitle1.fontSize,
                        color: Colors.orange.shade700,
                      ),
                    ),
              trailing: IconButton(
                icon: Icon(Icons.edit, color: Colors.blue.shade600),
                onPressed: () => _editStaffWorkSchedule(staff, schedule),
              ),
            ),
          );
        },
      ),
    );
  }

  // Tab 1: Gộp Giờ làm việc + Ngày nghỉ + Tăng ca
  Widget _buildGeneralSettingsTab() {
    final dayNames = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === SECTION: Giờ làm việc ===
          _buildSectionTitle(loc.workHoursLabel, Icons.access_time),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildCompactTimeCard(loc.startTimeLabel, startTimeCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildCompactTimeCard(loc.endTimeLabel, endTimeCtrl)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCompactNumberCard(
                  loc.lunchBreakLabel,
                  breakTimeCtrl,
                  'giờ',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactNumberCard(
                  loc.maxOvertimeLabel,
                  maxOtHoursCtrl,
                  'giờ',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // === SECTION: Ngày làm việc ===
          _buildSectionTitle(loc.workDaysLabel, Icons.calendar_today),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              return FilterChip(
                label: Text(dayNames[index]),
                selected: workDays[index],
                onSelected: (selected) {
                  setState(() => workDays[index] = selected ?? false);
                  // Auto-save when work day changes
                  _saveWorkSchedule();
                },
              );
            }),
          ),

          const SizedBox(height: 16),

          // Ngày nghỉ lễ
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.holidaysLabel,
                  style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, fontWeight: FontWeight.w500),
                ),
              ),
              TextButton.icon(
                onPressed: _addHoliday,
                icon: const Icon(Icons.add, size: 18),
                label: Text(loc.addBtn),
              ),
            ],
          ),
          if (holidays.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: holidays.map((holiday) {
                return Chip(
                  label: Text(holiday, style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() => holidays.remove(holiday)),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),

          const SizedBox(height: 24),

          // === SECTION: Tăng ca ===
          _buildSectionTitle(loc.overtimeRateLabel, Icons.timer),
          const SizedBox(height: 12),
          _buildCompactNumberCard(loc.weekdayLabel, weekdayOtRateCtrl, '%'),
          const SizedBox(height: 8),
          _buildCompactNumberCard(loc.weekendLabel, weekendOtRateCtrl, '%'),
          const SizedBox(height: 8),
          _buildCompactNumberCard(loc.holidayLabel, holidayOtRateCtrl, '%'),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveWorkSchedule,
              icon: const Icon(Icons.save),
              label: Text(loc.saveSettingsBtn, style: TextStyle(fontSize: AppTextStyles.headline3.fontSize)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 2: Gộp Lương NV + Chấm công
  Widget _buildStaffManagementTab() {
    return Builder(
      builder: (context) {
        debugPrint('📋 _buildStaffManagementTab START');

        try {
          debugPrint('📋 staffList.length = ${staffList.length}');

          // Show message if no staff found
          if (staffList.isEmpty) {
            debugPrint('📋 staffList is EMPTY - showing empty message');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có nhân viên nào',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline2.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vui lòng thêm nhân viên trong phần\n"Quản lý nhân sự" trước',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    if (_refreshingStaff)
                      const CircularProgressIndicator()
                    else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tải lại'),
                        onPressed: () async {
                          setState(() => _refreshingStaff = true);
                          await _loadStaffList();
                          await _loadStaffWorkSchedules();
                          setState(() => _refreshingStaff = false);
                        },
                      ),
                  ],
                ),
              ),
            );
          }

          debugPrint('📋 Building full staff management content');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Debug info card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Số nhân viên: ${staffList.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // === SECTION: Lịch làm việc từng nhân viên ===
                _buildSectionTitle(
                  'Lịch làm việc từng nhân viên',
                  Icons.schedule,
                ),
                const SizedBox(height: 12),
                _buildStaffWorkScheduleList(),

                const SizedBox(height: 24),

                // === SECTION: Lương nhân viên ===
                _buildSectionTitle('Cài đặt lương', Icons.attach_money),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedStaff,
                          decoration: const InputDecoration(
                            labelText: 'Chọn nhân viên',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: staffList.map((staff) {
                            return DropdownMenuItem<String>(
                              value: staff['id'] as String,
                              child: Text(
                                '${staff['name']} (${_getShortRoleName(staff['role'])})',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => selectedStaff = value),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: staffSalaryCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  NumberTextInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Lương cơ bản (VNĐ)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _saveStaffSalary,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              child: const Text(
                                'Lưu',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Danh sách lương
                if (staffSalaries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...staffSalaries.entries.map((entry) {
                    final staff = staffList.firstWhere(
                      (s) => s['id'] == entry.key,
                      orElse: () => {'name': 'Unknown', 'role': 'user'},
                    );
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          '${staff['name']} (${_getShortRoleName(staff['role'])})',
                        ),
                        trailing: Text(
                          '${NumberFormat('#,###').format(entry.value)} đ',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 24),

                // === SECTION: Chấm công ===
                _buildSectionTitle('Tra cứu chấm công', Icons.fingerprint),
                const SizedBox(height: 12),

                // Date + Staff picker
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 30),
                            ),
                          );
                          if (date != null) {
                            setState(() => selectedDate = date);
                            await _loadAttendanceRecords();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('dd/MM/yyyy').format(selectedDate),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStaffForAttendance,
                  decoration: const InputDecoration(
                    labelText: 'Nhân viên',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: staffList.map((staff) {
                    return DropdownMenuItem<String>(
                      value: staff['id'] as String,
                      child: Text(
                        '${staff['name']} (${_getShortRoleName(staff['role'])})',
                      ),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    setState(() => selectedStaffForAttendance = value);
                    await _loadAttendanceRecords();
                  },
                ),

                const SizedBox(height: 16),

                // Attendance info
                if (selectedStaffForAttendance != null) ...[
                  if (attendanceRecords.isEmpty)
                    Card(
                      color: Colors.grey.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'Không có dữ liệu chấm công ngày ${DateFormat('dd/MM').format(selectedDate)}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    )
                  else
                    ...attendanceRecords.map(
                      (record) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (record.checkInAt != null) ...[
                                    const Icon(
                                      Icons.login,
                                      color: Colors.green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Vào: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!))}',
                                    ),
                                  ],
                                  const SizedBox(width: 16),
                                  if (record.checkOutAt != null) ...[
                                    const Icon(
                                      Icons.logout,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ra: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!))}',
                                    ),
                                  ],
                                ],
                              ),
                              if (record.status.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Chip(
                                  label: Text(
                                    record.status == 'approved'
                                        ? 'Đã duyệt'
                                        : record.status == 'rejected'
                                        ? 'Từ chối'
                                        : 'Chờ duyệt',
                                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                  ),
                                  backgroundColor: record.status == 'approved'
                                      ? Colors.green.shade100
                                      : record.status == 'rejected'
                                      ? Colors.red.shade100
                                      : Colors.orange.shade100,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ] else
                  Card(
                    color: Colors.blue.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Chọn nhân viên để xem chấm công',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        } catch (e, stackTrace) {
          debugPrint('❌ Error in _buildStaffManagementTab: $e');
          debugPrint('$stackTrace');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Lỗi hiển thị',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lỗi: $e',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  if (_refreshingStaff)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                      onPressed: () async {
                        setState(() => _refreshingStaff = true);
                        await _loadStaffList();
                        await _loadStaffWorkSchedules();
                        setState(() => _refreshingStaff = false);
                      },
                    ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: AppTextStyles.headline3.fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  /// Widget hiển thị danh sách nhân viên với lịch làm việc
  Widget _buildStaffWorkScheduleList() {
    if (staffList.isEmpty) {
      return Card(
        color: Colors.orange.shade50,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chưa có nhân viên. Nhấn "Tải lại" phía dưới hoặc thêm nhân viên trong Quản lý nhân sự.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: staffList.map((staff) {
        final staffId = staff['id'] as String;
        final schedule = _staffWorkSchedules[staffId];
        final hasSchedule = schedule != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: hasSchedule
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
              child: Icon(
                hasSchedule ? Icons.check : Icons.schedule,
                color: hasSchedule ? Colors.green : Colors.grey,
                size: 20,
              ),
            ),
            title: Text(
              '${staff['name']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: hasSchedule
                ? Text(
                    '${schedule['startTime'] ?? '08:00'} - ${schedule['endTime'] ?? '17:00'} | Nghỉ: ${schedule['breakTime'] ?? 1}h | OT: ${schedule['maxOtHours'] ?? 4}h',
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade700),
                  )
                : Text(
                    'Chưa cài đặt lịch',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      color: Colors.orange.shade700,
                    ),
                  ),
            trailing: IconButton(
              icon: Icon(Icons.edit, color: Colors.blue.shade600),
              onPressed: () => _editStaffWorkSchedule(staff, schedule),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Dialog chỉnh sửa lịch làm việc cho 1 nhân viên
  Future<void> _editStaffWorkSchedule(
    Map<String, dynamic> staff,
    Map<String, dynamic>? currentSchedule,
  ) async {
    final startCtrl = TextEditingController(
      text: currentSchedule?['startTime'] ?? '08:00',
    );
    final endCtrl = TextEditingController(
      text: currentSchedule?['endTime'] ?? '17:00',
    );
    final breakCtrl = TextEditingController(
      text: (currentSchedule?['breakTime'] ?? 1).toString(),
    );
    final maxOtCtrl = TextEditingController(
      text: (currentSchedule?['maxOtHours'] ?? 4).toString(),
    );

    // Work days (default Mon-Sat)
    List<bool> workDays = List.generate(7, (i) {
      final savedDays = currentSchedule?['workDays'];
      if (savedDays is String && savedDays.isNotEmpty) {
        // Parse "1,2,3,4,5,6" format
        final dayIndices = savedDays
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? -1)
            .toList();
        return dayIndices.contains(i);
      } else if (savedDays is List) {
        return savedDays.contains(i);
      }
      // Default: Mon(1) to Sat(6)
      return i >= 1 && i <= 6;
    });
    final dayNames = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lịch làm việc: ${staff['name']}',
                  style: TextStyle(fontSize: AppTextStyles.headline3.fontSize),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Giờ làm việc
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startCtrl,
                        readOnly: true,
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            startCtrl.text =
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Bắt đầu',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Icon(Icons.access_time, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: endCtrl,
                        readOnly: true,
                        onTap: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            endCtrl.text =
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Kết thúc',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Icon(Icons.access_time, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Nghỉ trưa + OT
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: breakCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nghỉ trưa',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixText: 'giờ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxOtCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'OT tối đa',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixText: 'giờ',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Ngày làm việc
                const Text(
                  'Ngày làm việc:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(7, (index) {
                    return FilterChip(
                      label: Text(
                        dayNames[index],
                        style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                      ),
                      selected: workDays[index],
                      onSelected: (selected) {
                        setDialogState(() => workDays[index] = selected);
                      },
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: const Text('LƯU'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                // Convert workDays bool list to int list (indices of true values)
                final workDayIndices = <int>[];
                for (int i = 0; i < workDays.length; i++) {
                  if (workDays[i]) workDayIndices.add(i);
                }

                final newSchedule = {
                  'userId': staff['id'],
                  'startTime': startCtrl.text,
                  'endTime': endCtrl.text,
                  'breakTime': int.tryParse(breakCtrl.text) ?? 1,
                  'maxOtHours': int.tryParse(maxOtCtrl.text) ?? 4,
                  'workDays': workDayIndices.join(
                    ',',
                  ), // Store as "1,2,3,4,5,6"
                  'updatedAt': DateTime.now().millisecondsSinceEpoch,
                  'shopId': _currentShopId,
                };

                await DBHelper().upsertWorkSchedule(
                  staff['id'] as String,
                  newSchedule,
                );

                // Sync to Firestore
                if (_currentShopId != null) {
                  await FirebaseFirestore.instance
                      .collection('work_schedules')
                      .doc('staff_${staff['id']}_$_currentShopId')
                      .set(newSchedule, SetOptions(merge: true));
                }

                // Cập nhật state ngay lập tức
                _staffWorkSchedules[staff['id'] as String] = newSchedule;

                if (!mounted) return;
                Navigator.pop(ctx);
                setState(() {}); // Refresh UI

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Đã lưu lịch làm việc cho ${staff['name']}'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTimeCard(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: () => _selectTime(controller),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.access_time, size: 20),
        isDense: true,
      ),
    );
  }

  Widget _buildCompactNumberCard(
    String label,
    TextEditingController controller,
    String unit,
  ) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: unit,
        isDense: true,
      ),
    );
  }

  Widget _buildWorkScheduleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cài đặt giờ làm việc',
            style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
          ),
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
              child: Text(
                'Lưu cài đặt',
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.white),
              ),
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
            Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
            ),
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

  Widget _buildNumberCard(
    String label,
    TextEditingController controller,
    String unit,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
            ),
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
          Text(
            'Cài đặt ngày làm việc',
            style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Text(
            'Ngày làm việc trong tuần:',
            style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
          ),
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
          Text(
            'Ngày nghỉ lễ:',
            style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
          ),
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
            Text(
              'Danh sách ngày nghỉ:',
              style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, fontWeight: FontWeight.w500),
            ),
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
              child: Text(
                'Lưu cài đặt',
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.white),
              ),
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
          Text(
            'Cài đặt tăng ca',
            style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          _buildNumberCard(
            'Tăng ca ngày thường (% lương/giờ)',
            weekdayOtRateCtrl,
            '%',
          ),
          const SizedBox(height: 16),
          _buildNumberCard(
            'Tăng ca cuối tuần (% lương/giờ)',
            weekendOtRateCtrl,
            '%',
          ),
          const SizedBox(height: 16),
          _buildNumberCard(
            'Tăng ca ngày lễ (% lương/giờ)',
            holidayOtRateCtrl,
            '%',
          ),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveWorkSchedule,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: Text(
                'Lưu cài đặt',
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.white),
              ),
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
          Text(
            'Cài đặt lương nhân viên',
            style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thêm/Cập nhật lương',
                    style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
                  ),
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
                      child: const Text(
                        'Lưu lương',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (staffSalaries.isNotEmpty) ...[
            Text(
              'Danh sách lương hiện tại:',
              style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
            ),
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
          Text(
            'Quản lý chấm công nhân viên',
            style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Date picker
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chọn ngày',
                    style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
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
                  Text(
                    'Chọn nhân viên',
                    style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
                  ),
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
                        child: Text(
                          '${staff['name']} (${_getShortRoleName(staff['role'])})',
                        ),
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
            Text(
              'Thông tin chấm công',
              style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.w500),
            ),
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
              ...attendanceRecords.map(
                (record) => Card(
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
                              record.status == 'approved'
                                  ? 'Đã duyệt'
                                  : record.status == 'rejected'
                                  ? 'Từ chối'
                                  : 'Chờ duyệt',
                            ),
                            backgroundColor: record.status == 'approved'
                                ? Colors.green
                                : record.status == 'rejected'
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
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
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
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
