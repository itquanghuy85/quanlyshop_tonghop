import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/supplier_model.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import '../services/supplier_service.dart';
import '../services/payment_intent_service.dart';
import '../data/db_helper.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/gradient_fab.dart';
import '../utils/excel_export_helper.dart';

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
      // Truyền cả supplierId và supplierName để tìm được cả các record lưu với supplierId = 0
      final imports = await _db.getSupplierImportHistory(
        widget.supplier.id!,
        supplierName: widget.supplier.name,
      );
      final debts = (await _db.getAllDebts())
          .where((d) => d['type'] == 'SHOP_OWES' && (d['personName'] ?? '').toString().toUpperCase() == widget.supplier.name.toUpperCase() && (d['deleted'] ?? 0) != 1)
          .toList();
      final List<Map<String, dynamic>> payments = [];
      for (final d in debts) {
        final p = await _db.getDebtPayments(d['id'] as int);
        payments.addAll(p);
      }
      final stats = await _service.getSupplierStatistics(
        widget.supplier.id!.toString(),
        supplierName: widget.supplier.name,
      );
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(widget.supplier.name, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_tab.index == 0 && _imports.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Xuất Excel',
              onPressed: () => ExcelExportHelper.exportSupplierImportHistory(
                context,
                supplierName: widget.supplier.name,
                imports: _imports,
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Lịch sử nhập'),
            Tab(text: 'Công nợ'),
            Tab(text: 'Thống kê'),
          ],
        ),
      ),
      body: ResponsiveCenter(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildImportTab(),
                _buildDebtTab(),
                _buildStatsTab(),
              ],
            )),
      floatingActionButton: _tab.index == 1
          ? GradientFab.success(
              onPressed: _remainDebt <= 0 ? null : _payDialog,
              icon: Icons.payments,
              label: 'Thanh toán',
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
              CurrencyTextField(
                controller: payCtrl,
                label: 'Số tiền',
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
              Navigator.pop(ctx);
              await _confirmPay(amount, method, note);
            },
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPay(int amount, String methodStr, String note) async {
    // Tìm debt có thể trả
    final activeDebts = _debts.where((d) => 
      (d['status'] ?? 'ACTIVE') == 'ACTIVE' && 
      ((d['totalAmount'] as int? ?? 0) - (d['paidAmount'] as int? ?? 0)) > 0
    ).toList();
    
    if (activeDebts.isEmpty) {
      NotificationService.showSnackBar('Không có công nợ cần thanh toán', color: Colors.orange);
      return;
    }
    
    // Lấy debt đầu tiên có thể trả
    final debt = activeDebts.first;
    final debtFId = debt['firestoreId'] as String? ?? 'debt_supplier_${widget.supplier.id}';
    
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
      description: 'Trả nợ NCC: ${widget.supplier.name}',
      executedBy: user?.displayName ?? user?.email ?? 'unknown',
      referenceId: debtFId,
      referenceType: 'supplier_debt',
      personName: widget.supplier.name,
      personPhone: widget.supplier.phone,
      notes: note.isNotEmpty ? note : null,
      idempotencyKey: debtFId,
      metadata: {
        'supplierId': widget.supplier.id,
        'supplierName': widget.supplier.name,
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
