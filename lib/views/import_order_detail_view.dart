import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/import_order_model.dart';
import '../services/import_order_service.dart';
import '../theme/app_colors.dart';
import '../utils/money_utils.dart';

class ImportOrderDetailView extends StatefulWidget {
  final ImportOrder order;
  const ImportOrderDetailView({super.key, required this.order});

  @override
  State<ImportOrderDetailView> createState() => _ImportOrderDetailViewState();
}

class _ImportOrderDetailViewState extends State<ImportOrderDetailView> {
  List<ImportOrderItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (widget.order.firestoreId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final items = await ImportOrderService.getImportOrderItems(
        widget.order.firestoreId!,
      );
      if (mounted) setState(() => _items = items);
    } catch (e) {
      debugPrint('Error loading import order items: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final date = order.importDate != null
        ? DateTime.fromMillisecondsSinceEpoch(order.importDate!)
        : null;
    final isDebt = order.paymentStatus == 'DEBT';

    return Scaffold(
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
          order.orderCode,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order info card
                  _buildInfoCard(order, date, isDebt),
                  const SizedBox(height: 16),
                  // Items header
                  Row(
                    children: [
                      const Icon(
                        Icons.list_alt,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Chi tiết sản phẩm (${_items.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Items list
                  if (_items.isEmpty)
                    _buildEmptyItems()
                  else
                    ..._items.asMap().entries.map(
                      (entry) => _buildItemCard(entry.key + 1, entry.value),
                    ),
                  const SizedBox(height: 16),
                  // Total row
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TỔNG CỘNG',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          MoneyUtils.formatCurrency(order.totalAmount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard(ImportOrder order, DateTime? date, bool isDebt) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDebt
                    ? [
                        AppColors.warning.withAlpha(20),
                        AppColors.warning.withAlpha(8),
                      ]
                    : [
                        AppColors.success.withAlpha(20),
                        AppColors.success.withAlpha(8),
                      ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDebt
                        ? AppColors.warning.withAlpha(30)
                        : AppColors.success.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDebt ? Icons.warning_amber : Icons.check_circle,
                    color: isDebt ? AppColors.warning : AppColors.success,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDebt ? 'CÔNG NỢ' : 'ĐÃ THANH TOÁN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDebt
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                      ),
                      if (date != null)
                        Text(
                          DateFormat('HH:mm - dd/MM/yyyy').format(date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${order.totalQuantity} SP',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // Info rows
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _infoRow(Icons.store, 'NCC', order.supplierName ?? 'Không rõ'),
                const SizedBox(height: 8),
                _infoRow(
                  Icons.payments,
                  'Thanh toán',
                  _paymentMethodLabel(order.paymentMethod),
                ),
                if (order.importedBy != null && order.importedBy!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoRow(Icons.person, 'Người nhập', order.importedBy!),
                ],
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoRow(Icons.notes, 'Ghi chú', order.notes!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyItems() {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Text(
        'Không có dữ liệu chi tiết',
        style: TextStyle(color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildItemCard(int index, ImportOrderItem item) {
    final typeColor = _typeColor(item.productType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Index
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: typeColor.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: typeColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Details row
                  Row(
                    children: [
                      if (item.productBrand != null &&
                          item.productBrand!.isNotEmpty)
                        _detailChip(item.productBrand!),
                      if (item.imei != null && item.imei!.isNotEmpty)
                        _detailChip('IMEI: ${item.imei}'),
                      if (item.color != null && item.color!.isNotEmpty)
                        _detailChip(item.color!),
                      if (item.size != null && item.size!.isNotEmpty)
                        _detailChip(item.size!),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Price row
                  Row(
                    children: [
                      Text(
                        'SL: ${item.quantity}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '×',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        MoneyUtils.formatCurrency(item.costPrice),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        MoneyUtils.formatCurrency(item.totalAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'DIEN_THOAI':
        return Colors.blue;
      case 'PHU_KIEN':
        return Colors.teal;
      case 'LINH_KIEN':
        return Colors.orange;
      case 'QUAN_AO':
        return Colors.purple;
      case 'GIAY_DEP':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'CÔNG NỢ':
        return 'Công nợ';
      case 'CHUYỂN KHOẢN':
        return 'Chuyển khoản';
      case 'TIỀN MẶT':
        return 'Tiền mặt';
      default:
        return method ?? 'Không rõ';
    }
  }
}
