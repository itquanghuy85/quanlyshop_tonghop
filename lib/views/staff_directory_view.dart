import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/utils/money_utils.dart' as money;
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/responsive_wrapper.dart';

class StaffDirectoryView extends StatefulWidget {
  const StaffDirectoryView({super.key});

  @override
  State<StaffDirectoryView> createState() => _StaffDirectoryViewState();
}

class _StaffDirectoryViewState extends State<StaffDirectoryView> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String _query = '';
  String _myUid = '';
  String _myRole = 'user';
  bool _isSuperAdmin = false;
  List<Map<String, dynamic>> _staff = [];

  bool get _canViewSensitive {
    if (_isSuperAdmin) return true;
    return _myRole == 'owner' || _myRole == 'manager' || _myRole == 'admin';
  }

  bool get _canViewFinancial {
    if (_isSuperAdmin) return true;
    return _myRole == 'owner' || _myRole == 'manager';
  }

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final role = await UserService.getRoleFast();
      final isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _myUid = user?.uid ?? '';
          _myRole = role;
          _isSuperAdmin = isSuperAdmin;
          _staff = [];
          _loading = false;
        });
        return;
      }

      final list = await FirestoreService.getStaffByShopId(shopId) ?? [];
      if (!mounted) return;
      setState(() {
        _myUid = user?.uid ?? '';
        _myRole = role;
        _isSuperAdmin = isSuperAdmin;
        _staff = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return _staff;
    final q = _query.trim().toLowerCase();
    return _staff.where((s) {
      final name = (s['name'] ?? s['displayName'] ?? '').toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      final role = (s['role'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q) || role.contains(q);
    }).toList();
  }

  String _roleVi(String role) {
    switch (role) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật';
      case 'employee':
        return 'Nhân viên';
      case 'admin':
        return 'Admin';
      default:
        return 'Người dùng';
    }
  }

  ImageProvider? _avatar(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http') || path.startsWith('blob:') || path.startsWith('data:')) {
      return CachedNetworkImageProvider(path);
    }
    if (kIsWeb) return null;
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _fmtCompact(int v) {
    return money.MoneyUtils.formatCompact(v);
  }

  String _fmtFull(int v) {
    return '${money.MoneyUtils.formatVND(v)} đ';
  }

  String _maskPhone(String raw) {
    final v = raw.trim();
    if (v.length < 7) return '***';
    return '${v.substring(0, 3)}****${v.substring(v.length - 3)}';
  }

  String _maskEmail(String raw) {
    final v = raw.trim();
    final at = v.indexOf('@');
    if (at <= 1) return '***';
    final name = v.substring(0, at);
    final domain = v.substring(at);
    final first = name.substring(0, 1);
    final last = name.length > 1 ? name.substring(name.length - 1) : '';
    return '$first***$last$domain';
  }

  String _maskAddress(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return 'Chưa cập nhật địa chỉ';
    if (v.length <= 10) return '***';
    return '${v.substring(0, 6)}...';
  }

  Widget _moneyRow(String label, int value, {IconData? icon}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(color: AppColors.secondary),
            ),
          ),
          Text(
            _fmtCompact(value),
            style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtFull(value),
            style: AppTextStyles.caption.copyWith(color: AppColors.secondary),
          ),
        ],
      ),
    );
  }

  void _openProfile(Map<String, dynamic> s) {
    final name = (s['name'] ?? s['displayName'] ?? 'Chưa có tên').toString();
    final role = _roleVi((s['role'] ?? 'user').toString());
    final phone = (s['phone'] ?? '').toString();
    final email = (s['email'] ?? '').toString();
    final address = (s['address'] ?? '').toString();
    final isMe = (s['uid'] ?? '') == _myUid;

    final baseSalary = _toInt(s['baseSalary']);
    final dailyRate = _toInt(s['dailyRate']);
    final showSensitive = _canViewSensitive || isMe;
    final showFinancial = _canViewFinancial || isMe;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundImage: _avatar(s['photoUrl']?.toString()),
                        child: s['photoUrl'] == null ? const Icon(Icons.person, size: 26) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: AppTextStyles.headline4.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              '$role${isMe ? ' • Bạn' : ''}',
                              style: AppTextStyles.caption.copyWith(color: AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _infoLine(
                    Icons.phone_outlined,
                    phone.isEmpty
                        ? 'Chưa cập nhật SĐT'
                        : (showSensitive ? phone : _maskPhone(phone)),
                  ),
                  _infoLine(
                    Icons.mail_outline,
                    email.isEmpty
                        ? 'Chưa cập nhật email'
                        : (showSensitive ? email : _maskEmail(email)),
                  ),
                  _infoLine(
                    Icons.home_outlined,
                    address.isEmpty
                        ? 'Chưa cập nhật địa chỉ'
                        : (showSensitive ? address : _maskAddress(address)),
                  ),
                  if (showFinancial && (baseSalary > 0 || dailyRate > 0)) ...[
                    const SizedBox(height: 12),
                    Text('Tài chính (chỉ xem)', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700)),
                    if (baseSalary > 0)
                      _moneyRow('Lương cơ bản', baseSalary, icon: Icons.account_balance_wallet_outlined),
                    if (dailyRate > 0)
                      _moneyRow('Lương theo ngày', dailyRate, icon: Icons.calendar_today_outlined),
                  ],
                  if (!showFinancial) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Thông tin lương được ẩn theo quyền hiện tại.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.secondary),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      showSensitive
                          ? 'Chế độ xem nội bộ: chỉ xem hồ sơ, không sửa đổi.'
                          : 'Chế độ xem nội bộ: chỉ xem và một số dữ liệu được ẩn theo quyền.',
                      style: AppTextStyles.caption.copyWith(color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTextStyles.body1)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      appBar: CustomAppBar.build(
        title: 'DANH BẠ NỘI BỘ',
        accentColor: AppBarAccents.staff,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới',
            onPressed: _loadStaff,
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Tìm theo tên, SĐT, email, vai trò',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'Tổng nhân sự: ${list.length}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Text(
                            'Chưa có dữ liệu nhân sự',
                            style: AppTextStyles.body1.copyWith(color: AppColors.secondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = list[i];
                            final name = (s['name'] ?? s['displayName'] ?? 'Chưa có tên').toString();
                            final role = _roleVi((s['role'] ?? 'user').toString());
                            final phone = (s['phone'] ?? '').toString();
                            final isMe = (s['uid'] ?? '') == _myUid;
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: ListTile(
                                onTap: () => _openProfile(s),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                leading: CircleAvatar(
                                  backgroundImage: _avatar(s['photoUrl']?.toString()),
                                  child: s['photoUrl'] == null ? const Icon(Icons.person) : null,
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (isMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F2FD),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text('Bạn', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '$role${phone.isNotEmpty ? ' • $phone' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                                trailing: const Icon(Icons.visibility_outlined, color: AppColors.primary),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
