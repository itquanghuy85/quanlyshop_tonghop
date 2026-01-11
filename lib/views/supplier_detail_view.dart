import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';
import '../data/db_helper.dart';
import '../utils/money_utils.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/sync_orchestrator.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SupplierDetailView extends StatefulWidget {
  final Supplier supplier;
  const SupplierDetailView({super.key, required this.supplier});

  @override
  State<SupplierDetailView> createState() => _SupplierDetailViewState();
}

class _SupplierDetailViewState extends State<SupplierDetailView> with TickerProviderStateMixin {
  final _service = SupplierService();
  final _db = DBHelper();
  late TabController _tab;

  List<Map<String, dynamic>> _imports = [];
  List<Map<String, dynamic>> _debts = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
    EventBus().stream.where((e) => e == 'debts_changed' || e == 'suppliers_changed').listen((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final imports = await _db.getSupplierImportHistory(widget.supplier.id!);
      final debts = (await _db.getAllDebts())
          .where((d) => d['type'] == 'SHOP_OWES' && (d['personName'] ?? '').toString().toUpperCase() == widget.supplier.name.toUpperCase() && (d['deleted'] ?? 0) != 1)
          .toList();
      final List<Map<String, dynamic>> payments = [];
      for (final d in debts) {
        final p = await _db.getDebtPayments(d['id'] as int);
        payments.addAll(p);
      }
      final stats = await _service.getSupplierStatistics(widget.supplier.id!.toString());
      setState(() {
        _imports = imports;
        _debts = debts;
        _payments = payments;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải chi tiết: $e', color: Colors.red);
      setState(() => _loading = false);
    }
  }

  int get _totalDebt => _debts.fold(0, (s, d) => s + (d['totalAmount'] as int? ?? 0));
  int get _paidDebt => _debts.fold(0, (s, d) => s + (d['paidAmount'] as int? ?? 0));
  int get _remainDebt => _totalDebt - _paidDebt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.supplier.name),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Lịch sử nhập'),
            Tab(text: 'Công nợ'),
            Tab(text: 'Thống kê'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildImportTab(),
                _buildDebtTab(),
                _buildStatsTab(),
              ],
            ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton.extended(
              onPressed: _remainDebt <= 0 ? null : _payDialog,
              backgroundColor: AppColors.success,
              icon: const Icon(Icons.payments),
              label: const Text('THANH TOÁN'),
            )
          : null,
    );
  }

  Widget _buildImportTab() {
    if (_imports.isEmpty) {
      return Center(child: Text('Chưa có lịch sử nhập', style: AppTextStyles.body1));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _imports.length,
      itemBuilder: (ctx, i) {
        final h = _imports[i];
        final date = DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(h['importDate'] as int? ?? 0));
        return Card(
          child: ListTile(
            title: Text(h['productName'] ?? 'Sản phẩm', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ngày: $date', style: AppTextStyles.caption),
                Text('Số tiền: ${MoneyUtils.formatCurrency(h['totalAmount'] as int? ?? 0)}', style: AppTextStyles.caption),
                if (h['notes'] != null) Text('Ghi chú: ${h['notes']}', style: AppTextStyles.caption),
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
              _statChip('Còn lại', _remainDebt, AppColors.error),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text('Các khoản nợ', style: AppTextStyles.headline6),
              const SizedBox(height: 8),
              ..._debts.map((d) => _debtTile(d)),
              const SizedBox(height: 12),
              Text('Thanh toán đã ghi nhận', style: AppTextStyles.headline6),
              const SizedBox(height: 8),
              ..._payments.map((p) => _paymentTile(p)),
              if (_payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Chưa có thanh toán', style: AppTextStyles.caption),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab() {
    final totalImport = (_stats['totalImportValue'] as num?)?.toInt() ?? 0;
    final totalPaid = (_stats['totalPaid'] as num?)?.toInt() ?? 0;
    final totalImports = (_stats['totalImports'] as num?)?.toInt() ?? 0;
    final avg = totalImports == 0 ? 0 : (totalImport / totalImports).round();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statRow('Tổng nhập', MoneyUtils.formatCurrency(totalImport)),
          _statRow('Đã thanh toán', MoneyUtils.formatCurrency(totalPaid)),
          _statRow('Số lần giao dịch', '$totalImports lần'),
          _statRow('Trung bình/đơn', MoneyUtils.formatCurrency(avg)),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body1),
          Text(value, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
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
            Text(MoneyUtils.formatCurrency(value), style: AppTextStyles.headline6.copyWith(color: color)),
          ],
        ),
      ),
    );
  }

  Widget _debtTile(Map<String, dynamic> d) {
    final remain = (d['totalAmount'] as int? ?? 0) - (d['paidAmount'] as int? ?? 0);
    final date = DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(d['createdAt'] as int? ?? 0));
    return Card(
      child: ListTile(
        title: Text('Nợ ${MoneyUtils.formatCurrency(d['totalAmount'] as int? ?? 0)}', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ngày tạo: $date', style: AppTextStyles.caption),
            Text('Đã trả: ${MoneyUtils.formatCurrency(d['paidAmount'] as int? ?? 0)} | Còn: ${MoneyUtils.formatCurrency(remain)}', style: AppTextStyles.caption),
            if (d['note'] != null) Text('Ghi chú: ${d['note']}', style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> p) {
    final date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int? ?? 0));
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text('+ ${MoneyUtils.formatCurrency(p['amount'] as int? ?? 0)}'),
        subtitle: Text('$date | ${p['paymentMethod'] ?? ''}'),
        trailing: Text(p['note'] ?? '', style: AppTextStyles.caption),
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
      builder: (ctx) => AlertDialog(
        title: const Text('Thanh toán NCC'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyUtils.currencyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Số tiền'),
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 1,
                  max: _remainDebt,
                  fieldName: 'Số tiền',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['TIỀN MẶT', 'CHUYỂN KHOẢN']
                    .map((m) => ChoiceChip(
                          label: Text(m),
                          selected: method == m,
                          onSelected: (v) => setState(() => method = m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => note = v,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final raw = MoneyUtils.parseCurrency(payCtrl.text);
              final amount = raw > 0 && raw < 100000 ? raw * 1000 : raw;
              await _confirmPay(amount, method, note);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPay(int amount, String method, String note) async {
    try {
      final target = _debts.firstWhere((d) => (d['totalAmount'] as int? ?? 0) > (d['paidAmount'] as int? ?? 0));
      final debtId = target['id'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      final paymentData = {
        'firestoreId': 'pay_${now}_${widget.supplier.id ?? 'sup'}',
        'debtId': debtId,
        'debtFirestoreId': target['firestoreId'],
        'amount': amount,
        'paidAt': now,
        'paymentMethod': method,
        'note': note,
        'createdBy': FirebaseAuth.instance.currentUser?.email?.split('@').first.toUpperCase() ?? 'NV',
      };
      final paymentId = await _db.insertDebtPayment(paymentData);
      // Queue debt payment sync via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.debtPayment,
        entityId: paymentId,
        firestoreId: paymentData['firestoreId'] as String?,
        operation: SyncOperation.create,
        data: paymentData,
      );
      await _db.updateDebtPaid(debtId, amount);
      final allDebts = await _db.getAllDebts();
      final updated = allDebts.firstWhere((e) => e['id'] == debtId);
      // Queue debt update sync via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.debt,
        entityId: debtId,
        firestoreId: updated['firestoreId'] as String?,
        operation: SyncOperation.update,
        data: Map<String, dynamic>.from(updated),
      );
      EventBus().emit('debts_changed');
      NotificationService.showSnackBar('Đã ghi thanh toán', color: Colors.green);
      await _load();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi thanh toán: $e', color: Colors.red);
    }
  }
}
