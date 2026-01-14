import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import 'repair_detail_view.dart';
import 'create_repair_order_view.dart';
import 'global_search_view.dart';

class OrderListView extends StatefulWidget {
  final int? initialStatus;
  final bool todayOnly;
  final List<int>? statusFilter;
  final String role;
  const OrderListView({
    super.key,
    this.initialStatus,
    this.todayOnly = false,
    this.statusFilter,
    this.role = 'user',
  });

  @override
  State<OrderListView> createState() => OrderListViewState();
}

class OrderListViewState extends State<OrderListView> {
  final db = DBHelper();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _eventSubscription;

  List<Repair> _displayedRepairs = [];
  bool _isLoading = true;
  String _currentSearch = "";

  // Date filter
  String _timeFilter = 'all'; // all, today, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Status filter - null means all, otherwise specific status
  int? _statusFilter; // null=all, 1=tiếp nhận, 2=đang sửa, 3=xong, 4=đã giao

  bool get canDelete => widget.role == 'admin' || widget.role == 'owner';

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // Listen for repairs_changed events to refresh list
    _eventSubscription = EventBus().stream.listen((event) {
      if (event == 'repairs_changed' && mounted) {
        debugPrint(
          'OrderListView: Received repairs_changed event, reloading...',
        );
        _loadInitialData();
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final all = await db.getAllRepairs();
    if (!mounted) return;
    setState(() {
      _displayedRepairs = _applyFilters(all);
      _isLoading = false;
    });
  }

  void _onSearch(String val) async {
    setState(() => _currentSearch = val);
    final all = await db.getAllRepairs();
    setState(() {
      final filtered = _applyFilters(all);
      if (val.isEmpty) {
        _displayedRepairs = filtered;
      } else {
        _displayedRepairs = filtered
            .where(
              (r) =>
                  r.customerName.toLowerCase().contains(val.toLowerCase()) ||
                  r.phone.contains(val) ||
                  r.model.toLowerCase().contains(val.toLowerCase()),
            )
            .toList();
      }
    });
  }

  List<Repair> _applyFilters(List<Repair> list) {
    return list.where((r) {
      // Widget-level status filter (from constructor)
      if (widget.statusFilter != null &&
          !widget.statusFilter!.contains(r.status)) {
        return false;
      }
      // User-selected status filter
      if (_statusFilter != null && r.status != _statusFilter) {
        return false;
      }
      if (widget.todayOnly) {
        final d = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        final now = DateTime.now();
        if (!(d.year == now.year && d.month == now.month && d.day == now.day)) {
          return false;
        }
      }
      // Time filter
      if (_timeFilter != 'all' && !widget.todayOnly) {
        final d = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        switch (_timeFilter) {
          case 'today':
            final itemDay = DateTime(d.year, d.month, d.day);
            if (itemDay != today) return false;
            break;
          case 'week':
            final weekAgo = today.subtract(const Duration(days: 7));
            if (d.isBefore(weekAgo)) return false;
            break;
          case 'month':
            final monthStart = DateTime(now.year, now.month, 1);
            if (d.isBefore(monthStart)) return false;
            break;
          case 'custom':
            if (_customStartDate != null && d.isBefore(_customStartDate!)) {
              return false;
            }
            if (_customEndDate != null &&
                d.isAfter(_customEndDate!.add(const Duration(days: 1)))) {
              return false;
            }
            break;
        }
      }
      return true;
    }).toList();
  }

  int get _activeFilterCount {
    int count = 0;
    if (_timeFilter != 'all' && !widget.todayOnly) count++;
    if (_statusFilter != null) count++;
    return count;
  }

  String _getTimeFilterLabel() {
    switch (_timeFilter) {
      case 'today':
        return 'Hôm nay';
      case 'week':
        return '7 ngày';
      case 'month':
        return 'Tháng này';
      case 'custom':
        return 'Tùy chọn';
      default:
        return 'Tất cả';
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'BỘ LỌC',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _timeFilter = 'all';
                        _customStartDate = null;
                        _customEndDate = null;
                        _statusFilter = null;
                      });
                    },
                    child: const Text('Đặt lại tất cả'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // STATUS FILTER
              const Text(
                'TRẠNG THÁI',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip('Tất cả', null, setSheetState),
                  _statusChip('Tiếp nhận', 1, setSheetState, Colors.blue),
                  _statusChip('Đang sửa', 2, setSheetState, Colors.orange),
                  _statusChip('Đã xong', 3, setSheetState, Colors.green),
                  _statusChip('Đã giao', 4, setSheetState, Colors.purple),
                ],
              ),
              const SizedBox(height: 20),

              // TIME FILTER
              const Text(
                'THỜI GIAN',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('Tất cả', 'all', setSheetState),
                  _filterChip('Hôm nay', 'today', setSheetState),
                  _filterChip('7 ngày', 'week', setSheetState),
                  _filterChip('Tháng này', 'month', setSheetState),
                  GestureDetector(
                    onTap: () async {
                      final range = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange:
                            _customStartDate != null && _customEndDate != null
                            ? DateTimeRange(
                                start: _customStartDate!,
                                end: _customEndDate!,
                              )
                            : null,
                        locale: const Locale('vi', 'VN'),
                      );
                      if (range != null) {
                        setSheetState(() {
                          _timeFilter = 'custom';
                          _customStartDate = range.start;
                          _customEndDate = range.end;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _timeFilter == 'custom'
                            ? const Color(0xFF2962FF)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _timeFilter == 'custom'
                              ? const Color(0xFF2962FF)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 16,
                            color: _timeFilter == 'custom'
                                ? Colors.white
                                : Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Tùy chọn',
                            style: TextStyle(
                              color: _timeFilter == 'custom'
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: _timeFilter == 'custom'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_timeFilter == 'custom' &&
                  _customStartDate != null &&
                  _customEndDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${DateFormat('dd/MM/yyyy').format(_customStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_customEndDate!)}',
                    style: const TextStyle(
                      color: Color(0xFF2962FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _onSearch(_currentSearch);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2962FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ÁP DỤNG',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(
    String label,
    int? value,
    StateSetter setSheetState, [
    Color? activeColor,
  ]) {
    final isSelected = _statusFilter == value;
    final color = activeColor ?? const Color(0xFF2962FF);
    return GestureDetector(
      onTap: () => setSheetState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value, StateSetter setSheetState) {
    final isSelected = _timeFilter == value;
    return GestureDetector(
      onTap: () => setSheetState(() => _timeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2962FF) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF2962FF) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Repair r) {
    if (!canDelete) return;
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÁC NHẬN XÓA ĐƠN"),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: "Nhập mật khẩu quản lý"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) return;
              try {
                final navigator = Navigator.of(ctx);
                final cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: passCtrl.text,
                );
                await user.reauthenticateWithCredential(cred);

                // Lưu id trước khi xóa để dùng cho sync
                final repairId = r.id;
                final repairFirestoreId = r.firestoreId;

                // Nếu có firestoreId, xóa trực tiếp trên Firestore trước
                if (repairFirestoreId != null && repairFirestoreId.isNotEmpty) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('repairs')
                        .doc(repairFirestoreId)
                        .update({
                          'deleted': true,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                  } catch (e) {
                    debugPrint('❌ Failed to soft delete on Firestore: $e');
                    // Tiếp tục xóa local dù Firestore fail
                  }
                }

                // Xóa local bằng firestoreId nếu có, nếu không thì xóa bằng id
                if (repairFirestoreId != null && repairFirestoreId.isNotEmpty) {
                  await db.deleteRepairByFirestoreId(repairFirestoreId);
                } else if (repairId != null) {
                  await db.deleteRepair(repairId);
                }

                // Ghi nhật ký xóa đơn
                await db.logAction(
                  userId: user.uid,
                  userName: user.email?.split('@').first.toUpperCase() ?? 'NV',
                  action: 'XÓA ĐƠN SỬA',
                  type: 'REPAIR',
                  targetId: repairFirestoreId,
                  desc:
                      'Đã xóa đơn sửa ${r.model} - ${r.customerName} - ${r.phone}',
                );

                // Queue delete sync via SyncOrchestrator (backup nếu Firestore direct fail)
                if (repairId != null && repairFirestoreId != null) {
                  await SyncOrchestrator().enqueue(
                    entityType: SyncEntityType.repair,
                    entityId: repairId,
                    firestoreId: repairFirestoreId,
                    operation: SyncOperation.delete,
                    data: null,
                  );
                }

                navigator.pop();
                _loadInitialData();
                messenger.showSnackBar(
                  const SnackBar(content: Text('ĐÃ XÓA THÀNH CÔNG')),
                );
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Mật khẩu sai')),
                );
              }
            },
            child: const Text("XÓA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _displayedRepairs.length;
    final pendingCount = _displayedRepairs.where((r) => r.status < 3).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2962FF),
                const Color(0xFF2962FF).withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "DANH SÁCH MÁY SỬA",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              '$count máy • $pendingCount đang xử lý',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchView(role: widget.role),
              ),
            ),
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            tooltip: 'Tìm kiếm toàn app',
          ),
          if (!widget.todayOnly)
            Stack(
              children: [
                IconButton(
                  onPressed: _showFilterSheet,
                  icon: const Icon(
                    Icons.filter_list_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Lọc theo thời gian',
                ),
                if (_activeFilterCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_activeFilterCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: _loadInitialData,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: Column(
        children: [
          // Active filter chip
          if (_activeFilterCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list,
                    size: 16,
                    color: Color(0xFF2962FF),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lọc: ${_getTimeFilterLabel()}',
                    style: const TextStyle(
                      color: Color(0xFF2962FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _timeFilter = 'all';
                        _customStartDate = null;
                        _customEndDate = null;
                      });
                      _onSearch(_currentSearch);
                    },
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF2962FF),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: "Tìm khách, model, SĐT...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadInitialData,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _displayedRepairs.length,
                      itemBuilder: (ctx, i) =>
                          _buildRepairCard(_displayedRepairs[i], i + 1),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateRepairOrderView(role: widget.role),
            ),
          );
          if (res == true) _loadInitialData();
        },
        label: const Text("NHẬN MÁY MỚI"),
        icon: const Icon(Icons.add_a_photo_rounded),
        backgroundColor: const Color(0xFF2962FF),
      ),
    );
  }

  Widget _buildRepairCard(Repair r, int index) {
    final bool isDone = r.status >= 3;
    final List<String> images = r.receiveImages;
    final String firstImage = images.isNotEmpty ? images.first : "";

    return Dismissible(
      key: Key(r.firestoreId ?? r.createdAt.toString()),
      direction: canDelete
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 30),
      ),
      confirmDismiss: (_) async {
        _confirmDelete(r);
        return false;
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: InkWell(
          onTap: () async {
            final res = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)),
            );
            if (res == true) _loadInitialData();
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STT (Số thứ tự)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2962FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF2962FF),
                      ),
                    ),
                  ),
                ),
                // 1. HÌNH ẢNH NHẬN MÁY
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          image: firstImage.isNotEmpty
                              ? DecorationImage(
                                  image: firstImage.startsWith('http')
                                      ? NetworkImage(firstImage)
                                      : FileImage(File(firstImage))
                                            as ImageProvider,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: firstImage.isEmpty
                            ? const Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "+${images.length - 1}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // 2. THÔNG TIN CHI TIẾT
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.model,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF2962FF),
                        ),
                      ),
                      Text(
                        "Khách: ${r.customerName}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Lỗi: ${r.issue.split('|').first}",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Ghi chú: ${r.accessories}",
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 3. TRẠNG THÁI & THỜI GIAN
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('dd/MM').format(
                        DateTime.fromMillisecondsSinceEpoch(r.createdAt),
                      ),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(r.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getStatusLabel(r.status),
                        style: TextStyle(
                          color: _getStatusColor(r.status),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(int status) {
    switch (status) {
      case 1:
        return "TIẾP NHẬN";
      case 2:
        return "ĐANG SỬA";
      case 3:
        return "SỬA XONG";
      case 4:
        return "ĐÃ GIAO";
      default:
        return "KHÁC";
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.green;
      case 4:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
