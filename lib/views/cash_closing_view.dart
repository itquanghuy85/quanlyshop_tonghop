import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../models/sale_order_model.dart';
import '../models/repair_model.dart';
import '../models/shop_settings_model.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../services/notification_service.dart';
import '../services/category_service.dart';
import '../services/event_bus.dart';
import '../services/daily_financial_analysis_service.dart';
import '../services/firestore_write_helper.dart';
import '../utils/money_utils.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/custom_app_bar.dart';
import 'sale_detail_view.dart';
import 'repair_detail_view.dart';

/// Helper: Check if debtType is "Shop owes" (NCC) - includes SHOP_OWES and OTHER_SHOP_OWES
bool _isShopOwesDebt(String? debtType) {
  if (debtType == null) return false;
  return debtType == 'SHOP_OWES' ||
      debtType == 'OTHER_SHOP_OWES' ||
      debtType == 'OWED';
}

/// Helper: Check if debtType is "Customer owes" - includes CUSTOMER_OWES and OTHER_CUSTOMER_OWES
bool _isCustomerOwesDebt(String? debtType) {
  if (debtType == null) return true; // default
  return debtType == 'CUSTOMER_OWES' || debtType == 'OTHER_CUSTOMER_OWES';
}

/// Trang chốt quỹ chuyên nghiệp - Thiết kế lại hoàn toàn
class CashClosingView extends StatefulWidget {
  final int initialTab;
  final bool showOnlyTransactions;
  const CashClosingView({
    super.key,
    this.initialTab = 0,
    this.showOnlyTransactions = false,
  });

  @override
  State<CashClosingView> createState() => _CashClosingViewState();
}

class _CashClosingViewState extends State<CashClosingView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  // Data
  List<SaleOrder> _sales = [];
  List<Repair> _repairs = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _debtPayments = [];
  List<Map<String, dynamic>> _supplierImports = [];
  List<Map<String, dynamic>> _supplierPayments = [];
  List<Map<String, dynamic>> _repairPartnerPayments =
      []; // FIX: Thêm thanh toán đối tác sửa chữa
  List<Map<String, dynamic>> _salesReturns = []; // Trả hàng (sales returns)
  Map<String, String> _debtTypeMap =
      {}; // FIX: Map từ debtId/firestoreId -> debtType
  Map<String, dynamic>? _previousDayClosing;
  Map<String, dynamic>? _todayClosing;

  // Shop settings for multi-industry
  ShopSettings? _shopSettings;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;

  final cashEndCtrl = TextEditingController();
  final bankEndCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  StreamSubscription? _closingSubscription;
  StreamSubscription<String>?
  _eventBusSub; // Replace duplicate Firestore listeners with EventBus

  // Debounce để tránh load quá nhiều lần
  Timer? _debounceTimer;
  bool _isLoadingFromFirestore = false;

  // Transaction filter/search (showOnlyTransactions mode)
  String _txSearchQuery = '';
  String? _txTypeFilter; // null = all
  final _txSearchController = TextEditingController();
  DateTime? _txEndDate; // null = single date, set = date range
  bool _hasPermission = false;
  bool _canViewCostPrice = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _tabController = TabController(
      length: widget.showOnlyTransactions ? 1 : 4,
      vsync: this,
      initialIndex: widget.showOnlyTransactions
          ? 0
          : widget.initialTab.clamp(0, 3),
    );
    _loadShopSettings();
    _loadAllData();
    _initRealTimeSync();
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) setState(() => _shopSettings = settings);
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _hasPermission = perms['allowViewRevenue'] ?? false;
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _closingSubscription?.cancel();
    _eventBusSub?.cancel();
    _tabController.dispose();
    cashEndCtrl.dispose();
    bankEndCtrl.dispose();
    noteCtrl.dispose();
    _txSearchController.dispose();
    super.dispose();
  }

  /// Debounced reload — chỉ đọc local DB (SyncService đã sync Firestore → local)
  void _scheduleReload() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadAllDataFromLocalDB();
      }
    });
  }

  Future<void> _initRealTimeSync() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return;

    // Các collection đã được SyncService sync + emit EventBus
    // → sử dụng EventBus thay vì tạo duplicate Firestore listeners
    _eventBusSub = EventBus().stream.listen((event) {
      if (event == 'sales_changed' ||
          event == EventBus.repairsChanged ||
          event == 'expenses_changed' ||
          event == 'debts_changed' ||
          event == 'cash_closings_changed' ||
          event == 'sales_returns_changed' ||
          event == 'payment_requests_changed' ||
          event == 'repair_partner_payments_changed' ||
          event == 'debt_payments_changed' ||
          event == EventBus.financialChanged ||
          event == EventBus.shopChanged) {
        debugPrint(
          '💰 [CashClosingView] Nhận event "$event" → debounce reload local DB',
        );
        _scheduleReload();
      }
    });
  }

  /// Load dữ liệu trực tiếp từ Firestore để đảm bảo đồng bộ giữa các thiết bị
  Future<void> _loadAllDataFromFirestore() async {
    if (!mounted || _isLoadingFromFirestore) return;
    _isLoadingFromFirestore = true;
    // Don't show loading spinner if we already have local data
    if (_sales.isEmpty && _repairs.isEmpty && _expenses.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        _isLoadingFromFirestore = false;
        if (mounted) {
          await _loadAllDataFromLocalDB();
        } else {
          _isLoading = false;
        }
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // FIX BUG-CC-001: Tất cả collections đều là ROOT collections với shopId filter
      // Đồng nhất với cách FirestoreService và SyncService lưu dữ liệu
      final results = await Future.wait([
        // sales - ROOT collection
        firestore.collection('sales').where('shopId', isEqualTo: shopId).get(),
        // repairs - ROOT collection
        firestore
            .collection('repairs')
            .where('shopId', isEqualTo: shopId)
            .get(),
        // expenses - ROOT collection
        firestore
            .collection('expenses')
            .where('shopId', isEqualTo: shopId)
            .get(),
        // debt_payments - ROOT collection
        firestore
            .collection('debt_payments')
            .where('shopId', isEqualTo: shopId)
            .get(),
        // supplier_payments - ROOT collection
        firestore
            .collection('supplier_payments')
            .where('shopId', isEqualTo: shopId)
            .get(),
        // FIX: repair_partner_payments - thanh toán đối tác sửa chữa
        firestore
            .collection('repair_partner_payments')
            .where('shopId', isEqualTo: shopId)
            .get(),
        // FIX: debts - để lookup debtType cho debt_payments
        firestore.collection('debts').where('shopId', isEqualTo: shopId).get(),
        // sales_returns - trả hàng
        firestore
            .collection('sales_returns')
            .where('shopId', isEqualTo: shopId)
            .get(),
      ]).timeout(const Duration(seconds: 10));

      // Parse sales - filter deleted
      final sales = results[0].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return SaleOrder.fromMap(data);
          })
          .toList();

      // Parse repairs - filter deleted
      final repairs = results[1].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return Repair.fromMap(data);
          })
          .toList();

      // Parse expenses - filter deleted
      final expenses = results[2].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // Parse debt_payments - filter deleted
      final debtPayments = results[3].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // Parse supplier_payments - filter deleted
      final supplierPayments = results[4].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // FIX: Parse repair_partner_payments - thanh toán đối tác sửa chữa
      // Filter deleted: accept deleted == null, 0, false, but reject true or 1
      final repairPartnerPayments = results[5].docs
          .where((doc) {
            final deleted = doc.data()['deleted'];
            return deleted != true && deleted != 1;
          })
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // DEBUG: Log repair partner payments loaded
      debugPrint('=== REPAIR PARTNER PAYMENTS LOADED ===');
      debugPrint('Total count: ${repairPartnerPayments.length}');
      for (var p in repairPartnerPayments) {
        debugPrint(
          '  - ${p['partnerName']}: ${p['amount']}đ, paidAt: ${p['paidAt']}, method: ${p['paymentMethod']}',
        );
      }

      // FIX: Parse debts để tạo lookup map cho debtType
      final debtTypeMap = <String, String>{};
      for (var doc in results[6].docs) {
        final data = doc.data();
        final firestoreId = doc.id;
        final debtType =
            data['type'] as String? ?? data['debtType'] as String? ?? '';
        if (debtType.isNotEmpty) {
          debtTypeMap[firestoreId] = debtType;
          // Also map by local id if available
          final localId = data['id']?.toString();
          if (localId != null) debtTypeMap[localId] = debtType;
        }
      }
      debugPrint('=== DEBT TYPE MAP BUILT: ${debtTypeMap.length} entries ===');

      // Parse sales_returns
      final salesReturns = results[7].docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // FIX BUG-007: Load supplier imports từ Firestore thay vì SQLite
      // Để đảm bảo sync giữa các thiết bị (Device A == Device B)
      final supplierImportsSnapshot = await firestore
          .collection('supplier_import_history')
          .where('shopId', isEqualTo: shopId)
          .get()
          .timeout(const Duration(seconds: 10));
      final supplierImports = supplierImportsSnapshot.docs
          .where((doc) => doc.data()['deleted'] != true)
          .map((doc) {
            final data = doc.data();
            data['firestoreId'] = doc.id;
            _convertTimestampFields(data);
            return data;
          })
          .toList();

      // Load closings - FIX BUG-CC-001: cash_closings cũng là ROOT collection
      final yesterday = _selectedDate.subtract(const Duration(days: 1));
      final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);
      final todayKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final closingResults = await Future.wait([
        firestore
            .collection('cash_closings')
            .doc('closing_${shopId}_$yesterdayKey')
            .get(),
        firestore
            .collection('cash_closings')
            .doc('closing_${shopId}_$todayKey')
            .get(),
      ]);

      // FIX: Fallback to local DB if Firestore closing records don't exist
      // This ensures data saved locally (offline) is still reflected
      var previousClosing = closingResults[0].exists
          ? closingResults[0].data()
          : null;
      var todayClosing = closingResults[1].exists
          ? closingResults[1].data()
          : null;

      debugPrint(
        '📖 [LOAD] Firestore closing for $yesterdayKey: ${previousClosing != null ? 'FOUND cashEnd=${previousClosing!['cashEnd']}' : 'NOT FOUND'}',
      );
      debugPrint(
        '📖 [LOAD] Firestore closing for $todayKey: ${todayClosing != null ? 'FOUND' : 'NOT FOUND'}',
      );

      // FIX: Convert Timestamp fields in closing data from Firestore
      if (previousClosing != null) _convertTimestampFields(previousClosing);
      if (todayClosing != null) _convertTimestampFields(todayClosing);

      // Fallback to local DB for closing records not yet synced to Firestore
      if (previousClosing == null) {
        previousClosing = await db.getClosingByDateKey(yesterdayKey);
        debugPrint(
          '📖 [LOAD] Local DB fallback for $yesterdayKey: ${previousClosing != null ? 'FOUND cashEnd=${previousClosing['cashEnd']}, bankEnd=${previousClosing['bankEnd']}' : 'NOT FOUND'}',
        );
      }
      if (todayClosing == null) {
        todayClosing = await db.getClosingByDateKey(todayKey);
        debugPrint(
          '📖 [LOAD] Local DB fallback for $todayKey: ${todayClosing != null ? 'FOUND' : 'NOT FOUND'}',
        );
      }

      // ═══════════════════════════════════════════════════════════════════
      // MERGE LOCAL DB: Gộp dữ liệu chưa sync từ Local DB vào Firestore
      // để Sổ Quỹ luôn khớp với Home (cả hai dùng cùng nguồn dữ liệu)
      // Dedup by firestoreId để tránh trùng lặp
      // ═══════════════════════════════════════════════════════════════════

      // Merge sales
      final localSales = await db.getAllSales();
      final seenSaleIds = sales
          .map((s) => s.firestoreId)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final ls in localSales) {
        final fid = ls.firestoreId;
        if (fid != null && fid.isNotEmpty && seenSaleIds.add(fid)) {
          sales.add(ls);
        }
      }

      // Merge repairs
      final localRepairs = await db.getAllRepairs();
      final seenRepairIds = repairs
          .map((r) => r.firestoreId)
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final lr in localRepairs) {
        final fid = lr.firestoreId;
        if (fid != null && fid.isNotEmpty && seenRepairIds.add(fid)) {
          repairs.add(lr);
        }
      }

      // Merge expenses
      final localExpenses = await db.getAllExpenses();
      final seenExpenseIds = expenses
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final e in localExpenses) {
        final fid = e['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenExpenseIds.add(fid)) {
          expenses.add(e);
        }
      }

      // Merge debt_payments (critical for Trả nợ NCC + Thu nợ khách)
      final localDebtPayments = await db.getAllDebtPaymentsWithDetails();
      final seenDebtPaymentIds = debtPayments
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final dp in localDebtPayments) {
        final fid = dp['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenDebtPaymentIds.add(fid)) {
          debtPayments.add(dp);
        }
      }

      // Merge supplier_payments
      final localSupplierPayments = await db.getAllSupplierPayments();
      final seenSupplierPaymentIds = supplierPayments
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final sp in localSupplierPayments) {
        final fid = sp['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenSupplierPaymentIds.add(fid)) {
          supplierPayments.add(sp);
        }
      }

      // Merge repair_partner_payments
      final localPartnerPayments = await db.getRepairPartnerPaymentsForSync();
      final seenPartnerPaymentIds = repairPartnerPayments
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final pp in localPartnerPayments) {
        final fid = pp['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenPartnerPaymentIds.add(fid)) {
          repairPartnerPayments.add(pp);
        }
      }

      // Merge supplier_import_history
      final localSupplierImports = await db.getAllSupplierImportHistory();
      final seenImportIds = supplierImports
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final si in localSupplierImports) {
        final fid = si['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenImportIds.add(fid)) {
          supplierImports.add(si);
        }
      }

      // Merge sales_returns
      final localSalesReturns = await db.getSalesReturns();
      final seenReturnIds = salesReturns
          .map((e) => e['firestoreId'])
          .whereType<String>()
          .toSet();
      for (final sr in localSalesReturns) {
        final fid = sr['firestoreId'] as String?;
        if (fid != null && fid.isNotEmpty && seenReturnIds.add(fid)) {
          salesReturns.add(sr);
        }
      }

      // Build debtTypeMap from local debts too (for resolving debtType of local debt_payments)
      final localDebts = await db.getAllDebts();
      for (final debt in localDebts) {
        final fid = debt['firestoreId'] as String?;
        final localId = debt['id']?.toString();
        final dType = (debt['type'] as String?) ?? '';
        if (dType.isNotEmpty) {
          if (fid != null && fid.isNotEmpty && !debtTypeMap.containsKey(fid)) {
            debtTypeMap[fid] = dType;
          }
          if (localId != null && !debtTypeMap.containsKey(localId)) {
            debtTypeMap[localId] = dType;
          }
        }
      }

      debugPrint(
        '📖 [MERGE] sales=${sales.length}, repairs=${repairs.length}, '
        'debtPayments=${debtPayments.length}, supplierPayments=${supplierPayments.length}, '
        'partnerPayments=${repairPartnerPayments.length}, salesReturns=${salesReturns.length}',
      );

      if (mounted) {
        setState(() {
          _sales = sales;
          _repairs = repairs;
          _expenses = expenses.cast<Map<String, dynamic>>();
          _debtPayments = debtPayments.cast<Map<String, dynamic>>();
          _supplierImports = supplierImports;
          _supplierPayments = supplierPayments.cast<Map<String, dynamic>>();
          _repairPartnerPayments = repairPartnerPayments
              .cast<Map<String, dynamic>>();
          _salesReturns = salesReturns.cast<Map<String, dynamic>>();
          _debtTypeMap = debtTypeMap;
          _previousDayClosing = previousClosing;
          _todayClosing = todayClosing;
          _isLoading = false;
        });
      }
      _isLoadingFromFirestore = false;
    } catch (e) {
      debugPrint('Error loading from Firestore: $e');
      _isLoadingFromFirestore = false;
      if (mounted) {
        await _loadAllDataFromLocalDB();
      } else {
        _isLoading = false;
      }
    }
  }

  /// Fallback: Load từ local DB khi offline
  Future<void> _loadAllDataFromLocalDB() async {
    final sales = await db.getAllSales();
    final repairs = await db.getAllRepairs();
    final expenses = await db.getAllExpenses();
    final debtPayments = await db.getAllDebtPaymentsWithDetails();
    // Đọc supplier_import_history từ local DB (SyncService đã sync Firestore → local)
    final supplierImports = await db.getAllSupplierImportHistory();
    final supplierPayments = await db.getAllSupplierPayments();
    // FIX: Load repair_partner_payments từ local DB (trước đây bỏ sót → _repairPartnerPayments luôn rỗng khi offline)
    final repairPartnerPayments = await db.getRepairPartnerPaymentsForSync();
    final salesReturns = await db.getSalesReturns();
    final yesterday = _selectedDate.subtract(const Duration(days: 1));
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);
    final previousClosing = await db.getClosingByDateKey(yesterdayKey);
    final todayKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final todayClosing = await db.getClosingByDateKey(todayKey);
    debugPrint(
      '📖 [LOCAL-LOAD] yesterdayKey=$yesterdayKey previousClosing=${previousClosing != null ? 'FOUND cashEnd=${previousClosing['cashEnd']}' : 'NULL'}',
    );
    debugPrint('📖 [LOCAL-LOAD] shopIdSync=${UserService.getShopIdSync()}');

    if (mounted) {
      setState(() {
        _sales = sales;
        _repairs = repairs;
        _expenses = expenses;
        _debtPayments = debtPayments;
        _supplierImports = supplierImports;
        _supplierPayments = supplierPayments;
        _repairPartnerPayments = repairPartnerPayments; // FIX: Load từ local DB
        _salesReturns = salesReturns;
        _debtTypeMap = {}; // Local DB already has debtType from JOIN
        _previousDayClosing = previousClosing;
        _todayClosing = todayClosing;
        _isLoading = false;
      });
    } else {
      _isLoading = false;
    }
  }

  /// Chuyển đổi Timestamp fields sang milliseconds
  void _convertTimestampFields(Map<String, dynamic> data) {
    for (var key in data.keys.toList()) {
      if (data[key] is Timestamp) {
        data[key] = (data[key] as Timestamp).millisecondsSinceEpoch;
      }
    }
  }

  /// Load tất cả dữ liệu - local DB trước để hiển thị ngay, Firestore sau để đồng bộ
  Future<void> _loadAllData() async {
    // Load local DB first for instant display
    await _loadAllDataFromLocalDB();
    // Then merge Firestore data in background (non-blocking)
    _loadAllDataFromFirestore();
  }

  bool _isSameDay(int timestamp, DateTime target) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return d.year == target.year &&
        d.month == target.month &&
        d.day == target.day;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: CustomAppBar.build(
          title: 'SỔ QUỸ',
          accentColor: AppBarAccents.finance,
        ),
        body: const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    if (widget.showOnlyTransactions) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: CustomAppBar.build(
          title: 'LỊCH SỬ TÀI CHÍNH',
          subtitle: _txEndDate != null
              ? '${DateFormat('dd/MM').format(_selectedDate)} - ${DateFormat('dd/MM/yyyy').format(_txEndDate!)}'
              : DateFormat('dd/MM/yyyy').format(_selectedDate),
          accentColor: Colors.indigo,
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: _txTypeFilter != null,
                child: const Icon(
                  Icons.filter_list_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              onPressed: _showTxFilterSheet,
              splashRadius: 18,
              tooltip: 'Bộ lọc',
            ),
            IconButton(
              icon: const Icon(
                Icons.calendar_month,
                size: 20,
                color: Colors.white,
              ),
              onPressed: _pickDateRange,
              splashRadius: 18,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(42),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              color: Colors.white,
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: TextField(
                  controller: _txSearchController,
                  onChanged: (v) => setState(() => _txSearchQuery = v.trim()),
                  style: TextStyle(
                    color: CustomAppBar.kTextPrimary,
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                  cursorColor: Colors.indigo,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên, mô tả, ghi chú...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.indigo,
                      size: 16,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 34),
                    suffixIcon: _txSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.grey.shade500,
                              size: 16,
                            ),
                            onPressed: () {
                              _txSearchController.clear();
                              setState(() => _txSearchQuery = '');
                            },
                            splashRadius: 14,
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: ResponsiveCenter(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildTransactionsTab(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: ResponsiveCenter(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : NestedScrollView(
                headerSliverBuilder: (context, _) => [_buildSliverAppBar()],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildIncomeTab(),
                    _buildExpenseTab(),
                    _buildHistoryTab(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: false,
      pinned: true,
      toolbarHeight: CustomAppBar.kAppBarHeight,
      backgroundColor: CustomAppBar.kGradientStart,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 8,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [CustomAppBar.kGradientStart, CustomAppBar.kGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SỔ QUỸ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: CustomAppBar.kTitleFontSize,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM/yyyy', 'vi').format(_selectedDate),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: CustomAppBar.kSubtitleFontSize + 1,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Xuất Excel sổ quỹ',
          icon: const Icon(Icons.file_download, size: 20, color: Colors.white),
          onPressed: _exportCashClosingExcel,
          splashRadius: 18,
        ),
        IconButton(
          icon: const Icon(Icons.calendar_month, size: 20, color: Colors.white),
          onPressed: _pickDate,
          splashRadius: 18,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorWeight: 2,
        labelPadding: EdgeInsets.zero,
        tabs: [
          Tab(
            height: CustomAppBar.kTabBarHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard, size: 14),
                SizedBox(width: 4),
                Text('Tổng quan', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Tab(
            height: CustomAppBar.kTabBarHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward, size: 14),
                SizedBox(width: 4),
                Text('Thu', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Tab(
            height: CustomAppBar.kTabBarHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_upward, size: 14),
                SizedBox(width: 4),
                Text('Chi', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Tab(
            height: CustomAppBar.kTabBarHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 14),
                SizedBox(width: 4),
                Text('Lịch sử', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCashClosingExcel() async {
    try {
      final incomeList = _getIncomeTransactions(_selectedDate);
      final expenseList = _getExpenseTransactions(_selectedDate);

      await ExcelExportHelper.exportCashClosingTransactions(
        context,
        selectedDate: _selectedDate,
        incomeList: incomeList,
        expenseList: expenseList,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi xuất Excel sổ quỹ: $e')));
    }
  }

  Widget _fundCard(String emoji, String label, int amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: AppTextStyles.overlineSize,
                  ),
                ),
                Text(
                  MoneyUtils.formatCompactCurrency(amount),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.body1.fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('vi'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadAllData();
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _selectedDate,
        end: _txEndDate ?? _selectedDate,
      ),
      locale: const Locale('vi'),
    );
    if (range != null) {
      setState(() {
        _selectedDate = range.start;
        _txEndDate = range.start == range.end ? null : range.end;
      });
      _loadAllData();
    }
  }

  Widget _buildOverviewTab() {
    final analysis = _analyzeTransactions(_selectedDate);
    final openingCash = _previousDayClosing?['cashEnd'] as int? ?? 0;
    final openingBank = _previousDayClosing?['bankEnd'] as int? ?? 0;
    debugPrint(
      '📊 [OVERVIEW] _previousDayClosing=${_previousDayClosing != null ? 'EXISTS cashEnd=$openingCash bankEnd=$openingBank' : 'NULL'}',
    );
    final expectedCash = openingCash + analysis.cashIn - analysis.cashOut;
    final expectedBank = openingBank + analysis.bankIn - analysis.bankOut;
    final totalIncome = analysis.cashIn + analysis.bankIn;
    final totalExpense = analysis.cashOut + analysis.bankOut;
    final totalFund = expectedCash + expectedBank;
    final previousTotal = openingCash + openingBank;
    final diff = totalFund - previousTotal;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Card tổng quỹ hiện tại
          _buildCurrentFundCard(expectedCash, expectedBank, totalFund, diff),
          const SizedBox(height: 16),
          _buildOpeningBalanceCard(openingCash, openingBank),
          const SizedBox(height: 16),
          _buildSectionCard(
            "SỐ DƯ DỰ KIẾN CUỐI NGÀY",
            Icons.savings,
            Colors.green,
            [
              _infoRow(
                "Tiền mặt",
                MoneyUtils.formatCompactCurrency(expectedCash),
              ),
              _infoRow(
                "Ngân hàng",
                MoneyUtils.formatCompactCurrency(expectedBank),
              ),
              const Divider(height: 16),
              _infoRow(
                "Tổng dự kiến",
                MoneyUtils.formatCompactCurrency(expectedCash + expectedBank),
                bold: true,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildClosingStatusCard(expectedCash, expectedBank),
        ],
      ),
    );
  }

  Widget _buildCurrentFundCard(int cash, int bank, int total, int diff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                "TỔNG QUỸ HIỆN TẠI",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline5.fontSize,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: diff >= 0 ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${diff >= 0 ? '↑' : '↓'} ${MoneyUtils.formatCompactCurrency(diff.abs())}",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.body1.fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            MoneyUtils.formatCompactCurrency(total),
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTextStyles.headline1.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "💵 Tiền mặt",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyUtils.formatCompactCurrency(cash),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline4.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "🏦 Ngân hàng",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyUtils.formatCompactCurrency(bank),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline4.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.headline5.fontSize,
              color: Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTextStyles.headline4.fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningBalanceCard(int openingCash, int openingBank) {
    final hasOpening = _previousDayClosing != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "SỐ DƯ ĐẦU NGÀY",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: AppTextStyles.headline4.fontSize,
                  ),
                ),
              ),
              if (!hasOpening)
                TextButton.icon(
                  onPressed: _showSetOpeningBalanceDialog,
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(
                    "Nhập",
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow("Tiền mặt", MoneyUtils.formatCompactCurrency(openingCash)),
          _infoRow("Ngân hàng", MoneyUtils.formatCompactCurrency(openingBank)),
          const Divider(height: 16),
          _infoRow(
            "Tổng đầu ngày",
            MoneyUtils.formatCompactCurrency(openingCash + openingBank),
            bold: true,
          ),
          if (!hasOpening)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Chưa có số dư đầu kỳ. Bấm \"Nhập\" để thiết lập.",
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSetOpeningBalanceDialog() {
    final openingCashCtrl = TextEditingController();
    final openingBankCtrl = TextEditingController();
    final formatter = NumberFormat('#,###', 'vi');

    String formatCurrency(String value) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return '';
      return formatter.format(int.parse(digits));
    }

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "NHẬP SỐ DƯ ĐẦU KỲ",
                style: TextStyle(
                  fontSize: AppTextStyles.headline2.fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Số dư này sẽ được dùng làm điểm bắt đầu cho ${DateFormat('dd/MM/yyyy').format(_selectedDate)}",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: openingCashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final formatted = formatCurrency(v);
                  if (formatted != v) {
                    openingCashCtrl.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: "💵 Tiền mặt đầu kỳ",
                  hintText: "VD: 10,000,000",
                  suffixText: "đ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.money, color: Colors.amber),
                  filled: true,
                  fillColor: Colors.amber.shade50,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: openingBankCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final formatted = formatCurrency(v);
                  if (formatted != v) {
                    openingBankCtrl.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: "🏦 Số dư ngân hàng đầu kỳ",
                  hintText: "VD: 50,000,000",
                  suffixText: "đ",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(
                    Icons.account_balance,
                    color: Colors.blue,
                  ),
                  filled: true,
                  fillColor: Colors.blue.shade50,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("HỦY"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final cashText = openingCashCtrl.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final bankText = openingBankCtrl.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final cashEnd = int.tryParse(cashText) ?? 0;
                        final bankEnd = int.tryParse(bankText) ?? 0;

                        debugPrint(
                          'Saving opening balance: cash=$cashEnd, bank=$bankEnd',
                        );

                        Navigator.pop(ctx);
                        await _saveOpeningBalance(cashEnd, bankEnd);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("LƯU SỐ DƯ ĐẦU KỲ"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveOpeningBalance(int cashEnd, int bankEnd) async {
    debugPrint('_saveOpeningBalance called with cash=$cashEnd, bank=$bankEnd');
    try {
      // Lưu như là chốt quỹ ngày hôm trước
      final yesterday = _selectedDate.subtract(const Duration(days: 1));
      final dateKey = DateFormat('yyyy-MM-dd').format(yesterday);
      final now = DateTime.now().millisecondsSinceEpoch;
      final closedBy = FirebaseAuth.instance.currentUser?.email ?? 'unknown';
      final shopId = await UserService.getCurrentShopId();

      // Data cho local DB - bao gồm shopId + closedAt/closedBy
      final localData = {
        'dateKey': dateKey,
        'cashStart': 0,
        'bankStart': 0,
        'cashEnd': cashEnd,
        'bankEnd': bankEnd,
        'expectedCashDelta': 0,
        'expectedBankDelta': 0,
        'note': 'Số dư đầu kỳ được nhập thủ công',
        'createdAt': now,
        'closedAt': now,
        'closedBy': closedBy,
        if (shopId != null) 'shopId': shopId,
      };

      debugPrint(
        '💾 [OPENING] Saving to local DB: dateKey=$dateKey, cashEnd=$cashEnd, bankEnd=$bankEnd, shopId=$shopId',
      );
      await db.upsertCashClosing(localData);

      // Verify local save
      final verify = await db.getClosingByDateKey(dateKey);
      debugPrint(
        '💾 [OPENING] Verify local save: ${verify != null ? 'cashEnd=${verify['cashEnd']}, bankEnd=${verify['bankEnd']}, shopId=${verify['shopId']}' : 'NULL - SAVE FAILED!'}',
      );

      // Sync to Firestore (best effort - local already saved)
      debugPrint('💾 [OPENING] Shop ID: $shopId');
      if (shopId != null) {
        try {
          debugPrint('💾 [OPENING] Saving to Firestore...');
          final firestoreDoc = {
            ...localData,
            'shopId': shopId,
            'date': dateKey, // FIX: Firestore rules require 'date' field
            'firestoreId': 'closing_${shopId}_$dateKey',
            'isManualOpening': true,
            'isSynced': true,
            'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          };
          await FirebaseFirestore.instance
              .collection('cash_closings')
              .doc('closing_${shopId}_$dateKey')
              .set(firestoreDoc, SetOptions(merge: true));
          debugPrint('💾 [OPENING] ✅ Saved to Firestore successfully');

          // Mark local as synced
          await db.upsertCashClosing({
            ...localData,
            'firestoreId': 'closing_${shopId}_$dateKey',
            'isSynced': 1,
          });
        } catch (e) {
          // Firestore sync failed but local is saved - don't show error
          debugPrint('💾 [OPENING] ⚠️ Firestore sync failed (local saved): $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Đã lưu số dư đầu kỳ"),
            backgroundColor: Colors.indigo,
          ),
        );
        await _loadAllData();
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving opening balance: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildIncomeExpenseChart(
    int totalIncome,
    int totalExpense,
    DailyFinancialAnalysis analysis,
  ) {
    final maxVal = totalIncome > totalExpense ? totalIncome : totalExpense;
    final incomeRatio = maxVal > 0 ? totalIncome / maxVal : 0.0;
    final expenseRatio = maxVal > 0 ? totalExpense / maxVal : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "BIẾN ĐỘNG TRONG NGÀY",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 50,
                        height: 100 * incomeRatio,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.green.shade300,
                              Colors.green.shade600,
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "📥 THU",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.subtitle1.fontSize,
                      ),
                    ),
                    Text(
                      "+${MoneyUtils.formatCompactCurrency(totalIncome)}",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.headline5.fontSize,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 50,
                        height: 100 * expenseRatio,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.red.shade300, Colors.red.shade600],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "📤 CHI",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.subtitle1.fontSize,
                      ),
                    ),
                    Text(
                      "-${MoneyUtils.formatCompactCurrency(totalExpense)}",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.headline5.fontSize,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          // Phần thu
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "📥 CHI TIẾT THU",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _breakdownItem(
                      "Bán hàng",
                      analysis.saleIncome,
                      Colors.green,
                    ),
                    // FIX BUG-CC-005: Hiển thị tiền tất toán ngân hàng (trả góp)
                    _breakdownItem(
                      "Tất toán NH",
                      analysis.settlementIncome,
                      Colors.green,
                    ),
                    if (_enableRepair)
                      _breakdownItem(
                        "Sửa chữa",
                        analysis.repairIncome,
                        Colors.green,
                      ),
                    _breakdownItem(
                      "Thu nợ KH",
                      analysis.debtCollected,
                      Colors.green,
                    ),
                    _breakdownItem(
                      "Thu phát sinh",
                      analysis.miscIncome,
                      Colors.teal,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "📤 CHI TIẾT CHI",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _breakdownItem("Chi phí", analysis.expenseOut, Colors.red),
                    _breakdownItem("Nhập hàng", analysis.importOut, Colors.red),
                    _breakdownItem(
                      "Trả nợ NCC",
                      analysis.supplierPaid,
                      Colors.red,
                    ),
                    if (analysis.partnerPaid > 0)
                      _breakdownItem(
                        "TT đối tác SC",
                        analysis.partnerPaid,
                        Colors.red,
                      ),
                    if (analysis.repairPartsCostFund > 0)
                      _breakdownItem(
                        "Vốn LK SC",
                        analysis.repairPartsCostFund,
                        Colors.red,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          // Lợi nhuận ròng
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: analysis.netProfit >= 0
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: analysis.netProfit >= 0
                    ? Colors.green.shade200
                    : Colors.red.shade200,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "💰 LỢI NHUẬN RÒNG",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.headline5.fontSize,
                      ),
                    ),
                    Text(
                      "${analysis.netProfit >= 0 ? '+' : ''}${MoneyUtils.formatCompactCurrency(analysis.netProfit)}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.headline3.fontSize,
                        color: analysis.netProfit >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_canViewCostPrice)
                  Row(
                    children: [
                      Expanded(
                        child: _breakdownItem(
                          "Giá vốn bán",
                          analysis.saleCost,
                          Colors.orange,
                        ),
                      ),
                      Expanded(
                        child: _breakdownItem(
                          "Giá vốn SC",
                          analysis.repairCost,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                if (_canViewCostPrice) const SizedBox(height: 4),
                if (_canViewCostPrice)
                  Text(
                    "= Doanh thu - Chi phí - Giá vốn",
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownItem(String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.black54,
              ),
            ),
          ),
          Text(
            MoneyUtils.formatCompactCurrency(amount),
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingStatusCard(int expectedCash, int expectedBank) {
    final isToday = _isSameDay(
      DateTime.now().millisecondsSinceEpoch,
      _selectedDate,
    );
    final isClosed = _todayClosing != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isClosed ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClosed ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isClosed ? Icons.check_circle : Icons.pending_actions,
            size: 48,
            color: isClosed ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 12),
          Text(
            isClosed ? "✅ ĐÃ CHỐT QUỸ" : "⏳ CHƯA CHỐT QUỸ",
            style: TextStyle(
              fontSize: AppTextStyles.headline3.fontSize,
              fontWeight: FontWeight.bold,
              color: isClosed ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ),
          if (isClosed) ...[
            const SizedBox(height: 8),
            Text(
              "Chốt lúc ${_formatTime(_todayClosing!['closedAt'])} bởi ${_todayClosing!['closedBy'] ?? 'N/A'}",
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                color: Colors.green.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              "TM: ${MoneyUtils.formatCompactCurrency(_todayClosing!['cashEnd'] ?? 0)} • CK: ${MoneyUtils.formatCompactCurrency(_todayClosing!['bankEnd'] ?? 0)}",
              style: TextStyle(
                fontSize: AppTextStyles.headline5.fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (!isClosed && isToday) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showClosingDialog(expectedCash, expectedBank),
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  "CHỐT QUỸ NGAY",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    return DateFormat(
      'HH:mm dd/MM',
    ).format(DateTime.fromMillisecondsSinceEpoch(timestamp as int));
  }

  Widget _buildIncomeTab() {
    final incomeList = _getIncomeTransactions(_selectedDate);
    final totalIncome = incomeList.fold<int>(
      0,
      (sum, t) => sum + (t['amount'] as int),
    );

    // Group subtotals
    final saleTotal = incomeList
        .where((t) => t['type'] == 'sale')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final repairTotal = incomeList
        .where((t) => t['type'] == 'repair')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final debtTotal = incomeList
        .where((t) => t['type'] == 'debt_collect')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final settlementTotal = incomeList
        .where((t) => t['type'] == 'settlement')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final miscIncomeTotal = incomeList
        .where((t) => t['type'] == 'misc_income')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));

    return Column(
      children: [
        // Header summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.green.shade50,
                Colors.green.shade100.withOpacity(0.5),
              ],
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TỔNG THU',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      Text(
                        '${incomeList.length} giao dịch',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: AppTextStyles.caption.fontSize,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '+${MoneyUtils.formatCompactCurrency(totalIncome)}',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              if (incomeList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (saleTotal > 0)
                      _summaryChip('🛒 Bán hàng', saleTotal, Colors.green),
                    if (_enableRepair && repairTotal > 0)
                      _summaryChip('🔧 Sửa chữa', repairTotal, Colors.green),
                    if (debtTotal > 0)
                      _summaryChip('💳 Thu nợ', debtTotal, Colors.green),
                    if (settlementTotal > 0)
                      _summaryChip(
                        '🏦 Tất toán',
                        settlementTotal,
                        Colors.green,
                      ),
                    if (miscIncomeTotal > 0)
                      _summaryChip(
                        '💰 Thu phát sinh',
                        miscIncomeTotal,
                        Colors.green,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: incomeList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chưa có giao dịch thu',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: incomeList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _transactionCard(incomeList[i], true),
                ),
        ),
      ],
    );
  }

  Widget _buildExpenseTab() {
    final expenseList = _getExpenseTransactions(_selectedDate);
    final totalExpense = expenseList.fold<int>(
      0,
      (sum, t) => sum + (t['amount'] as int),
    );

    // Group subtotals
    final expenseOnly = expenseList
        .where((t) => t['type'] == 'expense' || t['type'] == 'refund')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final importTotal = expenseList
        .where((t) => t['type'] == 'import')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final supplierPayTotal = expenseList
        .where((t) => t['type'] == 'supplier_pay' || t['type'] == 'debt_pay')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final partnerPayTotal = expenseList
        .where((t) => t['type'] == 'partner_pay')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));
    final repairPartsCostTotal = expenseList
        .where((t) => t['type'] == 'repair_parts_cost')
        .fold<int>(0, (s, t) => s + (t['amount'] as int));

    return Column(
      children: [
        // Header summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.red.shade50,
                Colors.red.shade100.withOpacity(0.5),
              ],
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TỔNG CHI',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      Text(
                        '${expenseList.length} giao dịch',
                        style: TextStyle(
                          color: Colors.red.shade600,
                          fontSize: AppTextStyles.caption.fontSize,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '-${MoneyUtils.formatCompactCurrency(totalExpense)}',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              if (expenseList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (expenseOnly > 0)
                      _summaryChip('💸 Chi phí', expenseOnly, Colors.red),
                    if (importTotal > 0)
                      _summaryChip('📦 Nhập hàng', importTotal, Colors.red),
                    if (supplierPayTotal > 0)
                      _summaryChip('🏭 Trả NCC', supplierPayTotal, Colors.red),
                    if (partnerPayTotal > 0)
                      _summaryChip('🔧 Đối tác', partnerPayTotal, Colors.red),
                    if (repairPartsCostTotal > 0)
                      _summaryChip(
                        '🔩 Vốn LK SC',
                        repairPartsCostTotal,
                        Colors.red,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: expenseList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chưa có giao dịch chi',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: expenseList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _transactionCard(expenseList[i], false),
                ),
        ),
      ],
    );
  }

  Widget _transactionCard(Map<String, dynamic> t, bool isIncome) {
    final color = isIncome ? Colors.green : Colors.red;
    final type = t['type'] as String? ?? '';
    final payMethod = t['paymentMethod'] as String? ?? '';
    final isCash = payMethod == 'TIỀN MẶT';
    final customerName = t['customerName'] as String? ?? '';
    final detail = t['detail'] as String? ?? '';
    final note = t['note'] as String?;
    final hasTapAction =
        type == 'sale' || type == 'settlement' || type == 'repair';

    return GestureDetector(
      onTap: hasTapAction
          ? () => _onTransactionTap(t)
          : () => _showTransactionDetail(t, isIncome),
      child: Container(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Icon + Title + Amount
            Row(
              children: [
                // Type badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      t['icon'] as String? ?? '💰',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Title + Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['title'] as String? ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextStyles.headline5.fontSize,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            t['time'] as String? ?? '',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          if (note != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '• $note',
                                style: TextStyle(
                                  fontSize: AppTextStyles.caption.fontSize,
                                  color: Colors.orange.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Amount
                Text(
                  "${isIncome ? '+' : '-'}${MoneyUtils.formatCompactCurrency(t['amount'] as int)}",
                  style: TextStyle(
                    color: color,
                    fontSize: AppTextStyles.headline4.fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // Row 2: Detail info line
            if (customerName.isNotEmpty || detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    if (customerName.isNotEmpty) ...[
                      Icon(
                        Icons.person_outline,
                        size: 13,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        customerName,
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: AppTextStyles.caption.fontSize,
                          ),
                        ),
                    ],
                    if (detail.isNotEmpty)
                      Expanded(
                        child: Text(
                          detail,
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            // Row 3: Payment method pill + navigation hint
            const SizedBox(height: 6),
            Row(
              children: [
                _paymentMethodPill(payMethod, isCash),
                const Spacer(),
                if (hasTapAction)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Xem chi tiết',
                        style: TextStyle(
                          fontSize: AppTextStyles.caption.fontSize,
                          color: const Color(0xFF0068FF),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Color(0xFF0068FF),
                      ),
                    ],
                  )
                else
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodPill(String method, bool isCash) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCash ? Colors.amber.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCash ? Colors.amber.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isCash ? '💵' : '🏦', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            method.isEmpty ? 'Tiền mặt' : method,
            style: TextStyle(
              fontSize: AppTextStyles.caption.fontSize,
              fontWeight: FontWeight.w500,
              color: isCash ? Colors.amber.shade900 : Colors.blue.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: ${MoneyUtils.formatCompactCurrency(amount)}',
        style: TextStyle(
          fontSize: AppTextStyles.caption.fontSize,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Navigate to detail view for sale/repair transactions
  void _onTransactionTap(Map<String, dynamic> t) {
    final type = t['type'] as String? ?? '';
    if (type == 'sale' || type == 'settlement') {
      final sale = t['saleOrder'] as SaleOrder?;
      if (sale != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
        );
      }
    } else if (type == 'repair') {
      final repair = t['repair'] as Repair?;
      if (repair != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RepairDetailView(repair: repair)),
        );
      }
    }
  }

  /// Show bottom sheet detail for non-navigable transactions (expenses, debts, imports)
  void _showTransactionDetail(Map<String, dynamic> t, bool isIncome) {
    final color = isIncome ? Colors.green : Colors.red;
    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Icon + Title
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      t['icon'] as String? ?? '💰',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['title'] as String? ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline3.fontSize,
                        ),
                      ),
                      Text(
                        '${t['time'] ?? ''} • ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Amount
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    isIncome ? 'SỐ TIỀN THU' : 'SỐ TIỀN CHI',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: AppTextStyles.body1.fontSize,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${isIncome ? '+' : '-'}${MoneyUtils.formatCompactCurrency(t['amount'] as int? ?? 0)}",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.headline1.fontSize,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Detail rows
            if ((t['customerName'] as String? ?? '').isNotEmpty)
              _detailRow(
                Icons.person_outline,
                'Người liên quan',
                t['customerName'] as String,
              ),
            if ((t['detail'] as String? ?? '').isNotEmpty)
              _detailRow(
                Icons.description_outlined,
                'Chi tiết',
                t['detail'] as String,
              ),
            if ((t['paymentMethod'] as String? ?? '').isNotEmpty)
              _detailRow(
                (t['paymentMethod'] as String) == 'TIỀN MẶT'
                    ? Icons.money
                    : Icons.account_balance,
                'Phương thức',
                t['paymentMethod'] as String,
              ),
            if ((t['note'] as String? ?? '').isNotEmpty)
              _detailRow(Icons.note_outlined, 'Ghi chú', t['note'] as String),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: AppTextStyles.body1.fontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: AppTextStyles.body1.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TRANSACTION FILTER SHEET ──────────────────────────────

  void _showTxFilterSheet() {
    final types = <Map<String, String>>[
      {'value': '', 'label': 'Tất cả'},
      {'value': 'sale', 'label': '🛒 Bán hàng'},
      {'value': 'settlement', 'label': '🏦 Tất toán NH'},
      if (_enableRepair) {'value': 'repair', 'label': '🔧 Sửa chữa'},
      {'value': 'debt_collect', 'label': '💳 Thu nợ'},
      {'value': 'misc_income', 'label': '💰 Thu phát sinh'},
      {'value': 'expense', 'label': '📝 Chi phí'},
      {'value': 'refund', 'label': '↩️ Trả hàng'},
      {'value': 'import', 'label': '📦 Nhập hàng'},
      {'value': 'supplier_pay', 'label': '🏭 Trả NCC'},
      if (_enableRepair) {'value': 'partner_pay', 'label': '🤝 Trả đối tác SC'},
      if (_enableRepair)
        {'value': 'repair_parts_cost', 'label': '🔩 Vốn LK SC'},
      {'value': 'debt_pay', 'label': '💸 Trả nợ'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Lọc theo loại giao dịch',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline4.fontSize,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: types.map((t) {
                    final val = t['value']!;
                    final selected =
                        (val.isEmpty && _txTypeFilter == null) ||
                        val == _txTypeFilter;
                    return ChoiceChip(
                      label: Text(
                        t['label']!,
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      selected: selected,
                      selectedColor: Colors.indigo.shade100,
                      onSelected: (_) {
                        setSheetState(() {});
                        setState(() {
                          _txTypeFilter = val.isEmpty ? null : val;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                if (_txTypeFilter != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _txTypeFilter = null);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Xóa bộ lọc'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── TRANSACTIONS TAB ───────────────────────────────────────

  Widget _buildTransactionsTab() {
    // Collect transactions for single date or date range
    final incomeList = <Map<String, dynamic>>[];
    final expenseList = <Map<String, dynamic>>[];
    final end = _txEndDate ?? _selectedDate;
    for (
      var d = _selectedDate;
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))
    ) {
      incomeList.addAll(_getIncomeTransactions(d));
      expenseList.addAll(_getExpenseTransactions(d));
    }

    // Build unified list with isIncome flag
    var allTransactions = <Map<String, dynamic>>[];
    for (final t in incomeList) {
      allTransactions.add({...t, '_isIncome': true});
    }
    for (final t in expenseList) {
      allTransactions.add({...t, '_isIncome': false});
    }
    // Sort by time descending
    allTransactions.sort(
      (a, b) => (b['time'] as String).compareTo(a['time'] as String),
    );

    // Apply type filter
    if (_txTypeFilter != null) {
      allTransactions = allTransactions
          .where((t) => t['type'] == _txTypeFilter)
          .toList();
    }

    // Apply search filter
    if (_txSearchQuery.isNotEmpty) {
      final q = _txSearchQuery.toLowerCase();
      allTransactions = allTransactions.where((t) {
        final title = (t['title'] as String? ?? '').toLowerCase();
        final detail = (t['detail'] as String? ?? '').toLowerCase();
        final customer = (t['customerName'] as String? ?? '').toLowerCase();
        final note = (t['note'] as String? ?? '').toLowerCase();
        return title.contains(q) ||
            detail.contains(q) ||
            customer.contains(q) ||
            note.contains(q);
      }).toList();
    }

    final totalIn = incomeList.fold<int>(0, (s, t) => s + (t['amount'] as int));
    final totalOut = expenseList.fold<int>(
      0,
      (s, t) => s + (t['amount'] as int),
    );

    return Column(
      children: [
        // Summary header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.indigo.shade50,
                Colors.indigo.shade100.withOpacity(0.5),
              ],
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TẤT CẢ GIAO DỊCH',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade800,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      Text(
                        '${allTransactions.length} giao dịch',
                        style: TextStyle(
                          color: Colors.indigo.shade600,
                          fontSize: AppTextStyles.caption.fontSize,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    MoneyUtils.formatCompactCurrency(totalIn - totalOut),
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                      color: (totalIn - totalOut) >= 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _summaryChip('↓ Thu', totalIn, Colors.green),
                  const SizedBox(width: 8),
                  _summaryChip('↑ Chi', totalOut, Colors.red),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: allTransactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chưa có giao dịch nào',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: allTransactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = allTransactions[i];
                    return _transactionCard(t, t['_isIncome'] as bool);
                  },
                ),
        ),
      ],
    );
  }

  /// Load history from Firestore first, fallback to local DB
  Future<List<Map<String, dynamic>>> _loadHistoryClosings() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null) {
        // Try Firestore first
        final snap = await FirebaseFirestore.instance
            .collection('cash_closings')
            .where('shopId', isEqualTo: shopId)
            .orderBy('dateKey', descending: true)
            .get();
        if (snap.docs.isNotEmpty) {
          final firestoreClosings = snap.docs
              .where((doc) => doc.data()['deleted'] != true)
              .map((doc) {
                final data = doc.data();
                _convertTimestampFields(data);
                return data;
              })
              .toList();
          if (firestoreClosings.isNotEmpty) {
            debugPrint(
              '📋 [HISTORY] Loaded ${firestoreClosings.length} closings from Firestore',
            );
            return firestoreClosings;
          }
        }
      }
    } catch (e) {
      debugPrint('📋 [HISTORY] Firestore load failed: $e');
    }
    // Fallback to local DB
    final localClosings = await db.getAllCashClosings();
    debugPrint(
      '📋 [HISTORY] Loaded ${localClosings.length} closings from local DB',
    );
    return localClosings;
  }

  Widget _buildHistoryTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadHistoryClosings(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final closings = snapshot.data!;
        if (closings.isEmpty) {
          return const Center(child: Text("Chưa có lịch sử chốt quỹ"));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "LỊCH SỬ CHỐT QUỸ",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.headline4.fontSize,
              ),
            ),
            const SizedBox(height: 12),
            ...closings.map((c) => _historyCard(c)),
          ],
        );
      },
    );
  }

  Widget _buildHistoryChart(List<Map<String, dynamic>> closings) {
    if (closings.isEmpty) return const SizedBox.shrink();
    final maxAbsTotal = closings
        .map(
          (c) =>
              ((c['cashEnd'] as int? ?? 0) + (c['bankEnd'] as int? ?? 0)).abs(),
        )
        .fold<int>(0, (best, value) => value > best ? value : best);
    const chartMaxHeight = 72.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "📊 XU HƯỚNG QUỸ 7 NGÀY",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.headline5.fontSize,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 124,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: closings.reversed.map((c) {
                final total =
                    (c['cashEnd'] as int? ?? 0) + (c['bankEnd'] as int? ?? 0);
                final ratio = maxAbsTotal > 0 ? total.abs() / maxAbsTotal : 0.0;
                final rawHeight = chartMaxHeight * ratio;
                final barHeight = total == 0
                    ? 4.0
                    : rawHeight.clamp(6.0, chartMaxHeight).toDouble();
                final dateKey = c['dateKey'] as String? ?? '';
                final day = dateKey.length >= 10
                    ? dateKey.substring(8, 10)
                    : '';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: total >= 0
                                  ? [
                                      Colors.indigo.shade300,
                                      Colors.indigo.shade600,
                                    ]
                                  : [Colors.red.shade300, Colors.red.shade600],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day,
                          style: TextStyle(
                            fontSize: AppTextStyles.caption.fontSize,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> c) {
    final dateKey = c['dateKey'] as String? ?? '';
    final cashEnd = c['cashEnd'] as int? ?? 0;
    final bankEnd = c['bankEnd'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateKey,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "TM: ${MoneyUtils.formatCompactCurrency(cashEnd)} • CK: ${MoneyUtils.formatCompactCurrency(bankEnd)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isNarrow ? 96 : 130),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      MoneyUtils.formatCompactCurrency(cashEnd + bankEnd),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: AppTextStyles.headline3.fontSize,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showClosingDialog(int expectedCash, int expectedBank) {
    cashEndCtrl.text = expectedCash.toString();
    bankEndCtrl.text = expectedBank.toString();
    noteCtrl.clear();
    bool isSavingClosing = false;
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final actualCash = int.tryParse(cashEndCtrl.text) ?? 0;
          final actualBank = int.tryParse(bankEndCtrl.text) ?? 0;
          final cashDiff = actualCash - expectedCash;
          final bankDiff = actualBank - expectedBank;
          final hasDiff = cashDiff != 0 || bankDiff != 0;
          final canSubmit = !hasDiff || noteCtrl.text.trim().isNotEmpty;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "XÁC NHẬN CHỐT QUỸ",
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy').format(_selectedDate),
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  _closingInputCard(
                    "💵 TIỀN MẶT",
                    expectedCash,
                    cashEndCtrl,
                    cashDiff,
                    () => setModalState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _closingInputCard(
                    "🏦 NGÂN HÀNG",
                    expectedBank,
                    bankEndCtrl,
                    bankDiff,
                    () => setModalState(() {}),
                  ),
                  if (hasDiff) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: "Ghi chú chênh lệch (bắt buộc)",
                        hintText: "Giải thích lý do chênh lệch...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.orange.shade50,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSavingClosing
                              ? null
                              : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text("HỦY"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (!canSubmit || isSavingClosing)
                              ? null
                              : () async {
                                  setModalState(() => isSavingClosing = true);
                                  try {
                                    await _saveClosing();
                                    if (mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    setModalState(
                                      () => isSavingClosing = false,
                                    );
                                    NotificationService.showSnackBar(
                                      "Lỗi: $e",
                                      color: Colors.red,
                                    );
                                  }
                                },
                          icon: isSavingClosing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            isSavingClosing ? "ĐANG LƯU..." : "XÁC NHẬN CHỐT",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _closingInputCard(
    String label,
    int expected,
    TextEditingController ctrl,
    int diff,
    VoidCallback onChanged,
  ) {
    final isOk = diff == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOk ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                "Dự kiến: ",
                style: TextStyle(
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  color: Colors.black54,
                ),
              ),
              Text(
                MoneyUtils.formatCompactCurrency(expected),
                style: TextStyle(
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: "Thực tế",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                "Chênh lệch: ",
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
              ),
              Text(
                "${diff >= 0 ? '+' : ''}${MoneyUtils.formatCompactCurrency(diff)}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isOk ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isOk ? Icons.check_circle : Icons.warning,
                size: 16,
                color: isOk ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveClosing() async {
    try {
      final isToday = _isSameDay(
        DateTime.now().millisecondsSinceEpoch,
        _selectedDate,
      );
      if (!isToday) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Chỉ được chốt quỹ cho ngày hôm nay"),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (_todayClosing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("⚠️ Ngày hôm nay đã chốt quỹ, không thể chốt lại"),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final analysis = _analyzeTransactions(_selectedDate);
      final openingCash = _previousDayClosing?['cashEnd'] as int? ?? 0;
      final openingBank = _previousDayClosing?['bankEnd'] as int? ?? 0;
      final expectedCash = openingCash + analysis.cashIn - analysis.cashOut;
      final expectedBank = openingBank + analysis.bankIn - analysis.bankOut;
      final actualCash = int.tryParse(cashEndCtrl.text) ?? 0;
      final actualBank = int.tryParse(bankEndCtrl.text) ?? 0;
      final hasDiff =
          actualCash != expectedCash || actualBank != expectedBank;
      if (hasDiff && noteCtrl.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("⚠️ Vui lòng nhập ghi chú khi có chênh lệch"),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final now = DateTime.now().millisecondsSinceEpoch;
      final closedBy = FirebaseAuth.instance.currentUser?.email ?? 'unknown';

      // FIX: Include shopId in local data for proper data isolation
      final shopId = await UserService.getCurrentShopId();
      final localData = {
        'dateKey': dateKey,
        'cashEnd': actualCash,
        'bankEnd': actualBank,
        'note': noteCtrl.text.trim(),
        'createdAt': now,
        'closedAt': now,
        'closedBy': closedBy,
        if (shopId != null) 'shopId': shopId,
      };

      debugPrint(
        '💾 [CLOSING] Saving to local: dateKey=$dateKey, cashEnd=${localData['cashEnd']}, bankEnd=${localData['bankEnd']}, shopId=$shopId',
      );
      // Lưu local trước
      await db.upsertCashClosing(localData);

      // Sync to Firestore (best effort)
      if (shopId != null) {
        try {
          final firestoreData = {
            ...localData,
            'shopId': shopId,
            'date': dateKey, // FIX: Firestore rules require 'date' field
            'firestoreId': 'closing_${shopId}_$dateKey',
            'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          };
          await FirebaseFirestore.instance
              .collection('cash_closings')
              .doc('closing_${shopId}_$dateKey')
              .set(firestoreData, SetOptions(merge: true));
          debugPrint('💾 [CLOSING] ✅ Saved to Firestore');

          // Mark local as synced with firestoreId
          await db.upsertCashClosing({
            ...localData,
            'firestoreId': 'closing_${shopId}_$dateKey',
            'isSynced': 1,
          });
        } catch (e) {
          // Firestore sync failed but local is saved - log but don't show error
          debugPrint('💾 [CLOSING] ⚠️ Firestore sync failed (local saved): $e');
        }
      }

      if (mounted) {
        // Ghi log hoạt động chốt quỹ
        await AuditService.logAction(
          action: 'CHỐT QUỸ',
          entityType: 'CASH_CLOSING',
          entityId: 'closing_${shopId ?? 'local'}_$dateKey',
          summary:
              'Chốt quỹ ngày $dateKey - Tồn quỹ: ${MoneyUtils.formatCurrency(actualCash)}đ',
          payload: {
            'dateKey': dateKey,
            'cashEnd': actualCash,
            'bankEnd': actualBank,
            'note': noteCtrl.text.trim(),
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ ĐÃ CHỐT QUỸ THÀNH CÔNG"),
            backgroundColor: Colors.green,
          ),
        );
        await _loadAllData();
      }
    } catch (e) {
      debugPrint('Error saving closing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getIncomeTransactions(DateTime date) {
    final list = <Map<String, dynamic>>[];
    for (var s in _sales.where(
      (s) => _isSameDay(s.soldAt, date) && s.paymentMethod != 'CÔNG NỢ',
    )) {
      final saleAmount = s.isInstallment ? s.downPayment : s.finalPrice;
      // Skip installment entries with 0 down payment (no actual cash received)
      if (s.isInstallment && saleAmount <= 0) continue;
      final customerDisplay = s.customerName.isNotEmpty
          ? s.customerName
          : 'Khách lẻ';
      list.add({
        'type': 'sale',
        'icon': '🛒',
        'title': 'Bán hàng',
        'customerName': customerDisplay,
        'customerPhone': s.phone,
        'detail': s.productNames.isNotEmpty ? s.productNames : 'Đơn hàng',
        'paymentMethod': s.paymentMethod,
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(s.soldAt)),
        'amount': saleAmount,
        'saleOrder': s,
        'note': s.isInstallment ? 'Trả góp - Đặt cọc' : null,
      });
    }

    // Thêm tiền tất toán từ ngân hàng (trả góp đã nhận tiền trong ngày)
    for (var s in _sales.where(
      (s) =>
          s.isInstallment &&
          s.settlementReceivedAt != null &&
          _isSameDay(s.settlementReceivedAt!, date) &&
          s.settlementAmount > 0,
    )) {
      final totalLoan = s.loanAmount + s.loanAmount2;
      final actualAmount = s.settlementAmount.clamp(0, totalLoan);
      if (actualAmount > 0) {
        final bankDisplay = [
          s.bankName ?? 'Ngân hàng',
          if (s.bankName2 != null && s.bankName2!.isNotEmpty) s.bankName2!,
        ].join(' + ');
        list.add({
          'type': 'settlement',
          'icon': '🏦',
          'title': 'Tất toán ngân hàng',
          'customerName': s.customerName.isNotEmpty ? s.customerName : 'KH',
          'customerPhone': s.phone,
          'detail': '$bankDisplay • ${s.productNames}',
          'paymentMethod': 'CHUYỂN KHOẢN',
          'time': DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(s.settlementReceivedAt!),
          ),
          'amount': actualAmount,
          'saleOrder': s,
          'note': 'Trả góp - Nhận tiền từ NH',
        });
      }
    }

    if (_enableRepair) {
      for (var r in _repairs.where(
        (r) =>
            r.status == 4 &&
            r.deliveredAt != null &&
            _isSameDay(r.deliveredAt!, date) &&
            r.paymentMethod != 'CÔNG NỢ',
      )) {
        list.add({
          'type': 'repair',
          'icon': '🔧',
          'title': 'Sửa chữa',
          'customerName': r.customerName.isNotEmpty ? r.customerName : 'KH',
          'customerPhone': r.phone,
          'detail': '${r.model} - ${r.issue}',
          'paymentMethod': r.paymentMethod,
          'time': DateFormat(
            'HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!)),
          'amount': r.price,
          'repair': r,
        });
      }
    }

    for (var p in _debtPayments.where((p) {
      if (p['paidAt'] == null) return false;
      if (!_isSameDay(p['paidAt'] as int, date)) return false;
      var debtType = p['debtType'] as String?;
      if (debtType == null || debtType.isEmpty) {
        final debtFirestoreId = p['debtFirestoreId'] as String?;
        final debtId = p['debtId']?.toString();
        debtType = _debtTypeMap[debtFirestoreId] ?? _debtTypeMap[debtId];
      }
      return _isCustomerOwesDebt(debtType);
    })) {
      list.add({
        'type': 'debt_collect',
        'icon': '💳',
        'title': 'Thu nợ khách',
        'customerName':
            p['personName'] as String? ?? p['customerName'] as String? ?? 'KH',
        'detail': p['note'] as String? ?? 'Thanh toán công nợ',
        'paymentMethod': p['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int)),
        'amount': p['amount'] as int? ?? 0,
        'rawData': p,
      });
    }
    // Thu phát sinh (expenses với type=THU)
    for (var e in _expenses) {
      final expenseDate = (e['date'] ?? e['createdAt']) as int?;
      if (expenseDate == null) continue;
      if (!_isSameDay(expenseDate, date)) continue;
      final eType = (e['type'] ?? 'CHI').toString().toUpperCase();
      if (eType != 'THU') continue;

      list.add({
        'type': 'misc_income',
        'icon': '💰',
        'title': 'Thu phát sinh',
        'detail':
            e['title'] as String? ?? e['note'] as String? ?? 'Thu phát sinh',
        'paymentMethod': e['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(expenseDate)),
        'amount': e['amount'] as int? ?? 0,
        'rawData': e,
      });
    }

    list.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
    return list;
  }

  List<Map<String, dynamic>> _getExpenseTransactions(DateTime date) {
    final list = <Map<String, dynamic>>[];

    // Lưu danh sách expense NHẬP HÀNG để tránh double-count với supplier_imports
    final importExpenseAmounts = <int>{};

    // Chi phí thường (bỏ qua type=THU vì đó là thu phát sinh)
    for (var e in _expenses) {
      final expenseDate = (e['date'] ?? e['createdAt']) as int?;
      if (expenseDate == null) continue;
      if (!_isSameDay(expenseDate, date)) continue;
      final eType = (e['type'] ?? 'CHI').toString().toUpperCase();
      if (eType == 'THU') continue; // Thu phát sinh → hiển thị ở income

      final category = (e['category'] as String? ?? 'Chi phí').toUpperCase();
      final amount = e['amount'] as int? ?? 0;

      if (category.contains('NHẬP') ||
          category.contains('LINH KIỆN') ||
          category.contains('PURCHASE')) {
        importExpenseAmounts.add(amount);
      }

      String icon = '💸';
      String typeName = 'expense';
      if (category.contains('HOÀN TIỀN') || category.contains('TRẢ HÀNG')) {
        icon = '↩️';
        typeName = 'refund';
      }

      list.add({
        'type': typeName,
        'icon': icon,
        'title': e['category'] as String? ?? 'Chi phí',
        'detail': e['note'] as String? ?? '',
        'paymentMethod': e['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(expenseDate)),
        'amount': amount,
        'rawData': e,
      });
    }

    // Supplier imports - CHỈ hiển thị nếu KHÔNG có expense tương ứng
    for (var imp in _supplierImports.where(
      (i) =>
          _isSameDay((i['importDate'] ?? i['createdAt'] ?? 0) as int, date) &&
          (i['paymentMethod'] ?? '') != 'CÔNG NỢ',
    )) {
      final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
      final hasMatchingExpense = importExpenseAmounts.any(
        (expAmount) => (expAmount - amount).abs() < 1000,
      );
      if (hasMatchingExpense) continue;

      list.add({
        'type': 'import',
        'icon': '📦',
        'title': 'Nhập hàng',
        'customerName': imp['supplierName'] as String? ?? 'NCC',
        'detail':
            imp['productName'] as String? ??
            imp['note'] as String? ??
            'Hàng nhập',
        'paymentMethod': imp['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(
            (imp['importDate'] ?? imp['createdAt'] ?? 0) as int,
          ),
        ),
        'amount': amount,
        'rawData': imp,
      });
    }

    for (var pay in _supplierPayments.where(
      (p) => _isSameDay((p['paidAt'] ?? 0) as int, date),
    )) {
      list.add({
        'type': 'supplier_pay',
        'icon': '🏭',
        'title': 'Trả nợ NCC',
        'customerName': pay['supplierName'] as String? ?? 'NCC',
        'detail': pay['note'] as String? ?? 'Thanh toán công nợ NCC',
        'paymentMethod': pay['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat('HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch((pay['paidAt'] ?? 0) as int),
        ),
        'amount': (pay['amount'] ?? 0) as int,
        'rawData': pay,
      });
    }

    // Thanh toán đối tác sửa chữa
    if (_enableRepair) {
      for (var pay in _repairPartnerPayments.where(
        (p) => _isSameDay((p['paidAt'] ?? 0) as int, date),
      )) {
        list.add({
          'type': 'partner_pay',
          'icon': '🔧',
          'title': 'Trả đối tác SC',
          'customerName': pay['partnerName'] as String? ?? 'Đối tác sửa chữa',
          'detail': pay['note'] as String? ?? 'Thanh toán đối tác',
          'paymentMethod': pay['paymentMethod'] as String? ?? 'TIỀN MẶT',
          'time': DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch((pay['paidAt'] ?? 0) as int),
          ),
          'amount': (pay['amount'] ?? 0) as int,
          'rawData': pay,
        });
      }
    }

    // Chi phí vốn linh kiện sửa chữa đã ghi sổ quỹ
    if (_enableRepair) {
      for (var r in _repairs.where(
        (r) =>
            r.costRecordedInFund &&
            r.costRecordedAt != null &&
            _isSameDay(r.costRecordedAt!, date),
      )) {
        final recordedAmount = (r.costRecordedAmount ?? 0) > 0
            ? (r.costRecordedAmount ?? 0)
            : r.totalCost;
        list.add({
          'type': 'repair_parts_cost',
          'icon': '🔩',
          'title': 'Vốn LK: ${r.model}',
          'customerName': r.customerName.isNotEmpty
              ? r.customerName
              : 'KH vãng lai',
          'detail': 'Chi phí vốn linh kiện SC',
          'paymentMethod': r.costPaymentMethod ?? 'TIỀN MẶT',
          'time': DateFormat(
            'HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(r.costRecordedAt!)),
          'amount': recordedAmount,
          'rawData': r.toMap(),
        });
      }
    }

    // sales_returns - trả hàng
    for (var ret in _salesReturns.where((r) {
      final returnDate = r['returnDate'] as int? ?? r['createdAt'] as int? ?? 0;
      return _isSameDay(returnDate, date);
    })) {
      final amount = (ret['totalReturnAmount'] as num?)?.toInt() ?? 0;
      final method = (ret['refundMethod'] as String? ?? 'TIỀN MẶT').toString();
      if (method == 'CÔNG NỢ') continue;
      final returnDate =
          ret['returnDate'] as int? ?? ret['createdAt'] as int? ?? 0;
      list.add({
        'type': 'refund',
        'icon': '↩️',
        'title': 'Trả hàng',
        'customerName': ret['customerName'] as String? ?? '',
        'detail': ret['note'] as String? ?? 'Hoàn tiền trả hàng',
        'paymentMethod': method,
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(returnDate)),
        'amount': amount,
        'rawData': ret,
      });
    }

    // debt_payments với debtType SHOP_OWES = trả nợ NCC
    for (var p in _debtPayments.where((p) {
      final paidAt = p['paidAt'];
      if (paidAt == null) return false;
      if (!_isSameDay(paidAt as int, date)) return false;
      var debtType = p['debtType'] as String?;
      if (debtType == null || debtType.isEmpty) {
        final debtFirestoreId = p['debtFirestoreId'] as String?;
        final debtId = p['debtId']?.toString();
        debtType = _debtTypeMap[debtFirestoreId] ?? _debtTypeMap[debtId];
      }
      return _isShopOwesDebt(debtType);
    })) {
      list.add({
        'type': 'debt_pay',
        'icon': '🏭',
        'title': 'Trả nợ NCC',
        'customerName':
            p['personName'] as String? ?? p['customerName'] as String? ?? 'NCC',
        'detail': p['note'] as String? ?? 'Thanh toán công nợ',
        'paymentMethod': p['paymentMethod'] as String? ?? 'TIỀN MẶT',
        'time': DateFormat(
          'HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int)),
        'amount': p['amount'] as int? ?? 0,
        'rawData': p,
      });
    }
    list.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
    return list;
  }

  DailyFinancialAnalysis _analyzeTransactions(DateTime now) {
    final sales = _sales
        .where((sale) => _isSameDay(sale.soldAt, now))
        .map(
          (sale) => {
            'paymentMethod': sale.paymentMethod,
            'totalPrice': sale.totalPrice,
            'totalCost': sale.totalCost,
            'discount': sale.discount,
            'isInstallment': sale.isInstallment,
            'downPayment': sale.downPayment,
            'downPaymentMethod': sale.downPaymentMethod,
          },
        )
        .toList();

    final settlementSales = _sales
        .where(
          (sale) =>
              sale.isInstallment &&
              sale.settlementReceivedAt != null &&
              _isSameDay(sale.settlementReceivedAt!, now),
        )
        .map(
          (sale) => {
            'totalPrice': sale.totalPrice,
            'totalCost': sale.totalCost,
            'discount': sale.discount,
            'downPayment': sale.downPayment,
            'settlementAmount': sale.settlementAmount,
            'loanAmount': sale.loanAmount,
            'loanAmount2': sale.loanAmount2,
          },
        )
        .toList();

    final repairs = _repairs
        .where(
          (repair) =>
              repair.status == 4 &&
              repair.deliveredAt != null &&
              _isSameDay(repair.deliveredAt!, now),
        )
        .map(
          (repair) => {
            'price': repair.price,
            'totalCost': repair.totalCost,
            'paymentMethod': repair.paymentMethod,
          },
        )
        .toList();

    final expenses = _expenses.where((expense) {
      final expenseDate = (expense['date'] ?? expense['createdAt']) as int?;
      return expenseDate != null && _isSameDay(expenseDate, now);
    }).toList();

    final supplierImports = _supplierImports
        .where(
          (item) => _isSameDay(
            (item['importDate'] ?? item['createdAt'] ?? 0) as int,
            now,
          ),
        )
        .toList();

    final supplierPayments = _supplierPayments
        .where((item) => _isSameDay((item['paidAt'] ?? 0) as int, now))
        .toList();

    final repairPartnerPayments = _repairPartnerPayments
        .where((item) => _isSameDay((item['paidAt'] ?? 0) as int, now))
        .toList();

    final debtPayments = _debtPayments
        .where(
          (payment) =>
              payment['paidAt'] != null &&
              _isSameDay(payment['paidAt'] as int, now),
        )
        .map((payment) {
          var debtType = payment['debtType'] as String?;
          if (debtType == null || debtType.isEmpty) {
            final debtFirestoreId = payment['debtFirestoreId'] as String?;
            final debtId = payment['debtId']?.toString();
            debtType = _debtTypeMap[debtFirestoreId] ?? _debtTypeMap[debtId];
          }
          return {...payment, 'resolvedDebtType': debtType ?? ''};
        })
        .toList();

    final repairPartsCostFundRows = _repairs
        .where(
          (repair) =>
              repair.costRecordedInFund &&
              repair.costRecordedAt != null &&
              _isSameDay(repair.costRecordedAt!, now),
        )
        .map(
          (repair) => {
            'costRecordedAmount': repair.costRecordedAmount,
            'totalCost': repair.totalCost,
            'costPaymentMethod': repair.costPaymentMethod,
          },
        )
        .toList();

    final salesReturns = _salesReturns.where((item) {
      final returnDate =
          item['returnDate'] as int? ?? item['createdAt'] as int? ?? 0;
      return _isSameDay(returnDate, now);
    }).toList();

    return DailyFinancialAnalysisService.analyze(
      sales: sales,
      settlementSales: settlementSales,
      repairs: repairs,
      expenses: expenses,
      debtPayments: debtPayments,
      supplierPayments: supplierPayments,
      repairPartnerPayments: repairPartnerPayments,
      supplierImports: supplierImports,
      repairPartsCostFundRows: repairPartsCostFundRows,
      salesReturns: salesReturns,
      enableRepair: _enableRepair,
      logDebug: true,
    );
  }
}
