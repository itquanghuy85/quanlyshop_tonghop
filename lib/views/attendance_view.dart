import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'work_schedule_settings_view.dart'; // Import màn hình cài đặt lịch
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});
  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> with TickerProviderStateMixin {
  final db = DBHelper();
  bool _loading = true;
  Attendance? _today;
  String _role = 'employee'; 
  late TabController _tabController;
  bool _hasPermission = false;

  Map<String, dynamic> _workSchedule = {};
  List<Attendance> _history = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    final r = await UserService.getUserRole(uid);
    int tabCount = (r == 'owner' || r == 'manager') ? 3 : 2;
    _tabController = TabController(length: tabCount, vsync: this);

    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() { 
      _role = r; 
      _hasPermission = perms['allowViewAttendance'] ?? false;
    });
    _refreshAttendanceData();
  }

  Future<void> _refreshAttendanceData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);
    final rec = await db.getAttendance(DateFormat('yyyy-MM-dd').format(DateTime.now()), uid);
    final schedule = await db.getWorkSchedule(uid);
    final history = await db.getAttendanceByUser(uid);

    if (!mounted) return;
    setState(() {
      _today = rec;
      _workSchedule = schedule ?? {};
      _history = history;
      _loading = false;
    });
  }

  Future<void> _actionCheck(bool isIn) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 30);
    if (picked == null) return;

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final cloudUrl = await StorageService.uploadAndGetUrl(picked.path, 'attendance');
      if (cloudUrl == null) {
        NotificationService.showSnackBar("Lỗi mạng! Không thể tải ảnh lên.", color: Colors.red);
        setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;
      
      bool isLate = false;
      bool isEarly = false;
      
      // Lấy lịch làm việc thực tế từ Database
      String startStr = _workSchedule['startTime'] ?? '08:00';
      String endStr = _workSchedule['endTime'] ?? '17:00';
      
      final startHour = int.tryParse(startStr.split(':')[0]) ?? 8;
      final startMinute = int.tryParse(startStr.split(':')[1]) ?? 0;
      final endHour = int.tryParse(endStr.split(':')[0]) ?? 17;
      final endMinute = int.tryParse(endStr.split(':')[1]) ?? 0;
      
      final startTime = DateTime(now.year, now.month, now.day, startHour, startMinute);
      final endTime = DateTime(now.year, now.month, now.day, endHour, endMinute);

      if (isIn && now.isAfter(startTime.add(const Duration(minutes: 15)))) isLate = true;
      if (!isIn && now.isBefore(endTime)) isEarly = true;

      final attendance = Attendance(
        userId: user.uid,
        email: user.email!,
        name: user.email?.split('@').first.toUpperCase() ?? 'NV',
        dateKey: DateFormat('yyyy-MM-dd').format(now),
        checkInAt: isIn ? timestamp : _today?.checkInAt,
        checkOutAt: isIn ? null : timestamp,
        photoIn: isIn ? cloudUrl : _today?.photoIn,
        photoOut: isIn ? null : cloudUrl,
        status: 'completed',
        isLate: isLate ? 1 : 0,
        isEarlyLeave: isEarly ? 1 : 0,
        createdAt: _today?.createdAt ?? timestamp,
        updatedAt: timestamp,
        firestoreId: "att_${DateFormat('yyyyMMdd').format(now)}_${user.uid}",
      );

      await db.upsertAttendance(attendance);
      await _refreshAttendanceData();

      // Send attendance notification
      try {
        await NotificationService.notifyStaffAttendance(
          attendance.name,
          isIn ? 'check-in' : 'check-out',
          now
        );
      } catch (e) {
        // Don't fail the attendance process if notification fails
        debugPrint('Attendance notification failed: $e');
      }

      NotificationService.showSnackBar(isIn ? "CHECK-IN THÀNH CÔNG!" : "CHECK-OUT THÀNH CÔNG!", color: Colors.green);
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("CHẤM CÔNG NHÂN VIÊN"),
        ),
        body: Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: AppTextStyles.body1.copyWith(color: AppColors.inactive),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal, Colors.teal.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("CHẤM CÔNG NHÂN VIÊN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text("Quản lý giờ làm việc", style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: "HÔM NAY"),
            const Tab(text: "LỊCH SỬ"),
            if (_role == 'owner' || _role == 'manager') const Tab(text: "THỐNG KÊ"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayTab(),
          _buildHistoryTab(),
          if (_role == 'owner' || _role == 'manager') _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildTodayTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        _buildClockCard(),
        const SizedBox(height: 30),
        Row(children: [
          Expanded(child: _checkBtn("CHECK-IN", Icons.login, AppColors.success, () => _actionCheck(true), enabled: _today?.checkInAt == null)),
          const SizedBox(width: 15),
          Expanded(child: _checkBtn("CHECK-OUT", Icons.logout, AppColors.error, () => _actionCheck(false), enabled: _today?.checkInAt != null && _today?.checkOutAt == null)),
        ]),
        const SizedBox(height: 30),
        if (_today != null) _buildTodaySummary(),
        if (_role == 'owner' || _role == 'manager') ...[
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
            leading: Icon(Icons.calendar_month, color: AppColors.primary),
            title: Text("Cấu hình lịch làm việc", style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text("Thiết lập giờ vào/ra cho thợ", style: AppTextStyles.caption),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkScheduleSettingsView())),
          )
        ],
      ]),
    );
  }

  Widget _buildClockCard() {
    final now = DateTime.now();
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]), borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15)]),
      child: Column(children: [
        Text(DateFormat('HH:mm').format(now), style: AppTextStyles.headline1.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w900)),
        Text(DateFormat('EEEE, dd MMMM', 'vi_VN').format(now).toUpperCase(), style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary.withOpacity(0.7), letterSpacing: 1.2)),
      ]),
    );
  }

  Widget _checkBtn(String label, IconData icon, Color color, VoidCallback onTap, {bool enabled = true}) {
    return ElevatedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(label, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: AppColors.onPrimary, disabledBackgroundColor: AppColors.inactive.withOpacity(0.3), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    );
  }

  Widget _buildTodaySummary() {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("TRẠNG THÁI HÔM NAY", style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: AppColors.onSurface.withOpacity(0.7))),
        const Divider(height: 30),
        _rowInfo("Giờ vào", _today?.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_today!.checkInAt!)) : "--:--", _today?.isLate == 1 ? AppColors.error : AppColors.success),
        _rowInfo("Giờ ra", _today?.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_today!.checkOutAt!)) : "--:--", _today?.isEarlyLeave == 1 ? AppColors.warning : AppColors.primary),
      ]),
    );
  }

  Widget _rowInfo(String l, String v, Color c) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.6))), Text(v, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold, color: c))]));

  Widget _buildHistoryTab() {
    if (_history.isEmpty) return const Center(child: Text("Chưa có dữ liệu lịch sử"));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (ctx, i) {
        final item = _history[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: item.isLate == 1 ? AppColors.error.withOpacity(0.1) : AppColors.success.withOpacity(0.1), child: Icon(item.isLate == 1 ? Icons.warning : Icons.check, color: item.isLate == 1 ? AppColors.error : AppColors.success, size: 16)),
            title: Text(item.dateKey, style: AppTextStyles.headline6),
            subtitle: Text("Vào: ${item.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.checkInAt!)) : '--'} | Ra: ${item.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.checkOutAt!)) : '--'}"),
            trailing: item.photoIn != null ? Icon(Icons.image, color: AppColors.primary, size: 18) : null,
          ),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    int totalDays = _history.length;
    int lateDays = _history.where((h) => h.isLate == 1).length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        _statCard("TỔNG NGÀY CÔNG", "$totalDays", AppColors.primary),
        const SizedBox(height: 15),
        _statCard("SỐ LẦN ĐI MUỘN", "$lateDays", AppColors.error),
      ]),
    );
  }

  Widget _statCard(String l, String v, Color c) => Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold, color: AppColors.onSurface.withOpacity(0.7))), Text(v, style: AppTextStyles.headline3.copyWith(fontWeight: FontWeight.w900, color: c))]));
}
