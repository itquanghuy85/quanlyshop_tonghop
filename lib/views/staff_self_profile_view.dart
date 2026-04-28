import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/db_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/attendance_model.dart';
import '../services/event_bus.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/responsive_wrapper.dart';

class StaffSelfProfileView extends StatefulWidget {
  const StaffSelfProfileView({super.key});

  @override
  State<StaffSelfProfileView> createState() => _StaffSelfProfileViewState();
}

class _StaffSelfProfileViewState extends State<StaffSelfProfileView> {
  final _db = DBHelper();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String _uid = '';
  String _shopId = '';
  String _role = 'employee';
  String _email = '';
  String _avatarUrl = '';
  String _coverUrl = '';
  double _coverAlignX = 0;
  double _coverAlignY = 0;
  String _shopName = '';

  int _salesCount = 0;
  int _repairsCount = 0;
  String _scheduleText = 'Chưa cài lịch';
  int _attendanceCount = 0;
  int _lateCount = 0;
  List<Attendance> _recentAttendance = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      _uid = user.uid;
      _email = user.email ?? '';

      final userInfo = await UserService.getUserInfo(_uid);
      _nameCtrl.text = ((userInfo['displayName'] ?? userInfo['name'] ?? '').toString().trim());
      _phoneCtrl.text = (userInfo['phone'] ?? '').toString().trim();
      _addressCtrl.text = (userInfo['address'] ?? '').toString().trim();
      _role = (userInfo['role'] ?? 'employee').toString();
      _avatarUrl = (userInfo['photoUrl'] ?? '').toString().trim();
      _coverUrl = (userInfo['coverUrl'] ?? '').toString().trim();
      _coverAlignX = (userInfo['coverAlignX'] as num?)?.toDouble() ?? 0;
      _coverAlignY = (userInfo['coverAlignY'] as num?)?.toDouble() ?? 0;

      final shopId = await UserService.getCurrentShopId();
      _shopId = (shopId ?? '').trim();
      if (_shopId.isNotEmpty) {
        final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(_shopId).get();
        if (shopDoc.exists) {
          final data = shopDoc.data() ?? const <String, dynamic>{};
          _shopName = (data['name'] ?? '').toString().trim();
        }
      }

      try {
        _role = await UserService.getUserRole(_uid);
      } catch (_) {}

      await _loadStatsAndSchedule();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải hồ sơ nhân viên: $e', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadStatsAndSchedule() async {
    final emailPrefix = _email.split('@').first.toUpperCase();
    final displayName = _nameCtrl.text.trim().toUpperCase();

    bool matchesStaff(String? value) {
      if (value == null || value.isEmpty) return false;
      final v = value.toUpperCase();
      return v == emailPrefix || v == displayName || v.contains(emailPrefix);
    }

    final repairs = await _db.getAllRepairs();
    final sales = await _db.getAllSales();

    _repairsCount = repairs.where((r) {
      if (matchesStaff(r.repairedBy)) return true;
      if ((r.repairedBy == null || r.repairedBy!.isEmpty) && r.status >= 3 && matchesStaff(r.createdBy)) {
        return true;
      }
      return false;
    }).length;

    _salesCount = sales.where((s) => matchesStaff(s.sellerName)).length;

    if (_shopId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance.collection('work_schedules').doc('staff_${_uid}_$_shopId').get();
      Map<String, dynamic>? schedule;
      if (doc.exists) {
        schedule = doc.data();
        await _db.upsertWorkSchedule(_uid, schedule!);
      }
      schedule ??= await _db.getWorkSchedule(_uid);
      if (schedule != null) {
        final start = (schedule['startTime'] ?? '08:00').toString();
        final end = (schedule['endTime'] ?? '17:00').toString();
        final breakTime = schedule['breakTime'] ?? 1;
        final ot = schedule['maxOtHours'] ?? 4;
        _scheduleText = '$start - $end | Nghỉ: ${breakTime}h | OT: ${ot}h';
      }
    }

    final attendance = await _db.getAttendanceByUser(_uid, limit: 30);
    _recentAttendance = attendance;
    _attendanceCount = attendance.length;
    _lateCount = attendance.where((a) => a.isLate == 1).length;
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1200);
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      final uploadedUrl = await StorageService.uploadXFileAndGetUrl(picked, 'user_photos/$_uid');
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        NotificationService.showSnackBar('Không thể tải ảnh đại diện', color: Colors.red);
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'photoUrl': uploadedUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _avatarUrl = uploadedUrl);
      EventBus().emit('user_profile_changed');
      NotificationService.showSnackBar('Đã cập nhật ảnh đại diện', color: Colors.green);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCover() async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1800);
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      final uploadedUrl = await StorageService.uploadXFileAndGetUrl(
        picked,
        'user_photos/$_uid',
      );
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        NotificationService.showSnackBar('Không thể tải ảnh bìa', color: Colors.red);
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'coverUrl': uploadedUrl,
        'coverAlignX': 0,
        'coverAlignY': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _coverUrl = uploadedUrl;
        _coverAlignX = 0;
        _coverAlignY = 0;
      });
      EventBus().emit('user_profile_changed');
      NotificationService.showSnackBar('Đã cập nhật ảnh bìa', color: Colors.green);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveInfo() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await UserService.updateUserInfo(
        uid: _uid,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        role: null,
        loc: AppLocalizations.of(context)!,
        photoUrl: _avatarUrl,
      );
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'coverUrl': _coverUrl,
        'coverAlignX': _coverAlignX,
        'coverAlignY': _coverAlignY,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      EventBus().emit('user_profile_changed');
      if (!mounted) return;
      NotificationService.showSnackBar('Đã lưu hồ sơ nhân viên', color: Colors.green);
      await _loadStatsAndSchedule();
      setState(() {});
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lưu hồ sơ: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCoverAlignment() async {
    if (_uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'coverAlignX': _coverAlignX,
      'coverAlignY': _coverAlignY,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _onCoverPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
    setState(() {
      _coverAlignX = (_coverAlignX + (details.delta.dx / (width / 2))).clamp(-1.0, 1.0);
      _coverAlignY = (_coverAlignY + (details.delta.dy / (height / 2))).clamp(-1.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final coverImage = _coverUrl.isNotEmpty
      ? DecorationImage(
        image: NetworkImage(_coverUrl),
        fit: BoxFit.cover,
        alignment: Alignment(_coverAlignX, _coverAlignY),
        )
      : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hồ sơ nhân viên'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A56C2), Color(0xFF0E74DB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTap: _pickCover,
                    onPanUpdate: _coverUrl.trim().isNotEmpty
                        ? (details) => _onCoverPanUpdate(details, constraints)
                        : null,
                    onPanEnd: _coverUrl.trim().isNotEmpty
                        ? (_) => _saveCoverAlignment()
                        : null,
                    child: Container(
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade200,
                        image: coverImage,
                      ),
                      child: Stack(
                        children: [
                        if (coverImage != null)
                          Positioned.fill(
                            child: ClipRRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 1.8, sigmaY: 1.8),
                                child: Container(
                                  color: Colors.black.withOpacity(0.22),
                                ),
                              ),
                            ),
                          ),
                        if (coverImage == null)
                          Center(
                            child: Text(
                              'Thêm ảnh bìa',
                              style: AppTextStyles.body1.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Row(
                              children: [
                              if (_coverUrl.trim().isNotEmpty)
                                IconButton(
                                  tooltip: 'Xem ảnh lớn',
                                  onPressed: () => EntityAvatar.showPreview(
                                    context,
                                    _coverUrl,
                                    _nameCtrl.text,
                                  ),
                                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                                ),
                              if (_coverUrl.trim().isNotEmpty)
                                IconButton(
                                  tooltip: 'Căn giữa ảnh bìa',
                                  onPressed: () async {
                                    setState(() {
                                      _coverAlignX = 0;
                                      _coverAlignY = 0;
                                    });
                                    await _saveCoverAlignment();
                                  },
                                  icon: const Icon(Icons.filter_center_focus, color: Colors.white),
                                ),
                              IconButton(
                                tooltip: 'Đổi ảnh bìa',
                                onPressed: _pickCover,
                                icon: const Icon(Icons.camera_alt, color: Colors.white),
                              ),
                              ],
                            ),
                          ),
                          if (_coverUrl.trim().isNotEmpty)
                            Positioned(
                              left: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Kéo ảnh bìa để chọn vùng hiển thị',
                                  style: AppTextStyles.caption.copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  bottom: -32,
                  child: EntityAvatar(
                    imageUrl: _avatarUrl,
                    name: _nameCtrl.text.trim().isEmpty ? _email : _nameCtrl.text.trim(),
                    radius: 46,
                    showEditButton: true,
                    onEditTap: _pickAvatar,
                    heroTag: 'hero_staff_avatar_$_uid',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 42),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _nameCtrl.text.trim().isEmpty ? _email : _nameCtrl.text.trim(),
                style: AppTextStyles.headline2.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (_shopName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '${_roleLabel(_role)} thuộc shop ${_shopName.trim()}',
                  style: AppTextStyles.subtitle1.copyWith(color: Colors.grey.shade700),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(child: _statCard('Đơn bán', _salesCount.toString(), Icons.point_of_sale)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Đơn sửa', _repairsCount.toString(), Icons.build_circle_outlined)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Ngày công', _attendanceCount.toString(), Icons.event_available)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin cá nhân', style: AppTextStyles.headline6),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.location_on)),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveInfo,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'ĐANG LƯU...' : 'LƯU HỒ SƠ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B66D1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Chấm công cá nhân', style: AppTextStyles.headline6),
                        const Spacer(),
                        Text('Đi muộn: $_lateCount', style: AppTextStyles.caption.copyWith(color: Colors.orange.shade700)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_recentAttendance.isEmpty)
                      Text('Chưa có dữ liệu chấm công', style: AppTextStyles.caption)
                    else
                      ..._recentAttendance.take(8).map((a) {
                        final checkIn = a.checkInAt != null
                            ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkInAt!))
                            : '--:--';
                        final checkOut = a.checkOutAt != null
                            ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkOutAt!))
                            : '--:--';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: a.isLate == 1 ? Colors.orange.shade100 : Colors.green.shade100,
                            child: Icon(
                              a.isLate == 1 ? Icons.warning_amber_rounded : Icons.check,
                              size: 14,
                              color: a.isLate == 1 ? Colors.orange.shade700 : Colors.green.shade700,
                            ),
                          ),
                          title: Text(a.dateKey, style: AppTextStyles.body1),
                          subtitle: Text('Vào: $checkIn • Ra: $checkOut', style: AppTextStyles.caption),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0B66D1), size: 18),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
      case 'admin':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật viên';
      default:
        return 'Nhân viên';
    }
  }
}
