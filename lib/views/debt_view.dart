import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';
import '../widgets/custom_app_bar.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../services/adjustment_service.dart';
import '../services/first_time_guide_service.dart';
import '../services/debt_summary_service.dart';
import '../services/repair_partner_service.dart';
import '../services/payment_intent_service.dart';
import '../models/payment_intent_model.dart';
import '../services/audit_service.dart';
import '../services/user_service.dart';
import '../constants/financial_constants.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';
import '../models/shop_settings_model.dart';
import '../services/category_service.dart';
import '../widgets/responsive_wrapper.dart';
import 'repair_partner_detail_view.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';

class DebtView extends StatefulWidget {
  const DebtView({super.key});
  @override
  State<DebtView> createState() => _DebtViewState();
}

class _DebtViewState extends State<DebtView>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final db = DBHelper();
  final _partnerService = RepairPartnerService();
  final _debtSummaryService = DebtSummaryService();
  TabController? _tabController;
  List<Map<String, dynamic>> _debts = [];
  List<Map<String, dynamic>> _partnerDebts = []; // Công nợ đối tác sửa chữa
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatus = 'Đã đồng bộ';
  StreamSubscription<String>? _eventSub;
  Timer? _reloadDebounce;

  // Shop settings for multi-industry
  ShopSettings? _shopSettings;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;
  int get _tabCount =>
      _enableRepair ? 4 : 3; // 4 tabs for electronics, 3 for fashion
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadShopSettings();
    _loadRole();
    _refresh();

    // Listen to global events (e.g., debts changed) to refresh the list when other parts of the app write debts
    _eventSub = EventBus().stream
        .where((e) => e == 'debts_changed' || e == 'repair_partners_changed')
        .listen((_) {
          _debouncedRefresh();
        });

    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() {
          _shopSettings = settings;
          _tabController = TabController(length: _tabCount, vsync: this);
        });
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
      // Fallback to default 4 tabs
      if (mounted) {
        setState(() => _tabController = TabController(length: 4, vsync: this));
      }
    }
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keyDebtManagement,
      title: 'Quản Lý Công Nợ',
      icon: Icons.account_balance_wallet,
      color: Colors.red,
      steps: [
        GuideStep(
          title: _enableRepair ? '📊 3 loại công nợ' : '📊 2 loại công nợ',
          description: _enableRepair
              ? 'KHÁCH NỢ (khách chưa TT), NỢ NCC (nợ nhà cung cấp), NỢ ĐỐI TÁC (nợ thợ sửa ngoài).'
              : 'KHÁCH NỢ (khách chưa TT), NỢ NCC (nợ nhà cung cấp).',
          icon: Icons.category,
          iconColor: Colors.blue,
        ),
        const GuideStep(
          title: '💰 Ghi nhận thanh toán',
          description:
              'Nhấn vào khoản nợ để xem chi tiết và ghi nhận thanh toán từng phần hoặc toàn bộ.',
          icon: Icons.payment,
          iconColor: Colors.green,
        ),
        const GuideStep(
          title: '📅 Theo dõi hạn nợ',
          description:
              'Nợ quá hạn sẽ được highlight đỏ. Báo cáo tổng hợp giúp theo dõi dòng tiền.',
          icon: Icons.event,
          iconColor: Colors.orange,
        ),
        const GuideStep(
          title: '🔄 Tự động tạo nợ',
          description:
              'Khi bán hàng/nhập kho chọn "CÔNG NỢ", hệ thống tự tạo khoản nợ tương ứng.',
          icon: Icons.auto_mode,
          iconColor: Colors.blue,
        ),
      ],
    );
  }

  void _debouncedRefresh() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _tabController?.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRole() async {
    // Role loading not needed for current functionality
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewDebts'] ?? false);
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);

    // Load regular debts
    final data = await db.getAllDebts();
    debugPrint('DebtView: getAllDebts returned ${data.length} debts');
    for (final d in data) {
      debugPrint(
        '  - type=${d['type']}, personName=${d['personName']}, totalAmount=${d['totalAmount']}, deleted=${d['deleted']}, firestoreId=${d['firestoreId']}',
      );
    }

    final partnerDebts = await _debtSummaryService.loadPartnerDebts(
      allDebts: data,
    );

    final manualPartnerDebts = partnerDebts
        .where((d) => d['source'] == 'manual')
        .toList();

    debugPrint(
      'DebtView: Found ${manualPartnerDebts.length} manual REPAIR_PARTNER debts',
    );
    for (final d in manualPartnerDebts) {
      debugPrint('  - ${d['partnerName']}: ${d['totalAmount']}');
    }

    if (!mounted) return;
    setState(() {
      _debts = _debtSummaryService.filterStandardDebts(data);
      _partnerDebts = partnerDebts;
      _isLoading = false;
    });
  }

  Future<void> _syncWithFirebase() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Đang đồng bộ...';
    });

    try {
      await SyncService.syncAllToCloud();
      // Real-time listeners handle downloads — chỉ push local changes

      // Reload data after sync
      await _refresh();

      if (mounted) {
        setState(() {
          _syncStatus = 'Đã đồng bộ';
        });
      }
    } catch (e) {
      print('DEBUG: Sync error: $e');
      if (mounted) {
        setState(() {
          _syncStatus = 'Lỗi đồng bộ';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _showDebtHistory(Map<String, dynamic> debt) async {
    final payments = await db.getDebtPayments(debt['id']);
    if (!mounted) return;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "LỊCH SỬ THANH TOÁN",
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              debt['personName'].toString().toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.onSurface.withOpacity(0.7),
              ),
            ),
            const Divider(height: 30),
            if (payments.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  "Chưa có lịch sử trả nợ",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: ListView.builder(
                  itemCount: payments.length,
                  itemBuilder: (ctx, i) {
                    final p = payments[i];
                    final date = DateFormat(
                      'HH:mm - dd/MM/yyyy',
                    ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt']));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "+ ${MoneyUtils.formatCurrency(p['amount'])}",
                                style: AppTextStyles.priceStyle,
                              ),
                              Text(
                                date,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                p['createdBy'] ?? "NV",
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                p['paymentMethod'] ?? "TIỀN MẶT",
                                style: AppTextStyles.overline.copyWith(
                                  color: AppColors.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _payDebt(debt);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
              ),
              child: Text("THANH TOÁN NỢ", style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }

  // Widget hiển thị giá trị trong dialog thanh toán nợ
  Widget _miniPayValue(String label, int amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyles.overlineSize,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          '${MoneyUtils.formatCurrency(amount)}đ',
          style: TextStyle(
            fontSize: AppTextStyles.caption.fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _payDebt(Map<String, dynamic> debt) async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa (thanh toán ở ngày hiện tại)
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thu tiền trả nợ.',
        color: Colors.red,
      );
      return;
    }

    final totalAmount = debt['totalAmount'] as int? ?? 0;
    final paidAmount = debt['paidAmount'] as int? ?? 0;
    final remainingAmount = totalAmount - paidAmount;
    final isCustomerDebtForTitle =
        (debt['type'] ?? 'CUSTOMER_OWES') == 'CUSTOMER_OWES';

    final formKey = GlobalKey<FormState>();
    final payC = TextEditingController();
    String payMethod = 'TIỀN MẶT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isCustomerDebtForTitle ? "THU NỢ KHÁCH" : "THANH TOÁN NỢ"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin tổng quan nợ
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _miniPayValue('Tổng nợ', totalAmount, Colors.grey.shade700),
                      _miniPayValue('Đã trả', paidAmount, Colors.green),
                      _miniPayValue('Còn lại', remainingAmount, Colors.red),
                    ],
                  ),
                ),
                CurrencyTextField(
                  controller: payC,
                  label: isCustomerDebtForTitle ? "SỐ TIỀN THU (VNĐ)" : "SỐ TIỀN THANH TOÁN (VNĐ)",
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    max: remainingAmount,
                    fieldName: isCustomerDebtForTitle ? 'Số tiền thu' : 'Số tiền thanh toán',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "THANH TOÁN BẰNG",
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['TIỀN MẶT', 'CHUYỂN KHOẢN']
                      .map(
                        (m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text(m, style: AppTextStyles.caption),
                              selected: payMethod == m,
                              onSelected: (v) => setS(() => payMethod = m),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final parsed = MoneyUtils.parseCurrency(payC.text);
                final payAmount = parsed;
                if (payAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;

                // Đóng dialog trước
                Navigator.of(ctx).pop();

                // Xác định loại nợ để tạo PaymentIntent phù hợp
                final debtType = debt['type'] ?? 'CUSTOMER_OWES';
                final isCustomerDebt = debtType == 'CUSTOMER_OWES';

                // Convert payment method
                final method = payMethod == 'CHUYỂN KHOẢN'
                    ? PaymentMethod.transfer
                    : PaymentMethod.cash;

                // Execute payment directly without navigation
                final result = await PaymentIntentService.executePaymentDirect(
                  type: isCustomerDebt
                      ? PaymentIntentType.customerDebtCollection
                      : PaymentIntentType.supplierDebt,
                  amount: payAmount,
                  paymentMethod: method,
                  description: isCustomerDebt
                      ? 'Thu nợ khách: ${debt['personName'] ?? 'N/A'}'
                      : 'Thanh toán nợ NCC: ${debt['personName'] ?? 'N/A'}',
                  executedBy: user?.displayName ?? user?.email ?? 'unknown',
                  referenceId: debt['firestoreId'],
                  referenceType: 'debt',
                  personName: debt['personName'],
                  personPhone: debt['phone'],
                  idempotencyKey: debt['firestoreId'],
                  metadata: {
                    'debtId': debt['id'],
                    'debtFirestoreId': debt['firestoreId'],
                    'debtType': debtType,
                    'linkedId': debt['linkedId'],
                  },
                );

                if (result.success) {
                  // Audit log
                  await AuditService.logAction(
                    action: isCustomerDebt ? 'DEBT_COLLECTED' : 'SUPPLIER_PAID',
                    entityType: 'DEBT',
                    entityId: debt['firestoreId'] ?? '',
                    summary:
                        '${isCustomerDebt ? "Thu nợ" : "Thanh toán nợ"} ${debt['personName']}: ${MoneyUtils.formatCurrency(payAmount)}đ',
                  );
                  EventBus().emit('debts_changed');
                  if (mounted) {
                    NotificationService.showSnackBar(
                      "Đã ${isCustomerDebt ? 'thu' : 'trả'} nợ ${MoneyUtils.formatCurrency(payAmount)}đ!",
                      color: Colors.green,
                    );
                    await _refresh();
                  }
                } else {
                  if (mounted) {
                    NotificationService.showSnackBar(
                      result.errorMessage ?? 'Có lỗi xảy ra',
                      color: Colors.red,
                    );
                  }
                }
              },
              child: const Text("XÁC NHẬN"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: CustomAppBar.build(
          title: 'QUẢN LÝ CÔNG NỢ',
          accentColor: AppBarAccents.customer,
        ),
        body: const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Chờ shop settings load xong
    if (_tabController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Đếm số công nợ còn hiệu lực (bao gồm cả partner debts nếu có repair)
    final activeDebtsCount =
        _debts.where(_isActiveDebt).length +
        (_enableRepair ? _partnerDebts.length : 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.buildWithTabs(
        title: 'QUẢN LÝ CÔNG NỢ',
        subtitle: '$activeDebtsCount khoản nợ còn',
        tabController: _tabController!,
        tabs: [
          const Tab(text: "KHÁCH"),
          const Tab(text: "NCC"),
          if (_enableRepair) const Tab(text: "ĐỐI TÁC"),
          const Tab(text: "KHÁC"),
        ],
        accentColor: AppBarAccents.customer,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _syncStatus,
                style: AppTextStyles.caption.copyWith(
                  color: _syncStatus == 'Lỗi đồng bộ'
                      ? Colors.orange
                      : AppBarAccents.customer.withOpacity(0.7),
                  fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? Colors.orange : AppBarAccents.customer,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.file_download_outlined,
              color: AppBarAccents.customer,
            ),
            tooltip: 'Xuất Excel công nợ',
            onPressed: () async {
              final result = await ExportDateFilterDialog.show(
                context,
                title: 'Xuất công nợ',
              );
              if (result == null) return;
              if (!mounted) return;
              await ExcelExportHelper.exportDebts(
                context,
                startMs: result['startMs'],
                endMs: result['endMs'],
              );
            },
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildDebtList('CUSTOMER_OWES'),
                  _buildDebtList('SHOP_OWES'),
                  if (_enableRepair)
                    _buildPartnerDebtList(), // Tab cho công nợ đối tác sửa chữa - chỉ cho electronics
                  _buildDebtList('OTHER'),
                ],
              ),
      ),
      floatingActionButton: (_enableRepair && _tabController?.index == 2)
          ? null // Không có FAB cho tab đối tác (quản lý qua trang đối tác)
          : FloatingActionButton(
              onPressed: () {
                if (_tabController?.index == 0) {
                  _createCustomerDebt(); // Tạo nợ khách hàng (phải thu)
                } else if (_tabController?.index == 1) {
                  _createSupplierDebt(); // Tạo nợ nhà cung cấp (phải trả)
                } else if (_enableRepair
                    ? _tabController?.index == 3
                    : _tabController?.index == 2) {
                  _createOtherDebt(); // Tạo công nợ khác
                }
              },
              backgroundColor: _tabController?.index == 0
                  ? Colors.redAccent
                  : _tabController?.index == 1
                  ? Colors.blueAccent
                  : Colors.blueAccent,
              tooltip: _tabController?.index == 0
                  ? 'Tạo nợ khách hàng'
                  : _tabController?.index == 1
                  ? 'Tạo nợ nhà cung cấp'
                  : 'Tạo công nợ khác',
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  /// Kiểm tra công nợ còn hiệu lực (chưa thanh toán hết và chưa bị hủy)
  bool _isActiveDebt(Map<String, dynamic> d) {
    return DebtSummaryService.isActiveDebt(d);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  int _remainingDebt(Map<String, dynamic> debt) {
    final total = _toInt(debt['totalAmount']);
    final paid = _toInt(debt['paidAmount']);
    return (total - paid).clamp(0, total);
  }

  Widget _buildDebtList(String type) {
    List<Map<String, dynamic>> list;
    if (type == 'OTHER') {
      list = _debts
          .where(
            (d) =>
                d['type'].toString().startsWith('OTHER_') && _isActiveDebt(d),
          )
          .toList();
    } else if (type == 'CUSTOMER_OWES') {
      // Khách nợ shop: CUSTOMER_OWES hoặc legacy 'OWE'
      list = _debts.where((d) {
        final debtType = d['type']?.toString() ?? '';
        return (debtType == 'CUSTOMER_OWES' || debtType == 'OWE') &&
            _isActiveDebt(d);
      }).toList();
    } else if (type == 'SHOP_OWES') {
      // Shop nợ NCC: SHOP_OWES hoặc legacy 'OWED'
      list = _debts.where((d) {
        final debtType = d['type']?.toString() ?? '';
        return (debtType == 'SHOP_OWES' || debtType == 'OWED') &&
            _isActiveDebt(d);
      }).toList();
    } else {
      list = _debts
          .where((d) => d['type'] == type && _isActiveDebt(d))
          .toList();
    }

    list.sort((a, b) {
      final remainCmp = _remainingDebt(b).compareTo(_remainingDebt(a));
      if (remainCmp != 0) return remainCmp;
      return _toInt(b['createdAt']).compareTo(_toInt(a['createdAt']));
    });

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 10),
            Text(
              "Hiện tại không có khoản nợ nào",
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (type == 'OTHER') {
      // For OTHER tab, separate into receivable and payable debts
      final receivableDebts = list
          .where((d) => d['type'] == 'OTHER_CUSTOMER_OWES')
          .toList();
      final payableDebts = list
          .where((d) => d['type'] == 'OTHER_SHOP_OWES')
          .toList();

      receivableDebts.sort((a, b) {
        final remainCmp = _remainingDebt(b).compareTo(_remainingDebt(a));
        if (remainCmp != 0) return remainCmp;
        return _toInt(b['createdAt']).compareTo(_toInt(a['createdAt']));
      });
      payableDebts.sort((a, b) {
        final remainCmp = _remainingDebt(b).compareTo(_remainingDebt(a));
        if (remainCmp != 0) return remainCmp;
        return _toInt(b['createdAt']).compareTo(_toInt(a['createdAt']));
      });

      int totalReceivable = receivableDebts.fold(
        0,
        (sum, d) => sum + _remainingDebt(d),
      );

      int totalPayable = payableDebts.fold(
        0,
        (sum, d) => sum + _remainingDebt(d),
      );

      return Column(
        children: [
          // Summary for receivable debts
          if (receivableDebts.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(77)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_downward, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    "NỢ PHẢI THU",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    MoneyUtils.formatCompactCurrency(totalReceivable),
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Receivable debts list
          if (receivableDebts.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: receivableDebts.length,
                itemBuilder: (ctx, i) => _debtCardWithIcon(
                  receivableDebts[i],
                  Icons.arrow_downward,
                  Colors.red,
                  i + 1,
                ),
              ),
            ),

          // Summary for payable debts
          if (payableDebts.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withAlpha(77)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_upward, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    "NỢ PHẢI TRẢ",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.info,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    MoneyUtils.formatCompactCurrency(totalPayable),
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.info,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Payable debts list
          if (payableDebts.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: payableDebts.length,
                itemBuilder: (ctx, i) => _debtCardWithIcon(
                  payableDebts[i],
                  Icons.arrow_upward,
                  Colors.blue,
                  i + 1,
                ),
              ),
            ),

          // If no debts of either type
          if (receivableDebts.isEmpty && payableDebts.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  "Không có công nợ nào",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    int totalRemain = list.fold(0, (sum, d) => sum + _remainingDebt(d));

    return Column(
      children: [
        _summaryHeader(
          type == 'CUSTOMER_OWES'
              ? "TỔNG KHÁCH ĐANG NỢ"
              : "TỔNG SHOP ĐANG NỢ NCC",
          totalRemain,
          type == 'CUSTOMER_OWES' ? Colors.redAccent : Colors.blueAccent,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _debtCard(list[i], i + 1),
          ),
        ),
      ],
    );
  }

  /// Build danh sách công nợ đối tác sửa chữa
  Widget _buildPartnerDebtList() {
    if (_partnerDebts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.handshake_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              "Không có công nợ đối tác sửa chữa",
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Quản lý đối tác tại: Cài đặt > Quản lý đối tác",
              style: AppTextStyles.body2.copyWith(
                color: AppColors.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    // Tính tổng còn nợ
    int totalRemain = _partnerDebts.fold(0, (sum, p) {
      return sum + (p['remainingDebt'] as int? ?? 0);
    });

    return Column(
      children: [
        _summaryHeader("TỔNG NỢ ĐỐI TÁC SỬA CHỮA", totalRemain, Colors.orange),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _partnerDebts.length,
            itemBuilder: (ctx, i) => _partnerDebtCard(_partnerDebts[i], i + 1),
          ),
        ),
      ],
    );
  }

  /// Card hiển thị công nợ đối tác - style giống pending_stock_list_view
  Widget _partnerDebtCard(Map<String, dynamic> partner, int index) {
    final name = partner['name'] ?? 'Đối tác $index';
    final phone = partner['phone'] ?? '';
    final totalRepairs = _toInt(partner['totalRepairs']);
    final totalCost = _toInt(partner['totalCost']);
    final totalPaid = _toInt(partner['totalPaid']);
    final remainingDebt = _toInt(partner['remainingDebt']);
    final note = partner['note']?.toString() ?? '';
    final source = partner['source'] ?? 'repairs';
    final isAltRow = index.isEven;
    final hasMeaningfulNote =
        note.trim().isNotEmpty && note.trim().toLowerCase() != 'nợ';

    return Card(
      margin: const EdgeInsets.only(bottom: 3),
      color: isAltRow
          ? Color.alphaBlend(Colors.orange.withOpacity(0.03), Colors.white)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: InkWell(
        onTap: () => _navigateToPartnerDetail(partner),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Index badge
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        '$index',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                    ),
                  ),
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.handshake,
                      color: Colors.orange.shade800,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name and phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline5.fontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            '📞 $phone',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Order count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$totalRepairs đơn',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.caption.fontSize,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Info chips row
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _debtInfoChip(
                    'Đối tác sửa chữa',
                    Colors.orange.withValues(alpha: 0.14),
                    Colors.orange.shade800,
                  ),
                  _debtInfoChip(
                    source == 'manual' ? 'Thủ công' : 'Tự động',
                    Colors.grey.shade200,
                    Colors.grey.shade700,
                  ),
                ],
              ),

              if (hasMeaningfulNote) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],

              const Divider(height: 12),

              // Amount row
              Row(
                children: [
                  Expanded(
                    child: _amountPill(
                      label: 'Tổng phí',
                      amount: totalCost,
                      valueColor: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Đã trả',
                      amount: totalPaid,
                      valueColor: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Còn nợ',
                      amount: remainingDebt,
                      valueColor: Colors.white,
                      bgColor: Colors.orange,
                      labelColor: Colors.white70,
                    ),
                  ),
                ],
              ),

              // Action button
              if (remainingDebt > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _navigateToPartnerDetail(partner),
                      icon: const Icon(Icons.visibility, size: 15),
                      label: Text(
                        'Thanh toán',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, int amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.body2.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          MoneyUtils.formatCompactCurrency(amount),
          style: AppTextStyles.body1.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Điều hướng đến trang chi tiết đối tác để thanh toán
  /// (Thay vì thanh toán trực tiếp ở đây, chuyển đến trang chi tiết có đầy đủ lịch sử và audit log)
  Future<void> _navigateToPartnerDetail(Map<String, dynamic> partner) async {
    final partnerId = partner['id'];
    if (partnerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thông tin đối tác!')),
      );
      return;
    }

    try {
      // Lấy thông tin đối tác đầy đủ từ service
      final partnerObj = await _partnerService.getRepairPartnerById(partnerId);
      if (partnerObj != null && mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => RepairPartnerDetailView(partner: partnerObj),
          ),
        );
        // Refresh nếu có thay đổi từ trang chi tiết
        if (result == true) {
          _refresh();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy đối tác!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _summaryHeader(String label, int amount, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            MoneyUtils.formatCompactCurrency(amount),
            style: AppTextStyles.headline4.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _debtCard(Map<String, dynamic> d, [int? index]) {
    final int total = _toInt(d['totalAmount']);
    final int paid = _toInt(d['paidAmount']);
    final int remain = (total - paid).clamp(0, total);
    final createdAt = _toInt(d['createdAt']);
    final hasCreatedAt = createdAt > 0;
    final date = hasCreatedAt
        ? DateFormat(
            'dd/MM/yyyy',
          ).format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '--/--/----';
    final time = hasCreatedAt
        ? DateFormat(
            'HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '--:--';
    final personName = (d['personName'] ?? 'N/A').toString();
    final phone = d['phone']?.toString() ?? '';
    final note = d['note']?.toString() ?? '';
    final debtType = d['type']?.toString() ?? 'CUSTOMER_OWES';

    // Determine colors based on debt type
    final isCustomerDebt =
        debtType == 'CUSTOMER_OWES' ||
        debtType == 'OWE' ||
        debtType == 'OTHER_CUSTOMER_OWES';
    final mainColor = isCustomerDebt ? Colors.red : Colors.blue;
    final borderColor = isCustomerDebt
        ? Colors.red.shade200
        : Colors.blue.shade200;

    // Calculate days since creation for urgency
    final daysSince = hasCreatedAt
        ? DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(createdAt))
              .inDays
        : 0;
    final isUrgent = daysSince > 30;
    final isVeryUrgent = daysSince > 60;
    final isAltRow = (index ?? 0).isEven;
    final hasMeaningfulNote =
        note.trim().isNotEmpty && note.trim().toLowerCase() != 'nợ';
    final zebraBg = isAltRow
        ? Color.alphaBlend(mainColor.withOpacity(0.03), Colors.white)
        : Colors.white;

    return Card(
      margin: const EdgeInsets.only(bottom: 3),
      color: zebraBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: isVeryUrgent
              ? Colors.red.shade400
              : (isUrgent ? Colors.orange.shade300 : borderColor),
          width: isVeryUrgent ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showDebtHistory(d),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Index badge
                  if (index != null)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: mainColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: mainColor,
                            fontSize: AppTextStyles.subtitle1.fontSize,
                          ),
                        ),
                      ),
                    ),
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: mainColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isCustomerDebt
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: mainColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name and phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline5.fontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            '📞 $phone',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Date and time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: AppTextStyles.body2.fontSize,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: AppTextStyles.caption.fontSize,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 4),
              Row(
                children: [
                  _debtInfoChip(
                    isCustomerDebt ? 'Phải thu' : 'Phải trả',
                    mainColor.withValues(alpha: 0.14),
                    mainColor,
                  ),
                  const SizedBox(width: 6),
                  if (isVeryUrgent)
                    _debtInfoChip(
                      'Quá hạn $daysSince ngày',
                      Colors.red.shade100,
                      Colors.red.shade800,
                    )
                  else if (isUrgent)
                    _debtInfoChip(
                      '$daysSince ngày',
                      Colors.orange.shade100,
                      Colors.orange.shade800,
                    ),
                ],
              ),

              if (hasMeaningfulNote) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],

              const Divider(height: 10),

              // Amount row
              Row(
                children: [
                  Expanded(
                    child: _amountPill(
                      label: 'Tổng nợ',
                      amount: total,
                      valueColor: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Đã trả',
                      amount: paid,
                      valueColor: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Còn nợ',
                      amount: remain,
                      valueColor: Colors.white,
                      bgColor: mainColor,
                      labelColor: Colors.white70,
                    ),
                  ),
                ],
              ),

              // Action button
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showDebtHistory(d),
                    icon: const Icon(Icons.history, size: 14),
                    label: Text(
                      'Lịch sử',
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: () => _payDebt(d),
                    icon: Icon(
                      isCustomerDebt ? Icons.call_received : Icons.call_made,
                      size: 14,
                    ),
                    label: Text(
                      isCustomerDebt ? 'Thu nợ' : 'Thanh toán nợ',
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  Widget _debtInfoChip(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextStyles.overlineSize,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _amountPill({
    required String label,
    required int amount,
    required Color valueColor,
    Color? bgColor,
    Color? labelColor,
  }) {
    final chipBg = bgColor ?? Colors.grey.shade100;
    final chipLabelColor = labelColor ?? Colors.grey.shade600;
    final borderColor = bgColor == null
        ? Colors.grey.shade200
        : chipBg.withOpacity(0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.overlineSize,
              fontWeight: FontWeight.bold,
              color: chipLabelColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            MoneyUtils.formatCompactCurrency(amount),
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _createOtherDebt() async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể tạo công nợ mới.',
        color: Colors.red,
      );
      return;
    }

    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String debtType = "CUSTOMER_OWES"; // Default to customer owes (nợ phải thu)

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("TẠO CÔNG NỢ KHÁC"),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameC,
                    decoration: const InputDecoration(
                      labelText: "Tên người nợ",
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Vui lòng nhập tên người nợ'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneC,
                    decoration: const InputDecoration(
                      labelText: "Số điện thoại",
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  CurrencyTextField(
                    controller: amountC,
                    label: "Số tiền nợ (VNĐ)",
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 1,
                      fieldName: 'Số tiền nợ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteC,
                    decoration: const InputDecoration(labelText: "Ghi chú"),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Hình thức nợ:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => debtType = "CUSTOMER_OWES"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: debtType == "CUSTOMER_OWES"
                                  ? Colors.red.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: debtType == "CUSTOMER_OWES"
                                    ? Colors.red
                                    : Colors.grey.shade300,
                                width: debtType == "CUSTOMER_OWES" ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.arrow_downward,
                                  color: debtType == "CUSTOMER_OWES"
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "NỢ PHẢI THU",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: debtType == "CUSTOMER_OWES"
                                        ? Colors.red
                                        : Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const Text(
                                  "(Khách nợ shop)",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.overlineSize,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => debtType = "SHOP_OWES"),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: debtType == "SHOP_OWES"
                                  ? Colors.blue.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: debtType == "SHOP_OWES"
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                width: debtType == "SHOP_OWES" ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  color: debtType == "SHOP_OWES"
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "NỢ PHẢI TRẢ",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: debtType == "SHOP_OWES"
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const Text(
                                  "(Shop nợ người khác)",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.overlineSize,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                final debtAmount = MoneyUtils.parseCurrency(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_other_$now",
                  'personName': nameC.text.trim(),
                  'phone': phoneC.text.trim(),
                  'totalAmount': debtAmount,
                  'paidAmount': 0,
                  'type':
                      'OTHER_$debtType', // OTHER_CUSTOMER_OWES or OTHER_SHOP_OWES
                  'status': 'unpaid',
                  'createdAt': now,
                  'note': noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                  'createdBy': userName,
                };

                final debtId = await db.insertDebt(newDebtData);
                // Queue sync to cloud via SyncOrchestrator
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.debt,
                  entityId: debtId,
                  firestoreId: newDebtData['firestoreId'] as String,
                  operation: SyncOperation.create,
                  data: newDebtData,
                );

                EventBus().emit('debts_changed');
                if (mounted) {
                  Navigator.pop(ctx);
                  NotificationService.showSnackBar(
                    "Đã tạo công nợ mới",
                    color: Colors.green,
                  );
                  await _refresh();
                }
              },
              child: const Text("TẠO"),
            ),
          ],
        ),
      ),
    );
  }

  void _createCustomerDebt() async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể tạo công nợ mới.',
        color: Colors.red,
      );
      return;
    }

    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("TẠO NỢ KHÁCH HÀNG (PHẢI THU)"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameC,
                decoration: const InputDecoration(labelText: "Tên khách hàng"),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tên khách hàng'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: "Số điện thoại"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              CurrencyTextField(
                controller: amountC,
                label: "Số tiền nợ (VNĐ)",
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 1,
                  fieldName: 'Số tiền nợ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteC,
                decoration: const InputDecoration(labelText: "Ghi chú"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              try {
                // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                final debtAmount = MoneyUtils.parseCurrency(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_customer_$now",
                  'personName': nameC.text.trim(),
                  'phone': phoneC.text.trim(),
                  'totalAmount': debtAmount,
                  'paidAmount': 0,
                  'type': 'CUSTOMER_OWES',
                  'status': 'unpaid',
                  'createdAt': now,
                  'note': noteC.text.trim(),
                  'createdBy': userName,
                };

                final debtId = await db.insertDebt(newDebtData);
                // Queue sync to cloud via SyncOrchestrator
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.debt,
                  entityId: debtId,
                  firestoreId: newDebtData['firestoreId'] as String,
                  operation: SyncOperation.create,
                  data: newDebtData,
                );

                // Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "TẠO NỢ",
                  type: "DEBT",
                  targetId: newDebtData['firestoreId'] as String,
                  desc:
                      "Tạo nợ khách hàng: ${nameC.text} - ${MoneyUtils.formatCurrency(debtAmount)}.",
                );

                EventBus().emit('debts_changed');
                if (!mounted) return;
                Navigator.pop(context);
                NotificationService.showSnackBar(
                  "Đã tạo nợ khách hàng!",
                  color: Colors.green,
                );
                await _refresh();
              } catch (e) {
                if (!mounted) return;
                NotificationService.showSnackBar(
                  "Lỗi tạo nợ: $e",
                  color: Colors.red,
                );
              }
            },
            child: const Text("TẠO"),
          ),
        ],
      ),
    );
  }

  void _createSupplierDebt() async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể tạo công nợ mới.',
        color: Colors.red,
      );
      return;
    }

    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("TẠO NỢ NHÀ CUNG CẤP (PHẢI TRẢ)"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameC,
                decoration: const InputDecoration(
                  labelText: "Tên nhà cung cấp",
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tên nhà cung cấp'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: "Số điện thoại"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              CurrencyTextField(
                controller: amountC,
                label: "Số tiền nợ (VNĐ)",
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 1,
                  fieldName: 'Số tiền nợ',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteC,
                decoration: const InputDecoration(labelText: "Ghi chú"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              try {
                // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                final debtAmount = MoneyUtils.parseCurrency(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_supplier_$now",
                  'personName': nameC.text.trim(),
                  'phone': phoneC.text.trim(),
                  'totalAmount': debtAmount,
                  'paidAmount': 0,
                  'type': 'SHOP_OWES',
                  'status': 'unpaid',
                  'createdAt': now,
                  'note': noteC.text.trim(),
                  'createdBy': userName,
                };

                final debtId = await db.insertDebt(newDebtData);
                // Queue sync to cloud via SyncOrchestrator
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.debt,
                  entityId: debtId,
                  firestoreId: newDebtData['firestoreId'] as String,
                  operation: SyncOperation.create,
                  data: newDebtData,
                );

                // Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "TẠO NỢ",
                  type: "DEBT",
                  targetId: newDebtData['firestoreId'] as String,
                  desc:
                      "Tạo nợ nhà cung cấp: ${nameC.text} - ${MoneyUtils.formatCurrency(debtAmount)}.",
                );

                EventBus().emit('debts_changed');
                if (!mounted) return;
                Navigator.pop(context);
                NotificationService.showSnackBar(
                  "Đã tạo nợ nhà cung cấp!",
                  color: Colors.green,
                );
                await _refresh();
              } catch (e) {
                if (!mounted) return;
                NotificationService.showSnackBar(
                  "Lỗi tạo nợ: $e",
                  color: Colors.red,
                );
              }
            },
            child: const Text("TẠO"),
          ),
        ],
      ),
    );
  }

  Widget _debtCardWithIcon(
    Map<String, dynamic> d,
    IconData icon,
    Color iconColor, [
    int? index,
  ]) {
    final int total = _toInt(d['totalAmount']);
    final int paid = _toInt(d['paidAmount']);
    final int remain = (total - paid).clamp(0, total);
    final int createdAt = _toInt(d['createdAt']);
    final bool hasCreatedAt = createdAt > 0;
    final String date = hasCreatedAt
        ? DateFormat(
            'dd/MM/yyyy',
          ).format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '--/--/----';
    final String time = hasCreatedAt
        ? DateFormat(
            'HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '--:--';
    final String personName = (d['personName'] ?? 'N/A').toString();
    final String phone = d['phone']?.toString() ?? '';
    final String note = d['note']?.toString() ?? '';
    final bool hasMeaningfulNote =
        note.trim().isNotEmpty && note.trim().toLowerCase() != 'nợ';
    final bool isReceivable = icon == Icons.arrow_downward;
    final isAltRow = (index ?? 0).isEven;

    return Card(
      margin: const EdgeInsets.only(bottom: 3),
      color: isAltRow
          ? Color.alphaBlend(iconColor.withOpacity(0.04), Colors.white)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: iconColor.withOpacity(0.12)),
      ),
      child: InkWell(
        onTap: () => _showDebtHistory(d),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (index != null) ...[
                    Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: iconColor,
                            fontSize: AppTextStyles.caption.fontSize,
                          ),
                        ),
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline5.fontSize,
                          ),
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            '📞 $phone',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: AppTextStyles.caption.fontSize,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: AppTextStyles.overlineSize,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  _debtInfoChip(
                    isReceivable ? 'Phải thu' : 'Phải trả',
                    iconColor.withOpacity(0.14),
                    iconColor,
                  ),
                ],
              ),
              if (hasMeaningfulNote) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _amountPill(
                      label: 'Tổng nợ',
                      amount: total,
                      valueColor: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Đã trả',
                      amount: paid,
                      valueColor: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _amountPill(
                      label: 'Còn nợ',
                      amount: remain,
                      valueColor: Colors.white,
                      bgColor: iconColor,
                      labelColor: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showDebtHistory(d),
                    icon: const Icon(Icons.history, size: 14),
                    label: Text(
                      'Lịch sử',
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: () => _payDebt(d),
                    icon: Icon(
                      isReceivable ? Icons.call_received : Icons.call_made,
                      size: 14,
                    ),
                    label: Text(
                      isReceivable ? 'Thu nợ' : 'Trả nợ',
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
}
