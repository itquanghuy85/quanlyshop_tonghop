import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../services/event_bus.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';
import '../services/user_service.dart';
import '../widgets/currency_text_field.dart';

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
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkPermission();
    _loadRole();
    _refresh();

    // Listen to global events (e.g., debts changed) to refresh the list when other parts of the app write debts
    _eventSub = EventBus().stream.where((e) => e == 'debts_changed').listen((
      _,
    ) {
      if (mounted) _refresh();
    });
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

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewDebts'] ?? false);
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final data = await db.getAllDebts();
    if (!mounted) return;
    setState(() {
      _debts = data;
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
                padding: EdgeInsets.all(40),
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
                                "+ ${MoneyUtils.formatVND(p['amount'])} đ",
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
              child: Text("THU TIỀN TRẢ NỢ", style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }

  void _payDebt(Map<String, dynamic> debt) {
    final payC = TextEditingController();
    String method = "TIỀN MẶT";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("THU TIỀN TRẢ NỢ"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CurrencyTextField(controller: payC, label: "SỐ TIỀN THU"),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: () async {
                // Lấy giá trị đã được CurrencyTextField xử lý
                int payAmount = CurrencyTextField.parseValue(payC.text);
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

                // 1. Lưu lịch sử chi tiết
                final paymentData = {
                  'firestoreId': "pay_${now}_${user?.uid}",
                  'debtId': debt['id'],
                  'debtFirestoreId': debt['firestoreId'],
                  'amount': payAmount,
                  'paidAt': now,
                  'paymentMethod': method,
                  'createdBy': userName,
                };
                await db.insertDebtPayment(paymentData);
                // Sync debt payment lên cloud
                await FirestoreService.addDebtPaymentCloud(paymentData);

                // 2. CẬP NHẬT SỐ TIỀN ĐÃ TRẢ
                await db.updateDebtPaid(debt['id'], payAmount);

                // 3. LOGIC CHO THANH TOÁN MỘT PHẦN - KHÔNG CẦN TẠO DEBT MỚI
                // Debt sẽ vẫn active với số tiền còn lại = totalAmount - (alreadyPaid + payAmount)

                // 3. Cập nhật đơn hàng liên kết (nếu có)
                if (debt['linkedId'] != null) {
                  await db.updateOrderStatusFromDebt(
                    debt['linkedId'],
                    alreadyPaid + payAmount,
                  );
                  // Cập nhật Cloud cho order
                  if (debt['linkedId'].startsWith('sale_')) {
                    final sales = await db.getAllSales();
                    final matching = sales.where(
                      (s) => s.firestoreId == debt['linkedId'],
                    );
                    final sale = matching.isNotEmpty ? matching.first : null;
                    if (sale != null)
                      await FirestoreService.updateSaleCloud(sale);
                  } else if (debt['linkedId'].startsWith('rep_')) {
                    final repairs = await db.getAllRepairs();
                    final matching = repairs.where(
                      (r) => r.firestoreId == debt['linkedId'],
                    );
                    final repair = matching.isNotEmpty ? matching.first : null;
                    if (repair != null)
                      await FirestoreService.upsertRepair(repair);
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
                      await FirestoreService.addPurchaseOrder(purchase);
                    }
                  }
                }

                // Clean any potential duplicate data after debt payment
                try {
                  await db.cleanDuplicateData();
                } catch (e) {
                  debugPrint('Error cleaning duplicate data: $e');
                }

                // 4. Đồng bộ Cloud
                final allDebts = await db.getAllDebts();
                final updatedOldDebt = allDebts.firstWhere(
                  (e) => e['id'] == debt['id'],
                );
                await FirestoreService.addDebtCloud(
                  Map<String, dynamic>.from(updatedOldDebt),
                );

                // 5. Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "THU NỢ",
                  type: "DEBT",
                  targetId: debt['firestoreId'],
                  desc: "Khách trả ${MoneyUtils.formatVND(payAmount)} đ.",
                );

                if (!mounted) return;
                Navigator.pop(context);
                _refresh();
                NotificationService.showSnackBar(
                  "Đã thu nợ và đồng bộ hệ thống!",
                  color: Colors.green,
                );
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text("QUẢN LÝ CÔNG NỢ", style: AppTextStyles.headline5),
        automaticallyImplyLeading: true,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _syncStatus,
                style: AppTextStyles.caption.copyWith(
                  color: _syncStatus == 'Lỗi đồng bộ'
                      ? AppColors.error
                      : AppColors.onSurface.withOpacity(0.6),
                  fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? Colors.orange : Colors.blue,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2962FF),
          indicatorColor: const Color(0xFF2962FF),
          tabs: const [
            Tab(text: "KHÁCH NỢ"),
            Tab(text: "SHOP NỢ NCC"),
            Tab(text: "CÔNG NỢ KHÁC"),
          ],
        ),
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
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: _tabController.index == 0
            ? 'Tạo nợ khách hàng'
            : _tabController.index == 1
            ? 'Tạo nợ nhà cung cấp'
            : 'Tạo công nợ khác',
      ),
    );
  }

  Widget _buildDebtList(String type) {
    List<Map<String, dynamic>> list;
    if (type == 'OTHER') {
      list = _debts
          .where(
            (d) =>
                d['type'].toString().startsWith('OTHER_') &&
                (d['status'] != 'paid'),
          )
          .toList();
    } else {
      list = _debts
          .where((d) => d['type'] == type && (d['status'] != 'paid'))
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
        final int remain = total - paid;
        return remain > 0 ? sum + remain : sum;
      });

      int totalPayable = payableDebts.fold(0, (sum, d) {
        final int total = d['totalAmount'] as int;
        final int paid = d['paidAmount'] as int? ?? 0;
        final int remain = total - paid;
        return remain > 0 ? sum + remain : sum;
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
                    "${MoneyUtils.formatVND(totalReceivable)} đ",
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
                    "${MoneyUtils.formatVND(totalPayable)} đ",
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
      final int remain = total - paid;
      return remain > 0 ? sum + remain : sum;
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
            itemBuilder: (ctx, i) => _debtCard(list[i]),
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
            "${MoneyUtils.formatVND(amount)} đ",
            style: AppTextStyles.headline4.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _debtCard(Map<String, dynamic> d) {
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
        "${MoneyUtils.formatVND(v)}",
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c),
      ),
    ],
  );

  void _createOtherDebt() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String debtType = "CUSTOMER_OWES"; // Default to customer owes (nợ phải thu)

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("TẠO CÔNG NỢ KHÁC"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: "Tên người nợ"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: "Số điện thoại"),
              ),
              const SizedBox(height: 10),
              CurrencyTextField(controller: amountC, label: "Số tiền nợ"),
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
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text(
                      "NỢ PHẢI THU",
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: debtType == "CUSTOMER_OWES",
                    selectedColor: Colors.red.withAlpha(50),
                    onSelected: (v) => setS(() => debtType = "CUSTOMER_OWES"),
                  ),
                  ChoiceChip(
                    label: const Text(
                      "NỢ PHẢI TRẢ",
                      style: TextStyle(fontSize: 12),
                    ),
                    selected: debtType == "SHOP_OWES",
                    selectedColor: Colors.blue.withAlpha(50),
                    onSelected: (v) => setS(() => debtType = "SHOP_OWES"),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameC.text.isEmpty || amountC.text.isEmpty) return;

                // Lấy giá trị đã được CurrencyTextField xử lý
                int debtAmount = CurrencyTextField.parseValue(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_other_${now}",
                  'personName': nameC.text.trim(),
                  'phone': phoneC.text.trim(),
                  'totalAmount': debtAmount,
                  'paidAmount': 0,
                  'type':
                      'OTHER_${debtType}', // OTHER_CUSTOMER_OWES or OTHER_SHOP_OWES
                  'status': 'unpaid',
                  'createdAt': now,
                  'note': noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                  'createdBy': userName,
                };

                await db.insertDebt(newDebtData);
                await FirestoreService.addDebtCloud(newDebtData);

                if (mounted) {
                  Navigator.pop(ctx);
                  _refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Đã tạo công nợ mới")),
                  );
                }
              },
              child: const Text("TẠO"),
            ),
          ],
        ),
      ),
    );
  }

  void _createCustomerDebt() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("TẠO NỢ KHÁCH HÀNG (PHẢI THU)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: "Tên khách hàng"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneC,
              decoration: const InputDecoration(labelText: "Số điện thoại"),
            ),
            const SizedBox(height: 10),
            CurrencyTextField(controller: amountC, label: "Số tiền nợ"),
            const SizedBox(height: 10),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(labelText: "Ghi chú"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.isEmpty ||
                  phoneC.text.isEmpty ||
                  amountC.text.isEmpty)
                return;

              try {
                // Lấy giá trị đã được CurrencyTextField xử lý
                int debtAmount = CurrencyTextField.parseValue(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_customer_${now}",
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

                await db.insertDebt(newDebtData);
                await FirestoreService.addDebtCloud(newDebtData);

                // Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "TẠO NỢ",
                  type: "DEBT",
                  targetId: newDebtData['firestoreId'] as String,
                  desc:
                      "Tạo nợ khách hàng: ${nameC.text} - ${MoneyUtils.formatVND(debtAmount)} đ.",
                );

                if (!mounted) return;
                Navigator.pop(context);
                _refresh();
                NotificationService.showSnackBar(
                  "Đã tạo nợ khách hàng!",
                  color: Colors.green,
                );
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

  void _createSupplierDebt() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("TẠO NỢ NHÀ CUNG CẤP (PHẢI TRẢ)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: "Tên nhà cung cấp"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneC,
              decoration: const InputDecoration(labelText: "Số điện thoại"),
            ),
            const SizedBox(height: 10),
            CurrencyTextField(controller: amountC, label: "Số tiền nợ"),
            const SizedBox(height: 10),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(labelText: "Ghi chú"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameC.text.isEmpty ||
                  phoneC.text.isEmpty ||
                  amountC.text.isEmpty)
                return;

              try {
                // Lấy giá trị đã được CurrencyTextField xử lý
                int debtAmount = CurrencyTextField.parseValue(amountC.text);
                if (debtAmount <= 0) return;

                final user = FirebaseAuth.instance.currentUser;
                final userName =
                    user?.email?.split('@').first.toUpperCase() ?? "NV";
                final now = DateTime.now().millisecondsSinceEpoch;

                final newDebtData = {
                  'firestoreId': "debt_supplier_${now}",
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

                await db.insertDebt(newDebtData);
                await FirestoreService.addDebtCloud(newDebtData);

                // Nhật ký
                await db.logAction(
                  userId: user?.uid ?? "0",
                  userName: userName,
                  action: "TẠO NỢ",
                  type: "DEBT",
                  targetId: newDebtData['firestoreId'] as String,
                  desc:
                      "Tạo nợ nhà cung cấp: ${nameC.text} - ${MoneyUtils.formatVND(debtAmount)} đ.",
                );

                if (!mounted) return;
                Navigator.pop(context);
                _refresh();
                NotificationService.showSnackBar(
                  "Đã tạo nợ nhà cung cấp!",
                  color: Colors.green,
                );
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
    Color iconColor,
  ) {
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
        leading: CircleAvatar(
          backgroundColor: iconColor.withAlpha(25),
          child: Icon(icon, color: iconColor, size: 20),
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
