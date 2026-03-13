import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/leave_request_model.dart';
import '../services/attendance_approval_service.dart';
import '../services/encryption_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/osm_map_service.dart';
import 'work_schedule_settings_view.dart'; // Import màn hình cài đặt lịch
import '../widgets/app_cached_image.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../l10n/app_localizations.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';
import '../widgets/responsive_wrapper.dart';

class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});
  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView>
    with TickerProviderStateMixin {
  final db = DBHelper();
  bool _loading = true;
  Attendance? _today;
  String _role = 'employee';
  late TabController _tabController;
  Timer? _clockTimer;
  DateTime _clockNow = DateTime.now();
  String _userName = '';

  Map<String, dynamic> _workSchedule = {};
  List<Attendance> _history = [];
  List<LeaveRequest> _leaveRequests = [];

  // Shop location for attendance verification
  double? _shopLatitude;
  double? _shopLongitude;
  bool _locationRequired = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _clockNow = DateTime.now());
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final r = await UserService.getUserRole(uid);
    int tabCount = (r == 'owner' || r == 'manager') ? 3 : 2;
    _tabController = TabController(length: tabCount, vsync: this);

    // Load user display name
    final name = await UserService.getCurrentUserName();

    // Load shop location
    await _loadShopLocation();

    if (!mounted) return;
    setState(() {
      _role = r;
      _userName = name.isNotEmpty
          ? name
          : (FirebaseAuth.instance.currentUser?.email
                    ?.split('@')
                    .first
                    .toUpperCase() ??
                'NV');
    });
    _refreshAttendanceData();
  }

  Future<void> _loadShopLocation() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      if (shopDoc.exists) {
        final data = shopDoc.data()!;
        _shopLatitude = data['latitude']?.toDouble();
        _shopLongitude = data['longitude']?.toDouble();
        _locationRequired = _shopLatitude != null && _shopLongitude != null;
      }
    } catch (e) {
      debugPrint('Error loading shop location: $e');
    }
  }

  Future<void> _refreshAttendanceData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);
    final shopId = await UserService.getCurrentShopId();
    await _pullOwnCloudData(uid: uid, shopId: shopId);
    final rec = await db.getAttendance(
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      uid,
    );
    final schedule = await db.getWorkSchedule(uid);
    final history = await db.getAttendanceByUser(uid);
    final leaveRequests = await db.getLeaveRequestsByUser(uid);

    if (!mounted) return;
    setState(() {
      _today = rec;
      _workSchedule = schedule ?? {};
      _history = history;
      _leaveRequests = leaveRequests;
      _loading = false;
    });
  }

  Future<void> _pullOwnCloudData({
    required String uid,
    required String? shopId,
  }) async {
    if (shopId == null || shopId.isEmpty) return;

    try {
      final attendanceSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('shopId', isEqualTo: shopId)
          .where('userId', isEqualTo: uid)
          .get();

      for (final doc in attendanceSnap.docs) {
        final data = EncryptionService.decryptMap(doc.data());
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampField(data, 'checkInAt');
        _normalizeTimestampField(data, 'checkOutAt');
        _normalizeTimestampField(data, 'createdAt');
        _normalizeTimestampField(data, 'updatedAt');
        _normalizeTimestampField(data, 'approvedAt');
        await db.upsertAttendance(Attendance.fromMap(data));
      }

      final leaveSnap = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('shopId', isEqualTo: shopId)
          .where('userId', isEqualTo: uid)
          .get();

      for (final doc in leaveSnap.docs) {
        final data = EncryptionService.decryptMap(doc.data());
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampField(data, 'createdAt');
        _normalizeTimestampField(data, 'updatedAt');
        _normalizeTimestampField(data, 'approvedAt');
        await db.upsertLeaveRequest(LeaveRequest.fromMap(data));
      }
    } catch (e) {
      debugPrint('Error pulling personal attendance data: $e');
    }
  }

  void _normalizeTimestampField(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is Timestamp) {
      data[field] = value.millisecondsSinceEpoch;
    }
  }

  Future<void> _actionCheck(bool isIn) async {
    // Check location first if required
    if (_locationRequired) {
      final locationOk = await _verifyLocation();
      if (!locationOk) return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 30,
    );
    if (picked == null) {
      NotificationService.showSnackBar(
        "Bắt buộc chụp ảnh để chấm công!",
        color: Colors.orange,
      );
      return;
    }

    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final cloudUrl = await StorageService.uploadXFileAndGetUrl(
        picked,
        'attendance',
      );
      if (cloudUrl == null) {
        NotificationService.showSnackBar(
          "Lỗi mạng! Không thể tải ảnh lên.",
          color: Colors.red,
        );
        setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch;

      // Get current location for record
      String? locationStr;
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        locationStr = '${position.latitude},${position.longitude}';
      } catch (_) {}

      bool isLate = false;
      bool isEarly = false;

      // Lấy lịch làm việc thực tế từ Database
      String startStr = _workSchedule['startTime'] ?? '08:00';
      String endStr = _workSchedule['endTime'] ?? '17:00';

      final startHour = int.tryParse(startStr.split(':')[0]) ?? 8;
      final startMinute = int.tryParse(startStr.split(':')[1]) ?? 0;
      final endHour = int.tryParse(endStr.split(':')[0]) ?? 17;
      final endMinute = int.tryParse(endStr.split(':')[1]) ?? 0;

      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        startHour,
        startMinute,
      );
      final endTime = DateTime(
        now.year,
        now.month,
        now.day,
        endHour,
        endMinute,
      );

      if (isIn && now.isAfter(startTime.add(const Duration(minutes: 15)))) {
        isLate = true;
      }
      if (!isIn && now.isBefore(endTime)) {
        isEarly = true;
      }

      final firestoreId =
          "att_${DateFormat('yyyyMMdd').format(now)}_${user.uid}";
      final shopId = await UserService.getCurrentShopId();

      final attendance = Attendance(
        userId: user.uid,
        email: user.email!,
        name: _userName,
        dateKey: DateFormat('yyyy-MM-dd').format(now),
        checkInAt: isIn ? timestamp : _today?.checkInAt,
        checkOutAt: isIn ? null : timestamp,
        photoIn: isIn ? cloudUrl : _today?.photoIn,
        photoOut: isIn ? null : cloudUrl,
        status: 'pending',
        isLate: isLate ? 1 : 0,
        isEarlyLeave: isEarly ? 1 : 0,
        location: locationStr ?? _today?.location,
        createdAt: _today?.createdAt ?? timestamp,
        updatedAt: timestamp,
        firestoreId: firestoreId,
      );

      await db.upsertAttendance(attendance);

      // Sync to Firestore
      await _syncAttendanceToCloud(attendance, shopId);

      await _refreshAttendanceData();

      // Send attendance notification
      try {
        await NotificationService.notifyStaffAttendance(
          attendance.name,
          isIn ? 'check-in' : 'check-out',
          now,
        );
      } catch (e) {
        // Don't fail the attendance process if notification fails
        debugPrint('Attendance notification failed: $e');
      }

      NotificationService.showSnackBar(
        isIn ? "Chấm công vào thành công!" : "Chấm công ra thành công!",
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _verifyLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          NotificationService.showSnackBar(
            'Cần quyền truy cập vị trí để chấm công',
            color: Colors.red,
          );
          return false;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        NotificationService.showSnackBar(
          'Vui lòng bật quyền vị trí trong cài đặt',
          color: Colors.red,
        );
        return false;
      }

      NotificationService.showSnackBar(
        'Đang kiểm tra vị trí...',
        color: Colors.blue,
      );

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Calculate distance to shop
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _shopLatitude!,
        _shopLongitude!,
      );

      if (distanceInMeters > 100) {
        // 100 meters radius
        NotificationService.showSnackBar(
          'Bạn đang ở cách shop ${distanceInMeters.toInt()}m. Cần ở trong phạm vi 100m để chấm công.',
          color: Colors.red,
        );
        return false;
      }

      return true;
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi kiểm tra vị trí: $e',
        color: Colors.red,
      );
      return false;
    }
  }

  Future<void> _syncAttendanceToCloud(
    Attendance attendance,
    String? shopId,
  ) async {
    if (shopId == null) return;

    try {
      final data = attendance.toMap();
      data['shopId'] = shopId;
      data['syncedAt'] = FieldValue.serverTimestamp();
      data.remove('id');
      data.remove('isSynced');

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(attendance.firestoreId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing attendance to cloud: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: AppLocalizations.of(context)?.attendance ?? "CHẤM CÔNG",
        subtitle:
            AppLocalizations.of(context)?.personalAttendanceDescription ??
            "Check-in/out và xem lịch sử chấm công cá nhân",
        actions: [
          if (_role == 'owner' || _role == 'manager')
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Xuất Excel chấm công',
              onPressed: () async {
                final result = await ExportDateFilterDialog.show(
                  context,
                  title: 'Xuất chấm công',
                );
                if (result == null) return;
                if (!context.mounted) return;
                await ExcelExportHelper.exportAttendance(
                  context,
                  startMs: result['startMs'],
                  endMs: result['endMs'],
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: AppLocalizations.of(context)?.today ?? "HÔM NAY"),
            Tab(text: AppLocalizations.of(context)?.history ?? "LỊCH SỪ"),
            if (_role == 'owner' || _role == 'manager')
              Tab(text: AppLocalizations.of(context)?.stats ?? "THỐNG KÊ"),
          ],
        ),
      ),
      body: ResponsiveCenter(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildTodayTab(),
            _buildHistoryTab(),
            if (_role == 'owner' || _role == 'manager') _buildStatsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildClockCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _checkBtn(
                  "CHECK-IN",
                  Icons.login,
                  AppColors.success,
                  () => _actionCheck(true),
                  enabled: _today?.checkInAt == null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _checkBtn(
                  "CHECK-OUT",
                  Icons.logout,
                  AppColors.error,
                  () => _actionCheck(false),
                  enabled:
                      _today?.checkInAt != null && _today?.checkOutAt == null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_today != null) _buildTodaySummary(),
          const SizedBox(height: 12),
          _buildRequestActionsCard(),
          const SizedBox(height: 12),
          _buildMyLeaveRequestsCard(),
          if (_role == 'owner' || _role == 'manager') ...[
            const SizedBox(height: 10),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.calendar_month,
                color: AppColors.primary,
              ),
              title: Text(
                "Cấu hình lịch làm việc",
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Thiết lập giờ vào/ra cho thợ",
                style: AppTextStyles.caption,
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WorkScheduleSettingsView(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClockCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Text(
            DateFormat('HH:mm:ss').format(_clockNow),
            style: AppTextStyles.headline1.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 40,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat(
              'EEEE, dd MMMM yyyy',
              'vi_VN',
            ).format(_clockNow).toUpperCase(),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.onPrimary.withOpacity(0.7),
              letterSpacing: 1.2,
            ),
          ),
          if (_userName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _userName,
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onPrimary.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _checkBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.inactive.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: enabled ? 3 : 0,
        ),
      ),
    );
  }

  Widget _buildTodaySummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TRẠNG THÁI HÔM NAY",
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
          const Divider(height: 16),
          _rowInfo(
            "Giờ vào",
            _today?.checkInAt != null
                ? DateFormat('HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(_today!.checkInAt!),
                  )
                : "--:--",
            _today?.isLate == 1 ? AppColors.error : AppColors.success,
          ),
          _rowInfo(
            "Giờ ra",
            _today?.checkOutAt != null
                ? DateFormat('HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(_today!.checkOutAt!),
                  )
                : "--:--",
            _today?.isEarlyLeave == 1 ? AppColors.warning : AppColors.primary,
          ),
          if (_today?.checkInAt != null && _today?.checkOutAt != null)
            _rowInfo(
              "Số giờ làm",
              _formatWorkHours(_today!.checkInAt!, _today!.checkOutAt!),
              AppColors.primary,
            ),
        ],
      ),
    );
  }

  Widget _rowInfo(String l, String v, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            v,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.bold,
              color: c,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(child: Text("Chưa có dữ liệu lịch sử"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (ctx, i) {
        final item = _history[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _showAttendanceDetail(item),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: item.isLate == 1
                        ? AppColors.error.withOpacity(0.1)
                        : AppColors.success.withOpacity(0.1),
                    child: Icon(
                      item.isLate == 1 ? Icons.warning : Icons.check,
                      color: item.isLate == 1
                          ? AppColors.error
                          : AppColors.success,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.dateKey, style: AppTextStyles.headline6),
                        Text(
                          "Vào: ${item.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.checkInAt!)) : '--'} | Ra: ${item.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.checkOutAt!)) : '--'}",
                          style: TextStyle(
                            fontSize: AppTextStyles.subtitle1.fontSize,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.photoIn != null || item.photoOut != null)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.photo_library,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestActionsCard() {
    final loc = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YÊU CẦU CÁ NHÂN',
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gửi yêu cầu quên chấm công hoặc xin nghỉ mà không cần vào màn quản lý.',
            style: AppTextStyles.body2.copyWith(
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showForgotCheckinRequestDialog,
                  icon: const Icon(Icons.add_alarm),
                  label: Text(loc.forgotCheckin),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showCreateLeaveRequestDialog,
                  icon: const Icon(Icons.event_busy),
                  label: Text(loc.leaveRequests),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyLeaveRequestsCard() {
    final loc = AppLocalizations.of(context)!;
    final items = _leaveRequests.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ĐƠN CỦA TÔI',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface.withOpacity(0.7),
                ),
              ),
              const Spacer(),
              Text(
                '${_leaveRequests.length} đơn',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.inactive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              loc.noLeaveRequests,
              style: AppTextStyles.body2.copyWith(color: AppColors.inactive),
            )
          else
            ...items.map(_buildLeaveRequestItem),
        ],
      ),
    );
  }

  Widget _buildLeaveRequestItem(LeaveRequest request) {
    final statusColor = switch (request.status) {
      'approved' => AppColors.success,
      'rejected' => AppColors.error,
      _ => AppColors.warning,
    };
    final statusLabel = switch (request.status) {
      'approved' => 'Đã duyệt',
      'rejected' => 'Từ chối',
      _ => 'Chờ duyệt',
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  LeaveRequest.leaveTypeDisplayVi(request.leaveType),
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                statusLabel,
                style: AppTextStyles.caption.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${request.startDate} -> ${request.endDate}',
            style: AppTextStyles.body2.copyWith(color: AppColors.inactive),
          ),
          if ((request.reason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Lý do: ${request.reason}',
                style: AppTextStyles.caption,
              ),
            ),
          if ((request.rejectReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Từ chối: ${request.rejectReason}',
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ),
        ],
      ),
    );
  }

  void _showForgotCheckinRequestDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DateTime selectedDate = DateTime.now();
    TimeOfDay? checkInTime;
    TimeOfDay? checkOutTime;
    String note = '';
    final displayName = _userName.isNotEmpty
        ? _userName
        : (user.email?.split('@').first.toUpperCase() ?? 'NV');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.add_alarm, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.forgotCheckinRequest,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayName,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setDlg(() => selectedDate = d);
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Giờ vào: ${checkInTime?.format(ctx) ?? '--:--'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.access_time, size: 18),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (t != null) setDlg(() => checkInTime = t);
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Giờ ra: ${checkOutTime?.format(ctx) ?? '--:--'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.access_time, size: 18),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: const TimeOfDay(hour: 17, minute: 0),
                      );
                      if (t != null) setDlg(() => checkOutTime = t);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => note = v,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (checkInTime == null) {
                    NotificationService.showSnackBar(
                      'Chọn giờ vào',
                      color: Colors.red,
                    );
                    return;
                  }
                  final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
                  final inMs = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    checkInTime!.hour,
                    checkInTime!.minute,
                  ).millisecondsSinceEpoch;
                  final outMs = checkOutTime != null
                      ? DateTime(
                          selectedDate.year,
                          selectedDate.month,
                          selectedDate.day,
                          checkOutTime!.hour,
                          checkOutTime!.minute,
                        ).millisecondsSinceEpoch
                      : null;
                  Navigator.pop(ctx);
                  final ok =
                      await AttendanceApprovalService.createForgotCheckinRequest(
                        userId: user.uid,
                        email: user.email ?? '',
                        name: displayName,
                        dateKey: dateKey,
                        checkInAt: inMs,
                        checkOutAt: outMs,
                        note: note.isNotEmpty ? note : null,
                      );
                  if (ok) {
                    NotificationService.showSnackBar(
                      'Đã gửi yêu cầu bổ sung chấm công',
                      color: AppColors.success,
                    );
                    await _refreshAttendanceData();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Gửi yêu cầu'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateLeaveRequestDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String leaveType = 'annual';
    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    DateTime endDate = DateTime.now().add(const Duration(days: 1));
    String reason = '';
    final displayName = _userName.isNotEmpty
        ? _userName
        : (user.email?.split('@').first.toUpperCase() ?? 'NV');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final days = endDate.difference(startDate).inDays + 1;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.event_busy, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.createLeaveRequest,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayName,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: leaveType,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.leaveType,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: ['annual', 'sick', 'unpaid', 'personal', 'maternity']
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              LeaveRequest.leaveTypeDisplayVi(t),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDlg(() => leaveType = v ?? 'annual'),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${AppLocalizations.of(context)!.startDate}: ${DateFormat('dd/MM/yyyy').format(startDate)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: startDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setDlg(() {
                          startDate = d;
                          if (endDate.isBefore(startDate)) endDate = startDate;
                        });
                      }
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${AppLocalizations.of(context)!.endDate}: ${DateFormat('dd/MM/yyyy').format(endDate)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: startDate.add(const Duration(days: 90)),
                      );
                      if (d != null) setDlg(() => endDate = d);
                    },
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${AppLocalizations.of(context)!.totalDays}: $days ngày',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.leaveReason,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => reason = v,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final request = LeaveRequest(
                    userId: user.uid,
                    email: user.email ?? '',
                    name: displayName,
                    leaveType: leaveType,
                    startDate: DateFormat('yyyy-MM-dd').format(startDate),
                    endDate: DateFormat('yyyy-MM-dd').format(endDate),
                    totalDays: days.toDouble(),
                    reason: reason.isNotEmpty ? reason : null,
                    status: 'pending',
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                    isSynced: false,
                  );
                  Navigator.pop(ctx);
                  final ok = await AttendanceApprovalService.createLeaveRequest(
                    request,
                  );
                  if (ok) {
                    NotificationService.showSnackBar(
                      'Đã gửi đơn xin nghỉ',
                      color: AppColors.success,
                    );
                    await _refreshAttendanceData();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(AppLocalizations.of(context)!.createLeaveRequest),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAttendanceDetail(Attendance item) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_note, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHI TIẾT CHẤM CÔNG',
                        style: AppTextStyles.headline6.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.dateKey,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 24),

            // Info rows
            _detailRow('Nhân viên', item.name, Icons.person),
            _detailRow(
              'Trạng thái',
              item.isLate == 1 ? 'Đi muộn' : 'Đúng giờ',
              Icons.timer,
              valueColor: item.isLate == 1
                  ? AppColors.error
                  : AppColors.success,
            ),
            _detailRow(
              'Giờ vào',
              item.checkInAt != null
                  ? DateFormat('HH:mm:ss - dd/MM/yyyy').format(
                      DateTime.fromMillisecondsSinceEpoch(item.checkInAt!),
                    )
                  : 'Chưa check-in',
              Icons.login,
            ),
            _detailRow(
              'Giờ ra',
              item.checkOutAt != null
                  ? DateFormat('HH:mm:ss - dd/MM/yyyy').format(
                      DateTime.fromMillisecondsSinceEpoch(item.checkOutAt!),
                    )
                  : 'Chưa check-out',
              Icons.logout,
            ),
            if (item.location != null)
              _detailRow('Vị trí', item.location!, Icons.location_on),

            if (item.location != null &&
                OsmMapService.parseLatLng(item.location) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p = OsmMapService.parseLatLng(item.location);
                        if (p == null) return;
                        await OsmMapService.openPoint(p[0], p[1]);
                      },
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('Xem OSM'),
                    ),
                    if (_shopLatitude != null && _shopLongitude != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final p = OsmMapService.parseLatLng(item.location);
                          if (p == null) return;
                          await OsmMapService.openDirections(
                            fromLat: p[0],
                            fromLon: p[1],
                            toLat: _shopLatitude!,
                            toLon: _shopLongitude!,
                          );
                        },
                        icon: const Icon(Icons.alt_route, size: 18),
                        label: const Text('Đi tới shop'),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Photos section
            if (item.photoIn != null || item.photoOut != null) ...[
              Text(
                'ẢNH CHẤM CÔNG',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline5.fontSize,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (item.photoIn != null)
                    Expanded(
                      child: _photoCard(
                        'Check-in',
                        item.photoIn!,
                        item.checkInAt,
                      ),
                    ),
                  if (item.photoIn != null && item.photoOut != null)
                    const SizedBox(width: 12),
                  if (item.photoOut != null)
                    Expanded(
                      child: _photoCard(
                        'Check-out',
                        item.photoOut!,
                        item.checkOutAt,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(
              color: Colors.grey,
              fontSize: AppTextStyles.headline5.fontSize,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: AppTextStyles.headline5.fontSize,
                color: valueColor,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoCard(String label, String url, int? time) {
    return GestureDetector(
      onTap: () => _showFullImage(url, label),
      child: Column(
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: AppCachedImage(
              imageUrl: url,
              fit: BoxFit.cover,
              width: double.infinity,
              memCacheHeight: 240,
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (time != null)
            Text(
              DateFormat(
                'HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(time)),
              style: TextStyle(
                fontSize: AppTextStyles.caption.fontSize,
                color: Colors.grey,
              ),
            ),
        ],
      ),
    );
  }

  void _showFullImage(String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            AppCachedImage(imageUrl: url, fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    int totalDays = _history.length;
    int lateDays = _history.where((h) => h.isLate == 1).length;
    int earlyDays = _history.where((h) => h.isEarlyLeave == 1).length;
    int onTimeDays = _history
        .where((h) => h.isLate == 0 && h.isEarlyLeave == 0)
        .length;
    double onTimeRate = totalDays > 0 ? (onTimeDays / totalDays * 100) : 0;
    int totalMinutes = 0;
    for (final h in _history) {
      if (h.checkInAt != null && h.checkOutAt != null) {
        totalMinutes += ((h.checkOutAt! - h.checkInAt!) / 60000).round();
      }
    }
    int avgMinutes = totalDays > 0 ? (totalMinutes / totalDays).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Summary grid
          Row(
            children: [
              Expanded(
                child: _statCard(
                  "Tổng ngày công",
                  "$totalDays",
                  AppColors.primary,
                  Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  "Đúng giờ",
                  "$onTimeDays",
                  AppColors.success,
                  Icons.check_circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  "Đi muộn",
                  "$lateDays",
                  AppColors.error,
                  Icons.access_time_filled,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  "Về sớm",
                  "$earlyDays",
                  AppColors.warning,
                  Icons.directions_run,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  "Tỷ lệ đúng giờ",
                  "${onTimeRate.toStringAsFixed(0)}%",
                  Colors.teal,
                  Icons.trending_up,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  "TB giờ/ngày",
                  _formatMinutes(avgMinutes),
                  Colors.indigo,
                  Icons.hourglass_bottom,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _statCard(
            "Tổng giờ làm việc",
            _formatMinutes(totalMinutes),
            Colors.deepPurple,
            Icons.work_history,
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h${m > 0 ? ' ${m}p' : ''}';
  }

  String _formatWorkHours(int checkInMs, int checkOutMs) {
    final minutes = ((checkOutMs - checkInMs) / 60000).round();
    return _formatMinutes(minutes);
  }

  Widget _statCard(String l, String v, Color c, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: c.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        Text(
          v,
          style: AppTextStyles.headline4.copyWith(
            fontWeight: FontWeight.w900,
            color: c,
          ),
        ),
      ],
    ),
  );
}
