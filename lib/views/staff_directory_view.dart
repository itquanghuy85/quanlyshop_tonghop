import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'staff_public_profile_view.dart';
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
  List<Map<String, dynamic>> _staff = [];

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
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _myUid = user?.uid ?? '';
          _staff = [];
          _loading = false;
        });
        return;
      }

      final list = await FirestoreService.getStaffByShopId(shopId) ?? [];
      if (!mounted) return;
      setState(() {
        _myUid = user?.uid ?? '';
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


  void _openProfile(Map<String, dynamic> s) {
    final uid = (s['uid'] ?? '').toString().trim();
    if (uid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffPublicProfileView(
          userId: uid,
          fallbackName: (s['name'] ?? s['displayName'] ?? 'Nhân viên').toString(),
        ),
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
