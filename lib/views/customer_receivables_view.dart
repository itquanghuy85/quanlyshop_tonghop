import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import 'debt_view.dart';

/// Trang quản lý các khoản phải thu từ khách hàng
/// - Đơn bán công nợ (khách mua nợ)
/// - Đơn trả góp chờ tất toán từ ngân hàng
class CustomerReceivablesView extends StatefulWidget {
  const CustomerReceivablesView({super.key});

  @override
  State<CustomerReceivablesView> createState() => _CustomerReceivablesViewState();
}

class _CustomerReceivablesViewState extends State<CustomerReceivablesView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;

  List<SaleOrder> _debtSales = []; // Đơn bán công nợ
  List<SaleOrder> _installmentSales = []; // Đơn trả góp
  List<Map<String, dynamic>> _customerDebts = []; // Công nợ khách hàng từ bảng debts
  bool _isLoading = true;

  // Filter
  String _statusFilter = 'all'; // all, pending, partial, paid

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    
    // Listen to changes
    EventBus().on('sales_changed', (_) => _loadData());
    EventBus().on('debts_changed', (_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final allSales = await db.getAllSales();
      final dbRaw = await db.database;
      
      // Lấy đơn bán công nợ (paymentMethod = CÔNG NỢ)
      _debtSales = allSales.where((s) => s.paymentMethod == 'CÔNG NỢ').toList();
      
      // Lấy đơn trả góp chưa nhận tiền tất toán
      _installmentSales = allSales.where((s) => 
        s.isInstallment && s.settlementReceivedAt == null
      ).toList();
      
      // Lấy công nợ khách hàng từ bảng debts (type = CUSTOMER_OWES hoặc legacy OWE)
      final debts = await dbRaw.query(
        'debts',
        where: '(type = ? OR type = ?) AND (deleted IS NULL OR deleted = 0)',
        whereArgs: ['CUSTOMER_OWES', 'OWE'],
        orderBy: 'createdAt DESC',
      );
      _customerDebts = debts;
    } catch (e) {
      debugPrint('CustomerReceivablesView _loadData error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Tính tổng phải thu từ đơn công nợ
  int get _totalDebtSalesAmount {
    return _debtSales.fold<int>(0, (sum, s) => sum + s.totalPrice);
  }

  // Tính tổng phải thu từ trả góp (loanAmount chưa nhận)
  int get _totalInstallmentPending {
    return _installmentSales.fold<int>(0, (sum, s) => sum + s.loanAmount);
  }

  // Tính tổng công nợ khách hàng còn lại
  int get _totalCustomerDebtsRemaining {
    return _customerDebts.fold<int>(0, (sum, d) {
      final total = d['totalAmount'] as int? ?? 0;
      final paid = d['paidAmount'] as int? ?? 0;
      return sum + (total - paid).clamp(0, total);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Summary Cards
        _buildSummarySection(),
        
        // Tab Bar
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: [
              Tab(text: 'CÔNG NỢ KHÁCH (${_customerDebts.length})'),
              Tab(text: 'BÁN CÔNG NỢ (${_debtSales.length})'),
              Tab(text: 'TRẢ GÓP CHỜ TT (${_installmentSales.length})'),
            ],
          ),
        ),
        
        // Tab Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCustomerDebtsTab(),
                    _buildDebtSalesTab(),
                    _buildInstallmentTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSummarySection() {
    final totalReceivable = _totalDebtSalesAmount + _totalInstallmentPending + _totalCustomerDebtsRemaining;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Tổng phải thu
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TỔNG CẦN THU TỪ KHÁCH',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${NumberFormat('#,###').format(totalReceivable)} đ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Chi tiết 3 loại
          Row(
            children: [
              _summaryMiniCard(
                'Công nợ khách',
                _totalCustomerDebtsRemaining,
                Icons.person_outline,
                Colors.orange,
              ),
              const SizedBox(width: 8),
              _summaryMiniCard(
                'Đơn bán nợ',
                _totalDebtSalesAmount,
                Icons.receipt_long,
                Colors.red,
              ),
              const SizedBox(width: 8),
              _summaryMiniCard(
                'Chờ NH tất toán',
                _totalInstallmentPending,
                Icons.account_balance,
                Colors.blue,
              ),
            ],
          ),
          
          // Nút xem công nợ NCC
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtView()),
              );
            },
            icon: const Icon(Icons.store, color: Colors.white, size: 16),
            label: const Text(
              'XEM CÔNG NỢ NHÀ CUNG CẤP',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryMiniCard(String label, int amount, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 9),
              textAlign: TextAlign.center,
            ),
            Text(
              NumberFormat('#,###').format(amount),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tab 1: Công nợ khách hàng (từ bảng debts)
  Widget _buildCustomerDebtsTab() {
    if (_customerDebts.isEmpty) {
      return _emptyState('Không có công nợ khách hàng', Icons.check_circle_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _customerDebts.length,
      itemBuilder: (ctx, i) {
        final debt = _customerDebts[i];
        final total = debt['totalAmount'] as int? ?? 0;
        final paid = debt['paidAmount'] as int? ?? 0;
        final remaining = (total - paid).clamp(0, total);
        final personName = debt['personName'] ?? 'N/A';
        final phone = debt['phone'] ?? '';
        final note = debt['note'] ?? '';
        final createdAt = debt['createdAt'] as int? ?? 0;
        final isPaid = remaining == 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showDebtDetail(debt),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isPaid ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                        child: Icon(
                          isPaid ? Icons.check : Icons.person,
                          color: isPaid ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (phone.isNotEmpty)
                              Text(phone, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Còn nợ: ${NumberFormat('#,###').format(remaining)}đ',
                            style: TextStyle(
                              color: isPaid ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Tổng: ${NumberFormat('#,###').format(total)}đ',
                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.note, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              note,
                              style: TextStyle(color: Colors.grey[700], fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ngày tạo: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(createdAt))}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      if (!isPaid)
                        TextButton.icon(
                          onPressed: () => _showPayDebtDialog(debt),
                          icon: const Icon(Icons.payment, size: 16),
                          label: const Text('THU TIỀN', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Tab 2: Đơn bán công nợ
  Widget _buildDebtSalesTab() {
    if (_debtSales.isEmpty) {
      return _emptyState('Không có đơn bán công nợ', Icons.receipt_long_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _debtSales.length,
      itemBuilder: (ctx, i) {
        final sale = _debtSales[i];
        return _buildSaleCard(sale, isInstallment: false);
      },
    );
  }

  // Tab 3: Đơn trả góp chờ tất toán
  Widget _buildInstallmentTab() {
    if (_installmentSales.isEmpty) {
      return _emptyState('Không có đơn trả góp chờ tất toán', Icons.account_balance_outlined);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _installmentSales.length,
      itemBuilder: (ctx, i) {
        final sale = _installmentSales[i];
        return _buildSaleCard(sale, isInstallment: true);
      },
    );
  }

  Widget _buildSaleCard(SaleOrder sale, {required bool isInstallment}) {
    final daysAgo = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(sale.soldAt)).inDays;
    final isOverdue = daysAgo > 30; // Quá 30 ngày coi là quá hạn

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSaleDetail(sale),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isInstallment 
                          ? Colors.blue.withValues(alpha: 0.1) 
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isInstallment ? Icons.account_balance : Icons.receipt_long,
                      color: isInstallment ? Colors.blue : Colors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          sale.phone,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'QUÁ HẠN',
                        style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              
              // Sản phẩm
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sale.productNames,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Thông tin tài chính
              if (isInstallment) ...[
                _infoRow('Giá bán', '${NumberFormat('#,###').format(sale.totalPrice)}đ', Colors.black),
                _infoRow('Đã nhận (cọc)', '${NumberFormat('#,###').format(sale.downPayment)}đ', Colors.green),
                _infoRow('Chờ NH tất toán', '${NumberFormat('#,###').format(sale.loanAmount)}đ', Colors.blue),
                if (sale.bankName != null && sale.bankName!.isNotEmpty)
                  _infoRow('Ngân hàng', sale.bankName!, Colors.grey),
                if (sale.settlementPlannedAt != null)
                  _infoRow(
                    'Dự kiến TT',
                    DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(sale.settlementPlannedAt!)),
                    Colors.purple,
                  ),
              ] else ...[
                _infoRow('Tổng tiền nợ', '${NumberFormat('#,###').format(sale.totalPrice)}đ', Colors.red),
              ],
              
              const Divider(height: 16),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ngày bán: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt))} ($daysAgo ngày)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  if (isInstallment)
                    TextButton.icon(
                      onPressed: () => _showSettlementDialog(sale),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('XÁC NHẬN TT', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => _showCollectDebtDialog(sale),
                      icon: const Icon(Icons.payment, size: 16),
                      label: const Text('THU TIỀN', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
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

  Widget _infoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          const Text('🎉', style: TextStyle(fontSize: 32)),
        ],
      ),
    );
  }

  void _showDebtDetail(Map<String, dynamic> debt) {
    // TODO: Show debt detail dialog
    NotificationService.showSnackBar('Chi tiết công nợ: ${debt['personName']}');
  }

  void _showSaleDetail(SaleOrder sale) {
    // TODO: Navigate to sale detail
    NotificationService.showSnackBar('Chi tiết đơn hàng: ${sale.customerName}');
  }

  void _showPayDebtDialog(Map<String, dynamic> debt) {
    // Navigate to DebtView for payment
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DebtView()),
    );
  }

  void _showCollectDebtDialog(SaleOrder sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment, color: Colors.green),
            SizedBox(width: 8),
            Text('THU TIỀN NỢ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách hàng: ${sale.customerName}'),
            Text('Số điện thoại: ${sale.phone}'),
            const Divider(),
            Text(
              'Số tiền nợ: ${NumberFormat('#,###').format(sale.totalPrice)}đ',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),
            const Text(
              'Để thu tiền, vui lòng cập nhật phương thức thanh toán trong chi tiết đơn hàng.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  void _showSettlementDialog(SaleOrder sale) {
    final amountCtrl = TextEditingController(text: sale.loanAmount.toString());
    final feeCtrl = TextEditingController(text: '0');
    final codeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance, color: Colors.blue),
            SizedBox(width: 8),
            Text('XÁC NHẬN TẤT TOÁN'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Khách hàng: ${sale.customerName}'),
              Text('Ngân hàng: ${sale.bankName ?? 'N/A'}'),
              Text('Số tiền vay: ${NumberFormat('#,###').format(sale.loanAmount)}đ'),
              const Divider(),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số tiền thực nhận từ NH',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: feeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phí/Hoa hồng NH giữ lại',
                  prefixIcon: Icon(Icons.money_off),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mã hồ sơ/Biên nhận',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 2,
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
              final amount = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
              final fee = int.tryParse(feeCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
              
              // Cập nhật sale với thông tin tất toán
              final now = DateTime.now().millisecondsSinceEpoch;
              final dbRaw = await db.database;
              await dbRaw.update(
                'sales',
                {
                  'settlementReceivedAt': now,
                  'settlementAmount': amount,
                  'settlementFee': fee,
                  'settlementCode': codeCtrl.text.trim(),
                  'settlementNote': noteCtrl.text.trim(),
                  'isSynced': 0,
                },
                where: 'id = ?',
                whereArgs: [sale.id],
              );
              
              Navigator.pop(ctx);
              NotificationService.showSnackBar(
                '✅ Đã xác nhận tất toán ${NumberFormat('#,###').format(amount)}đ',
                color: Colors.green,
              );
              EventBus().emit('sales_changed');
              _loadData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
