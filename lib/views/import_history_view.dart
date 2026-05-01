import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/import_order_model.dart';
import '../services/import_order_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../utils/excel_export_helper.dart';
import '../utils/money_utils.dart';
import '../constants/product_constants.dart';
import 'import_order_detail_view.dart';

class ImportHistoryView extends StatefulWidget {
  const ImportHistoryView({super.key});

  @override
  State<ImportHistoryView> createState() => _ImportHistoryViewState();
}

class _ImportHistoryViewState extends State<ImportHistoryView> {
  List<ImportOrder> _orders = [];
  Map<String, List<String>> _orderItemNames = {};
  bool _isLoading = true;
  bool _canViewCostPrice = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadOrders();
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (mounted) {
      setState(() {
        _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
      });
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      // Backfill import orders from existing confirmed stock entries
      final backfilled = await ImportOrderService.backfillFromFirestore();
      if (backfilled > 0) {
        debugPrint('Backfilled $backfilled import orders');
      }

      final startMs = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      ).millisecondsSinceEpoch;
      final endMs = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final orders = await ImportOrderService.getImportOrders(
        startDate: startMs,
        endDate: endMs,
      );
      // Load product names for all orders in one query
      final itemNames = await _loadItemNames(orders);
      if (mounted) setState(() {
        _orders = orders;
        _orderItemNames = itemNames;
      });
    } catch (e) {
      debugPrint('Error loading import orders: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, List<String>>> _loadItemNames(List<ImportOrder> orders) async {
    final result = <String, List<String>>{};
    final ids = orders
        .where((o) => o.firestoreId != null && o.firestoreId!.isNotEmpty)
        .map((o) => o.firestoreId!)
        .toList();
    if (ids.isEmpty) return result;
    try {
      final db = await DBHelper().database;
      // Query in batches of 500 to avoid SQL variable limits
      for (var i = 0; i < ids.length; i += 500) {
        final batch = ids.skip(i).take(500).toList();
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT importOrderFirestoreId, productName, quantity, capacity, color, size '
          'FROM import_order_items '
          'WHERE importOrderFirestoreId IN ($placeholders) AND deleted = 0',
          batch,
        );
        for (final row in rows) {
          final orderId = row['importOrderFirestoreId'] as String;
          final name = row['productName'] as String? ?? '';
          final qty = (row['quantity'] as num?)?.toInt() ?? 1;
          final cap = row['capacity'] as String? ?? '';
          final clr = row['color'] as String? ?? '';
          final sz = row['size'] as String? ?? '';
          final cleanedName = ProductConstants.cleanProductName(name);
          final baseUpper = cleanedName.toUpperCase();

          final parts = <String>[cleanedName];
          if (cap.isNotEmpty && !baseUpper.contains(cap.toUpperCase())) {
            parts.add(cap);
          }
          if (clr.isNotEmpty && !baseUpper.contains(clr.toUpperCase())) {
            parts.add(clr);
          }
          if (sz.isNotEmpty && !baseUpper.contains(sz.toUpperCase())) {
            parts.add('Size $sz');
          }

          final display = qty > 1
              ? '${parts.join(' - ')} x$qty'
              : parts.join(' - ');
          result.putIfAbsent(orderId, () => []).add(display);
        }
      }
    } catch (e) {
      debugPrint('Error loading item names: $e');
    }
    return result;
  }

  Future<void> _exportExcel() async {
    final startMs = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
    ).millisecondsSinceEpoch;
    final endMs = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;
    try {
      await ExcelExportHelper.exportImportOrders(
        context,
        startMs: startMs,
        endMs: endMs,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất Excel: $e')),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate totals
    int totalAmount = 0;
    int totalQuantity = 0;
    int debtCount = 0;
    for (final o in _orders) {
      totalAmount += o.totalAmount;
      totalQuantity += o.totalQuantity;
      if (o.paymentStatus == 'DEBT') debtCount++;
    }

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
        title: const Text(
          'LỊCH SỬ NHẬP KHO',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _exportExcel,
            icon: const Icon(Icons.file_download),
            tooltip: 'Xuất Excel',
          ),
          IconButton(
            onPressed: _loadOrders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Summary row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                _summaryChip(
                  '${_orders.length} phiếu',
                  Icons.receipt_long,
                  AppColors.primary,
                ),
                const SizedBox(width: 8),
                _summaryChip(
                  '$totalQuantity SP',
                  Icons.inventory_2,
                  AppColors.info,
                ),
                if (_canViewCostPrice) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _summaryChip(
                      MoneyUtils.formatCurrency(totalAmount),
                      Icons.payments,
                      AppColors.success,
                    ),
                  ),
                ],
                if (debtCount > 0) ...[
                  const SizedBox(width: 8),
                  _summaryChip(
                    '$debtCount nợ',
                    Icons.warning_amber,
                    AppColors.warning,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) =>
                              _buildOrderCard(_orders[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Chưa có phiếu nhập kho',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            'Phiếu nhập sẽ được tạo tự động khi xác nhận nhập kho',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(ImportOrder order) {
    final date = order.importDate != null
        ? DateTime.fromMillisecondsSinceEpoch(order.importDate!)
        : null;
    final isDebt = order.paymentStatus == 'DEBT';
    final statusColor = isDebt ? AppColors.warning : AppColors.success;
    final paymentLabel = _paymentLabel(order.paymentMethod);
    final items = order.firestoreId != null
        ? (_orderItemNames[order.firestoreId] ?? const <String>[])
        : const <String>[];
    final previewItems = items.take(3).toList();
    final remainItems = items.length - previewItems.length;
    final debtAmount = order.totalAmount - (order.paidAmount ?? 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withAlpha(40)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImportOrderDetailView(order: order),
            ),
          );
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.orderCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(22),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              paymentLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${order.supplierName ?? 'Không rõ NCC'} • ${order.totalQuantity} SP',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (previewItems.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            ...previewItems.map(
                              (it) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  it,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                ),
                              ),
                            ),
                            if (remainItems > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+$remainItems mục',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (_canViewCostPrice)
                            Text(
                              MoneyUtils.formatCompactCurrency(order.totalAmount),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          if (_canViewCostPrice && isDebt) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Nợ ${MoneyUtils.formatCompactCurrency(debtAmount)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            date == null
                                ? '--'
                                : DateFormat('dd/MM HH:mm').format(date),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      if ((order.importedBy ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Bởi: ${order.importedBy!.trim()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _paymentLabel(String? method) {
    switch (method) {
      case 'CÔNG NỢ':
        return 'Công nợ';
      case 'CHUYỂN KHOẢN':
        return 'CK';
      case 'TIỀN MẶT':
        return 'TM';
      default:
        return method ?? '';
    }
  }
}
