import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/shift_swap_request_model.dart';
import '../services/notification_service.dart';
import '../services/shift_swap_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/responsive_wrapper.dart';

class ShiftSwapView extends StatefulWidget {
  const ShiftSwapView({super.key});

  @override
  State<ShiftSwapView> createState() => _ShiftSwapViewState();
}

class _ShiftSwapViewState extends State<ShiftSwapView>
  with TickerProviderStateMixin {
  static const List<String> _shifts = [
    'Ca sáng (08:00-12:00)',
    'Ca chiều (13:00-17:00)',
    'Ca tối (18:00-22:00)',
    'Ca linh hoạt',
  ];

  late TabController _tabController;
  bool _loadingRole = true;
  bool _canReview = false;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadRole();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loadingRole = false;
          _canReview = false;
          _currentUid = null;
        });
        return;
      }

      final role = await UserService.getUserRole(user.uid);
      final canReview =
          UserService.isCurrentUserSuperAdmin() ||
          role == 'owner' ||
          role == 'manager';

      if (!mounted) return;
      final targetLength = canReview ? 2 : 1;

      if (_tabController.length != targetLength) {
        final oldController = _tabController;
        final nextController = TabController(
          length: targetLength,
          initialIndex: oldController.index.clamp(0, targetLength - 1),
          vsync: this,
        );

        setState(() {
          _loadingRole = false;
          _canReview = canReview;
          _currentUid = user.uid;
          _tabController = nextController;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      } else {
        setState(() {
          _loadingRole = false;
          _canReview = canReview;
          _currentUid = user.uid;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRole = false;
        _canReview = false;
      });
      NotificationService.showSnackBar('Không tải được quyền đổi ca: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tabs = <Tab>[const Tab(text: 'YÊU CẦU CỦA TÔI')];
    if (_canReview) {
      tabs.add(const Tab(text: 'CHỜ DUYỆT'));
    }

    final views = <Widget>[_buildMyRequestsTab()];
    if (_canReview) {
      views.add(_buildPendingRequestsTab());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: 'ĐỔI CA',
        subtitle: 'Tạo và duyệt yêu cầu đổi ca theo shop',
        accentColor: AppBarAccents.staff,
        actions: [
          IconButton(
            tooltip: 'Tạo yêu cầu mới',
            icon: const Icon(Icons.add_task),
            onPressed: _showCreateDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: ResponsiveCenter(
        child: TabBarView(controller: _tabController, children: views),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('YÊU CẦU ĐỔI CA'),
      ),
    );
  }

  Widget _buildMyRequestsTab() {
    return StreamBuilder<List<ShiftSwapRequest>>(
      stream: ShiftSwapService.watchMyRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <ShiftSwapRequest>[];
        if (data.isEmpty) {
          return _buildEmptyState('Bạn chưa tạo yêu cầu đổi ca nào');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, index) {
            final item = data[index];
            return _buildRequestCard(item, showReviewActions: false);
          },
        );
      },
    );
  }

  Widget _buildPendingRequestsTab() {
    return StreamBuilder<List<ShiftSwapRequest>>(
      stream: ShiftSwapService.watchPendingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? const <ShiftSwapRequest>[];
        if (data.isEmpty) {
          return _buildEmptyState('Không có yêu cầu nào đang chờ duyệt');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: data.length,
          itemBuilder: (_, index) {
            final item = data[index];
            return _buildRequestCard(item, showReviewActions: true);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horizontal_circle_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: AppTextStyles.body1Size)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('TẠO YÊU CẦU'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    ShiftSwapRequest item, {
    required bool showReviewActions,
  }) {
    final statusColor = _statusColor(item.status);
    final statusLabel = _statusLabel(item.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.requesterName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Ngày đổi ca: ${_fmtDate(item.requestedDate)}'),
            Text('Từ: ${item.currentShift}'),
            Text('Sang: ${item.desiredShift}'),
            if ((item.targetUserName ?? '').isNotEmpty) Text('Đổi với: ${item.targetUserName}'),
            if ((item.note ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Ghi chú: ${item.note}'),
            ],
            const SizedBox(height: 6),
            Text(
              'Tạo lúc: ${_fmtMs(item.createdAt)}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: AppTextStyles.captionSize),
            ),
            if (item.reviewedAt != null)
              Text(
                'Xử lý lúc: ${_fmtMs(item.reviewedAt!)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: AppTextStyles.captionSize),
              ),
            if ((item.rejectReason ?? '').isNotEmpty)
              Text(
                'Lý do từ chối: ${item.rejectReason}',
                style: TextStyle(color: Colors.red.shade700, fontSize: AppTextStyles.captionSize),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_canCancel(item) && !showReviewActions)
                  OutlinedButton.icon(
                    onPressed: () => _cancelRequest(item),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('HUỶ'),
                  ),
                if (showReviewActions) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approve(item),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('DUYỆT'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(item),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('TỪ CHỐI'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canCancel(ShiftSwapRequest item) {
    return item.status == 'pending' && _currentUid != null && item.requesterId == _currentUid;
  }

  Future<void> _showCreateDialog() async {
    final staff = await ShiftSwapService.getShopStaffOptions();
    if (!mounted) return;

    final dateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final noteController = TextEditingController();
    String currentShift = _shifts.first;
    String desiredShift = _shifts[1];
    String? targetUid;
    String? targetName;
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx,
                initialDate: now,
                firstDate: now.subtract(const Duration(days: 30)),
                lastDate: now.add(const Duration(days: 90)),
              );
              if (picked == null) return;
              dateController.text = DateFormat('yyyy-MM-dd').format(picked);
            }

            return AlertDialog(
              title: const Text('TẠO YÊU CẦU ĐỔI CA'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: dateController,
                      readOnly: true,
                      onTap: pickDate,
                      decoration: const InputDecoration(
                        labelText: 'Ngày cần đổi ca',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: currentShift,
                      items: _shifts
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      decoration: const InputDecoration(labelText: 'Ca hiện tại'),
                      onChanged: (v) {
                        if (v == null) return;
                        setS(() => currentShift = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: desiredShift,
                      items: _shifts
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      decoration: const InputDecoration(labelText: 'Ca muốn đổi'),
                      onChanged: (v) {
                        if (v == null) return;
                        setS(() => desiredShift = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: targetUid,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Đổi với nhân viên (tuỳ chọn)'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Không chỉ định'),
                        ),
                        ...staff.map(
                          (s) => DropdownMenuItem<String>(
                            value: s['uid'],
                            child: Text(s['name'] ?? 'Nhân viên'),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setS(() {
                          targetUid = v;
                          targetName = staff
                              .firstWhere(
                                (s) => s['uid'] == v,
                                orElse: () => const {'name': ''},
                              )['name'];
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
                        hintText: 'Lý do đổi ca (không bắt buộc)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('ĐÓNG'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (currentShift == desiredShift) {
                            NotificationService.showSnackBar(
                              'Ca hiện tại và ca muốn đổi không được trùng nhau',
                              color: Colors.orange,
                            );
                            return;
                          }

                          setS(() => submitting = true);
                          try {
                            await ShiftSwapService.createRequest(
                              requestedDate: dateController.text.trim(),
                              currentShift: currentShift,
                              desiredShift: desiredShift,
                              targetUserId: targetUid,
                              targetUserName: targetName,
                              note: noteController.text.trim(),
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            NotificationService.showSnackBar(
                              '✅ Đã gửi yêu cầu đổi ca',
                              color: Colors.green,
                            );
                          } catch (e) {
                            NotificationService.showSnackBar('❌ Không thể gửi yêu cầu: $e', color: Colors.red);
                          } finally {
                            if (ctx.mounted) {
                              setS(() => submitting = false);
                            }
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(submitting ? 'ĐANG GỬI' : 'GỬI YÊU CẦU'),
                ),
              ],
            );
          },
        );
      },
    );

    dateController.dispose();
    noteController.dispose();
  }

  Future<void> _approve(ShiftSwapRequest item) async {
    try {
      await ShiftSwapService.approveRequest(item);
      NotificationService.showSnackBar('✅ Đã duyệt yêu cầu đổi ca', color: Colors.green);
    } catch (e) {
      NotificationService.showSnackBar('❌ Duyệt thất bại: $e', color: Colors.red);
    }
  }

  Future<void> _reject(ShiftSwapRequest item) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TỪ CHỐI YÊU CẦU'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Lý do từ chối',
            hintText: 'Nhập lý do để nhân viên biết và xử lý lại',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÓNG')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (result == null) return;
    try {
      await ShiftSwapService.rejectRequest(item, reason: result);
      NotificationService.showSnackBar('✅ Đã từ chối yêu cầu đổi ca', color: Colors.orange);
    } catch (e) {
      NotificationService.showSnackBar('❌ Từ chối thất bại: $e', color: Colors.red);
    }
  }

  Future<void> _cancelRequest(ShiftSwapRequest item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HUỶ YÊU CẦU'),
        content: const Text('Bạn có chắc muốn huỷ yêu cầu đổi ca này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('KHÔNG')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('HUỶ YÊU CẦU')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ShiftSwapService.cancelRequest(item);
      NotificationService.showSnackBar('✅ Đã huỷ yêu cầu', color: Colors.green);
    } catch (e) {
      NotificationService.showSnackBar('❌ Không thể huỷ yêu cầu: $e', color: Colors.red);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'ĐÃ DUYỆT';
      case 'rejected':
        return 'TỪ CHỐI';
      case 'cancelled':
        return 'ĐÃ HUỶ';
      default:
        return 'CHỜ DUYỆT';
    }
  }

  String _fmtDate(String value) {
    try {
      final dt = DateTime.parse(value);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return value;
    }
  }

  String _fmtMs(int value) {
    if (value <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }
}
