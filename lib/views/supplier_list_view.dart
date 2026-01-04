import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/supplier_model.dart';
import '../models/repair_partner_model.dart';
import '../services/supplier_service.dart';
import '../services/repair_partner_service.dart';
import '../services/repair_partner_payment_service.dart';
import '../data/db_helper.dart';
import '../core/utils/money_utils.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'supplier_form_view.dart';
import 'supplier_detail_view.dart';
import 'repair_partner_form_view.dart';
import 'repair_partner_detail_view.dart';

class SupplierListView extends StatefulWidget {
  const SupplierListView({super.key});

  @override
  State<SupplierListView> createState() => _SupplierListViewState();
}

class _SupplierListViewState extends State<SupplierListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supplierService = SupplierService();
  final _partnerService = RepairPartnerService();
  final _paymentService = RepairPartnerPaymentService();
  final _db = DBHelper();
  final _searchCtrl = TextEditingController();
  final _partnerSearchCtrl = TextEditingController();

  List<_SupplierCardData> _items = [];
  bool _loading = true;
  bool _filterDebt = false;
  bool _filterSettled = false;
  bool _filterOverdue = false;
  bool _filterFavorite = false;
  String _sort = 'debt_desc';

  int _totalSuppliers = 0;
  int _totalPayable = 0;
  int _supplierOwing = 0;
  int _paidThisMonth = 0;

  // Repair partner data
  List<_PartnerCardData> _partners = [];
  bool _partnerLoading = true;
  bool _filterPartnerActive = false;
  bool _filterPartnerInactive = false;
  bool _filterPartnerOwing = false;
  String _partnerSort = 'name';

  int _totalPartners = 0;
  int _totalPartnerCost = 0;
  int _totalPartnerPaid = 0;
  int _partnerOwingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); // Rebuild FAB when tab changes
    });
    _load();
    _loadPartners();
    EventBus().stream.where((e) => e == 'suppliers_changed' || e == 'debts_changed').listen((_) {
      if (mounted) _load();
    });
    EventBus().stream.where((e) => e == 'repair_partners_changed').listen((_) {
      if (mounted) _loadPartners();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _partnerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final suppliers = await _supplierService.getSuppliers();
      final debts = await _db.getAllDebts();
      final dbInstance = await _db.database;
      final supplierImport = await dbInstance.query('supplier_import_history');
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1).millisecondsSinceEpoch;

      final List<_SupplierCardData> data = [];
      int totalPayable = 0;
      int owingCount = 0;
      int paidMonth = 0;

      for (final s in suppliers) {
        final relatedDebts = debts.where((d) => d['type'] == 'SHOP_OWES' && (d['personName'] ?? '').toString().toUpperCase() == s.name.toUpperCase()).toList();
        int total = 0;
        int paid = 0;
        int lastTx = s.updatedAt;
        for (final d in relatedDebts) {
          total += (d['totalAmount'] as int? ?? 0);
          paid += (d['paidAmount'] as int? ?? 0);
          lastTx = d['createdAt'] != null && d['createdAt'] > lastTx ? d['createdAt'] : lastTx;
          final payments = await _db.getDebtPayments(d['id'] as int);
          for (final p in payments) {
            if (p['paidAt'] != null && p['paidAt'] > lastTx) lastTx = p['paidAt'];
            if (p['paidAt'] != null && p['paidAt'] >= monthStart) {
              paidMonth += p['amount'] as int? ?? 0;
            }
          }
        }
        final remain = total - paid;
        final imports = supplierImport.where((h) => h['supplierId'] == s.id).toList();
        int totalImportValue = 0;
        int lastImport = lastTx;
        for (final h in imports) {
          totalImportValue += h['totalAmount'] as int? ?? 0;
          final importDate = h['importDate'] as int? ?? 0;
          if (importDate > lastImport) lastImport = importDate;
        }

        if (remain > 0) owingCount++;
        totalPayable += remain > 0 ? remain : 0;

        data.add(_SupplierCardData(
          supplier: s,
          totalDebt: total,
          paid: paid,
          remain: remain,
          totalImport: totalImportValue,
          lastTransactionAt: lastImport,
          isOverdue: remain > 0 && DateTime.now().millisecondsSinceEpoch - lastImport > const Duration(days: 30).inMilliseconds,
        ));
      }

      setState(() {
        _items = data;
        _totalSuppliers = suppliers.length;
        _totalPayable = totalPayable;
        _supplierOwing = owingCount;
        _paidThisMonth = paidMonth;
        _loading = false;
      });
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải danh sách NCC: $e', color: Colors.red);
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPartners() async {
    setState(() => _partnerLoading = true);
    try {
      final partners = await _partnerService.getRepairPartners();
      final List<_PartnerCardData> data = [];
      int totalCost = 0;
      int totalPaid = 0;
      int owingCount = 0;

      for (final p in partners) {
        final stats = await _partnerService.getPartnerRepairStats(p.id!);
        final cost = stats?['totalCost'] as int? ?? 0;
        final paid = stats?['totalPaid'] as int? ?? 0;
        final remain = cost - paid;
        final orders = stats?['totalOrders'] as int? ?? 0;

        totalCost += cost;
        totalPaid += paid;
        if (remain > 0) owingCount++;

        data.add(_PartnerCardData(
          partner: p,
          totalCost: cost,
          totalPaid: paid,
          remain: remain,
          totalOrders: orders,
        ));
      }

      setState(() {
        _partners = data;
        _totalPartners = partners.length;
        _totalPartnerCost = totalCost;
        _totalPartnerPaid = totalPaid;
        _partnerOwingCount = owingCount;
        _partnerLoading = false;
      });
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải danh sách đối tác: $e', color: Colors.red);
      setState(() => _partnerLoading = false);
    }
  }

  List<_PartnerCardData> _applyPartnerFilters() {
    final query = _partnerSearchCtrl.text.trim().toUpperCase();
    List<_PartnerCardData> list = _partners.where((item) {
      final matchesSearch = query.isEmpty ||
          item.partner.name.toUpperCase().contains(query) ||
          (item.partner.phone ?? '').toUpperCase().contains(query) ||
          (item.partner.note ?? '').toUpperCase().contains(query);
      final matchesActive = !_filterPartnerActive || item.partner.active;
      final matchesInactive = !_filterPartnerInactive || !item.partner.active;
      final matchesOwing = !_filterPartnerOwing || item.remain > 0;
      return matchesSearch && matchesActive && matchesInactive && matchesOwing;
    }).toList();

    if (_partnerSort == 'name') {
      list.sort((a, b) => a.partner.name.compareTo(b.partner.name));
    } else if (_partnerSort == 'debt_desc') {
      list.sort((a, b) => b.remain.compareTo(a.remain));
    } else if (_partnerSort == 'orders_desc') {
      list.sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
    }
    return list;
  }

  List<_SupplierCardData> _applyFilters() {
    final query = _searchCtrl.text.trim().toUpperCase();
    List<_SupplierCardData> list = _items.where((item) {
      final matchesSearch = query.isEmpty ||
          item.supplier.name.toUpperCase().contains(query) ||
          (item.supplier.phone ?? '').toUpperCase().contains(query) ||
          (item.supplier.note ?? '').toUpperCase().contains(query);
      final matchesDebt = !_filterDebt || item.remain > 0;
      final matchesSettled = !_filterSettled || item.remain <= 0;
      final matchesOverdue = !_filterOverdue || item.isOverdue;
      final matchesFavorite = !_filterFavorite || item.supplier.favorite;
      return matchesSearch && matchesDebt && matchesSettled && matchesOverdue && matchesFavorite;
    }).toList();

    if (_sort == 'debt_desc') {
      list.sort((a, b) => b.remain.compareTo(a.remain));
    } else if (_sort == 'last_tx') {
      list.sort((a, b) => (b.lastTransactionAt ?? 0).compareTo(a.lastTransactionAt ?? 0));
    }
    return list;
  }

  Color _statusColor(_SupplierCardData d) {
    if (d.remain <= 0) return AppColors.success;
    if (d.isOverdue) return AppColors.error;
    return AppColors.warning;
  }

  String _statusText(_SupplierCardData d) {
    if (d.remain <= 0) return 'Đã tất toán';
    if (d.isOverdue) return 'Quá hạn';
    return 'Còn nợ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('QUẢN LÝ ĐỐI TÁC'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.onPrimary,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: AppColors.onPrimary.withOpacity(0.7),
          tabs: const [
            Tab(text: 'NHÀ CUNG CẤP'),
            Tab(text: 'ĐỐI TÁC SỬA CHỮA'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_tabController.index == 0) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierFormView()));
            await _load();
          } else {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const RepairPartnerFormView()));
            await _loadPartners();
          }
        },
        icon: Icon(_tabController.index == 0 ? Icons.add_business : Icons.handyman),
        label: Text(_tabController.index == 0 ? 'THÊM NCC' : 'THÊM ĐỐI TÁC'),
        backgroundColor: AppColors.primary,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSupplierTab(),
          _buildPartnerTab(),
        ],
      ),
    );
  }

  Widget _buildSupplierTab() {
    final filtered = _applyFilters();
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(),
                const SizedBox(height: 12),
                _buildSearchFilter(),
                const SizedBox(height: 12),
                ...filtered.map(_buildCard),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text('Không tìm thấy NCC phù hợp', style: AppTextStyles.body1.copyWith(color: AppColors.onSurface.withOpacity(0.6))),
                    ),
                  )
              ],
            ),
          );
  }

  Widget _buildPartnerTab() {
    final filtered = _applyPartnerFilters();
    return _partnerLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadPartners,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPartnerHeader(),
                const SizedBox(height: 12),
                _buildPartnerSearchFilter(),
                const SizedBox(height: 12),
                ...filtered.map(_buildPartnerCard),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text('Không tìm thấy đối tác phù hợp', style: AppTextStyles.body1.copyWith(color: AppColors.onSurface.withOpacity(0.6))),
                    ),
                  )
              ],
            ),
          );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _headerTile('Tổng NCC', _totalSuppliers.toString(), Icons.apartment, AppColors.primary)),
            const SizedBox(width: 8),
            Expanded(child: _headerTile('Tổng công nợ', MoneyUtils.formatVND(_totalPayable), Icons.account_balance, AppColors.error)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _headerTile('NCC còn nợ', _supplierOwing.toString(), Icons.warning, AppColors.warning)),
            const SizedBox(width: 8),
            Expanded(child: _headerTile('Đã trả trong tháng', MoneyUtils.formatVND(_paidThisMonth), Icons.payments, AppColors.success)),
          ],
        ),
      ],
    );
  }

  Widget _headerTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.headline6.copyWith(color: color, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.7)), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildSearchFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Tìm NCC theo tên / SĐT / ghi chú',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(label: const Text('Còn nợ'), selected: _filterDebt, onSelected: (v) => setState(() => _filterDebt = v)),
            FilterChip(label: const Text('Đã tất toán'), selected: _filterSettled, onSelected: (v) => setState(() => _filterSettled = v)),
            FilterChip(label: const Text('Quá hạn'), selected: _filterOverdue, onSelected: (v) => setState(() => _filterOverdue = v)),
            FilterChip(label: const Text('Ưu tiên'), selected: _filterFavorite, onSelected: (v) => setState(() => _filterFavorite = v)),
            ChoiceChip(label: const Text('Nợ cao → thấp'), selected: _sort == 'debt_desc', onSelected: (v) => setState(() => _sort = 'debt_desc')),
            ChoiceChip(label: const Text('Giao dịch gần nhất'), selected: _sort == 'last_tx', onSelected: (v) => setState(() => _sort = 'last_tx')),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(_SupplierCardData d) {
    final color = _statusColor(d);
    final status = _statusText(d);
    final date = d.lastTransactionAt != null ? DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(d.lastTransactionAt!)) : 'Chưa có GD';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(d.supplier.name, style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.6))),
                child: Text(status, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Công nợ: ', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
              Text(MoneyUtils.formatVND(d.remain), style: AppTextStyles.body1.copyWith(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.history, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('GD gần nhất: $date', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.inventory_2, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('Tổng nhập: ${MoneyUtils.formatVND(d.totalImport)}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierDetailView(supplier: d.supplier)));
                  await _load();
                },
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Lịch sử'),
                style: AppButtonStyles.elevatedButtonStyle,
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await _openPayDialog(d);
                },
                icon: const Icon(Icons.payments, size: 16),
                label: const Text('Thanh toán'),
                style: AppButtonStyles.successElevatedButtonStyle,
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierFormView(editing: d.supplier)));
                  await _load();
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Sửa'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPayDialog(_SupplierCardData d) async {
    if (d.remain <= 0) {
      NotificationService.showSnackBar('NCC này đã tất toán.', color: Colors.green);
      return;
    }
    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Thanh toán công nợ cho ${d.supplier.name}', style: AppTextStyles.headline6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Còn nợ: ${MoneyUtils.formatVND(d.remain)}', style: AppTextStyles.body1.copyWith(color: AppColors.error, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số tiền (nghìn đồng)',
                  hintText: 'VD: 500 = ${MoneyUtils.formatVND(500000)}',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['TIỀN MẶT', 'CHUYỂN KHOẢN'].map((m) => ChoiceChip(label: Text(m), selected: method == m, onSelected: (v) => setDialogState(() => method = m))).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => note = v,
                decoration: const InputDecoration(labelText: 'Ghi chú (tùy chọn)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: () async {
                final inputVal = int.tryParse(payCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
                final amount = inputVal * 1000; // Nhân 1000 để chuyển sang VNĐ
                if (amount <= 0 || amount > d.remain) {
                  NotificationService.showSnackBar('Số tiền không hợp lệ (tối đa ${MoneyUtils.formatVND(d.remain)})', color: Colors.red);
                  return;
                }
                await _payDebt(d, amount, method, note);
                if (mounted) Navigator.pop(ctx);
              },
              style: AppButtonStyles.successElevatedButtonStyle,
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _payDebt(_SupplierCardData d, int amount, String method, String note) async {
    try {
      // Find first active debt
      final debts = await _db.getAllDebts();
      final target = debts.firstWhere(
        (e) => e['type'] == 'SHOP_OWES' && (e['personName'] ?? '').toString().toUpperCase() == d.supplier.name.toUpperCase() && (e['totalAmount'] as int? ?? 0) > (e['paidAmount'] as int? ?? 0),
        orElse: () => {},
      );
      if (target.isEmpty) {
        NotificationService.showSnackBar('Không tìm thấy công nợ để thanh toán', color: Colors.red);
        return;
      }
      final debtId = target['id'] as int;
      await _db.insertDebtPayment({
        'firestoreId': 'pay_${DateTime.now().millisecondsSinceEpoch}_${d.supplier.id ?? 'sup'}',
        'debtId': debtId,
        'debtFirestoreId': target['firestoreId'],
        'amount': amount,
        'paidAt': DateTime.now().millisecondsSinceEpoch,
        'paymentMethod': method,
        'note': note,
        'createdBy': FirebaseAuth.instance.currentUser?.email?.split('@').first.toUpperCase() ?? 'NV',
      });
      await _db.updateDebtPaid(debtId, amount);

      final allDebts = await _db.getAllDebts();
      final updated = allDebts.firstWhere((e) => e['id'] == debtId);
      await FirestoreService.addDebtCloud(Map<String, dynamic>.from(updated));
      
      // Ghi nhật ký hệ thống
      await AuditService.logAction(
        action: 'SUPPLIER_PAYMENT',
        entityType: 'supplier',
        entityId: d.supplier.id?.toString() ?? '',
        summary: 'Thanh toán công nợ NCC ${d.supplier.name}: ${MoneyUtils.formatVND(amount)} ($method)',
        payload: {
          'supplierId': d.supplier.id,
          'supplierName': d.supplier.name,
          'amount': amount,
          'paymentMethod': method,
          'note': note,
          'remainBefore': d.remain,
          'remainAfter': d.remain - amount,
        },
      );
      
      EventBus().emit('debts_changed');
      NotificationService.showSnackBar('Đã ghi nhận thanh toán', color: Colors.green);
      await _load();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi thanh toán: $e', color: Colors.red);
    }
  }

  // ==================== PARTNER TAB WIDGETS ====================

  Widget _buildPartnerHeader() {
    final remain = _totalPartnerCost - _totalPartnerPaid;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _headerTile('Tổng đối tác', _totalPartners.toString(), Icons.handyman, AppColors.primary)),
            const SizedBox(width: 8),
            Expanded(child: _headerTile('Còn nợ đối tác', MoneyUtils.formatVND(remain), Icons.account_balance, remain > 0 ? AppColors.error : AppColors.success)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _headerTile('ĐT còn nợ', _partnerOwingCount.toString(), Icons.warning, AppColors.warning)),
            const SizedBox(width: 8),
            Expanded(child: _headerTile('Đã thanh toán', MoneyUtils.formatVND(_totalPartnerPaid), Icons.payments, AppColors.success)),
          ],
        ),
      ],
    );
  }

  Widget _buildPartnerSearchFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _partnerSearchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Tìm đối tác theo tên / SĐT / ghi chú',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(label: const Text('Hoạt động'), selected: _filterPartnerActive, onSelected: (v) => setState(() => _filterPartnerActive = v)),
            FilterChip(label: const Text('Ngừng HĐ'), selected: _filterPartnerInactive, onSelected: (v) => setState(() => _filterPartnerInactive = v)),
            FilterChip(label: const Text('Còn nợ'), selected: _filterPartnerOwing, onSelected: (v) => setState(() => _filterPartnerOwing = v)),
            ChoiceChip(label: const Text('Theo tên'), selected: _partnerSort == 'name', onSelected: (v) => setState(() => _partnerSort = 'name')),
            ChoiceChip(label: const Text('Nợ cao → thấp'), selected: _partnerSort == 'debt_desc', onSelected: (v) => setState(() => _partnerSort = 'debt_desc')),
            ChoiceChip(label: const Text('Nhiều đơn nhất'), selected: _partnerSort == 'orders_desc', onSelected: (v) => setState(() => _partnerSort = 'orders_desc')),
          ],
        ),
      ],
    );
  }

  Widget _buildPartnerCard(_PartnerCardData d) {
    final color = d.remain > 0 ? AppColors.warning : AppColors.success;
    final status = d.remain > 0 ? 'Còn nợ' : 'Đã tất toán';
    final activeColor = d.partner.active ? AppColors.success : AppColors.onSurface.withOpacity(0.5);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                d.partner.active ? Icons.check_circle : Icons.cancel,
                color: activeColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(d.partner.name, style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.6))),
                child: Text(status, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d.partner.phone != null) ...[
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
                const SizedBox(width: 6),
                Text(d.partner.phone!, style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Text('Công nợ: ', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
              Text(MoneyUtils.formatVND(d.remain), style: AppTextStyles.body1.copyWith(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.assignment, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('Tổng đơn gửi: ${d.totalOrders}', style: AppTextStyles.caption),
              const SizedBox(width: 16),
              Icon(Icons.receipt_long, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
              const SizedBox(width: 6),
              Text('Tổng chi: ${MoneyUtils.formatVND(d.totalCost)}', style: AppTextStyles.caption),
            ],
          ),
          if (d.partner.note != null && d.partner.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.note, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
                const SizedBox(width: 6),
                Expanded(child: Text(d.partner.note!, style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => RepairPartnerDetailView(partner: d.partner)));
                  await _loadPartners();
                },
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Chi tiết'),
                style: AppButtonStyles.elevatedButtonStyle,
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await _openPartnerPayDialog(d);
                },
                icon: const Icon(Icons.payments, size: 16),
                label: const Text('Thanh toán'),
                style: AppButtonStyles.successElevatedButtonStyle,
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => RepairPartnerFormView(editing: d.partner)));
                  await _loadPartners();
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Sửa'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPartnerPayDialog(_PartnerCardData d) async {
    if (d.remain <= 0) {
      NotificationService.showSnackBar('Đối tác này đã tất toán.', color: Colors.green);
      return;
    }
    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Thanh toán cho ${d.partner.name}', style: AppTextStyles.headline6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Còn nợ: ${MoneyUtils.formatVND(d.remain)}', style: AppTextStyles.body1.copyWith(color: AppColors.error, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số tiền (nghìn đồng)',
                  hintText: 'VD: 500 = ${MoneyUtils.formatVND(500000)}',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['TIỀN MẶT', 'CHUYỂN KHOẢN'].map((m) => ChoiceChip(label: Text(m), selected: method == m, onSelected: (v) => setDialogState(() => method = m))).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => note = v,
                decoration: const InputDecoration(labelText: 'Ghi chú (tùy chọn)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: () async {
                final inputVal = int.tryParse(payCtrl.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
                final amount = inputVal * 1000; // Nhân 1000 để chuyển sang VNĐ
                if (amount <= 0 || amount > d.remain) {
                  NotificationService.showSnackBar('Số tiền không hợp lệ (tối đa ${MoneyUtils.formatVND(d.remain)})', color: Colors.red);
                  return;
                }
                await _paymentService.addPayment(
                  partnerId: d.partner.id!,
                  amount: amount,
                  paymentMethod: method,
                  note: note,
                );
                
                // Ghi nhật ký hệ thống
                await AuditService.logAction(
                  action: 'PARTNER_PAYMENT',
                  entityType: 'repair_partner',
                  entityId: d.partner.id!.toString(),
                  summary: 'Thanh toán đối tác ${d.partner.name}: ${MoneyUtils.formatVND(amount)} ($method)',
                  payload: {
                    'partnerId': d.partner.id,
                    'partnerName': d.partner.name,
                    'amount': amount,
                    'paymentMethod': method,
                    'note': note,
                    'remainBefore': d.remain,
                    'remainAfter': d.remain - amount,
                  },
                );
                
                NotificationService.showSnackBar('Đã ghi nhận thanh toán', color: Colors.green);
                EventBus().emit('repair_partners_changed');
                await _loadPartners();
                if (mounted) Navigator.pop(ctx);
              },
              style: AppButtonStyles.successElevatedButtonStyle,
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierCardData {
  final Supplier supplier;
  final int totalDebt;
  final int paid;
  final int remain;
  final int totalImport;
  final int? lastTransactionAt;
  final bool isOverdue;

  _SupplierCardData({
    required this.supplier,
    required this.totalDebt,
    required this.paid,
    required this.remain,
    required this.totalImport,
    required this.lastTransactionAt,
    required this.isOverdue,
  });
}

class _PartnerCardData {
  final RepairPartner partner;
  final int totalCost;
  final int totalPaid;
  final int remain;
  final int totalOrders;

  _PartnerCardData({
    required this.partner,
    required this.totalCost,
    required this.totalPaid,
    required this.remain,
    required this.totalOrders,
  });
}
