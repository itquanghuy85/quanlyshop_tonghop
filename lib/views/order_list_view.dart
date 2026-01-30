import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../models/repair_model.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../widgets/gradient_fab.dart';
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
  List<Repair> _allLoadedRepairs = []; // Cache for filtering
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 30;
  String _currentSearch = "";

  // Date filter
  String _timeFilter = 'all'; // all, today, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Status filter - Set để cho phép chọn nhiều trạng thái
  Set<int> _statusFilters = {}; // Empty = all, {1,2} = tiếp nhận + đang sửa
  bool _filterPendingApproval = false; // Lọc đơn chờ duyệt giao

  bool get canDelete => widget.role == 'admin' || widget.role == 'owner';
  
  /// Check if we need full data (for filtering)
  bool get _needsFullData => true; // Luôn lấy full data để sort đúng

  // Ưu tiên: Tiếp nhận -> Đang sửa -> Đã xong -> Chờ duyệt giao -> Giao máy
  int _compareRepairs(Repair a, Repair b) {
    int priority(Repair r) {
      if (r.status == 1) return 1;
      if (r.status == 2) return 2;
      if (r.status == 3 && !r.pendingDeliveryApproval) return 3;
      if (r.status == 3 && r.pendingDeliveryApproval) return 4;
      if (r.status == 4) return 5;
      return 6;
    }

    final pa = priority(a);
    final pb = priority(b);
    if (pa != pb) return pa.compareTo(pb);
    return b.createdAt.compareTo(a.createdAt); // Mới nhất trước
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    
    // Setup scroll listener for lazy loading
    _scrollController.addListener(_onScroll);

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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreIfNeeded();
    }
  }
  
  Future<void> _loadMoreIfNeeded() async {
    // Không dùng phân trang khi cần sort toàn bộ
    return;
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _allLoadedRepairs = [];
      _hasMore = false;
      _isLoadingMore = false;
    });

    final all = await db.getAllRepairs();
    if (!mounted) return;

    final filtered = _applyFilters(all)..sort(_compareRepairs);
    setState(() {
      _allLoadedRepairs = filtered;
      _displayedRepairs = List<Repair>.from(filtered);
      _currentOffset = filtered.length;
      _isLoading = false;
    });
  }

  void _onSearch(String val) async {
    setState(() => _currentSearch = val);
    
    if (_allLoadedRepairs.isEmpty) {
      _allLoadedRepairs = await db.getAllRepairs();
    }

    final filtered = _applyFilters(_allLoadedRepairs);
    final searched = val.isEmpty
        ? filtered
        : filtered
            .where(
              (r) =>
                  r.customerName.toLowerCase().contains(val.toLowerCase()) ||
                  r.phone.contains(val) ||
                  r.model.toLowerCase().contains(val.toLowerCase()),
            )
            .toList();

    searched.sort(_compareRepairs);

    if (mounted) {
      setState(() {
        _displayedRepairs = searched;
        _hasMore = false;
      });
    }
  }

  List<Repair> _applyFilters(List<Repair> list) {
    return list.where((r) {
      // Widget-level status filter (from constructor)
      if (widget.statusFilter != null &&
          !widget.statusFilter!.contains(r.status)) {
        return false;
      }
      // Lọc đơn chờ duyệt giao
      if (_filterPendingApproval) {
        if (!r.pendingDeliveryApproval) return false;
      } else {
        // User-selected status filter - cho phép chọn nhiều trạng thái
        if (_statusFilters.isNotEmpty && !_statusFilters.contains(r.status)) {
          return false;
        }
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
    if (_statusFilters.isNotEmpty) count++;
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
                  Text(
                    'BỘ LỌC',
                    style: AppTextStyles.headline3.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _timeFilter = 'all';
                        _customStartDate = null;
                        _customEndDate = null;
                        _statusFilters = {};
                      });
                    },
                    child: const Text('Đặt lại tất cả'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // STATUS FILTER - CHO PHÉP CHỌN NHIỀU
              Text(
                'TRẠNG THÁI (chọn nhiều)',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChipMulti('Tất cả', null, setSheetState),
                  _statusChipMulti('Tiếp nhận', 1, setSheetState, Colors.blue),
                  _statusChipMulti('Đang sửa', 2, setSheetState, Colors.orange),
                  _statusChipMulti('Đã xong', 3, setSheetState, Colors.green),
                  _pendingApprovalChip(setSheetState),
                  _statusChipMulti('Đã giao', 4, setSheetState, Colors.purple),
                ],
              ),
              if (_statusFilters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Đã chọn: ${_statusFilters.length} trạng thái',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // TIME FILTER
              Text(
                'THỜI GIAN',
                style: AppTextStyles.subtitle1.copyWith(
                  fontWeight: FontWeight.w600,
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

  Widget _statusChipMulti(
    String label,
    int? value,
    StateSetter setSheetState, [
    Color? activeColor,
  ]) {
    // null = "Tất cả" - khi bấm sẽ clear hết selection
    final isSelected = value == null
        ? _statusFilters.isEmpty && !_filterPendingApproval
        : _statusFilters.contains(value);
    final color = activeColor ?? const Color(0xFF2962FF);
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          if (value == null) {
            // Bấm "Tất cả" -> clear hết
            _statusFilters = {};
            _filterPendingApproval = false;
          } else {
            // Toggle trạng thái được chọn
            if (_statusFilters.contains(value)) {
              _statusFilters.remove(value);
            } else {
              _statusFilters.add(value);
            }
            _filterPendingApproval = false; // Reset pending filter
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected && value != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle, size: 14, color: Colors.white),
              ),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingApprovalChip(StateSetter setSheetState) {
    final isSelected = _filterPendingApproval;
    final color = Colors.deepOrange;
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          _filterPendingApproval = !_filterPendingApproval;
          if (_filterPendingApproval) {
            _statusFilters = {}; // Clear other filters when selecting pending
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle, size: 14, color: Colors.white),
              ),
            Text(
              'Chờ duyệt',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
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
    
    // === KIỂM TRA ĐIỀU KIỆN XÓA ===
    // 1. Chỉ xóa đơn chưa giao (status < 4)
    if (r.status >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Không thể xóa đơn ĐÃ GIAO. Chỉ xóa đơn chưa giao.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // 2. Cảnh báo nếu đơn đã có giá (có số liệu kế toán)
    final hasAccountingData = r.price > 0 || r.cost > 0;
    final hasPartsUsed = r.partsUsed.isNotEmpty;
    
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              hasAccountingData || hasPartsUsed ? Icons.warning_amber_rounded : Icons.delete_forever,
              color: Colors.red,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text("XÁC NHẬN XÓA ĐƠN")),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin đơn
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.model, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${r.customerName} - ${r.phone}'),
                  Text('Trạng thái: ${_getStatusText(r.status)}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Cảnh báo nếu có số liệu
            if (hasAccountingData)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_money, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đơn có số liệu kế toán:\n• Giá: ${_formatMoney(r.price)}\n• Chi phí: ${_formatMoney(r.cost)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Cảnh báo nếu có phụ tùng
            if (hasPartsUsed)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.build, color: Colors.purple, size: 20),
                        SizedBox(width: 8),
                        Text('Đơn có phụ tùng:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(r.partsUsed, style: const TextStyle(fontSize: 11, color: Colors.purple)),
                    const SizedBox(height: 4),
                    const Text(
                      '⚠️ Phụ tùng sẽ được hoàn trả về kho!',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: "Nhập mật khẩu quản lý để xác nhận",
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _executeDelete(ctx, r, passCtrl.text),
            child: const Text("XÓA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  String _getStatusText(int status) {
    switch (status) {
      case 1: return 'Tiếp nhận';
      case 2: return 'Đang sửa';
      case 3: return 'Sửa xong';
      case 4: return 'Đã giao';
      default: return 'Không xác định';
    }
  }
  
  String _formatMoney(int amount) {
    if (amount == 0) return '0đ';
    return '${NumberFormat('#,###', 'vi_VN').format(amount)}đ';
  }
  
  Future<void> _executeDelete(BuildContext ctx, Repair r, String password) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    
    try {
      final navigator = Navigator.of(ctx);
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);

      // === HOÀN TRẢ PHỤ TÙNG VỀ KHO ===
      if (r.partsUsed.isNotEmpty) {
        await _restorePartsToInventory(r.partsUsed);
      }

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
        }
      }

      // Xóa local
      if (repairFirestoreId != null && repairFirestoreId.isNotEmpty) {
        await db.deleteRepairByFirestoreId(repairFirestoreId);
      } else if (repairId != null) {
        await db.deleteRepair(repairId);
      }

      // Ghi nhật ký
      await db.logAction(
        userId: user.uid,
        userName: user.email?.split('@').first.toUpperCase() ?? 'NV',
        action: 'XÓA ĐƠN SỬA',
        type: 'REPAIR',
        targetId: repairFirestoreId,
        desc: 'Đã xóa đơn sửa ${r.model} - ${r.customerName} - ${r.phone}${r.partsUsed.isNotEmpty ? ' (đã hoàn trả phụ tùng: ${r.partsUsed})' : ''}',
      );

      // Queue delete sync
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
        SnackBar(
          content: Text(r.partsUsed.isNotEmpty 
            ? '✅ Đã xóa đơn và hoàn trả phụ tùng về kho'
            : '✅ Đã xóa đơn thành công'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ Mật khẩu sai'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// Hoàn trả phụ tùng về kho
  /// Format partsUsed: "Part1 x1, Part2 x2, ..."
  Future<void> _restorePartsToInventory(String partsUsed) async {
    if (partsUsed.isEmpty) return;
    
    // Parse partsUsed
    final parts = partsUsed.split(', ');
    for (final part in parts) {
      // Parse "PartName x2" hoặc "PartName"
      final match = RegExp(r'^(.+?)\s*x(\d+)$').firstMatch(part.trim());
      String partName;
      int quantity;
      
      if (match != null) {
        partName = match.group(1)!.trim();
        quantity = int.tryParse(match.group(2)!) ?? 1;
      } else {
        partName = part.trim();
        quantity = 1;
      }
      
      if (partName.isEmpty) continue;
      
      // Tìm part trong kho và cộng số lượng
      await db.restorePartQuantityByName(partName, quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _displayedRepairs.length;
    final pendingCount = _displayedRepairs.where((r) => r.status < 3).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "DANH SÁCH MÁY SỬA",
              style: AppTextStyles.headline2.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              '$count máy • $pendingCount đang xử lý',
              style: AppTextStyles.caption.copyWith(
                color: Colors.white70,
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
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
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
                    style: AppTextStyles.subtitle1.copyWith(
                      color: const Color(0xFF2962FF),
                      fontWeight: FontWeight.bold,
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
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _displayedRepairs.length + (_isLoadingMore ? 1 : 0) + (!_hasMore && _displayedRepairs.isNotEmpty ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i < _displayedRepairs.length) {
                          return _buildRepairCard(_displayedRepairs[i], i + 1);
                        }
                        if (_isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        // End of list indicator
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'Đã hiển thị ${_displayedRepairs.length} đơn sửa',
                              style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: GradientFab.purple(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateRepairOrderView(role: widget.role),
            ),
          );
          if (res == true) _loadInitialData();
        },
        icon: Icons.phone_android,
        label: 'Nhận máy',
      ),
    );
  }

  Widget _buildRepairCard(Repair r, int index) {
    final List<String> images = r.receiveImages;
    final String firstImage = images.isNotEmpty ? images.first : "";
    
    // Determine card color based on status
    Color bgColor;
    Color borderColor;
    switch (r.status) {
      case 1: // TIẾP NHẬN
        bgColor = Colors.blue.shade50;
        borderColor = Colors.blue.shade300;
        break;
      case 2: // ĐANG SỬA
        bgColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade300;
        break;
      case 3: // SỬA XONG
        bgColor = r.pendingDeliveryApproval
            ? Colors.deepOrange.shade50
            : Colors.green.shade50;
        borderColor = r.pendingDeliveryApproval
            ? Colors.deepOrange.shade300
            : Colors.green.shade300;
        break;
      case 4: // ĐÃ GIAO
        bgColor = Colors.purple.shade50;
        borderColor = Colors.purple.shade300;
        break;
      default:
        bgColor = Colors.grey.shade50;
        borderColor = Colors.grey.shade300;
    }

    return Dismissible(
      key: Key(r.firestoreId ?? r.createdAt.toString()),
      direction: canDelete
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        _confirmDelete(r);
        return false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: bgColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          onTap: () async {
            final res = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)),
            );
            if (res == true) _loadInitialData();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // STT (Số thứ tự)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: borderColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.bold,
                            color: borderColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // HÌNH ẢNH NHẬN MÁY
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: Stack(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
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
                                    Icons.phone_android,
                                    color: Colors.grey,
                                    size: 24,
                                  )
                                : null,
                          ),
                          if (images.length > 1)
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "+${images.length - 1}",
                                  style: AppTextStyles.overline.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Thông tin chính
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.model,
                            style: AppTextStyles.subtitle1.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 6),
                
                // Info chips row
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // Trạng thái (đưa xuống chip để tiêu đề hiển thị được nhiều hơn)
                    _repairInfoChip(
                      _getStatusLabel(
                        r.status,
                        pendingApproval: r.pendingDeliveryApproval,
                      ),
                      _getStatusColor(
                        r.status,
                        pendingApproval: r.pendingDeliveryApproval,
                      ),
                      textColor: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    // Khách hàng + SĐT (gom xuống chip)
                    _repairInfoChip(
                      '👤 ${r.customerName} • ${r.phone}',
                      Colors.grey.shade200,
                      textColor: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                    // Ngày tạo
                    _repairInfoChip(
                      '⏱ ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))}',
                      Colors.grey.shade200,
                      textColor: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                    // Lỗi / Vấn đề
                    _repairInfoChip(
                      '🔧 ${r.issue.split('|').first}',
                      Colors.red.shade100,
                    ),
                    // Giá
                    if (r.price > 0)
                      _repairInfoChip(
                        '💰 ${NumberFormat.compact(locale: 'vi').format(r.price)}đ',
                        Colors.green.shade100,
                      ),
                    // Ghi chú
                    if (r.accessories.isNotEmpty)
                      _repairInfoChip(
                        '📝 ${r.accessories}',
                        Colors.blue.shade100,
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
  
  Widget _repairInfoChip(
    String text,
    Color color, {
    Color textColor = Colors.black,
    FontWeight fontWeight = FontWeight.w500,
    double fontSize = 10,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text, 
        style: AppTextStyles.caption.copyWith(
          color: textColor,
          fontWeight: fontWeight,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _getStatusLabel(int status, {bool pendingApproval = false}) {
    if (status == 3 && pendingApproval) {
      return "CHỜ DUYỆT";
    }
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

  Color _getStatusColor(int status, {bool pendingApproval = false}) {
    if (status == 3 && pendingApproval) {
      return Colors.deepOrange;
    }
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
