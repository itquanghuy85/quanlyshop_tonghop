import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/shop_settings_model.dart';
import '../services/category_service.dart';
import '../services/user_service.dart';
import '../widgets/custom_app_bar.dart';
import '../theme/app_text_styles.dart';
import '../utils/excel_export_helper.dart';

/// Trang theo dõi nhật ký hoạt động tài chính + hệ thống
/// Chỉ xem, không sửa - có bộ lọc
class FinancialActivityLogView extends StatefulWidget {
  final int initialTab; // 0 = tài chính, 1 = hệ thống
  final bool embedded;
  const FinancialActivityLogView({super.key, this.initialTab = 0, this.embedded = false});

  @override
  State<FinancialActivityLogView> createState() =>
      _FinancialActivityLogViewState();
}

class _FinancialActivityLogViewState extends State<FinancialActivityLogView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;

  // Tab Tài chính
  List<FinancialActivity> _activities = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 50;

  // Shop settings for multi-industry
  ShopSettings? _shopSettings;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;

  // Tab Hệ thống
  List<Map<String, dynamic>> _auditLogs = [];
  bool _auditLoading = true;

  // Bộ lọc - mặc định 30 ngày gần nhất
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedType;
  String? _selectedDirection;
  String _searchQuery = '';

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // Search cho tab hệ thống
  String _auditSearchQuery = '';
  final _auditSearchController = TextEditingController();

  // Danh sách loại activity - bao gồm cả types từ FinancialActivityService và PaymentIntentService
  List<Map<String, String>> get _activityTypes => [
    {'value': '', 'label': 'Tất cả'},
    {'value': 'SALE', 'label': '🛒 Bán hàng'},
    {'value': 'SALE_PAYMENT', 'label': '🛒 Thanh toán bán hàng'},
    {'value': 'PURCHASE', 'label': '📦 Nhập hàng'},
    {'value': 'INVENTORY_PURCHASE', 'label': '📦 Nhập kho'},
    {'value': 'EXPENSE', 'label': '💸 Chi phí'},
    {'value': 'OPERATING_EXPENSE', 'label': '💸 Chi phí vận hành'},
    {'value': 'UTILITY_EXPENSE', 'label': '💸 Chi phí tiện ích'},
    {'value': 'DEBT_COLLECT', 'label': '💰 Thu nợ'},
    {'value': 'CUSTOMER_DEBT_COLLECT', 'label': '💰 Thu nợ khách'},
    {'value': 'DEBT_PAY', 'label': '💳 Trả NCC'},
    {'value': 'SUPPLIER_DEBT', 'label': '💳 Trả nợ NCC'},
    {'value': 'SETTLEMENT', 'label': '🏦 Tất toán'},
    if (_enableRepair) {'value': 'REPAIR', 'label': '🔧 Sửa chữa'},
    if (_enableRepair) {'value': 'REPAIR_SERVICE', 'label': '🔧 Thanh toán sửa chữa'},
    if (_enableRepair) {'value': 'REPAIR_PARTNER_DEBT', 'label': '🔧 Trả đối tác SC'},
    if (_enableRepair) {'value': 'REPAIR_PARTS_COST', 'label': '🔩 Vốn LK SC'},
  ];

  final List<Map<String, String>> _directions = [
    {'value': '', 'label': 'Tất cả'},
    {'value': 'IN', 'label': '📥 Thu vào'},
    {'value': 'OUT', 'label': '📤 Chi ra'},
    {'value': 'DEBT', 'label': '📋 Công nợ'},
  ];

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(() {
      if (_tabController.index == 1 && _auditLogs.isEmpty) {
        _loadAuditLogs();
      }
    });
    _scrollController.addListener(_onScroll);
    _loadData();
    if (widget.initialTab == 1) {
      _loadAuditLogs();
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

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _auditSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _auditLoading = true);
    final data = await db.getAuditLogs();
    if (!mounted) return;
    setState(() {
      _auditLogs = data;
      _auditLoading = false;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  /// Query Firestore collection with server-side date filter.
  /// Falls back to unfiltered query if composite index is not ready yet.
  Future<QuerySnapshot<Map<String, dynamic>>> _queryWithDateFilter(
    CollectionReference<Map<String, dynamic>> collection,
    String shopId,
    String dateField,
    int startMs,
    int endMs,
  ) async {
    try {
      return await collection
          .where('shopId', isEqualTo: shopId)
          .where(dateField, isGreaterThanOrEqualTo: startMs)
          .where(dateField, isLessThanOrEqualTo: endMs)
          .get();
    } catch (e) {
      debugPrint('⚠️ Date filter failed for ${collection.path} (index may be building), fallback to full query');
      return await collection
          .where('shopId', isEqualTo: shopId)
          .get();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _offset = 0;
      _activities = [];
    });

    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final startMs = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      ).millisecondsSinceEpoch;
      final endMs = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;

      final firestore = FirebaseFirestore.instance;

      // Query all collections in parallel — with server-side date filter where safe
      // Note: expenses & supplier_import_history use unfiltered queries due to
      // inconsistent timestamp field names (date vs createdAt, importDate vs createdAt)
      final results = await Future.wait([
        // sales: composite index (shopId, soldAt) exists
        _queryWithDateFilter(firestore.collection('sales'), shopId, 'soldAt', startMs, endMs),
        // repairs: recognize only delivered repairs in period
        _queryWithDateFilter(firestore.collection('repairs'), shopId, 'deliveredAt', startMs, endMs),
        // expenses: field name varies (date/createdAt) — keep unfiltered for safety
        firestore.collection('expenses').where('shopId', isEqualTo: shopId).get(),
        // debt_payments: composite index (shopId, paidAt) deployed
        _queryWithDateFilter(firestore.collection('debt_payments'), shopId, 'paidAt', startMs, endMs),
        // supplier_payments: composite index (shopId, paidAt) deployed
        _queryWithDateFilter(firestore.collection('supplier_payments'), shopId, 'paidAt', startMs, endMs),
        // supplier_import_history: field name varies (importDate/importedAt/createdAt) — keep unfiltered
        firestore.collection('supplier_import_history').where('shopId', isEqualTo: shopId).get(),
        if (_enableRepair)
          // repair_partner_payments: composite index (shopId, paidAt) deployed
          _queryWithDateFilter(firestore.collection('repair_partner_payments'), shopId, 'paidAt', startMs, endMs),
      ]);

      final List<FinancialActivity> allActivities = [];

      void convertTimestamps(Map<String, dynamic> data) {
        for (var key in data.keys.toList()) {
          if (data[key] is Timestamp) {
            data[key] = (data[key] as Timestamp).millisecondsSinceEpoch;
          }
        }
      }

      // --- Sales ---
      for (var doc in results[0].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        final soldAt = data['soldAt'] as int? ?? 0;
        if (soldAt < startMs || soldAt > endMs) continue;

        data['firestoreId'] = doc.id;
        final sale = SaleOrder.fromMap(data);
        allActivities.add(FinancialActivity.fromSale(
          firestoreId: doc.id,
          amount: sale.finalPrice,
          paymentMethod: sale.paymentMethod,
          customerName: sale.customerName,
          phone: sale.phone,
          productNames: sale.productNames,
          sellerName: sale.sellerName,
          createdAt: sale.soldAt,
          shopId: shopId,
          isInstallment: sale.isInstallment,
          downPayment: sale.downPayment,
          downPaymentMethod: sale.downPaymentMethod,
          bankName: sale.bankName,
        ));
      }

      // --- Bank Settlements (Tất toán NH) ---
      // Iterate sales again to add settlement entries for bank installment sales
      // where the bank disbursement was received within the selected date range.
      for (var doc in results[0].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        data['firestoreId'] = doc.id;
        final sale = SaleOrder.fromMap(data);
        if (!sale.isInstallment) continue;
        if (sale.settlementReceivedAt == null || sale.settlementAmount <= 0) continue;
        if (sale.settlementReceivedAt! < startMs || sale.settlementReceivedAt! > endMs) continue;

        final banks = <String>[];
        if (sale.bankName != null && sale.bankName!.isNotEmpty) banks.add(sale.bankName!);
        if (sale.bankName2 != null && sale.bankName2!.isNotEmpty) banks.add(sale.bankName2!);
        final bankDisplay = banks.isNotEmpty ? banks.join(' + ') : 'NH';

        allActivities.add(FinancialActivity.fromSettlement(
          saleFirestoreId: doc.id,
          amount: sale.settlementAmount,
          bankName: bankDisplay,
          customerName: sale.customerName,
          productNames: sale.productNames,
          createdAt: sale.settlementReceivedAt!,
          settlementFee: sale.settlementFee,
          shopId: shopId,
        ));
      }

      // --- Repairs ---
      if (_enableRepair) {
        for (var doc in results[1].docs) {
          final data = doc.data();
          if (data['deleted'] == true) continue;
          convertTimestamps(data);
          final deliveredAt = data['deliveredAt'] as int? ?? 0;
          final status = (data['status'] as num?)?.toInt() ?? 0;
          if (status != 4) continue;
          if (deliveredAt < startMs || deliveredAt > endMs) continue;

          data['firestoreId'] = doc.id;
          final repair = Repair.fromMap(data);
          // Thu sửa chỉ ghi nhận khi đã thu tiền, không ghi khi còn công nợ.
          if (repair.paymentMethod != 'CÔNG NỢ' && repair.price > 0) {
            allActivities.add(FinancialActivity.fromRepair(
              firestoreId: doc.id,
              amount: repair.price,
              paymentMethod: repair.paymentMethod,
              customerName: repair.customerName,
              phone: repair.phone,
              deviceModel: repair.model,
              createdAt: deliveredAt,
              shopId: shopId,
            ));
          }

          // Repair parts cost recorded in fund
          if (repair.costRecordedInFund &&
              repair.costRecordedAt != null &&
              repair.costRecordedAt! >= startMs &&
              repair.costRecordedAt! <= endMs) {
            final recordedAmount = (repair.costRecordedAmount ?? 0) > 0
                ? (repair.costRecordedAmount ?? 0)
                : repair.totalCost;
            allActivities.add(FinancialActivity.fromRepairPartsCost(
              firestoreId: doc.id,
              amount: recordedAmount,
              paymentMethod: repair.costPaymentMethod ?? 'TIỀN MẶT',
              customerName: repair.customerName,
              phone: repair.phone,
              deviceModel: repair.model,
              createdAt: repair.costRecordedAt!,
              shopId: shopId,
            ));
          }
        }
      }

      // --- Expenses ---
      for (var doc in results[2].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        final createdAt = data['createdAt'] as int? ?? data['date'] as int? ?? 0;
        if (createdAt < startMs || createdAt > endMs) continue;

        allActivities.add(FinancialActivity.fromExpense(
          firestoreId: doc.id,
          amount: (data['amount'] as num?)?.toInt() ?? 0,
          paymentMethod: data['paymentMethod'] as String? ?? 'TIỀN MẶT',
          title: data['title'] as String? ?? 'Chi phí',
          category: data['category'] as String? ?? '',
          note: data['note'] as String?,
          createdAt: createdAt,
          createdBy: data['createdBy'] as String?,
          shopId: shopId,
        ));
      }

      // --- Debt Payments (Thu nợ) ---
      for (var doc in results[3].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        final paidAt = data['paidAt'] as int? ?? data['createdAt'] as int? ?? 0;
        if (paidAt < startMs || paidAt > endMs) continue;

        allActivities.add(FinancialActivity.fromDebtCollection(
          firestoreId: doc.id,
          amount: (data['amount'] as num?)?.toInt() ?? 0,
          paymentMethod: data['paymentMethod'] as String? ?? 'TIỀN MẶT',
          customerName: data['customerName'] as String? ?? data['debtorName'] as String? ?? '',
          phone: data['phone'] as String? ?? '',
          createdAt: paidAt,
          createdBy: data['collectedBy'] as String? ?? data['createdBy'] as String?,
          shopId: shopId,
          note: data['note'] as String?,
        ));
      }

      // --- Supplier Payments (Trả NCC) ---
      for (var doc in results[4].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        final paidAt = data['paidAt'] as int? ?? data['createdAt'] as int? ?? 0;
        if (paidAt < startMs || paidAt > endMs) continue;

        allActivities.add(FinancialActivity.fromSupplierPayment(
          firestoreId: doc.id,
          amount: (data['amount'] as num?)?.toInt() ?? 0,
          paymentMethod: data['paymentMethod'] as String? ?? 'TIỀN MẶT',
          supplierName: data['supplierName'] as String? ?? '',
          createdAt: paidAt,
          note: data['note'] as String?,
          createdBy: data['createdBy'] as String?,
          shopId: shopId,
        ));
      }

      // --- Supplier Imports (Nhập hàng) ---
      for (var doc in results[5].docs) {
        final data = doc.data();
        if (data['deleted'] == true) continue;
        convertTimestamps(data);
        final importedAt = data['importedAt'] as int? ?? data['createdAt'] as int? ?? 0;
        if (importedAt < startMs || importedAt > endMs) continue;

        allActivities.add(FinancialActivity.fromPurchase(
          firestoreId: doc.id,
          amount: (data['totalAmount'] as num?)?.toInt() ?? (data['amount'] as num?)?.toInt() ?? 0,
          paymentMethod: data['paymentMethod'] as String? ?? 'TIỀN MẶT',
          productName: data['productName'] as String? ?? data['note'] as String? ?? 'Nhập hàng',
          supplierName: data['supplierName'] as String? ?? '',
          quantity: (data['quantity'] as num?)?.toInt() ?? 1,
          createdAt: importedAt,
          createdBy: data['createdBy'] as String?,
          shopId: shopId,
        ));
      }

      // --- Repair Partner Payments (Trả đối tác sửa chữa) ---
      if (_enableRepair && results.length > 6) {
        for (var doc in results[6].docs) {
          final data = doc.data();
          if (data['deleted'] == true || data['deleted'] == 1) continue;
          convertTimestamps(data);
          final paidAt = data['paidAt'] as int? ?? data['createdAt'] as int? ?? 0;
          if (paidAt < startMs || paidAt > endMs) continue;

          allActivities.add(FinancialActivity.fromRepairPartnerPayment(
            firestoreId: doc.id,
            amount: (data['amount'] as num?)?.toInt() ?? 0,
            paymentMethod: data['paymentMethod'] as String? ?? 'TIỀN MẶT',
            partnerName: data['partnerName'] as String? ?? 'Đối tác',
            createdAt: paidAt,
            note: data['note'] as String?,
            createdBy: data['createdBy'] as String?,
            shopId: shopId,
          ));
        }
      }

      // Apply filters
      var filtered = allActivities;
      if (_selectedType != null && _selectedType!.isNotEmpty) {
        filtered = filtered.where((a) => a.activityType == _selectedType).toList();
      }
      if (_selectedDirection != null && _selectedDirection!.isNotEmpty) {
        filtered = filtered.where((a) => a.direction == _selectedDirection).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        filtered = filtered.where((a) =>
          a.title.toLowerCase().contains(q) ||
          (a.customerName?.toLowerCase().contains(q) ?? false) ||
          (a.phone?.toLowerCase().contains(q) ?? false) ||
          (a.description?.toLowerCase().contains(q) ?? false) ||
          (a.productInfo?.toLowerCase().contains(q) ?? false)
        ).toList();
      }

      // Sort by date descending
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Compute summary
      int totalIn = 0, totalOut = 0, totalDebt = 0;
      for (var a in filtered) {
        if (a.direction == 'IN') totalIn += a.amount;
        else if (a.direction == 'OUT') totalOut += a.amount;
        else if (a.direction == 'DEBT') totalDebt += a.amount;
      }

      if (!mounted) return;
      setState(() {
        _summary = {
          'totalIn': totalIn,
          'totalOut': totalOut,
          'totalDebt': totalDebt,
          'totalCount': filtered.length,
        };
        _activities = filtered;
        _offset = filtered.length;
        _hasMore = false;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading financial activities: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    // All data loaded in _loadData(), no pagination needed
  }

  void _showFilterSheet() {
    // Lưu giá trị tạm để có thể cancel
    String? tempType = _selectedType;
    String? tempDirection = _selectedDirection;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bộ lọc',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        tempType = null;
                        tempDirection = null;
                      });
                      setState(() {
                        _startDate = DateTime.now();
                        _endDate = DateTime.now();
                        _selectedType = null;
                        _selectedDirection = null;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                      Navigator.pop(ctx);
                      _loadData();
                    },
                    child: const Text('Đặt lại'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Khoảng thời gian
              const Text(
                '📅 Khoảng thời gian',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('→'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('dd/MM/yyyy').format(_endDate)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Loại hoạt động
              const Text(
                '📊 Loại hoạt động',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _activityTypes.map((t) {
                  final isSelected = (tempType ?? '') == t['value'];
                  return ChoiceChip(
                    label: Text(
                      t['label']!,
                      style: TextStyle(
                        fontSize: AppTextStyles.subtitle1.fontSize,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setSheetState(() => tempType = t['value']),
                    selectedColor: Colors.blue.shade100,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Hướng tiền
              const Text(
                '💵 Hướng tiền',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _directions.map((d) {
                  final isSelected = (tempDirection ?? '') == d['value'];
                  return ChoiceChip(
                    label: Text(
                      d['label']!,
                      style: TextStyle(
                        fontSize: AppTextStyles.subtitle1.fontSize,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setSheetState(() => tempDirection = d['value']),
                    selectedColor: Colors.green.shade100,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Nút áp dụng
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Áp dụng filter
                    setState(() {
                      _selectedType = tempType;
                      _selectedDirection = tempDirection;
                    });
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2962FF),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'ÁP DỤNG BỘ LỌC',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 10),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_startDate.isAfter(_endDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_endDate.isBefore(_startDate)) _startDate = _endDate;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildEmbeddedContent();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.build(
        title: 'NHẬT KÝ',
        subtitle: _tabController.index == 0
            ? '${_activities.length} hoạt động'
            : '${_auditLogs.length} log',
        accentColor: AppBarAccents.finance,
        actions: [
          if (_tabController.index == 0) ...[
            IconButton(
              onPressed: _showFilterSheet,
              icon: Badge(
                isLabelVisible:
                    _selectedType != null ||
                    _selectedDirection != null ||
                    _searchQuery.isNotEmpty,
                child: const Icon(
                  Icons.filter_list_rounded,
                  size: 20,
                  color: AppBarAccents.finance,
                ),
              ),
              tooltip: 'Bộ lọc',
              splashRadius: 18,
            ),
          ],
          IconButton(
            onPressed: () {
              if (_tabController.index == 0) {
                _loadData();
              } else {
                _loadAuditLogs();
              }
            },
            icon: const Icon(
              Icons.refresh_rounded,
              size: 20,
              color: AppBarAccents.finance,
            ),
            tooltip: 'Làm mới',
            splashRadius: 18,
          ),
          IconButton(
            icon: const Icon(
              Icons.file_download_outlined,
              size: 20,
              color: AppBarAccents.finance,
            ),
            tooltip: 'Xuất Excel nhật ký',
            splashRadius: 18,
            onPressed: () async {
              if (_tabController.index == 0) {
                // Export "Tài chính" tab — use already-loaded data
                if (_activities.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không có dữ liệu tài chính để xuất')),
                  );
                  return;
                }
                if (!mounted) return;
                await ExcelExportHelper.exportActivityLog(
                  context,
                  activities: _activities,
                  startMs: DateTime(_startDate.year, _startDate.month, _startDate.day).millisecondsSinceEpoch,
                  endMs: DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59).millisecondsSinceEpoch,
                );
              } else {
                // Export "Hệ thống" tab — use already-loaded audit logs
                final logs = _filteredAuditLogs;
                if (logs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không có dữ liệu hệ thống để xuất')),
                  );
                  return;
                }
                if (!mounted) return;
                await ExcelExportHelper.exportAuditLog(
                  context,
                  auditLogs: logs,
                );
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_tabController.index == 0 ? 82 : 40),
          child: _buildStandaloneTabBar(),
        ),
      ),
      body: ResponsiveCenter(
        child: TabBarView(
        controller: _tabController,
        children: [_buildFinancialTab(), _buildAuditLogTab()],
      ),
      ),
    );
  }

  /// TabBar for standalone mode (used in AppBar bottom)
  Widget _buildStandaloneTabBar() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppBarAccents.finance,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppBarAccents.finance,
            indicatorWeight: 2,
            labelStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.subtitle1.fontSize,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: AppTextStyles.subtitle1.fontSize,
            ),
            tabs: const [
              Tab(height: 36, text: 'Tài chính'),
              Tab(height: 36, text: 'Hệ thống'),
            ],
            onTap: (_) => setState(() {}),
          ),
        ),
        if (_tabController.index == 0)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Colors.white,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(17),
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: (v) {
                  _searchQuery = v.trim();
                  _loadData();
                },
                style: TextStyle(
                  color: CustomAppBar.kTextPrimary,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                ),
                cursorColor: AppBarAccents.finance,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, SĐT, mô tả...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppBarAccents.finance,
                    size: 16,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade500,
                            size: 16,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _loadData();
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
      ],
    );
  }

  /// Embedded mode - no Scaffold/AppBar, compact inline tabs
  Widget _buildEmbeddedContent() {
    return Column(
      children: [
        // TabBar + actions in one row
        _buildTabBarAndSearch(),
        // Body
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildFinancialTab(), _buildAuditLogTab()],
          ),
        ),
      ],
    );
  }

  /// Shared TabBar + Search widget
  Widget _buildTabBarAndSearch() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppBarAccents.finance,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppBarAccents.finance,
                  indicatorWeight: 2,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                  tabs: const [
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(Icons.account_balance_wallet, size: 16), SizedBox(width: 6), Text('Tài chính')],
                      ),
                    ),
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(Icons.history, size: 16), SizedBox(width: 6), Text('Hệ thống')],
                      ),
                    ),
                  ],
                  onTap: (_) => setState(() {}),
                ),
              ),
              if (_tabController.index == 0)
                IconButton(
                  onPressed: _showFilterSheet,
                  icon: Badge(
                    isLabelVisible:
                        _selectedType != null ||
                        _selectedDirection != null ||
                        _searchQuery.isNotEmpty,
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color: AppBarAccents.finance,
                    ),
                  ),
                  tooltip: 'Bộ lọc',
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              IconButton(
                onPressed: () {
                  if (_tabController.index == 0) {
                    _loadData();
                  } else {
                    _loadAuditLogs();
                  }
                },
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppBarAccents.finance,
                ),
                tooltip: 'Làm mới',
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (_tabController.index == 0)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Colors.white,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(17),
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: (v) {
                  _searchQuery = v.trim();
                  _loadData();
                },
                style: TextStyle(
                  color: CustomAppBar.kTextPrimary,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                ),
                cursorColor: AppBarAccents.finance,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, SĐT, mô tả...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppBarAccents.finance,
                    size: 16,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.grey.shade500,
                            size: 16,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _loadData();
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
      ],
    );
  }

  /// Tab Tài chính - dùng single scrollable list tránh bottom overflow
  Widget _buildFinancialTab() {
    if (_loading && _activities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_activities.isEmpty) {
      return _buildEmptyState();
    }
    // Header count: summary (0) + date range (1) = 2
    final headerCount = 2;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: headerCount + _activities.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == 0) return _buildSummarySection();
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.date_range, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_activities.length} hoạt động',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                ),
              ],
            ),
          );
        }
        final actIndex = i - headerCount;
        if (actIndex >= _activities.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _buildActivityCard(_activities[actIndex]);
      },
    );
  }

  /// Filtered audit logs based on search
  List<Map<String, dynamic>> get _filteredAuditLogs {
    if (_auditSearchQuery.isEmpty) return _auditLogs;
    final q = _auditSearchQuery.toLowerCase();
    return _auditLogs.where((log) {
      final action = (log['action'] ?? '').toString().toLowerCase();
      final description = (log['description'] ?? log['summary'] ?? '').toString().toLowerCase();
      final userName = (log['userName'] ?? '').toString().toLowerCase();
      final entityType = (log['targetType'] ?? log['entityType'] ?? '').toString().toLowerCase();
      final entityId = (log['targetId'] ?? log['entityId'] ?? '').toString().toLowerCase();
      return action.contains(q) || description.contains(q) || userName.contains(q) || entityType.contains(q) || entityId.contains(q);
    }).toList();
  }

  /// Tab Nhật ký hệ thống
  Widget _buildAuditLogTab() {
    if (_auditLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = _filteredAuditLogs;
    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          color: Colors.white,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(19),
            ),
            child: TextField(
              controller: _auditSearchController,
              onChanged: (v) {
                setState(() => _auditSearchQuery = v.trim());
              },
              style: TextStyle(
                color: Colors.black87,
                fontSize: AppTextStyles.subtitle1.fontSize,
              ),
              decoration: InputDecoration(
                hintText: 'Tìm theo hành động, người dùng, mô tả...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                suffixIcon: _auditSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade500),
                        onPressed: () {
                          _auditSearchController.clear();
                          setState(() => _auditSearchQuery = '');
                        },
                        splashRadius: 14,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        ),
        // Count
        if (_auditSearchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Tìm thấy ${filtered.length} kết quả',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        // Content
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        _auditSearchQuery.isNotEmpty
                            ? 'Không tìm thấy kết quả cho "$_auditSearchQuery"'
                            : 'Chưa có ghi chép hoạt động nào',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildAuditLogCard(filtered[i], i + 1),
                ),
        ),
      ],
    );
  }

  Widget _buildAuditLogCard(Map<String, dynamic> log, int index) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(log['createdAt']);
    final Color actionColor = _getAuditActionColor(log['action']);
    final String entityType = log['targetType'] ?? log['entityType'] ?? '';
    final String entityId = log['targetId'] ?? log['entityId'] ?? '';
    final String description = log['description'] ?? log['summary'] ?? '';

    return GestureDetector(
      onTap: () => _showAuditLogDetail(log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: STT + Action + Time
            Row(
              children: [
                // STT badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: actionColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        fontWeight: FontWeight.bold,
                        color: actionColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: actionColor.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getAuditActionIcon(log['action']),
                    color: actionColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                // Action name
                Expanded(
                  child: Text(
                    log['action'] ?? '',
                    style: TextStyle(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.body1.fontSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Time badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('HH:mm').format(date),
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Content row: Description
            if (description.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 10),
            // Footer row: User, EntityType, Date
            Row(
              children: [
                // User badge
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 12,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            log['userName'] ?? '?',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // EntityType badge
                if (entityType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getEntityTypeColor(entityType).withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getEntityTypeName(entityType),
                      style: TextStyle(
                        fontSize: AppTextStyles.caption.fontSize,
                        fontWeight: FontWeight.bold,
                        color: _getEntityTypeColor(entityType),
                      ),
                    ),
                  ),
                const Spacer(),
                // Date
                Text(
                  DateFormat('dd/MM').format(date),
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
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

  void _showAuditLogDetail(Map<String, dynamic> log) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(log['createdAt']);
    final Color actionColor = _getAuditActionColor(log['action']);
    final String entityType = log['targetType'] ?? log['entityType'] ?? '';
    final String entityId = log['targetId'] ?? log['entityId'] ?? '';
    final String description = log['description'] ?? log['summary'] ?? '';

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: actionColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getAuditActionIcon(log['action']),
                      color: actionColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log['action'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline2.fontSize,
                            color: actionColor,
                          ),
                        ),
                        Text(
                          DateFormat('HH:mm - dd/MM/yyyy').format(date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: AppTextStyles.body1.fontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              // Details
              _buildAuditDetailRow(
                'Người thực hiện',
                log['userName'] ?? 'Unknown',
              ),
              if (log['email'] != null && log['email'].toString().isNotEmpty)
                _buildAuditDetailRow('Email', log['email'].toString()),
              if (log['role'] != null && log['role'].toString().isNotEmpty)
                _buildAuditDetailRow('Vai trò', log['role'].toString()),
              if (entityType.isNotEmpty)
                _buildAuditDetailRow(
                  'Loại đối tượng',
                  _getEntityTypeName(entityType),
                ),
              if (entityId.isNotEmpty)
                _buildAuditDetailRow('ID đối tượng', entityId),
              if (description.isNotEmpty)
                _buildAuditDetailRow('Mô tả', description),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  Color _getEntityTypeColor(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PRODUCT':
        return Colors.indigo;
      case 'SALE':
        return Colors.pink;
      case 'SUPPLIER':
        return Colors.teal;
      case 'STAFF':
        return Colors.orange;
      case 'EXPENSE':
        return Colors.red;
      case 'REPAIR':
        return Colors.blue;
      case 'CASH_CLOSE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getEntityTypeName(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PRODUCT':
        return 'Sản phẩm';
      case 'SALE':
        return 'Đơn bán';
      case 'SUPPLIER':
        return 'NCC';
      case 'STAFF':
        return 'Nhân viên';
      case 'EXPENSE':
        return 'Chi phí';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'CASH_CLOSE':
        return 'Chốt sổ';
      default:
        return entityType;
    }
  }

  Color _getAuditActionColor(String? action) {
    if (action == null) return Colors.blue;
    if (action.contains("XÓA")) return Colors.red;
    if (action.contains("NHẬP") || action.contains("THÊM")) return Colors.green;
    if (action.contains("SỬA") || action.contains("CẬP NHẬT"))
      return Colors.orange;
    if (action.contains("BÁN")) return Colors.pink;
    return Colors.blue;
  }

  IconData _getAuditActionIcon(String? action) {
    if (action == null) return Icons.info_outline;
    if (action.contains("XÓA")) return Icons.delete_forever;
    if (action.contains("NHẬP")) return Icons.add_business;
    if (action.contains("BÁN")) return Icons.shopping_cart;
    if (action.contains("SỬA")) return Icons.edit_note;
    return Icons.info_outline;
  }

  Widget _buildSummarySection() {
    final totalIn = _summary['totalIn'] as int? ?? 0;
    final totalOut = _summary['totalOut'] as int? ?? 0;
    final totalDebt = _summary['totalDebt'] as int? ?? 0;
    final totalCount = _summary['totalCount'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withAlpha(50),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.arrow_downward,
                  iconColor: Colors.greenAccent,
                  label: 'Tổng thu',
                  value: _formatMoney(totalIn),
                ),
              ),
              Container(width: 1, height: 50, color: Colors.white30),
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.arrow_upward,
                  iconColor: Colors.redAccent,
                  label: 'Tổng chi',
                  value: _formatMoney(totalOut),
                ),
              ),
              Container(width: 1, height: 50, color: Colors.white30),
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.receipt_long,
                  iconColor: Colors.amberAccent,
                  label: 'Công nợ',
                  value: _formatMoney(totalDebt),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  '💵 Lãi: ',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: AppTextStyles.caption.fontSize,
                  ),
                ),
                Flexible(
                  child: Text(
                    _formatMoney(totalIn - totalOut),
                    style: TextStyle(
                      color: (totalIn - totalOut) >= 0
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '📊 $totalCount GD',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: AppTextStyles.caption.fontSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.subtitle1.fontSize,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(200),
            fontSize: AppTextStyles.caption.fontSize,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Chưa có hoạt động tài chính',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: AppTextStyles.headline3.fontSize,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Các giao dịch sẽ được ghi lại tự động',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: AppTextStyles.headline5.fontSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(FinancialActivity activity) {
    final date = DateTime.fromMillisecondsSinceEpoch(activity.createdAt);
    final directionColor = _getDirectionColor(activity.direction);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showActivityDetail(activity),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: directionColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  activity.icon,
                  style: TextStyle(fontSize: AppTextStyles.headline1.fontSize),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + Time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            activity.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextStyles.headline5.fontSize,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat('HH:mm').format(date),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: AppTextStyles.body1.fontSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Customer + Date
                    Row(
                      children: [
                        if (activity.customerName != null &&
                            activity.customerName!.isNotEmpty) ...[
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              activity.customerName!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: AppTextStyles.body1.fontSize,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          DateFormat('dd/MM').format(date),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: AppTextStyles.body1.fontSize,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Amount + Type badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Amount
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: directionColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                activity.direction == 'IN'
                                    ? Icons.add
                                    : activity.direction == 'OUT'
                                    ? Icons.remove
                                    : Icons.swap_horiz,
                                size: 12,
                                color: directionColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${activity.direction == 'OUT'
                                    ? '-'
                                    : activity.direction == 'IN'
                                    ? '+'
                                    : ''}${_formatMoney(activity.amount)}',
                                style: TextStyle(
                                  color: directionColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextStyles.subtitle1.fontSize,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Payment method + Type
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                activity.paymentMethod,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: AppTextStyles.caption.fontSize,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getTypeColor(
                                  activity.activityType,
                                ).withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                activity.activityTypeName,
                                style: TextStyle(
                                  color: _getTypeColor(activity.activityType),
                                  fontSize: AppTextStyles.caption.fontSize,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActivityDetail(FinancialActivity activity) {
    final date = DateTime.fromMillisecondsSinceEpoch(activity.createdAt);

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getDirectionColor(activity.direction).withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activity.icon,
                    style: TextStyle(
                      fontSize: AppTextStyles.headline1.fontSize,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.activityTypeName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline2.fontSize,
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm - dd/MM/yyyy').format(date),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: AppTextStyles.headline5.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getDirectionColor(activity.direction).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${activity.direction == 'IN'
                        ? '+'
                        : activity.direction == 'OUT'
                        ? '-'
                        : ''}${_formatMoney(activity.amount)}',
                    style: TextStyle(
                      color: _getDirectionColor(activity.direction),
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.headline3.fontSize,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Details
            _buildDetailRow('Tiêu đề', activity.title),
            if (activity.description != null &&
                activity.description!.isNotEmpty)
              _buildDetailRow('Mô tả', activity.description!),
            if (activity.customerName != null &&
                activity.customerName!.isNotEmpty)
              _buildDetailRow('Khách hàng / NCC', activity.customerName!),
            if (activity.phone != null && activity.phone!.isNotEmpty)
              _buildDetailRow('SĐT', activity.phone!),
            if (activity.productInfo != null &&
                activity.productInfo!.isNotEmpty)
              _buildDetailRow('Sản phẩm', activity.productInfo!),
            _buildDetailRow('Hình thức', activity.paymentMethod),
            _buildDetailRow(
              'Hướng tiền',
              activity.direction == 'IN'
                  ? 'Thu vào quỹ'
                  : activity.direction == 'OUT'
                  ? 'Chi ra quỹ'
                  : 'Công nợ (chưa thu/chi)',
            ),
            if (activity.createdBy != null && activity.createdBy!.isNotEmpty)
              _buildDetailRow('Người thực hiện', activity.createdBy!),
            if (activity.referenceType != null)
              _buildDetailRow('Loại tham chiếu', activity.referenceType!),

            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: AppTextStyles.headline5.fontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: AppTextStyles.headline5.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getDirectionColor(String direction) {
    switch (direction) {
      case 'IN':
        return Colors.green;
      case 'OUT':
        return Colors.red;
      case 'DEBT':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'SALE':
        return Colors.pink;
      case 'PURCHASE':
        return Colors.indigo;
      case 'EXPENSE':
        return Colors.red;
      case 'DEBT_COLLECT':
        return Colors.green;
      case 'DEBT_PAY':
        return Colors.orange;
      case 'SETTLEMENT':
        return Colors.blue;
      case 'REPAIR':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(1)}tỷ';
    } else if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      final formatter = NumberFormat('#,###', 'vi_VN');
      return '${formatter.format(amount)}đ';
    }
    return '$amountđ';
  }
}
