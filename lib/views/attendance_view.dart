import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'work_schedule_settings_view.dart'; // Import màn hình cài đặt lịch
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../l10n/app_localizations.dart';

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
  bool _hasPermission = false;

  Map<String, dynamic> _workSchedule = {};
  List<Attendance> _history = [];

  // Shop location for attendance verification
  double? _shopLatitude;
  double? _shopLongitude;
  bool _locationRequired = false;

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

    // Load shop location
    await _loadShopLocation();

    if (!mounted) return;
    setState(() {
      _role = r;
      _hasPermission = perms['allowViewAttendance'] ?? false;
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
    final rec = await db.getAttendance(
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      uid,
    );
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

      final cloudUrl = await StorageService.uploadAndGetUrl(
        picked.path,
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

      if (isIn && now.isAfter(startTime.add(const Duration(minutes: 15))))
        isLate = true;
      if (!isIn && now.isBefore(endTime)) isEarly = true;

      final firestoreId =
          "att_${DateFormat('yyyyMMdd').format(now)}_${user.uid}";
      final shopId = await UserService.getCurrentShopId();

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
        isIn ? "CHECK-IN THÀNH CÔNG!" : "CHECK-OUT THÀNH CÔNG!",
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
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (!_hasPermission) {
      return Scaffold(
        appBar: CustomAppBar.build(
          title: AppLocalizations.of(context)?.attendance ?? "ATTENDANCE",
        ),
        body: Center(
          child: Text(
            AppLocalizations.of(context)?.noAccessPermission ??
                "You don't have access to this feature",
            style: AppTextStyles.body1.copyWith(color: AppColors.inactive),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: AppLocalizations.of(context)?.attendance ?? "ATTENDANCE",
        subtitle: AppLocalizations.of(context)?.attendanceManagement ?? "Manage work hours",
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: AppLocalizations.of(context)?.today ?? "TODAY"),
            Tab(text: AppLocalizations.of(context)?.history ?? "HISTORY"),
            if (_role == 'owner' || _role == 'manager')
              Tab(text: AppLocalizations.of(context)?.stats ?? "STATS"),
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
    final now = DateTime.now();
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
            DateFormat('HH:mm').format(now),
            style: AppTextStyles.headline1.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            DateFormat('EEEE, dd MMMM', 'vi_VN').format(now).toUpperCase(),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.onPrimary.withOpacity(0.7),
              letterSpacing: 1.2,
            ),
          ),
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
    return ElevatedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.inactive.withOpacity(0.3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            "TODAY'S STATUS / TRẠNG THÁI HÔM NAY",
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
          const Divider(height: 16),
          _rowInfo(
            "Check-in / Giờ vào",
            _today?.checkInAt != null
                ? DateFormat('HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(_today!.checkInAt!),
                  )
                : "--:--",
            _today?.isLate == 1 ? AppColors.error : AppColors.success,
          ),
          _rowInfo(
            "Check-out / Giờ ra",
            _today?.checkOutAt != null
                ? DateFormat('HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(_today!.checkOutAt!),
                  )
                : "--:--",
            _today?.isEarlyLeave == 1 ? AppColors.warning : AppColors.primary,
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
    if (_history.isEmpty)
      return const Center(child: Text("Chưa có dữ liệu lịch sử"));
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

  void _showAttendanceDetail(Attendance item) {
    showModalBottomSheet(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (ctx, e, s) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
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
            Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    int totalDays = _history.length;
    int lateDays = _history.where((h) => h.isLate == 1).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _statCard(
            "TOTAL DAYS / TỔNG NGÀY CÔNG",
            "$totalDays",
            AppColors.primary,
          ),
          const SizedBox(height: 8),
          _statCard(
            "LATE COUNT / SỐ LẦN ĐI MUỘN",
            "$lateDays",
            AppColors.error,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String l, String v, Color c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            l,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            v,
            style: AppTextStyles.headline3.copyWith(
              fontWeight: FontWeight.w900,
              color: c,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
