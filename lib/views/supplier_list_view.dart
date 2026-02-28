import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/supplier_model.dart';
import '../models/repair_partner_model.dart';
import '../models/payment_intent_model.dart';
import '../models/shop_settings_model.dart';
import '../constants/financial_constants.dart';
import '../services/supplier_service.dart';
import '../services/repair_partner_service.dart';
import '../services/repair_partner_payment_service.dart';
import '../services/user_service.dart';
import '../services/first_time_guide_service.dart';
import '../services/payment_intent_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../data/db_helper.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/gradient_fab.dart';
import 'supplier_form_view.dart';
import 'supplier_detail_view.dart';
import 'repair_partner_form_view.dart';
import 'repair_partner_detail_view.dart';
import 'create_sale_view.dart';
import 'inventory_view.dart';

class SupplierListView extends StatefulWidget {
  const SupplierListView({super.key});

  @override
  State<SupplierListView> createState() => _SupplierListViewState();
}

class _SupplierListViewState extends State<SupplierListView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supplierService = SupplierService();
  final _partnerService = RepairPartnerService();
  final _paymentService = RepairPartnerPaymentService();
  final _db = DBHelper();
  final _searchCtrl = TextEditingController();
  final _partnerSearchCtrl = TextEditingController();
  StreamSubscription? _eventBusSub;
  Timer? _reloadDebounce;

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

  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);
  bool get _isElectronics => _shopSettings?.businessType == 'electronics' || _shopSettings?.businessType == null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // Will be recreated after settings load
    _tabController.addListener(() {
      if (mounted) setState(() {}); // Rebuild FAB when tab changes
    });
    _loadShopSettings();
    _load();
    _loadPartners();
    _eventBusSub = EventBus().stream
        .where((e) => e == 'suppliers_changed' || e == 'debts_changed')
        .listen((_) {
      if (!mounted) return;
      _debouncedReload();
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
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keySupplierList,
      title: 'Quản Lý Đối Tác',
      icon: Icons.store,
      color: Colors.teal,
      steps: const [
        GuideStep(
          title: '🏢 Nhà cung cấp (NCC)',
          description: 'Quản lý NCC hàng hóa. PHẢI tạo NCC trước khi nhập kho để theo dõi công nợ chính xác.',
          icon: Icons.local_shipping,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🔧 Đối tác sửa chữa',
          description: 'Quản lý thợ/tiệm ngoài gửi sửa. Theo dõi đơn gửi đi và công nợ phải trả.',
          icon: Icons.build,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '💰 Công nợ NCC',
          description: 'Khi nhập kho chọn "CÔNG NỢ", hệ thống tự tạo nợ. Thanh toán dần trong chi tiết NCC.',
          icon: Icons.account_balance_wallet,
          iconColor: Colors.red,
        ),
        GuideStep(
          title: '➕ Thêm mới',
          description: 'Nhấn nút + góc phải để thêm NCC hoặc Đối tác mới. Điền đầy đủ thông tin liên hệ.',
          icon: Icons.add_circle,
          iconColor: Colors.green,
        ),
      ],
    );
  }

  void _debouncedReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _load();
      _loadPartners();
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _eventBusSub?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    _partnerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final suppliers = await _supplierService.getSuppliers();
      final debts = await _db.getAllDebts();
      final dbInstance = await _db.database;
      final rawImports = await dbInstance.query('supplier_import_history');
      // Deduplicate imports by natural key to avoid double counting
      final Map<String, Map<String, dynamic>> importMap = {};
      for (final h in rawImports) {
        final key = [
          h['referenceId'] ?? '',
          h['productName'] ?? '',
          h['imei'] ?? '',
          h['importDate'] ?? '',
          h['totalAmount'] ?? '',
          h['quantity'] ?? '',
          h['costPrice'] ?? '',
          h['supplierName'] ?? '',
        ].join('|');
        importMap[key] = h;
      }
      final supplierImport = importMap.values.toList();
      final monthStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        1,
      ).millisecondsSinceEpoch;

      final List<_SupplierCardData> data = [];
      int totalPayable = 0;
      int owingCount = 0;
      int paidMonth = 0;

      for (final s in suppliers) {
        // BUG-007: Filter out soft-deleted debts
        final relatedDebts = debts
            .where(
              (d) =>
                  d['type'] == 'SHOP_OWES' &&
                  (d['personName'] ?? '').toString().toUpperCase() ==
                      s.name.toUpperCase() &&
                  (d['deleted'] ?? 0) != 1,
            )
            .toList();
        int total = 0;
        int paid = 0;
        int lastTx = s.updatedAt;
        for (final d in relatedDebts) {
          total += (d['totalAmount'] as int? ?? 0);
          paid += (d['paidAmount'] as int? ?? 0);
          lastTx = d['createdAt'] != null && d['createdAt'] > lastTx
              ? d['createdAt']
              : lastTx;
          final payments = await _db.getDebtPayments(d['id'] as int);
          for (final p in payments) {
            if (p['paidAt'] != null && p['paidAt'] > lastTx) {
              lastTx = p['paidAt'];
            }
            if (p['paidAt'] != null && p['paidAt'] >= monthStart) {
              paidMonth += p['amount'] as int? ?? 0;
            }
          }
        }
        // BUG-002: Clamp remain để không âm (tránh hiển thị số nợ sai)
        final remain = (total - paid).clamp(0, total);
        final imports = supplierImport
            .where((h) => h['supplierId'] == s.id)
            .toList();
        int totalImportValue = 0;
        int lastImport = lastTx;
        for (final h in imports) {
          totalImportValue += h['totalAmount'] as int? ?? 0;
          final importDate = h['importDate'] as int? ?? 0;
          if (importDate > lastImport) lastImport = importDate;
        }

        if (remain > 0) owingCount++;
        totalPayable += remain > 0 ? remain : 0;

        data.add(
          _SupplierCardData(
            supplier: s,
            totalDebt: total,
            paid: paid,
            remain: remain,
            totalImport: totalImportValue,
            lastTransactionAt: lastImport,
            isOverdue:
                remain > 0 &&
                DateTime.now().millisecondsSinceEpoch - lastImport >
                    const Duration(days: 30).inMilliseconds,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _items = data;
        _totalSuppliers = suppliers.length;
        _totalPayable = totalPayable;
        _supplierOwing = owingCount;
        _paidThisMonth = paidMonth;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      NotificationService.showSnackBar(
        'Lỗi tải danh sách NCC: $e',
        color: Colors.red,
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPartners() async {
    if (!mounted) return;
    setState(() => _partnerLoading = true);
    try {
      final partners = await _partnerService.getRepairPartners();
      final List<_PartnerCardData> data = [];
      int totalCost = 0;
      int totalPaid = 0;
      int owingCount = 0;

      for (final p in partners) {
        final stats = await _partnerService.getPartnerRepairStats(p.id!, partnerFirestoreId: p.firestoreId, partnerName: p.name);
        final cost = stats?['totalCost'] as int? ?? 0;
        final paid = stats?['totalPaid'] as int? ?? 0;
        final remain = cost - paid;
        final orders = stats?['totalOrders'] as int? ?? 0;

        totalCost += cost;
        totalPaid += paid;
        if (remain > 0) owingCount++;

        data.add(
          _PartnerCardData(
            partner: p,
            totalCost: cost,
            totalPaid: paid,
            remain: remain,
            totalOrders: orders,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _partners = data;
        _totalPartners = partners.length;
        _totalPartnerCost = totalCost;
        _totalPartnerPaid = totalPaid;
        _partnerOwingCount = owingCount;
        _partnerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      NotificationService.showSnackBar(
        'Lỗi tải danh sách đối tác: $e',
        color: Colors.red,
      );
      setState(() => _partnerLoading = false);
    }
  }

  List<_PartnerCardData> _applyPartnerFilters() {
    final query = _partnerSearchCtrl.text.trim().toUpperCase();
    List<_PartnerCardData> list = _partners.where((item) {
      final matchesSearch =
          query.isEmpty ||
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
      final matchesSearch =
          query.isEmpty ||
          item.supplier.name.toUpperCase().contains(query) ||
          (item.supplier.phone ?? '').toUpperCase().contains(query) ||
          (item.supplier.note ?? '').toUpperCase().contains(query);
      final matchesDebt = !_filterDebt || item.remain > 0;
      final matchesSettled = !_filterSettled || item.remain <= 0;
      final matchesOverdue = !_filterOverdue || item.isOverdue;
      final matchesFavorite = !_filterFavorite || item.supplier.favorite;
      return matchesSearch &&
          matchesDebt &&
          matchesSettled &&
          matchesOverdue &&
          matchesFavorite;
    }).toList();

    if (_sort == 'debt_desc') {
      list.sort((a, b) => b.remain.compareTo(a.remain));
    } else if (_sort == 'last_tx') {
      list.sort(
        (a, b) =>
            (b.lastTransactionAt ?? 0).compareTo(a.lastTransactionAt ?? 0),
      );
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QUẢN LÝ ĐỐI TÁC',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline2.fontSize),
            ),
            Text(
              _isElectronics
                  ? '${_items.length} NCC • ${_partners.length} đối tác'
                  : '${_items.length} nhà cung cấp',
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            tooltip: 'Tạo đơn bán hàng',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateSaleView()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2),
            tooltip: 'Quản lý kho',
            onPressed: () async {
              final role = await UserService.getRoleFast();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => InventoryView(role: role)),
              );
            },
          ),
        ],
        bottom: _isElectronics ? TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'NHÀ CUNG CẤP'),
            Tab(text: 'ĐỐI TÁC SỬA CHỮA'),
          ],
        ) : null,
      ),
      floatingActionButton: GradientFab(
        onPressed: () async {
          if (!_isElectronics || _tabController.index == 0) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupplierFormView()),
            );
            await _load();
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RepairPartnerFormView()),
            );
            await _loadPartners();
          }
        },
        icon: (!_isElectronics || _tabController.index == 0) ? Icons.add_business : Icons.handyman,
        label: (!_isElectronics || _tabController.index == 0) ? 'Thêm NCC' : 'Thêm đối tác',
        gradientColors: (!_isElectronics || _tabController.index == 0)
            ? const [Color(0xFF667eea), Color(0xFF764ba2)]
            : const [Color(0xFF11998e), Color(0xFF38ef7d)],
      ),
      body: _isElectronics
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildSupplierTab(),
                _buildPartnerTab(),
              ],
            )
          : _buildSupplierTab(),
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
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Không tìm thấy NCC phù hợp',
                        style: AppTextStyles.body1.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
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
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Không tìm thấy đối tác phù hợp',
                        style: AppTextStyles.body1.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _headerTile(
                'Tổng NCC',
                _totalSuppliers.toString(),
                Icons.apartment,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _headerTile(
                'Tổng công nợ',
                MoneyUtils.formatCurrency(_totalPayable),
                Icons.account_balance,
                AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _headerTile(
                'NCC còn nợ',
                _supplierOwing.toString(),
                Icons.warning,
                AppColors.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _headerTile(
                'Đã trả trong tháng',
                MoneyUtils.formatCurrency(_paidThisMonth),
                Icons.payments,
                AppColors.success,
              ),
            ),
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
          Text(
            value,
            style: AppTextStyles.headline6.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.onSurface.withOpacity(0.7),
            ),
            overflow: TextOverflow.ellipsis,
          ),
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
            FilterChip(
              label: const Text('Còn nợ'),
              selected: _filterDebt,
              onSelected: (v) => setState(() => _filterDebt = v),
            ),
            FilterChip(
              label: const Text('Đã tất toán'),
              selected: _filterSettled,
              onSelected: (v) => setState(() => _filterSettled = v),
            ),
            FilterChip(
              label: const Text('Quá hạn'),
              selected: _filterOverdue,
              onSelected: (v) => setState(() => _filterOverdue = v),
            ),
            FilterChip(
              label: const Text('Ưu tiên'),
              selected: _filterFavorite,
              onSelected: (v) => setState(() => _filterFavorite = v),
            ),
            ChoiceChip(
              label: const Text('Nợ cao → thấp'),
              selected: _sort == 'debt_desc',
              onSelected: (v) => setState(() => _sort = 'debt_desc'),
            ),
            ChoiceChip(
              label: const Text('Giao dịch gần nhất'),
              selected: _sort == 'last_tx',
              onSelected: (v) => setState(() => _sort = 'last_tx'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(_SupplierCardData d) {
    final color = _statusColor(d);
    final status = _statusText(d);
    final date = d.lastTransactionAt != null
        ? DateFormat(
            'dd/MM/yyyy',
          ).format(DateTime.fromMillisecondsSinceEpoch(d.lastTransactionAt!))
        : 'Chưa có GD';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Thông tin NCC
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.supplier.name,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: AppTextStyles.caption.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Nợ: ', style: AppTextStyles.caption),
                    Text(
                      MoneyUtils.formatCurrency(d.remain),
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'GD: $date',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Buttons compact
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút thanh toán (chỉ hiện nếu còn nợ)
              if (d.remain > 0)
                IconButton(
                  onPressed: () async => await _openPayDialog(d),
                  icon: const Icon(Icons.payments, size: 20),
                  color: AppColors.success,
                  tooltip: 'Thanh toán',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              // Menu thêm
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                padding: const EdgeInsets.all(6),
                onSelected: (value) async {
                  switch (value) {
                    case 'history':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SupplierDetailView(supplier: d.supplier),
                        ),
                      );
                      await _load();
                      break;
                    case 'edit':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupplierFormView(editing: d.supplier),
                        ),
                      );
                      await _load();
                      break;
                    case 'delete':
                      await _confirmDeleteSupplier(d);
                      break;
                    case 'pay':
                      await _openPayDialog(d);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, size: 18),
                        SizedBox(width: 8),
                        Text('Lịch sử nhập'),
                      ],
                    ),
                  ),
                  if (d.remain > 0)
                    const PopupMenuItem(
                      value: 'pay',
                      child: Row(
                        children: [
                          Icon(Icons.payments, size: 18, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Thanh toán'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Sửa thông tin'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Xóa', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPayDialog(_SupplierCardData d) async {
    if (d.remain <= 0) {
      NotificationService.showSnackBar(
        'NCC này đã tất toán.',
        color: Colors.green,
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Thanh toán công nợ cho ${d.supplier.name}',
            style: AppTextStyles.headline6,
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Còn nợ: ${MoneyUtils.formatCurrency(d.remain)}',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                CurrencyTextField(
                  controller: payCtrl,
                  label: 'Số tiền (VNĐ)',
                  hint: 'VD: 500000',
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    max: d.remain,
                    fieldName: 'Số tiền',
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
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => note = v,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú (tùy chọn)',
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
                // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                final amount = MoneyUtils.parseCurrency(payCtrl.text);
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

  Future<void> _payDebt(
    _SupplierCardData d,
    int amount,
    String methodStr,
    String note,
  ) async {
    try {
      // Find the first active supplier debt
      final debts = await _db.getAllDebts();
      final target = debts.firstWhere(
        (e) =>
            e['type'] == 'SHOP_OWES' &&
            (e['personName'] ?? '').toString().toUpperCase() ==
                d.supplier.name.toUpperCase() &&
            (e['totalAmount'] as int? ?? 0) > (e['paidAmount'] as int? ?? 0),
        orElse: () => {},
      );
      
      final debtFId = target.isNotEmpty 
          ? (target['firestoreId'] as String? ?? 'debt_supplier_${d.supplier.id}')
          : 'debt_supplier_${d.supplier.id}';
      
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
        description: 'Trả nợ NCC: ${d.supplier.name}',
        executedBy: user?.displayName ?? user?.email ?? 'unknown',
        referenceId: debtFId,
        referenceType: 'supplier_debt',
        personName: d.supplier.name,
        personPhone: d.supplier.phone,
        notes: note.isNotEmpty ? note : null,
        metadata: {
          'supplierId': d.supplier.id,
          'supplierName': d.supplier.name,
          'debtId': target.isNotEmpty ? target['id'] : null,
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
          await _load();
        }
      } else {
        if (mounted) {
          NotificationService.showSnackBar(
            result.errorMessage ?? 'Có lỗi xảy ra',
            color: Colors.red,
          );
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('Lỗi: $e', color: Colors.red);
    }
  }

  // ==================== PARTNER TAB WIDGETS ====================

  Widget _buildPartnerHeader() {
    final remain = _totalPartnerCost - _totalPartnerPaid;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _headerTile(
                'Tổng đối tác',
                _totalPartners.toString(),
                Icons.handyman,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _headerTile(
                'Còn nợ đối tác',
                MoneyUtils.formatCurrency(remain),
                Icons.account_balance,
                remain > 0 ? AppColors.error : AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _headerTile(
                'ĐT còn nợ',
                _partnerOwingCount.toString(),
                Icons.warning,
                AppColors.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _headerTile(
                'Đã thanh toán',
                MoneyUtils.formatCurrency(_totalPartnerPaid),
                Icons.payments,
                AppColors.success,
              ),
            ),
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
            FilterChip(
              label: const Text('Hoạt động'),
              selected: _filterPartnerActive,
              onSelected: (v) => setState(() => _filterPartnerActive = v),
            ),
            FilterChip(
              label: const Text('Ngừng HĐ'),
              selected: _filterPartnerInactive,
              onSelected: (v) => setState(() => _filterPartnerInactive = v),
            ),
            FilterChip(
              label: const Text('Còn nợ'),
              selected: _filterPartnerOwing,
              onSelected: (v) => setState(() => _filterPartnerOwing = v),
            ),
            ChoiceChip(
              label: const Text('Theo tên'),
              selected: _partnerSort == 'name',
              onSelected: (v) => setState(() => _partnerSort = 'name'),
            ),
            ChoiceChip(
              label: const Text('Nợ cao → thấp'),
              selected: _partnerSort == 'debt_desc',
              onSelected: (v) => setState(() => _partnerSort = 'debt_desc'),
            ),
            ChoiceChip(
              label: const Text('Nhiều đơn nhất'),
              selected: _partnerSort == 'orders_desc',
              onSelected: (v) => setState(() => _partnerSort = 'orders_desc'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPartnerCard(_PartnerCardData d) {
    final color = d.remain > 0 ? AppColors.warning : AppColors.success;
    final status = d.remain > 0 ? 'Còn nợ' : 'Tất toán';
    final activeColor = d.partner.active
        ? AppColors.success
        : AppColors.onSurface.withOpacity(0.5);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon trạng thái hoạt động
          Icon(
            d.partner.active ? Icons.check_circle : Icons.cancel,
            color: activeColor,
            size: 16,
          ),
          const SizedBox(width: 8),

          // Thông tin đối tác
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.partner.name,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: AppTextStyles.caption.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Nợ: ', style: AppTextStyles.caption),
                    Text(
                      MoneyUtils.formatCurrency(d.remain),
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Đơn: ${d.totalOrders}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Buttons compact
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút thanh toán (chỉ hiện nếu còn nợ)
              if (d.remain > 0)
                IconButton(
                  onPressed: () async => await _openPartnerPayDialog(d),
                  icon: const Icon(Icons.payments, size: 20),
                  color: AppColors.success,
                  tooltip: 'Thanh toán',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              // Menu thêm
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                padding: const EdgeInsets.all(6),
                onSelected: (value) async {
                  switch (value) {
                    case 'detail':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RepairPartnerDetailView(partner: d.partner),
                        ),
                      );
                      await _loadPartners();
                      break;
                    case 'edit':
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RepairPartnerFormView(editing: d.partner),
                        ),
                      );
                      await _loadPartners();
                      break;
                    case 'pay':
                      await _openPartnerPayDialog(d);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 18),
                        SizedBox(width: 8),
                        Text('Chi tiết / Lịch sử'),
                      ],
                    ),
                  ),
                  if (d.remain > 0)
                    const PopupMenuItem(
                      value: 'pay',
                      child: Row(
                        children: [
                          Icon(Icons.payments, size: 18, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Thanh toán'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Sửa thông tin'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPartnerPayDialog(_PartnerCardData d) async {
    if (d.remain <= 0) {
      NotificationService.showSnackBar(
        'Đối tác này đã tất toán.',
        color: Colors.green,
      );
      return;
    }
    final formKey = GlobalKey<FormState>();
    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Thanh toán cho ${d.partner.name}',
            style: AppTextStyles.headline6,
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Còn nợ: ${MoneyUtils.formatCurrency(d.remain)}',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                CurrencyTextField(
                  controller: payCtrl,
                  label: 'Số tiền (VNĐ)',
                  hint: 'VD: 500000',
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    max: d.remain,
                    fieldName: 'Số tiền',
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
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => note = v,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú (tùy chọn)',
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
                // MoneyUtils.parseCurrency đã xử lý đơn vị nghìn (VD: "500" -> 500000)
                // KHÔNG nhân thêm x1000
                final amount = MoneyUtils.parseCurrency(payCtrl.text);
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
                  summary:
                      'Thanh toán đối tác ${d.partner.name}: ${MoneyUtils.formatCurrency(amount)} ($method)',
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

                EventBus().emit('repair_partners_changed');
                if (mounted) Navigator.pop(ctx);
                NotificationService.showSnackBar(
                  'Đã ghi nhận thanh toán',
                  color: Colors.green,
                );
                await _loadPartners();
              },
              style: AppButtonStyles.successElevatedButtonStyle,
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showPasswordDialog() async {
    String password = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              'XÁC NHẬN XÓA',
              style: AppTextStyles.headline6.copyWith(color: AppColors.primary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chỉ chủ shop/quản lý được phép xóa nhà cung cấp.\nNhập mật khẩu tài khoản để xác nhận:',
              style: AppTextStyles.body2.copyWith(
                color: AppColors.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              style: AppTextStyles.body1,
              decoration: InputDecoration(
                hintText: 'Mật khẩu',
                hintStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                ),
                prefixIcon: const Icon(
                  Icons.password,
                  color: AppColors.primary,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text('HỦY', style: AppTextStyles.button),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, password),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('XÁC NHẬN', style: AppTextStyles.button),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSupplier(_SupplierCardData d) async {
    final messenger = ScaffoldMessenger.of(context);

    // Yêu cầu xác thực mật khẩu trước khi xóa
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return;

    // Xác thực mật khẩu
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Vui lòng đăng nhập lại',
            style: AppTextStyles.body2.copyWith(color: AppColors.onError),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Mật khẩu không đúng!',
            style: AppTextStyles.body2.copyWith(color: AppColors.onError),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              "XÓA NHÀ CUNG CẤP",
              style: AppTextStyles.headline6.copyWith(color: AppColors.error),
            ),
          ],
        ),
        content: Text(
          "Bạn chắc chắn muốn xóa nhà cung cấp \"${d.supplier.name}\" khỏi danh sách? Các ${_terms.productLabel.toLowerCase()} cũ vẫn giữ nguyên thông tin NCC dạng chữ.",
          style: AppTextStyles.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text("HỦY", style: AppTextStyles.button),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onError,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text("XÓA", style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (ok == true) {
      // Sử dụng SupplierService để xóa cả local và cloud (soft delete)
      final success = await _supplierService.deleteSupplier(
        d.supplier.id!,
        firestoreId: d.supplier.firestoreId,
      );

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.onSuccess,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'ĐÃ XÓA NHÀ CUNG CẤP',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSuccess,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        await _load();
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Lỗi: Không thể xóa nhà cung cấp',
              style: AppTextStyles.body2.copyWith(color: AppColors.onError),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
