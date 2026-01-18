import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/money_utils.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';
import '../widgets/custom_app_bar.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../services/adjustment_service.dart';
import '../services/firestore_service.dart';
import '../services/financial_activity_service.dart';
import '../services/first_time_guide_service.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

class DebtView extends StatefulWidget {
  const DebtView({super.key});
  @override
  State<DebtView> createState() => _DebtViewState();
}

class _DebtViewState extends State<DebtView>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final db = DBHelper();
  late TabController _tabController;
  List<Map<String, dynamic>> _debts = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncStatus = 'Đã đồng bộ';
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRole();
    _refresh();

    // Listen to global events (e.g., debts changed) to refresh the list when other parts of the app write debts
    _eventSub = EventBus().stream.where((e) => e == 'debts_changed').listen((
      _,
    ) {
      if (mounted) _refresh();
    });

    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keyDebtManagement,
      title: 'Quản Lý Công Nợ',
      icon: Icons.account_balance_wallet,
      color: Colors.red,
      steps: const [
        GuideStep(
          title: '📊 3 loại công nợ',
          description: 'KHÁCH NỢ (khách chưa TT), NỢ NCC (nợ nhà cung cấp), NỢ ĐỐI TÁC (nợ thợ sửa ngoài).',
          icon: Icons.category,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '💰 Ghi nhận thanh toán',
          description: 'Nhấn vào khoản nợ để xem chi tiết và ghi nhận thanh toán từng phần hoặc toàn bộ.',
          icon: Icons.payment,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '📅 Theo dõi hạn nợ',
          description: 'Nợ quá hạn sẽ được highlight đỏ. Báo cáo tổng hợp giúp theo dõi dòng tiền.',
          icon: Icons.event,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '🔄 Tự động tạo nợ',
          description: 'Khi bán hàng/nhập kho chọn "CÔNG NỢ", hệ thống tự tạo khoản nợ tương ứng.',
          icon: Icons.auto_mode,
          iconColor: Colors.purple,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRole() async {
    // Role loading not needed for current functionality
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final data = await db.getAllDebts();
    if (!mounted) return;
    setState(() {
      // Filter out soft-deleted debts
      _debts = data.where((d) => (d['deleted'] ?? 0) != 1).toList();
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
      await SyncService.downloadAllFromCloud();

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
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
              child: Text("TRẢ NỢ", style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }

  void _payDebt(Map<String, dynamic> debt) async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa (thanh toán ở ngày hiện tại)
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thu tiền trả nợ.',
        color: Colors.red,
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final payC = TextEditingController();
    String method = "TIỀN MẶT";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("TRẢ NỢ"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: payC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(labelText: "SỐ TIỀN THU (VNĐ)"),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    max: (debt['totalAmount'] as int? ?? 0) - (debt['paidAmount'] as int? ?? 0),
                    fieldName: 'Số tiền thu',
                  ),
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 8,
                  children: ["TIỀN MẶT", "CHUYỂN KHOẢN"]
                      .map(
                        (m) => ChoiceChip(
                          label: Text(m, style: AppTextStyles.caption),
                          selected: method == m,
                          onSelected: (v) => setS(() => method = m),
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
                // Không tự động nhân 1000 - người dùng nhập bao nhiêu dùng bấy nhiêu
                final payAmount = parsed;
                if (payAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                int total = debt['totalAmount'];
                int alreadyPaid = debt['paidAmount'] ?? 0;
                int remain = total - alreadyPaid;

                if (payAmount > remain) {
                  NotificationService.showSnackBar(
                    "Số tiền trả không được vượt số nợ còn lại!",
                    color: Colors.red,
                  );
                  return;
                }

                // === FIRESTORE TRANSACTION: Tránh race condition khi 2 user thanh toán cùng lúc ===
                final debtFId = debt['firestoreId'] as String?;
                if (debtFId != null && debtFId.isNotEmpty) {
                  // Có firestoreId → dùng transaction để đảm bảo atomic
                  final txResult = await FirestoreService.executeDebtPaymentTransaction(
                    debtFirestoreId: debtFId,
                    payAmount: payAmount,
                    paymentMethod: method,
                    createdBy: userName,
                  );
                  
                  if (!txResult['success']) {
                    NotificationService.showSnackBar(
                      "❌ ${txResult['error'] ?? 'Lỗi thanh toán'}",
                      color: Colors.red,
                    );
                    return;
                  }
                  
                  // Transaction thành công → cập nhật local DB
                  await db.updateDebtPaid(debt['id'], payAmount);
                  
                  // Lưu payment vào local (thêm debtType để cash_closing phân biệt được)
                  final paymentData = {
                    'firestoreId': txResult['paymentDocId'] ?? "pay_${now}_${user?.uid}",
                    'debtId': debt['id'],
                    'debtFirestoreId': debtFId,
                    'debtType': debt['type'] ?? 'CUSTOMER_OWES',
                    'amount': payAmount,
                    'paidAt': now,
                    'paymentMethod': method,
                    'createdBy': userName,
                    'isSynced': 1, // Đã sync qua transaction
                  };
                  await db.insertDebtPayment(paymentData);
                  
                  // Ghi nhật ký hoạt động tài chính - phân biệt loại nợ
                  try {
                    final debtType = debt['type'] ?? 'CUSTOMER_OWES';
                    // FIX: Bao gồm OTHER_SHOP_OWES cho công nợ khác (shop nợ)
                    if (debtType == 'SHOP_OWES' || debtType == 'OWED' || debtType == 'OTHER_SHOP_OWES') {
                      // Trả nợ NCC/Khác → logSupplierPayment (direction = OUT)
                      await FinancialActivityService.logSupplierPayment(
                        firestoreId: paymentData['firestoreId'] as String,
                        amount: payAmount,
                        paymentMethod: method,
                        supplierName: debt['personName'] ?? '',
                        createdAt: now,
                        createdBy: userName,
                        note: debtType == 'OTHER_SHOP_OWES' ? 'Trả nợ đối tác' : 'Trả nợ NCC',
                      );
                    } else {
                      // Thu nợ khách (CUSTOMER_OWES, OTHER_CUSTOMER_OWES) → logDebtCollection (direction = IN)
                      await FinancialActivityService.logDebtCollection(
                        firestoreId: paymentData['firestoreId'] as String,
                        amount: payAmount,
                        paymentMethod: method,
                        customerName: debt['personName'] ?? '',
                        phone: debt['phone'] ?? '',
                        createdAt: now,
                        createdBy: userName,
                      );
                    }
                  } catch (e) {
                    debugPrint('Failed to log financial activity: $e');
                  }
                } else {
                  // Chưa có firestoreId → xử lý offline-first như cũ
                  final paymentData = {
                    'firestoreId': "pay_${now}_${user?.uid}",
                    'debtId': debt['id'],
                    'debtFirestoreId': debt['firestoreId'],
                    'debtType': debt['type'] ?? 'CUSTOMER_OWES',
                    'amount': payAmount,
                    'paidAt': now,
                    'paymentMethod': method,
                    'createdBy': userName,
                  };
                  final paymentId = await db.insertDebtPayment(paymentData);
                  
                  // Ghi nhật ký hoạt động tài chính (offline) - phân biệt loại nợ
                  try {
                    final debtType = debt['type'] ?? 'CUSTOMER_OWES';
                    // FIX: Bao gồm OTHER_SHOP_OWES cho công nợ khác (shop nợ)
                    if (debtType == 'SHOP_OWES' || debtType == 'OWED' || debtType == 'OTHER_SHOP_OWES') {
                      // Trả nợ NCC/Khác → logSupplierPayment (direction = OUT)
                      await FinancialActivityService.logSupplierPayment(
                        firestoreId: paymentData['firestoreId'] as String,
                        amount: payAmount,
                        paymentMethod: method,
                        supplierName: debt['personName'] ?? '',
                        createdAt: now,
                        createdBy: userName,
                        note: debtType == 'OTHER_SHOP_OWES' ? 'Trả nợ đối tác' : 'Trả nợ NCC',
                      );
                    } else {
                      // Thu nợ khách (CUSTOMER_OWES, OTHER_CUSTOMER_OWES) → logDebtCollection (direction = IN)
                      await FinancialActivityService.logDebtCollection(
                        firestoreId: paymentData['firestoreId'] as String,
                        amount: payAmount,
                        paymentMethod: method,
                        customerName: debt['personName'] ?? '',
                        phone: debt['phone'] ?? '',
                        createdAt: now,
                        createdBy: userName,
                      );
                    }
                  } catch (e) {
                    debugPrint('Failed to log financial activity: $e');
                  }
                  
                  // Queue sync debt payment to cloud via SyncOrchestrator
                  await SyncOrchestrator().enqueue(
                    entityType: SyncEntityType.debtPayment,
                    entityId: paymentId,
                    firestoreId: paymentData['firestoreId'] as String,
                    operation: SyncOperation.create,
                    data: paymentData,
                  );

                  // CẬP NHẬT SỐ TIỀN ĐÃ TRẢ
                  await db.updateDebtPaid(debt['id'], payAmount);
                  
                  // Queue sync updated debt to cloud
                  final allDebts = await db.getAllDebts();
                  final updatedDebt = allDebts.firstWhere(
                    (e) => e['id'] == debt['id'],
                  );
                  await SyncOrchestrator().enqueue(
                    entityType: SyncEntityType.debt,
                    entityId: debt['id'] as int,
                    firestoreId: debt['firestoreId'] as String?,
                    operation: SyncOperation.update,
                    data: Map<String, dynamic>.from(updatedDebt),
                  );
                }

                // Cập nhật đơn hàng liên kết (nếu có)
                if (debt['linkedId'] != null) {
                  await db.updateOrderStatusFromDebt(
                    debt['linkedId'],
                    alreadyPaid + payAmount,
                  );
                  // Queue sync for linked orders
                  if (debt['linkedId'].startsWith('sale_')) {
                    final sales = await db.getAllSales();
                    final matching = sales.where(
                      (s) => s.firestoreId == debt['linkedId'],
                    );
                    final sale = matching.isNotEmpty ? matching.first : null;
                    if (sale != null && sale.id != null) {
                      await SyncOrchestrator().enqueue(
                        entityType: SyncEntityType.sale,
                        entityId: sale.id!,
                        firestoreId: sale.firestoreId,
                        operation: SyncOperation.update,
                        data: sale.toMap(),
                      );
                    }
                  } else if (debt['linkedId'].startsWith('rep_')) {
                    final repairs = await db.getAllRepairs();
                    final matching = repairs.where(
                      (r) => r.firestoreId == debt['linkedId'],
                    );
                    final repair = matching.isNotEmpty ? matching.first : null;
                    if (repair != null && repair.id != null) {
                      await SyncOrchestrator().enqueue(
                        entityType: SyncEntityType.repair,
                        entityId: repair.id!,
                        firestoreId: repair.firestoreId,
                        operation: SyncOperation.update,
                        data: repair.toMap(),
                      );
                    }
                  } else {
                    // Assume it's a purchase order code
                    final purchases = await db.getAllPurchaseOrders();
                    final matching = purchases.where(
                      (p) => p.orderCode == debt['linkedId'],
                    );
                    final purchase = matching.isNotEmpty
                        ? matching.first
                        : null;
                    if (purchase != null) {
                      purchase.status = 'RECEIVED';
                      await db.updatePurchaseOrder(purchase);
                      // Queue sync via SyncOrchestrator
                      final orderId = await db.getPurchaseOrderIdByFirestoreId(purchase.firestoreId ?? '');
                      await SyncOrchestrator().enqueue(
                        entityType: SyncEntityType.purchaseOrder,
                        entityId: orderId ?? 0,
                        firestoreId: purchase.firestoreId,
                        operation: SyncOperation.update,
                        data: purchase.toMap(),
                      );
                    }
                  }
                }

                // Clean any potential duplicate data after debt payment
                try {
                  await db.cleanDuplicateData();
                } catch (e) {
                  debugPrint('Error cleaning duplicate data: $e');
                }

                // Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "THU NỢ",
                  type: "DEBT",
                  targetId: debt['firestoreId'],
                  desc: "Khách trả ${MoneyUtils.formatCurrency(payAmount)}.",
                );

                EventBus().emit('debts_changed');
                // Đóng dialog TRƯỚC rồi mới show snackbar và refresh
                Navigator.of(ctx).pop();
                if (!mounted) return;
                NotificationService.showSnackBar(
                  "Đã thu nợ ${MoneyUtils.formatCurrency(payAmount)}đ!",
                  color: Colors.green,
                );
                await _refresh();
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
    
    // Đếm số công nợ còn hiệu lực
    final activeDebtsCount = _debts.where(_isActiveDebt).length;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.buildWithTabs(
        title: 'QUẢN LÝ CÔNG NỢ',
        subtitle: '$activeDebtsCount khoản nợ còn',
        tabController: _tabController,
        tabs: const [
          Tab(text: "KHÁCH NỢ"),
          Tab(text: "SHOP NỢ NCC"),
          Tab(text: "CÔNG NỢ KHÁC"),
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDebtList('CUSTOMER_OWES'),
                _buildDebtList('SHOP_OWES'),
                _buildDebtList('OTHER'),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _createCustomerDebt(); // Tạo nợ khách hàng (phải thu)
          } else if (_tabController.index == 1) {
            _createSupplierDebt(); // Tạo nợ nhà cung cấp (phải trả)
          } else {
            _createOtherDebt(); // Tạo công nợ khác
          }
        },
        backgroundColor: _tabController.index == 0
            ? Colors.redAccent
            : _tabController.index == 1
            ? Colors.blueAccent
            : Colors.purpleAccent,
        tooltip: _tabController.index == 0
            ? 'Tạo nợ khách hàng'
            : _tabController.index == 1
            ? 'Tạo nợ nhà cung cấp'
            : 'Tạo công nợ khác',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// Kiểm tra công nợ còn hiệu lực (chưa thanh toán hết và chưa bị hủy)
  bool _isActiveDebt(Map<String, dynamic> d) {
    final status = d['status']?.toString().toUpperCase() ?? 'ACTIVE';
    // Bỏ qua nếu đã thanh toán hoặc đã hủy (cả lowercase và uppercase)
    if (status == 'PAID' || status == 'CANCELLED' || status == 'UNPAID') {
      // "UNPAID" là status cũ khi chưa trả hết, nhưng vẫn cần kiểm tra số tiền
      // Không bỏ qua UNPAID vì đó là nợ chưa trả hết
    }
    if (status == 'PAID' || status == 'CANCELLED') return false;
    
    // Kiểm tra số tiền còn nợ (clamp để không âm)
    final totalAmount = d['totalAmount'] as int? ?? 0;
    final paidAmount = d['paidAmount'] as int? ?? 0;
    final remaining = (totalAmount - paidAmount).clamp(0, totalAmount);
    
    // Công nợ hợp lệ: còn tiền nợ > 0 và tổng nợ > 0
    return remaining > 0 && totalAmount > 0;
  }

  Widget _buildDebtList(String type) {
    List<Map<String, dynamic>> list;
    if (type == 'OTHER') {
      list = _debts
          .where(
            (d) =>
                d['type'].toString().startsWith('OTHER_') &&
                _isActiveDebt(d),
          )
          .toList();
    } else if (type == 'CUSTOMER_OWES') {
      // Khách nợ shop: CUSTOMER_OWES hoặc legacy 'OWE'
      list = _debts
          .where((d) {
            final debtType = d['type']?.toString() ?? '';
            return (debtType == 'CUSTOMER_OWES' || debtType == 'OWE') && _isActiveDebt(d);
          })
          .toList();
    } else if (type == 'SHOP_OWES') {
      // Shop nợ NCC: SHOP_OWES hoặc legacy 'OWED'
      list = _debts
          .where((d) {
            final debtType = d['type']?.toString() ?? '';
            return (debtType == 'SHOP_OWES' || debtType == 'OWED') && _isActiveDebt(d);
          })
          .toList();
    } else {
      list = _debts
          .where((d) => d['type'] == type && _isActiveDebt(d))
          .toList();
    }

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

      int totalReceivable = receivableDebts.fold(0, (sum, d) {
        final int total = d['totalAmount'] as int;
        final int paid = d['paidAmount'] as int? ?? 0;
        final int remain = (total - paid).clamp(0, total);
        return sum + remain;
      });

      int totalPayable = payableDebts.fold(0, (sum, d) {
        final int total = d['totalAmount'] as int;
        final int paid = d['paidAmount'] as int? ?? 0;
        final int remain = (total - paid).clamp(0, total);
        return sum + remain;
      });

      return Column(
        children: [
          // Summary for receivable debts
          if (receivableDebts.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
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
                    MoneyUtils.formatCurrency(totalReceivable),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
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
                    MoneyUtils.formatCurrency(totalPayable),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

    int totalRemain = list.fold(0, (sum, d) {
      final int total = d['totalAmount'] as int;
      final int paid = d['paidAmount'] as int? ?? 0;
      final int remain = (total - paid).clamp(0, total);
      return sum + remain;
    });

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
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _debtCard(list[i], i + 1),
          ),
        ),
      ],
    );
  }

  Widget _summaryHeader(String label, int amount, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            MoneyUtils.formatCurrency(amount),
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
    final int total = d['totalAmount'];
    final int paid = d['paidAmount'] ?? 0;
    final int remain = (total - paid).clamp(0, total);
    final date = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(d['createdAt']));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: ListTile(
        onTap: () => _showDebtHistory(d),
        contentPadding: const EdgeInsets.all(15),
        leading: index != null
            ? Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            : null,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                (d['personName'] ?? 'N/A').toString().toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              date,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d['phone'] != null)
              Text(
                "SĐT: ${d['phone']}",
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            Text(
              "Nội dung: ${d['note'] ?? ''}",
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniValue("ĐÃ TRẢ", paid, Colors.green),
                _miniValue("CÒN NỢ", remain, Colors.red),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  Widget _miniValue(String l, int v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
      Text(
        MoneyUtils.formatCurrency(v),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c),
      ),
    ],
  );

  void _createOtherDebt() async {
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
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
                    decoration: const InputDecoration(labelText: "Tên người nợ"),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên người nợ' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneC,
                    decoration: const InputDecoration(labelText: "Số điện thoại"),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: amountC,
                    keyboardType: TextInputType.number,
                    inputFormatters: [MoneyUtils.currencyInputFormatter()],
                    decoration: const InputDecoration(labelText: "Số tiền nợ (VNĐ)"),
                    validator: (v) => MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền nợ'),
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
                                    fontSize: 11,
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
                                    fontSize: 9,
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
                                    fontSize: 11,
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
                                    fontSize: 9,
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

                final parsed = MoneyUtils.parseCurrency(amountC.text);
                final debtAmount = parsed >= 1000 && parsed < 100000 ? parsed * 1000 : parsed;
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
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
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
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên khách hàng' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: "Số điện thoại"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: amountC,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyUtils.currencyInputFormatter()],
                decoration: const InputDecoration(labelText: "Số tiền nợ (VNĐ)"),
                validator: (v) => MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền nợ'),
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
                final parsed = MoneyUtils.parseCurrency(amountC.text);
                final debtAmount = parsed >= 1000 && parsed < 100000 ? parsed * 1000 : parsed;
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
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
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
                decoration: const InputDecoration(labelText: "Tên nhà cung cấp"),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên nhà cung cấp' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: "Số điện thoại"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: amountC,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyUtils.currencyInputFormatter()],
                decoration: const InputDecoration(labelText: "Số tiền nợ (VNĐ)"),
                validator: (v) => MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền nợ'),
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
                final parsed = MoneyUtils.parseCurrency(amountC.text);
                final debtAmount = parsed >= 1000 && parsed < 100000 ? parsed * 1000 : parsed;
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
    final int total = d['totalAmount'];
    final int paid = d['paidAmount'] ?? 0;
    final int remain = total - paid;
    final date = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(d['createdAt']));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: ListTile(
        onTap: () => _showDebtHistory(d),
        contentPadding: const EdgeInsets.all(15),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != null) ...[
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
            CircleAvatar(
              backgroundColor: iconColor.withAlpha(25),
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ],
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                (d['personName'] ?? 'N/A').toString().toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              date,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d['phone'] != null)
              Text(
                "SĐT: ${d['phone']}",
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            Text(
              "Nội dung: ${d['note'] ?? ''}",
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniValue("ĐÃ TRẢ", paid, Colors.green),
                _miniValue("CÒN NỢ", remain, iconColor),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
