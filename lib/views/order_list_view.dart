import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_text_styles.dart';
import '../models/repair_model.dart';
import '../models/shop_settings_model.dart';
import '../services/event_bus.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../services/encryption_service.dart';
import '../services/sync_service.dart';
import '../services/firestore_service.dart';
import '../utils/vietnamese_utils.dart';
import '../utils/money_utils.dart';
import '../widgets/gradient_fab.dart';
import 'repair_detail_view.dart';
import 'create_repair_order_view.dart';
import 'global_search_view.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';
import '../theme/app_colors.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/app_cached_image.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  StreamSubscription<String>? _eventSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _repairRealtimeSubscription;
  final Map<String, Repair> _repairsByFirestoreId = <String, Repair>{};
  String? _listeningShopId;
  bool _receivedServerSnapshot = false;
  bool _isRealtimeConnected = false;
  bool _useRealtimeIndexFallback = false;

  AppLocalizations get loc => AppLocalizations.of(context)!;

  List<Repair> _displayedRepairs = [];
  bool _isLoading = true;
  String _currentSearch = "";

  // Shop settings for dynamic terminology
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  // Date filter
  String _timeFilter = 'all'; // all, today, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Status filter - Set để cho phép chọn nhiều trạng thái
  Set<int> _statusFilters = {}; // Empty = all, {1,2} = tiếp nhận + đang sửa
  bool _filterPendingApproval = false; // Lọc đơn chờ duyệt giao
  bool _canDelete = false;
  bool _canViewCostPrice = false;

  bool get canDelete => _canDelete;

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
    _loadShopSettings();
    _loadDeletePermission();
    unawaited(_startRealtimeRepairsListener(forceRestart: true));

    // Chỉ rebind listener khi đổi shop hoặc refresh dữ liệu tổng.
    _eventSubscription = EventBus().stream.listen((event) {
      if (!mounted) return;

      if (event == EventBus.shopChanged || event == EventBus.dataRefresh) {
        unawaited(_startRealtimeRepairsListener(forceRestart: true));
        return;
      }

      if (event == EventBus.repairsChanged) {
        unawaited(_showPendingLocalRepairsWhileWaitingRealtime());
      }
    });
  }

  Future<void> _loadDeletePermission() async {
    try {
      final results = await Future.wait([
        UserService.isCurrentUserAdmin(),
        UserService.getCurrentUserPermissions(),
      ]);
      if (!mounted) return;
      setState(() {
        _canDelete = results[0] as bool;
        final perms = results[1] as Map<String, dynamic>;
        _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _canDelete = widget.role == 'admin' || widget.role == 'owner',
      );
    }
  }

  bool _isGsStoragePath(String path) {
    return StorageService.isGsStoragePath(path);
  }

  bool _isStorageRelativePath(String path) {
    return StorageService.isStorageRelativePath(path);
  }

  Future<String?> _resolveDisplayImagePath(String path) async {
    return StorageService.resolveDisplayUrl(path);
  }

  @override
  void dispose() {
    _repairRealtimeSubscription?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startRealtimeRepairsListener({bool forceRestart = false}) async {
    final shopId = (await UserService.getCurrentShopId())?.trim();
    if (!mounted) return;

    if (shopId == null || shopId.isEmpty) {
      setState(() {
        _isLoading = false;
        _isRealtimeConnected = false;
        _listeningShopId = null;
        _repairsByFirestoreId.clear();
        _displayedRepairs = [];
      });
      return;
    }

    if (!forceRestart &&
        _repairRealtimeSubscription != null &&
        _listeningShopId == shopId) {
      return;
    }

    await _repairRealtimeSubscription?.cancel();
    _repairRealtimeSubscription = null;
    _receivedServerSnapshot = false;
    _listeningShopId = shopId;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _isRealtimeConnected = false;
      });
    }

    if (_useRealtimeIndexFallback) {
      // Fallback mode: avoid limit so newly-created orders are not missed.
      // We sort/filter on client side after snapshot is received.
      debugPrint(
        'ℹ️ [OrderListView] Realtime fallback mode active (no orderBy/limit) due missing index',
      );
    }

    _repairRealtimeSubscription = FirestoreService.watchRepairsByShop(
      shopId,
      useIndexedQuery: !_useRealtimeIndexFallback,
    ).listen(
      (snapshot) {
        unawaited(_handleRealtimeSnapshot(snapshot));
      },
      onError: (error) {
        debugPrint('❌ [OrderListView] Realtime listener lỗi: $error');

        final errorText = error.toString().toLowerCase();
        final isMissingIndex =
            (error is FirebaseException && error.code == 'failed-precondition') ||
            errorText.contains('requires an index');

        if (isMissingIndex && !_useRealtimeIndexFallback) {
          debugPrint(
            '⚠️ [OrderListView] Thiếu index cho query realtime, chuyển sang fallback không orderBy(updatedAt)',
          );
          _useRealtimeIndexFallback = true;
          unawaited(_startRealtimeRepairsListener(forceRestart: true));
          return;
        }

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _isRealtimeConnected = false;
        });

        unawaited(_showPendingLocalRepairsWhileWaitingRealtime());
      },
    );

    unawaited(_showPendingLocalRepairsWhileWaitingRealtime());
  }

  Repair? _parseRepairDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) return null;
      final raw = Map<String, dynamic>.from(data);
      final decrypted = EncryptionService.decryptMap(raw);
      if (decrypted['deleted'] == true) return null;

      SyncService.convertTimestampFieldsPublic(decrypted);
      decrypted['firestoreId'] = doc.id;
      decrypted['isSynced'] = 1;

      return Repair.fromMap(decrypted);
    } catch (e) {
      debugPrint('⚠️ [OrderListView] Parse repair ${doc.id} lỗi: $e');
      return null;
    }
  }

  Future<bool> _mergePendingLocalRepairsIntoCache() async {
    final shopId = (await UserService.getCurrentShopId())?.trim();
    if (shopId == null || shopId.isEmpty) {
      return false;
    }

    try {
      final dbConn = await db.database;
      final recentThreshold = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;

      final rows = await dbConn.query(
        'repairs',
        where: 'isSynced = 0 AND deleted = 0 AND createdAt >= ?',
        whereArgs: [recentThreshold],
        orderBy: 'createdAt DESC',
        limit: 150,
      );

      var hasChanges = false;
      for (final row in rows) {
        final localRepair = Repair.fromMap(Map<String, dynamic>.from(row));
        final localFirestoreId = (localRepair.firestoreId ?? '').trim();
        if (localFirestoreId.isEmpty) continue;

        final existing = _repairsByFirestoreId[localFirestoreId];
        if (existing == null) {
          _repairsByFirestoreId[localFirestoreId] = localRepair;
          hasChanges = true;
          continue;
        }

        final localStamp = localRepair.lastCaredAt ?? localRepair.createdAt;
        final existingStamp = existing.lastCaredAt ?? existing.createdAt;
        if (localStamp > existingStamp && !localRepair.isSynced) {
          _repairsByFirestoreId[localFirestoreId] = localRepair;
          hasChanges = true;
        }
      }

      return hasChanges;
    } catch (e) {
      debugPrint('⚠️ [OrderListView] Merge pending local repairs lỗi: $e');
      return false;
    }
  }

  Future<void> _showPendingLocalRepairsWhileWaitingRealtime() async {
    final hasChanges = await _mergePendingLocalRepairsIntoCache();
    if (!hasChanges || !mounted) return;
    _rebuildDisplayedRepairs(markLoaded: true);
  }

  Future<void> _handleRealtimeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (snapshot.metadata.isFromCache && _receivedServerSnapshot) {
      return;
    }

    if (!snapshot.metadata.isFromCache) {
      _receivedServerSnapshot = true;
    }

    var hasChanges = false;
    final upsertFutures = <Future<void>>[];

    if (_repairsByFirestoreId.isEmpty &&
        snapshot.docChanges.length == snapshot.docs.length) {
      _repairsByFirestoreId.clear();
      for (final doc in snapshot.docs) {
        final repair = _parseRepairDoc(doc);
        if (repair == null) continue;
        _repairsByFirestoreId[doc.id] = repair;
        upsertFutures.add(db.upsertRepair(repair));
      }
      hasChanges = true;
    } else {
      for (final change in snapshot.docChanges) {
        final id = change.doc.id;
        if (change.type == DocumentChangeType.removed) {
          if (_repairsByFirestoreId.remove(id) != null) {
            hasChanges = true;
          }
          continue;
        }

        final repair = _parseRepairDoc(change.doc);
        if (repair == null) {
          if (_repairsByFirestoreId.remove(id) != null) {
            hasChanges = true;
          }
          continue;
        }

        _repairsByFirestoreId[id] = repair;
        upsertFutures.add(db.upsertRepair(repair));
        hasChanges = true;
      }
    }

    if (upsertFutures.isNotEmpty) {
      await Future.wait(upsertFutures);
    }

    final mergedPendingLocal = await _mergePendingLocalRepairsIntoCache();

    if (!mounted) return;

    if (hasChanges || mergedPendingLocal) {
      _rebuildDisplayedRepairs(markLoaded: true);
    } else if (_isLoading || !_isRealtimeConnected) {
      setState(() {
        _isLoading = false;
        _isRealtimeConnected = true;
      });
    }
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  void _rebuildDisplayedRepairs({bool markLoaded = false}) {
    final all = _repairsByFirestoreId.values.toList()..sort(_compareRepairs);
    final filtered = _applyFilters(all);
    final keyword = _currentSearch.trim();

    final searched = keyword.isEmpty
        ? filtered
        : filtered
              .where(
                (r) =>
                    VietnameseUtils.containsVietnamese(r.customerName, keyword) ||
                    r.phone.contains(keyword) ||
                    VietnameseUtils.containsVietnamese(r.model, keyword) ||
                    VietnameseUtils.containsVietnamese(r.issue, keyword) ||
                    (r.notes != null &&
                        VietnameseUtils.containsVietnamese(r.notes!, keyword)),
              )
              .toList();

    if (!mounted) return;

    setState(() {
      _displayedRepairs = searched;
      if (markLoaded || _isLoading || !_isRealtimeConnected) {
        _isLoading = false;
        _isRealtimeConnected = true;
      }
    });
  }

  void _removeRepairFromRealtimeCache(String? firestoreId) {
    final id = (firestoreId ?? '').trim();
    if (id.isEmpty) return;
    final removed = _repairsByFirestoreId.remove(id);
    if (removed != null) {
      _rebuildDisplayedRepairs();
    }
  }

  void _onSearch(String val) {
    _currentSearch = val;
    _rebuildDisplayedRepairs();
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
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'BỘ LỌC',
                    style: AppTextStyles.headline3.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                    child: Text(loc.resetAll),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // STATUS FILTER - CHO PHÉP CHỌN NHIỀU
              Text(
                loc.statusSelectMultiple,
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
                  _statusChipMulti(loc.all, null, setSheetState),
                  _statusChipMulti(
                    loc.received,
                    1,
                    setSheetState,
                    AppColors.repairReceived,
                  ),
                  _statusChipMulti(
                    loc.repairing,
                    2,
                    setSheetState,
                    AppColors.repairRepairing,
                  ),
                  _statusChipMulti(
                    loc.repairDone,
                    3,
                    setSheetState,
                    AppColors.repairDone,
                  ),
                  _pendingApprovalChip(setSheetState),
                  _statusChipMulti(
                    loc.delivered,
                    4,
                    setSheetState,
                    AppColors.repairDelivered,
                  ),
                ],
              ),
              if (_statusFilters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    loc.selectedStatuses(_statusFilters.length),
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 10),

              // TIME FILTER
              Text(
                loc.timeFilter,
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
                        borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 10),
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
                  child: Text(
                    loc.apply,
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected && value != null)
              const Padding(
                padding: EdgeInsets.only(right: 4),
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
    const color = Colors.deepOrange;
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
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
          borderRadius: BorderRadius.circular(12),
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
              hasAccountingData || hasPartsUsed
                  ? Icons.warning_amber_rounded
                  : Icons.delete_forever,
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
                  Text(
                    r.model,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                    const Icon(
                      Icons.attach_money,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _canViewCostPrice
                            ? loc.orderHasAccounting(
                                _formatMoney(r.price),
                                _formatMoney(r.cost),
                              )
                            : loc.orderHasAccounting(
                                _formatMoney(r.price),
                                '***',
                              ),
                        style: const TextStyle(fontSize: 14),
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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.build, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          loc.orderHasParts,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.partsUsed,
                      style: const TextStyle(fontSize: 13, color: Colors.blue),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.partsWillReturn,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
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
      case 1:
        return loc.received;
      case 2:
        return loc.repairing;
      case 3:
        return loc.repairDone;
      case 4:
        return loc.delivered;
      default:
        return 'Unknown';
    }
  }

  String _formatMoney(int amount) {
    if (amount == 0) return '0đ';
    return '${NumberFormat('#,###', 'vi_VN').format(amount)}đ';
  }

  Future<void> _executeDelete(
    BuildContext ctx,
    Repair r,
    String password,
  ) async {
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
          await FirestoreService.deleteRepair(repairFirestoreId);
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
      final partsInfo = r.partsUsed.isNotEmpty
          ? loc.returnedParts(r.partsUsed)
          : '';
      await db.logAction(
        userId: user.uid,
        userName: user.email?.split('@').first.toUpperCase() ?? 'NV',
        action: loc.deleteRepairAction,
        type: 'REPAIR',
        targetId: repairFirestoreId,
        desc: loc.deletedRepairDesc(
          r.model,
          r.customerName,
          r.phone,
          partsInfo,
        ),
      );

      // KHÔNG cần enqueue delete nữa vì đã soft delete trực tiếp trên Firestore rồi
      // Việc enqueue delete sẽ tạo pending sync không cần thiết
      // Realtime listener sẽ tự đồng xóa local khi nhận deleted=true từ Firestore
      debugPrint(
        '✅ Repair deleted directly on Firestore - no need for sync queue',
      );

      navigator.pop();
      _removeRepairFromRealtimeCache(repairFirestoreId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.partsUsed.isNotEmpty
                ? '✅ Đã xóa đơn và hoàn trả phụ tùng về kho'
                : '✅ Đã xóa đơn thành công',
          ),
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
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "DANH SÁCH ${_terms.productLabel.toUpperCase()} SỬA",
              style: AppTextStyles.headline2.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '$count ${_terms.productLabel.toLowerCase()} • $pendingCount đang xử lý',
              style: AppTextStyles.caption.copyWith(color: Colors.white70),
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
            icon: const Icon(Icons.file_download_outlined, color: Colors.white),
            tooltip: 'Xuất Excel đơn sửa',
            onPressed: () async {
              final result = await ExportDateFilterDialog.show(
                context,
                title: 'Xuất đơn sửa',
              );
              if (result == null) return;
              if (!mounted) return;
              await ExcelExportHelper.exportRepairs(
                context,
                startMs: result['startMs'],
                endMs: result['endMs'],
              );
            },
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            // Active filter chip
            if (_activeFilterCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                  hintText: "Tìm khách, model, lỗi, SĐT...",
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _buildListInsightBar(),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _displayedRepairs.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i < _displayedRepairs.length) {
                          return _buildRepairCard(_displayedRepairs[i], i + 1);
                        }
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              loc.displayedRepairs(_displayedRepairs.length),
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: GradientFab.purple(
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateRepairOrderView(role: widget.role),
            ),
          );
          if (res == true) {
            _rebuildDisplayedRepairs();
          }
        },
        icon: Icons.phone_android,
        label: 'Nhận ${_terms.productLabel.toLowerCase()}',
      ),
    );
  }

  Widget _buildRepairCard(Repair r, int index) {
    final List<String> images = _collectRepairImages(r);
    final String firstImage = _pickBestPreviewImage(images);
    final int displayCost = r.totalCost;
    final int displayProfit = r.price - displayCost;

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
        bgColor = Colors.blue.shade50;
        borderColor = Colors.blue.shade300;
        break;
      default:
        bgColor = Colors.grey.shade50;
        borderColor = Colors.grey.shade300;
    }

    final bool isAltRow = index.isEven;
    final Color cardColor = isAltRow
        ? bgColor
        : Color.alphaBlend(const Color(0x14000000), bgColor);

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
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: cardColor,
        elevation: 1.5,
        shadowColor: borderColor.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: 1.2),
        ),
        child: InkWell(
          onTap: () async {
            final res = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)),
            );
            if (res == true) {
              _rebuildDisplayedRepairs();
            }
          },
          onLongPress: () {
            if (!canDelete) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chỉ quản lý/chủ shop mới có quyền xóa đơn'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            if (r.status >= 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '❌ Không thể xóa đơn ĐÃ GIAO. Chỉ xóa đơn chưa giao.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            _confirmDelete(r);
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
                              image:
                                  firstImage.isNotEmpty &&
                                      !_isGsStoragePath(firstImage) &&
                                      !_isStorageRelativePath(firstImage) &&
                                      ((firstImage.startsWith('http') ||
                                              firstImage.startsWith('blob:') ||
                                              firstImage.startsWith('data:')) ||
                                          !kIsWeb)
                                  ? DecorationImage(
                                      image:
                                          (firstImage.startsWith('http') ||
                                              firstImage.startsWith('blob:') ||
                                              firstImage.startsWith('data:'))
                                          ? CachedNetworkImageProvider(
                                              firstImage,
                                            )
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
                                : ((_isGsStoragePath(firstImage) ||
                                          _isStorageRelativePath(firstImage))
                                      ? FutureBuilder<String?>(
                                          future: _resolveDisplayImagePath(
                                            firstImage,
                                          ),
                                          builder: (context, snapshot) {
                                            final url = snapshot.data;
                                            if (url == null || url.isEmpty) {
                                              return const Icon(
                                                Icons.broken_image,
                                                color: Colors.grey,
                                                size: 20,
                                              );
                                            }
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: AppCachedImage(
                                                imageUrl: url,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 100,
                                                memCacheHeight: 100,
                                              ),
                                            );
                                          },
                                        )
                                      : null),
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
                              color: const Color(0xFF0F172A),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // KTV sửa chữa (header) - luôn hiển thị
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (r.repairedBy != null && r.repairedBy!.isNotEmpty)
                            ? Colors.purple.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (r.repairedBy != null && r.repairedBy!.isNotEmpty)
                            ? '👨‍🔧 ${r.repairedBy!}'
                            : '👨‍🔧 Chưa có KTV',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              (r.repairedBy != null && r.repairedBy!.isNotEmpty)
                              ? Colors.purple.shade800
                              : Colors.grey.shade600,
                        ),
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
                      fontSize: 12,
                    ),
                    // Khách hàng / SĐT: tách riêng để tránh overflow trên màn hình nhỏ.
                    if (r.customerName.trim().isNotEmpty)
                      _repairInfoChip(
                        '👤 ${r.customerName}',
                        Colors.blueGrey.shade50,
                        textColor: Colors.blueGrey.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    if (r.phone.trim().isNotEmpty)
                      _repairInfoChip(
                        '📞 ${r.phone}',
                        Colors.blueGrey.shade50,
                        textColor: Colors.blueGrey.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    // Ngày tạo
                    _repairInfoChip(
                      '⏱ ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))}',
                      Colors.blueGrey.shade50,
                      textColor: Colors.blueGrey.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    // Lỗi / Vấn đề
                    if (r.issue.isNotEmpty)
                      _repairInfoChip(
                        '🔧 ${r.issue.split('|').first}',
                        Colors.red.shade100,
                        maxLines: 2,
                      ),
                    // Mô tả lỗi chi tiết (phần sau dấu |)
                    if (r.issue.contains('|') && r.issue.split('|').length > 1)
                      _repairInfoChip(
                        '📋 ${r.issue.split('|').sublist(1).join(', ')}',
                        Colors.orange.shade50,
                        textColor: Colors.orange.shade900,
                        maxLines: 2,
                      ),
                    // Giá thu khách (chỉ hiện khi có giá > 0)
                    if (r.price > 0)
                      _repairInfoChip(
                        '💰 ${MoneyUtils.formatCompactCurrency(r.price)}đ',
                        Colors.green.shade100,
                        textColor: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    // Giá vốn + Lợi nhuận (chỉ hiện với người có quyền)
                    if (_canViewCostPrice && displayCost > 0)
                      _repairInfoChip(
                        '🏷 Vốn ${MoneyUtils.formatCompactCurrency(displayCost)}đ',
                        Colors.blue.shade50,
                        textColor: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    if (_canViewCostPrice && r.price > 0 && displayCost > 0)
                      _repairInfoChip(
                        displayProfit >= 0
                            ? '📈 Lãi ${MoneyUtils.formatCompactCurrency(displayProfit)}đ'
                            : '📉 Lỗ ${MoneyUtils.formatCompactCurrency(displayProfit.abs())}đ',
                        displayProfit >= 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        textColor: displayProfit >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    // Ghi chú KTV (nếu có) - giới hạn 2 dòng tránh overflow
                    if (r.notes != null && r.notes!.isNotEmpty)
                      _repairInfoChip(
                        '📝 ${r.notes!}',
                        Colors.amber.shade100,
                        textColor: Colors.amber.shade900,
                        maxLines: 2,
                      ),
                    // Ghi chú phụ kiện (nếu có)
                    if (r.accessories.isNotEmpty)
                      _repairInfoChip(
                        '🧰 ${r.accessories}',
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

  List<String> _collectRepairImages(Repair r) {
    final result = <String>[];

    void addCandidate(String? value) {
      if (value == null) return;
      var s = value.trim();
      if (s.isEmpty) return;
      if ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.startsWith('[') && s.endsWith(']')) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.isEmpty) return;
      if (!result.contains(s)) {
        result.add(s);
      }
    }

    for (final image in r.receiveImages) {
      addCandidate(image);
    }

    final raw = (r.imagePath ?? '').trim();
    if (raw.isNotEmpty) {
      final parts = raw
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      for (final part in parts) {
        addCandidate(part);
      }
    }

    return result.where((path) {
      if (StorageService.isResolvableDisplayPath(path)) return true;
      return !kIsWeb;
    }).toList();
  }

  String _pickBestPreviewImage(List<String> images) {
    if (images.isEmpty) return '';

    for (final image in images) {
      if (_isWebPreviewSource(image)) {
        return image;
      }
    }

    if (kIsWeb) {
      // On web, local file paths cannot be rendered across sessions/devices.
      return '';
    }

    return images.first;
  }

  bool _isWebPreviewSource(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('gs://') ||
        lower.startsWith('repairs/') ||
        lower.startsWith('/repairs/') ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:');
  }

  Widget _repairInfoChip(
    String text,
    Color color, {
    Color textColor = Colors.black,
    FontWeight fontWeight = FontWeight.w500,
    double fontSize = 10,
    int maxLines = 1,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width - 100).clamp(
          0,
          400,
        ), // Prevent overflow
      ),
      child: Container(
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
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildListInsightBar() {
    final modeLabel = _isRealtimeConnected
      ? (_useRealtimeIndexFallback
            ? 'Realtime Firestore (fallback no-index)'
            : 'Realtime Firestore • 50 đơn mới nhất')
      : 'Đang kết nối realtime...';
    final statusLabel = _isRealtimeConnected
      ? 'Đồng bộ tức thì giữa thiết bị'
      : 'Chưa nhận snapshot server';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, size: 14, color: Color(0xFF2962FF)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$modeLabel • Đang hiển thị ${_displayedRepairs.length} đơn',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              color: _isRealtimeConnected
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(int status, {bool pendingApproval = false}) {
    if (status == 3 && pendingApproval) {
      return loc.statusPendingApproval;
    }
    switch (status) {
      case 1:
        return loc.statusReceivedUpper;
      case 2:
        return loc.statusRepairingUpper;
      case 3:
        return loc.statusRepairDoneUpper;
      case 4:
        return loc.statusDeliveredUpper;
      default:
        return loc.statusOther;
    }
  }

  Color _getStatusColor(int status, {bool pendingApproval = false}) {
    if (status == 3 && pendingApproval) {
      return AppColors.repairPendingApproval;
    }
    switch (status) {
      case 1:
        return AppColors.repairReceived;
      case 2:
        return AppColors.repairRepairing;
      case 3:
        return AppColors.repairDone;
      case 4:
        return AppColors.repairDelivered;
      default:
        return Colors.grey;
    }
  }
}
