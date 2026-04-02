import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/shift_swap_model.dart';
import '../services/shift_swap_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// Widget hiển thị danh sách yêu cầu đổi ca
/// Dùng embedded trong AttendanceManagementView hoặc AttendanceView
class ShiftSwapTab extends StatefulWidget {
  final bool isManager;
  final List<Map<String, dynamic>> staffList;
  final VoidCallback? onChanged;

  const ShiftSwapTab({
    super.key,
    required this.isManager,
    required this.staffList,
    this.onChanged,
  });

  @override
  State<ShiftSwapTab> createState() => _ShiftSwapTabState();
}

class _ShiftSwapTabState extends State<ShiftSwapTab> {
  final _db = DBHelper();
  bool _loading = true;
  List<ShiftSwap> _swaps = [];
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _loadSwaps();
  }

  Future<void> _loadSwaps() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (widget.isManager) {
        _swaps = await ShiftSwapService.getAllSwaps();
      } else if (_currentUid != null) {
        _swaps = await ShiftSwapService.getSwapsForUser(_currentUid!);
      }
    } catch (e) {
      debugPrint('Error loading shift swaps: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Create button
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Yêu cầu đổi ca'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        // List
        Expanded(
          child: _swaps.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'Chưa có yêu cầu đổi ca',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSwaps,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _swaps.length,
                    itemBuilder: (ctx, i) => _buildSwapCard(_swaps[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSwapCard(ShiftSwap swap) {
    final isRequester = swap.requesterId == _currentUid;
    final isTarget = swap.targetId == _currentUid;
    final statusColor = _statusColor(swap.status);
    final statusText = ShiftSwap.statusDisplayVi(swap.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: status + date
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(swap.swapDate),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Swap info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Người yêu cầu',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        swap.requesterName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isRequester ? FontWeight.bold : FontWeight.normal,
                          color: isRequester ? AppColors.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.swap_horiz, color: Colors.grey),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Đổi với',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        swap.targetName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isTarget ? FontWeight.bold : FontWeight.normal,
                          color: isTarget ? AppColors.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (swap.returnDate != null && swap.returnDate!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Ngày trả ca: ${_formatDate(swap.returnDate!)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            if (swap.reason != null && swap.reason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Lý do: ${swap.reason}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            if (swap.rejectReason != null &&
                swap.rejectReason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Lý do từ chối: ${swap.rejectReason}',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
            // Action buttons
            if (_canAct(swap)) ...[
              const Divider(height: 16),
              _buildActions(swap, isRequester, isTarget),
            ],
          ],
        ),
      ),
    );
  }

  bool _canAct(ShiftSwap swap) {
    if (swap.canTargetRespond && swap.targetId == _currentUid) return true;
    if (swap.canManagerApprove && widget.isManager) return true;
    if (swap.canCancel && swap.requesterId == _currentUid) return true;
    return false;
  }

  Widget _buildActions(ShiftSwap swap, bool isRequester, bool isTarget) {
    List<Widget> buttons = [];

    // Target can accept/decline
    if (swap.canTargetRespond && isTarget) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: () => _declineSwap(swap),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Từ chối', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        Expanded(
          child: ElevatedButton(
            onPressed: () => _acceptSwap(swap),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đồng ý', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
    }

    // Manager can approve/reject
    if (swap.canManagerApprove && widget.isManager) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: () => _rejectSwap(swap),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Từ chối', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
      buttons.add(const SizedBox(width: 8));
      buttons.add(
        Expanded(
          child: ElevatedButton(
            onPressed: () => _approveSwap(swap),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Duyệt', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
    }

    // Requester can cancel
    if (swap.canCancel && isRequester && buttons.isEmpty) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: () => _cancelSwap(swap),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Huỷ yêu cầu', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
    }

    return Row(children: buttons);
  }

  // ========================
  // ACTIONS
  // ========================

  Future<void> _acceptSwap(ShiftSwap swap) async {
    final ok = await ShiftSwapService.acceptSwap(swap);
    if (ok) {
      _showSnack('Đã đồng ý đổi ca, chờ quản lý duyệt');
      _loadSwaps();
      widget.onChanged?.call();
    }
  }

  Future<void> _declineSwap(ShiftSwap swap) async {
    final reason = await _showReasonDialog('Lý do từ chối');
    if (reason == null) return;
    final ok = await ShiftSwapService.declineSwap(swap, reason);
    if (ok) {
      _showSnack('Đã từ chối đổi ca');
      _loadSwaps();
      widget.onChanged?.call();
    }
  }

  Future<void> _approveSwap(ShiftSwap swap) async {
    final ok = await ShiftSwapService.approveSwap(swap);
    if (ok) {
      _showSnack('Đã duyệt đổi ca');
      _loadSwaps();
      widget.onChanged?.call();
    }
  }

  Future<void> _rejectSwap(ShiftSwap swap) async {
    final reason = await _showReasonDialog('Lý do từ chối');
    if (reason == null) return;
    final ok = await ShiftSwapService.rejectSwap(swap, reason);
    if (ok) {
      _showSnack('Đã từ chối yêu cầu đổi ca');
      _loadSwaps();
      widget.onChanged?.call();
    }
  }

  Future<void> _cancelSwap(ShiftSwap swap) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Huỷ yêu cầu đổi ca này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Huỷ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ShiftSwapService.cancelSwap(swap);
    if (ok) {
      _showSnack('Đã huỷ yêu cầu');
      _loadSwaps();
      widget.onChanged?.call();
    }
  }

  // ========================
  // CREATE DIALOG
  // ========================

  Future<void> _showCreateDialog() async {
    if (_currentUid == null) return;

    // Filter out current user from staff list
    final otherStaff = widget.staffList
        .where((s) => (s['uid'] ?? s['id']) != _currentUid)
        .toList();

    if (otherStaff.isEmpty) {
      _showSnack('Không có nhân viên khác để đổi ca');
      return;
    }

    Map<String, dynamic>? selectedStaff;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    DateTime? returnDate;
    final reasonCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Yêu cầu đổi ca'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Select colleague
                  const Text(
                    'Đổi ca với:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedStaff,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      hintText: 'Chọn nhân viên',
                    ),
                    items: otherStaff
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s['displayName'] ?? s['name'] ?? s['email'] ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedStaff = v),
                  ),
                  const SizedBox(height: 12),
                  // Select swap date
                  const Text(
                    'Ngày đổi ca:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 90)),
                      );
                      if (d != null) setDialogState(() => selectedDate = d);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(selectedDate),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Return date (optional)
                  const Text(
                    'Ngày trả ca (tuỳ chọn):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate:
                            returnDate ?? selectedDate.add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 90)),
                      );
                      setDialogState(() => returnDate = d);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        returnDate != null
                            ? DateFormat('dd/MM/yyyy').format(returnDate!)
                            : 'Không bắt buộc',
                        style: TextStyle(
                          fontSize: 14,
                          color: returnDate != null ? null : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Reason
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Lý do',
                      border: OutlineInputBorder(),
                      hintText: 'VD: Có việc gia đình',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                onPressed: selectedStaff == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Gửi yêu cầu'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true || selectedStaff == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final swap = ShiftSwap(
      shopId: '',
      requesterId: user.uid,
      requesterName: user.displayName ?? user.email?.split('@').first ?? '',
      requesterEmail: user.email ?? '',
      targetId: selectedStaff!['uid'] ?? selectedStaff!['id'] ?? '',
      targetName: selectedStaff!['displayName'] ?? selectedStaff!['name'] ?? selectedStaff!['email'] ?? '',
      targetEmail: selectedStaff!['email'] ?? '',
      swapDate: DateFormat('yyyy-MM-dd').format(selectedDate),
      returnDate: returnDate != null
          ? DateFormat('yyyy-MM-dd').format(returnDate!)
          : null,
      reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    reasonCtrl.dispose();

    final ok = await ShiftSwapService.createSwapRequest(swap);
    if (ok) {
      _showSnack('Đã gửi yêu cầu đổi ca');
      _loadSwaps();
      widget.onChanged?.call();
    } else {
      _showSnack('Lỗi khi gửi yêu cầu');
    }
  }

  // ========================
  // HELPERS
  // ========================

  Future<String?> _showReasonDialog(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Nhập lý do...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  String _formatDate(String dateKey) {
    try {
      final d = DateFormat('yyyy-MM-dd').parse(dateKey);
      return DateFormat('dd/MM/yyyy (EEE)', 'vi').format(d);
    } catch (_) {
      return dateKey;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_target':
        return Colors.orange;
      case 'pending_manager':
        return Colors.blue;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
