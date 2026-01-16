import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/repair_partner_model.dart';
import '../models/partner_repair_history_model.dart';
import '../services/repair_partner_service.dart';
import '../services/repair_partner_payment_service.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../core/utils/money_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/gradient_fab.dart';
import 'repair_partner_form_view.dart';

class RepairPartnerDetailView extends StatefulWidget {
  final RepairPartner partner;
  const RepairPartnerDetailView({super.key, required this.partner});

  @override
  State<RepairPartnerDetailView> createState() =>
      _RepairPartnerDetailViewState();
}

class _RepairPartnerDetailViewState extends State<RepairPartnerDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _partnerService = RepairPartnerService();
  final _paymentService = RepairPartnerPaymentService();

  List<PartnerRepairHistory> _histories = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
    EventBus().stream.where((e) => e == 'repair_partners_changed').listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final histories = await _partnerService.getPartnerRepairHistory(
        partnerId: widget.partner.id,
      );
      final payments = await _paymentService.getPaymentsByPartnerId(
        widget.partner.id!,
      );
      final stats = await _partnerService.getPartnerRepairStats(
        widget.partner.id!,
      );
      setState(() {
        _histories = histories;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.partner.name),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RepairPartnerFormView(editing: widget.partner),
                ),
              );
              if (mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.edit),
            tooltip: 'Sửa',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.onPrimary,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: AppColors.onPrimary.withOpacity(0.7),
          tabs: const [
            Tab(text: 'ĐƠN ĐÃ GỬI'),
            Tab(text: 'THANH TOÁN'),
            Tab(text: 'THỐNG KÊ'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRepairHistoryTab(),
                _buildPaymentsTab(),
                _buildStatsTab(),
              ],
            ),
      floatingActionButton: GradientFab.success(
        onPressed: _showPaymentDialog,
        icon: Icons.payments,
        label: 'Thanh toán',
      ),
    );
  }

  Widget _buildRepairHistoryTab() {
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
              'Chưa có đơn sửa chữa nào',
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _histories.length,
      itemBuilder: (_, i) => _buildHistoryCard(_histories[i]),
    );
  }

  Widget _buildHistoryCard(PartnerRepairHistory h) {
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(h.sentAt));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6)],
      ),
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
              Text(
                MoneyUtils.formatVND(h.partnerCost),
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: AppColors.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Text(h.customerName, style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.build,
                size: 14,
                color: AppColors.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  h.issue,
                  style: AppTextStyles.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (h.repairContent != null && h.repairContent!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.note,
                  size: 14,
                  color: AppColors.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    h.repairContent!,
                    style: AppTextStyles.caption.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            date,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payments,
              size: 64,
              color: AppColors.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có thanh toán nào',
              style: AppTextStyles.body1.copyWith(
                color: AppColors.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _payments.length,
      itemBuilder: (_, i) => _buildPaymentCard(_payments[i]),
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> p) {
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int? ?? 0));
    final amount = p['amount'] as int? ?? 0;
    final method = p['paymentMethod'] as String? ?? 'TIỀN MẶT';
    final note = p['note'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle, color: AppColors.success, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyUtils.formatVND(amount),
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$method • $date', style: AppTextStyles.caption),
                if (note.isNotEmpty)
                  Text(
                    note,
                    style: AppTextStyles.caption.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    final totalCost = _stats?['totalCost'] as int? ?? 0;
    final totalPaid = _stats?['totalPaid'] as int? ?? 0;
    final remain = totalCost - totalPaid;
    final totalOrders = _stats?['totalOrders'] as int? ?? _histories.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatTile(
          'Tổng đơn gửi sửa',
          totalOrders.toString(),
          Icons.assignment,
          AppColors.primary,
        ),
        const SizedBox(height: 12),
        _buildStatTile(
          'Tổng phí sửa chữa',
          MoneyUtils.formatVND(totalCost),
          Icons.receipt_long,
          AppColors.warning,
        ),
        const SizedBox(height: 12),
        _buildStatTile(
          'Đã thanh toán',
          MoneyUtils.formatVND(totalPaid),
          Icons.check_circle,
          AppColors.success,
        ),
        const SizedBox(height: 12),
        _buildStatTile(
          'Còn nợ',
          MoneyUtils.formatVND(remain),
          Icons.account_balance,
          remain > 0 ? AppColors.error : AppColors.success,
        ),
        const SizedBox(height: 24),
        _buildInfoSection(),
      ],
    );
  }

  Widget _buildStatTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.headline6.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    final createdDate = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(widget.partner.createdAt));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông tin đối tác',
            style: AppTextStyles.headline6.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(height: 20),
          _infoRow(Icons.business, 'Tên', widget.partner.name),
          if (widget.partner.phone != null)
            _infoRow(Icons.phone, 'SĐT', widget.partner.phone!),
          if (widget.partner.note != null)
            _infoRow(Icons.note, 'Ghi chú', widget.partner.note!),
          _infoRow(Icons.calendar_today, 'Ngày tạo', createdDate),
          _infoRow(
            Icons.toggle_on,
            'Trạng thái',
            widget.partner.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.onSurface.withOpacity(0.6)),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value, style: AppTextStyles.body2)),
        ],
      ),
    );
  }

  Future<void> _showPaymentDialog() async {
    final totalCost = _stats?['totalCost'] as int? ?? 0;
    final totalPaid = _stats?['totalPaid'] as int? ?? 0;
    final remain = totalCost - totalPaid;

    if (remain <= 0) {
      NotificationService.showSnackBar(
        'Đối tác này không còn công nợ',
        color: Colors.green,
      );
      return;
    }

    final payCtrl = TextEditingController();
    String method = 'TIỀN MẶT';
    String note = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Thanh toán cho ${widget.partner.name}',
            style: AppTextStyles.headline6,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Còn nợ: ${MoneyUtils.formatVND(remain)}',
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số tiền (nghìn đồng)',
                  hintText: 'VD: 500 = ${MoneyUtils.formatVND(500000)}',
                ),
              ),
              const SizedBox(height: 12),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () async {
                final inputVal = int.tryParse(
                  payCtrl.text.replaceAll('.', '').replaceAll(',', ''),
                ) ?? 0;
                final amount = inputVal * 1000; // Nhân 1000 để chuyển sang VNĐ
                if (amount <= 0 || amount > remain) {
                  NotificationService.showSnackBar(
                    'Số tiền không hợp lệ (tối đa ${MoneyUtils.formatVND(remain)})',
                    color: Colors.red,
                  );
                  return;
                }
                await _paymentService.addPayment(
                  partnerId: widget.partner.id!,
                  amount: amount,
                  paymentMethod: method,
                  note: note,
                );
                
                // Ghi nhật ký hệ thống
                await AuditService.logAction(
                  action: 'PARTNER_PAYMENT',
                  entityType: 'repair_partner',
                  entityId: widget.partner.id!.toString(),
                  summary: 'Thanh toán đối tác ${widget.partner.name}: ${MoneyUtils.formatVND(amount)} ($method)',
                  payload: {
                    'partnerId': widget.partner.id,
                    'partnerName': widget.partner.name,
                    'amount': amount,
                    'paymentMethod': method,
                    'note': note,
                    'remainBefore': remain,
                    'remainAfter': remain - amount,
                  },
                );
                
                NotificationService.showSnackBar(
                  'Đã ghi nhận thanh toán',
                  color: Colors.green,
                );
                EventBus().emit('repair_partners_changed');
                await _load();
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
