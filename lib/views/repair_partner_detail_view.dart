import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/repair_partner_model.dart';
import '../models/partner_repair_history_model.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import '../services/repair_partner_service.dart';
import '../services/payment_intent_service.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../data/db_helper.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/gradient_fab.dart';

class RepairPartnerDetailView extends StatefulWidget {
  final RepairPartner partner;
  const RepairPartnerDetailView({super.key, required this.partner});

  @override
  State<RepairPartnerDetailView> createState() =>
      _RepairPartnerDetailViewState();
}

class _RepairPartnerDetailViewState extends State<RepairPartnerDetailView>
    with TickerProviderStateMixin {
  final _partnerService = RepairPartnerService();
  final _db = DBHelper();
  late TabController _tab;

  List<PartnerRepairHistory> _histories = [];
  List<Map<String, dynamic>> _debts = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    EventBus().stream
        .where((e) => e == 'repair_partners_changed' || e == 'debts_changed')
        .listen((_) {
          if (mounted) _load();
        });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Use partnerFirestoreId for stable cross-device lookup, fallback to local id
      final histories = await _partnerService.getPartnerRepairHistory(
        partnerId: widget.partner.id,
        partnerFirestoreId: widget.partner.firestoreId,
      );
      // Lấy debts theo personName giống như supplier_detail_view
      final allDebts = await _db.getAllDebts();
      final debts = allDebts
          .where(
            (d) =>
                d['type'] == 'SHOP_OWES' &&
                (d['personName'] ?? '').toString().toUpperCase() ==
                    widget.partner.name.toUpperCase() &&
                (d['deleted'] ?? 0) != 1,
          )
          .toList();

      // Lấy payments từ debt_payments table (giống supplier)
      final List<Map<String, dynamic>> payments = [];
      for (final d in debts) {
        final p = await _db.getDebtPayments(d['id'] as int);
        payments.addAll(p);
      }

      final stats =
          await _partnerService.getPartnerRepairStats(
            widget.partner.id!,
            partnerFirestoreId: widget.partner.firestoreId,
          ) ?? {};

      setState(() {
        _histories = histories;
        _debts = debts;
        _payments = payments;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi tải dữ liệu: $e',
        color: Colors.red,
      );
      setState(() => _loading = false);
    }
  }

  // Tính toán từ debts (giống supplier)
  int get _totalDebt =>
      _debts.fold(0, (s, d) => s + (d['totalAmount'] as int? ?? 0));
  int get _paidDebt =>
      _debts.fold(0, (s, d) => s + (d['paidAmount'] as int? ?? 0));
  int get _remainDebt => _totalDebt - _paidDebt;

  // Backup từ stats nếu chưa có debts
  int get _totalCost =>
      _debts.isNotEmpty ? _totalDebt : ((_stats['totalCost'] as int?) ?? 0);
  int get _totalPaid =>
      _debts.isNotEmpty ? _paidDebt : ((_stats['totalPaid'] as int?) ?? 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
        title: Text(
          widget.partner.name,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'ĐƠN GỬI SỬA'),
            Tab(text: 'CÔNG NỢ'),
            Tab(text: 'THỐNG KÊ'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_buildHistoryTab(), _buildDebtTab(), _buildStatsTab()],
            ),
      floatingActionButton: _tab.index == 1 && _remainDebt > 0
          ? GradientFab.success(
              onPressed: _payDialog,
              icon: Icons.payments,
              label: 'Thanh toán',
            )
          : null,
    );
  }

  Widget _buildHistoryTab() {
    if (_histories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: AppColors.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có đơn gửi sửa nào',
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _histories.length,
      itemBuilder: (ctx, i) {
        final h = _histories[i];
        final date = DateFormat(
          'dd/MM/yyyy HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(h.sentAt));
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        h.deviceModel,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        MoneyUtils.formatCurrency(h.partnerCost),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Khách: ${h.customerName}', style: AppTextStyles.caption),
                Text('Lỗi: ${h.issue}', style: AppTextStyles.caption),
                if (h.repairContent != null && h.repairContent!.isNotEmpty)
                  Text(
                    'Nội dung sửa: ${h.repairContent}',
                    style: AppTextStyles.caption,
                  ),
                const SizedBox(height: 4),
                Text(
                  'Ngày gửi: $date',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebtTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _statChip('Tổng nợ', _totalDebt, AppColors.warning),
              const SizedBox(width: 8),
              _statChip('Đã trả', _paidDebt, AppColors.success),
              const SizedBox(width: 8),
              _statChip(
                'Còn lại',
                _remainDebt,
                _remainDebt > 0 ? AppColors.error : AppColors.success,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text('Các khoản nợ', style: AppTextStyles.headline6),
              const SizedBox(height: 8),
              if (_debts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Chưa có khoản nợ nào',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                )
              else
                ..._debts.map((d) => _debtTile(d)),
              const SizedBox(height: 12),
              Text('Thanh toán đã ghi nhận', style: AppTextStyles.headline6),
              const SizedBox(height: 8),
              if (_payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Chưa có thanh toán',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                )
              else
                ..._payments.map((p) => _paymentTile(p)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _debtTile(Map<String, dynamic> d) {
    final remain =
        (d['totalAmount'] as int? ?? 0) - (d['paidAmount'] as int? ?? 0);
    final date = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(d['createdAt'] as int? ?? 0));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          'Nợ ${MoneyUtils.formatCurrency(d['totalAmount'] as int? ?? 0)}',
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ngày tạo: $date', style: AppTextStyles.caption),
            Text(
              'Đã trả: ${MoneyUtils.formatCurrency(d['paidAmount'] as int? ?? 0)} | Còn: ${MoneyUtils.formatCurrency(remain)}',
              style: AppTextStyles.caption,
            ),
            if (d['note'] != null)
              Text('Ghi chú: ${d['note']}', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    final totalOrders =
        (_stats['totalOrders'] ?? _stats['totalRepairs'] ?? 0) as int;
    final avgCost = totalOrders == 0 ? 0 : (_totalCost / totalOrders).round();
    final lastRepairDate = _stats['lastRepairDate'] as int?;
    final lastDateStr = lastRepairDate != null
        ? DateFormat(
            'dd/MM/yyyy',
          ).format(DateTime.fromMillisecondsSinceEpoch(lastRepairDate))
        : 'N/A';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statRow('Tổng đơn gửi sửa', '$totalOrders đơn'),
          _statRow('Tổng chi phí', MoneyUtils.formatCurrency(_totalCost)),
          _statRow('Đã thanh toán', MoneyUtils.formatCurrency(_totalPaid)),
          _statRow('Trung bình/đơn', MoneyUtils.formatCurrency(avgCost)),
          _statRow('Lần gửi sửa cuối', lastDateStr),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body1),
          Text(
            value,
            style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(
              MoneyUtils.formatCurrency(value),
              style: AppTextStyles.headline6.copyWith(
                color: color,
                fontSize: AppTextStyles.headline4.fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> p) {
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int? ?? 0));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text('+ ${MoneyUtils.formatCurrency(p['amount'] as int? ?? 0)}'),
        subtitle: Text('$date | ${p['paymentMethod'] ?? ''}'),
        trailing: p['note'] != null && (p['note'] as String).isNotEmpty
            ? Tooltip(
                message: p['note'],
                child: const Icon(Icons.info_outline, size: 18),
              )
            : null,
      ),
    );
  }

  Future<void> _payDialog() async {
    final formKey = GlobalKey<FormState>();
    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.payments, color: AppColors.success),
              const SizedBox(width: 12),
              Text('Thanh toán đối tác', style: AppTextStyles.headline6),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Còn nợ: ${MoneyUtils.formatCurrency(_remainDebt)}',
                  style: AppTextStyles.body2.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 16),
                CurrencyTextField(
                  controller: payCtrl,
                  label: 'Số tiền thanh toán',
                  icon: Icons.attach_money,
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    max: _remainDebt,
                    fieldName: 'Số tiền',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Phương thức',
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['TIỀN MẶT', 'CHUYỂN KHOẢN']
                      .map(
                        (m) => ChoiceChip(
                          label: Text(m),
                          selected: method == m,
                          onSelected: (v) => setDialogState(() => method = m),
                          selectedColor: AppColors.primary.withOpacity(0.2),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (v) => note = v,
                  decoration: InputDecoration(
                    labelText: 'Ghi chú (tùy chọn)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final raw = MoneyUtils.parseCurrency(payCtrl.text);
                final amount = raw > 0 && raw < 100000 ? raw * 1000 : raw;
                Navigator.pop(ctx);
                await _confirmPay(amount, method, note);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPay(int amount, String methodStr, String note) async {
    // Tìm debt có thể trả (giống supplier_detail_view)
    final activeDebts = _debts
        .where(
          (d) =>
              (d['status'] ?? 'ACTIVE') == 'ACTIVE' &&
              ((d['totalAmount'] as int? ?? 0) -
                      (d['paidAmount'] as int? ?? 0)) >
                  0,
        )
        .toList();

    if (activeDebts.isEmpty) {
      NotificationService.showSnackBar(
        'Không có công nợ cần thanh toán',
        color: Colors.orange,
      );
      return;
    }

    // Lấy debt đầu tiên có thể trả
    final debt = activeDebts.first;
    final debtFId =
        debt['firestoreId'] as String? ?? 'debt_partner_${widget.partner.id}';

    // Convert payment method string to enum
    final method = methodStr == 'CHUYỂN KHOẢN' 
        ? PaymentMethod.transfer 
        : PaymentMethod.cash;

    // Execute payment directly without navigation
    final user = FirebaseAuth.instance.currentUser;
    final result = await PaymentIntentService.executePaymentDirect(
      type: PaymentIntentType.supplierDebt,
      amount: amount,
      paymentMethod: method,
      description: 'Trả nợ đối tác: ${widget.partner.name}',
      executedBy: user?.displayName ?? user?.email ?? 'unknown',
      referenceId: debtFId,
      referenceType: 'repair_partner_debt',
      personName: widget.partner.name,
      personPhone: widget.partner.phone,
      notes: note.isNotEmpty ? note : null,
      metadata: {
        'partnerId': widget.partner.id,
        'partnerName': widget.partner.name,
        'partnerFirestoreId': widget.partner.firestoreId,
        'debtId': debt['id'],
        'debtFirestoreId': debtFId,
        'debtType': 'SHOP_OWES',
        'suggestedMethod': methodStr,
      },
    );

    if (result.success) {
      if (mounted) {
        NotificationService.showSnackBar(
          'Đã thanh toán ${MoneyUtils.formatCurrency(amount)}đ!',
          color: Colors.green,
        );
        _load();
      }
    } else {
      if (mounted) {
        NotificationService.showSnackBar(
          result.errorMessage ?? 'Có lỗi xảy ra',
          color: Colors.red,
        );
      }
    }
  }
}
