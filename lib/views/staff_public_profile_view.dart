import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/community_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/entity_avatar.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';

class StaffPublicProfileView extends StatefulWidget {
  const StaffPublicProfileView({
    super.key,
    required this.userId,
    this.fallbackName,
  });

  final String userId;
  final String? fallbackName;

  @override
  State<StaffPublicProfileView> createState() => _StaffPublicProfileViewState();
}

class _StaffPublicProfileViewState extends State<StaffPublicProfileView> {
  final DBHelper _db = DBHelper();
  bool _loading = true;
  Map<String, dynamic>? _userInfo;
  int _salesCount = 0;
  int _repairsCount = 0;
  int _attendanceCount = 0;
  List<SaleOrder> _monthlySales = const [];
  List<Repair> _monthlyRepairs = const [];
  List<Attendance> _recentAttendance = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await CommunityService.getUserProfile(widget.userId);
      await _loadReadonlyStats(info ?? const <String, dynamic>{});
      if (!mounted) return;
      setState(() {
        _userInfo = info;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadReadonlyStats(Map<String, dynamic> info) async {
    final targetUid = widget.userId.trim();
    final targetEmail = (info['email'] ?? '').toString().trim();
    final targetName = (info['displayName'] ?? info['name'] ?? '').toString().trim();
    final targetUpper = targetName.toUpperCase();
    final emailPrefix = targetEmail.split('@').first.toUpperCase();

    bool matchesStaff(String? value) {
      if (value == null || value.isEmpty) return false;
      final v = value.toUpperCase();
      if (targetUpper.isNotEmpty && v == targetUpper) return true;
      if (emailPrefix.isNotEmpty && (v == emailPrefix || v.contains(emailPrefix))) {
        return true;
      }
      return false;
    }

    final repairs = await _db.getAllRepairs();
    final sales = await _db.getAllSales();
    final attendance = await _db.getAttendanceByUser(targetUid, limit: 120);

    final monthlyRepairs = repairs.where((r) {
      if (!_isTimestampInCurrentMonth(_repairActivityAt(r))) return false;
      if (matchesStaff(r.repairedBy)) return true;
      if ((r.repairedBy == null || r.repairedBy!.isEmpty) && r.status >= 3 && matchesStaff(r.createdBy)) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => _repairActivityAt(b).compareTo(_repairActivityAt(a)));

    final monthlySales = sales.where((s) {
      if (!_isTimestampInCurrentMonth(s.soldAt)) return false;
      return matchesStaff(s.sellerName);
    }).toList()
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    final monthlyAttendance = attendance.where(_isAttendanceInCurrentMonth).toList();

    _monthlyRepairs = monthlyRepairs;
    _monthlySales = monthlySales;
    _recentAttendance = monthlyAttendance;
    _repairsCount = monthlyRepairs.length;
    _salesCount = monthlySales.length;
    _attendanceCount = monthlyAttendance.length;
  }

  int _repairActivityAt(Repair repair) {
    return repair.finishedAt ?? repair.deliveredAt ?? repair.startedAt ?? repair.createdAt;
  }

  bool _isTimestampInCurrentMonth(int timestamp) {
    if (timestamp <= 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  bool _isAttendanceInCurrentMonth(Attendance attendance) {
    final now = DateTime.now();
    DateTime? date;
    if (attendance.dateKey.trim().isNotEmpty) {
      date = DateTime.tryParse(attendance.dateKey.trim());
    }
    date ??= attendance.checkInAt != null
        ? DateTime.fromMillisecondsSinceEpoch(attendance.checkInAt!)
        : DateTime.fromMillisecondsSinceEpoch(attendance.createdAt);
    return date.year == now.year && date.month == now.month;
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
        return 'Quản trị';
      default:
        return 'Người dùng';
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _userInfo ?? const <String, dynamic>{};
    final name = (info['displayName'] ?? info['name'] ?? widget.fallbackName ?? 'Nhân viên').toString();
    final role = _roleVi((info['role'] ?? '').toString());
    final phone = (info['phone'] ?? '').toString().trim();
    final email = (info['email'] ?? '').toString().trim();
    final address = (info['address'] ?? '').toString().trim();
    final photo = (info['photoUrl'] ?? '').toString().trim();
    final cover = ((info['coverOriginalUrl'] ?? info['coverUrl']) ?? '').toString().trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hồ sơ nhân viên'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 190,
                    width: double.infinity,
                    child: cover.isEmpty
                        ? Container(color: const Color(0xFF153B5E))
                        : Image(
                            image: CachedNetworkImageProvider(cover),
                            fit: BoxFit.cover,
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        EntityAvatar(
                          imageUrl: photo,
                          name: name,
                          radius: 34,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTextStyles.headline4.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                role,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (phone.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(phone),
                    ),
                  if (email.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(email),
                    ),
                  if (address.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(address),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _statBox('Đơn bán', _salesCount, Icons.shopping_cart_outlined),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statBox('Đơn sửa', _repairsCount, Icons.build_outlined),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statBox('Chấm công', _attendanceCount, Icons.access_time_outlined),
                        ),
                      ],
                    ),
                  ),
                  _buildSalesSection(),
                  _buildRepairsSection(),
                  _buildAttendanceSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _statBox(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSalesSection() {
    return _activitySection(
      title: 'Bán hàng tháng này',
      count: _monthlySales.length,
      emptyText: 'Chưa có đơn bán',
      children: _monthlySales.take(5).map((sale) {
        return ListTile(
          dense: true,
          leading: const Icon(Icons.shopping_cart, size: 18, color: Colors.green),
          title: Text(
            sale.customerName.isNotEmpty ? sale.customerName : 'Khách lẻ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt))} • ${sale.productNames}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildRepairsSection() {
    return _activitySection(
      title: 'Sửa chữa tháng này',
      count: _monthlyRepairs.length,
      emptyText: 'Chưa có đơn sửa',
      children: _monthlyRepairs.take(5).map((repair) {
        return ListTile(
          dense: true,
          leading: const Icon(Icons.build, size: 18, color: Colors.blue),
          title: Text(
            repair.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_repairActivityAt(repair)))} • ${repair.model}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepairDetailView(repair: repair)),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildAttendanceSection() {
    return _activitySection(
      title: 'Chấm công tháng này',
      count: _recentAttendance.length,
      emptyText: 'Chưa có dữ liệu chấm công',
      children: _recentAttendance.take(5).map((a) {
        final status = a.isLate == 1 ? 'Đi trễ' : 'Đúng giờ';
        return ListTile(
          dense: true,
          leading: Icon(
            a.isLate == 1 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 18,
            color: a.isLate == 1 ? Colors.orange : Colors.green,
          ),
          title: Text(a.dateKey),
          subtitle: Text(
            'Vào: ${a.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkInAt!)) : '--'} | Ra: ${a.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkOutAt!)) : '--'} • $status',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  Widget _activitySection({
    required String title,
    required int count,
    required String emptyText,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text('$count', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 6),
          if (children.isEmpty)
            Text(emptyText, style: AppTextStyles.caption)
          else
            ...children,
        ],
      ),
    );
  }
}
