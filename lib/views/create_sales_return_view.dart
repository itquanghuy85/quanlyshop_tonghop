import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale_order_model.dart';
import '../models/sales_return_model.dart';
import '../models/product_model.dart';
import '../data/db_helper.dart';
import '../services/sales_return_service.dart';
import '../services/notification_service.dart';
import '../utils/money_utils.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_colors.dart';
import '../constants/product_constants.dart';

/// View to create a sales return from a specific sale order
class CreateSalesReturnView extends StatefulWidget {
  final SaleOrder sale;
  const CreateSalesReturnView({super.key, required this.sale});

  @override
  State<CreateSalesReturnView> createState() => _CreateSalesReturnViewState();
}

class _CreateSalesReturnViewState extends State<CreateSalesReturnView> {
  final _db = DBHelper();
  final _noteController = TextEditingController();
  late String _refundMethod;
  bool _isLoading = false;

  // Parsed items from sale
  List<_ReturnableItem> _items = [];

  bool _loadingItems = true;

  @override
  void initState() {
    super.initState();
    // Nếu đơn gốc là công nợ (chưa thanh toán), mặc định giảm nợ (không chi tiền mặt)
    _refundMethod = widget.sale.paymentMethod == 'CÔNG NỢ' ? 'CÔNG NỢ' : 'TIỀN MẶT';
    _parseItems();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Parse productNames + productImeis into returnable items.
  /// QUAN TRỌNG: phân bổ giá trên TOÀN BỘ sản phẩm gốc TRƯỚC, sau đó mới
  /// trừ số lượng đã trả. Điều này đảm bảo giá đơn vị đúng khi trả 1 phần.
  Future<void> _parseItems() async {
    final names = widget.sale.productNames.split(RegExp(r',\s*'));
    final imeis = widget.sale.productImeis.split(RegExp(r',\s*'));
    final totalPrice = widget.sale.finalPrice;
    final totalCost = widget.sale.totalCost;

    int totalQty = 0;
    final allItems = <_ReturnableItem>[];

    for (int i = 0; i < names.length; i++) {
      final nameEntry = names[i].trim();
      if (nameEntry.isEmpty) continue;

      final imei = i < imeis.length ? imeis[i].trim() : '';
      int qty = 1;
      String cleanName = nameEntry;

      final qtyMatch = RegExp(r'^(.+?)\s+[xX](\d+)').firstMatch(nameEntry);
      if (qtyMatch != null) {
        cleanName = qtyMatch.group(1)!.trim();
        qty = int.tryParse(qtyMatch.group(2)!) ?? 1;
      }

      if (imei.toUpperCase().startsWith('PKX')) {
        qty = int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? 1;
      }

      cleanName = cleanName.replaceAll(RegExp(r'\s*\(TẶNG\)\s*$', caseSensitive: false), '');
      cleanName = cleanName.replaceAll(RegExp(r'\s*\(GIẢM\s+[\d,.]+\)\s*$', caseSensitive: false), '');
      cleanName = cleanName.trim();

      allItems.add(_ReturnableItem(
        name: cleanName,
        imei: imei,
        maxQuantity: qty,
        returnQuantity: 0,
        isSelected: false,
      ));
      totalQty += qty;
    }

    // BƯỚC 1: Phân bổ giá đều theo số lượng trên TOÀN BỘ sản phẩm
    if (allItems.isNotEmpty && totalQty > 0) {
      int distributed = 0;
      int distributedCost = 0;
      for (int i = 0; i < allItems.length; i++) {
        final item = allItems[i];
        if (i == allItems.length - 1) {
          item.pricePerUnit = totalPrice > 0 ? ((totalPrice - distributed) / item.maxQuantity).round() : 0;
          item.costPerUnit = totalCost > 0 ? ((totalCost - distributedCost) / item.maxQuantity).round() : 0;
        } else {
          final linePrice = (totalPrice * item.maxQuantity / totalQty).round();
          final lineCost = (totalCost * item.maxQuantity / totalQty).round();
          item.pricePerUnit = (linePrice / item.maxQuantity).round();
          item.costPerUnit = (lineCost / item.maxQuantity).round();
          distributed += item.pricePerUnit * item.maxQuantity;
          distributedCost += item.costPerUnit * item.maxQuantity;
        }
      }
    }

    // BƯỚC 2: Nạp thông tin sản phẩm (productId, referencePrice) cho TOÀN BỘ
    for (final item in allItems) {
      Product? product;
      if (item.imei.isNotEmpty &&
          !item.imei.toUpperCase().startsWith('PKX') &&
          item.imei != 'NO_IMEI') {
        product = await _db.getProductByImei(item.imei);
      }
      product ??= await _db.getProductByName(item.name);
      if (product != null) {
        item.productId = product.id;
        item.productFirestoreId = product.firestoreId;
        if (product.price > 0) item.referencePrice = product.price;
        if (product.cost > 0) item.referenceCost = product.cost;
      }
    }

    // BƯỚC 3: Cân bằng lại giá theo referencePrice trên TOÀN BỘ sản phẩm gốc
    _rebalancePrices(allItems, totalPrice, totalCost);

    // BƯỚC 4: Trừ số lượng đã trả và xóa các sản phẩm đã trả hết
    // (giá đã được tính đúng ở bước 3, không bị ảnh hưởng khi xóa item)
    if (widget.sale.id != null && widget.sale.id! > 0) {
      final returnedMap = await _db.getReturnedQuantitiesForSale(widget.sale.id!);
      for (final item in allItems) {
        final isPhone = item.imei.isNotEmpty &&
            !item.imei.toUpperCase().startsWith('PKX') &&
            item.imei != 'NO_IMEI';
        final key = isPhone ? item.imei.toUpperCase() : item.name.toUpperCase();
        final alreadyReturned = returnedMap[key] ?? 0;
        item.maxQuantity = (item.maxQuantity - alreadyReturned).clamp(0, item.maxQuantity);
      }
      allItems.removeWhere((item) => item.maxQuantity <= 0);
    }

    if (mounted) {
      setState(() {
        _items = allItems;
        _loadingItems = false;
      });
    }
  }

  /// Cân bằng giá trên danh sách items dựa theo referencePrice (tỉ lệ theo giá vốn thực tế).
  /// Gọi trên TOÀN BỘ items TRƯỚC khi trừ số lượng đã trả.
  void _rebalancePrices(List<_ReturnableItem> items, int targetTotalPrice, int targetTotalCost) {
    if (items.isEmpty) return;

    int totalWeightPrice = 0;
    int totalWeightCost = 0;
    for (final item in items) {
      final qty = item.maxQuantity <= 0 ? 1 : item.maxQuantity;
      final refPrice = item.referencePrice > 0 ? item.referencePrice : 1;
      final refCost = item.referenceCost > 0 ? item.referenceCost : 1;
      totalWeightPrice += refPrice * qty;
      totalWeightCost += refCost * qty;
    }

    int distributedPrice = 0;
    int distributedCost = 0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = item.maxQuantity <= 0 ? 1 : item.maxQuantity;
      final refPrice = item.referencePrice > 0 ? item.referencePrice : 1;
      final refCost = item.referenceCost > 0 ? item.referenceCost : 1;

      int linePrice;
      int lineCost;
      if (i == items.length - 1) {
        linePrice = (targetTotalPrice - distributedPrice).clamp(0, targetTotalPrice);
        lineCost = (targetTotalCost - distributedCost).clamp(0, targetTotalCost);
      } else {
        linePrice = (targetTotalPrice * (refPrice * qty) / (totalWeightPrice == 0 ? 1 : totalWeightPrice)).round();
        lineCost = (targetTotalCost * (refCost * qty) / (totalWeightCost == 0 ? 1 : totalWeightCost)).round();
      }
      distributedPrice += linePrice;
      distributedCost += lineCost;

      item.pricePerUnit = (linePrice / qty).round();
      item.costPerUnit = (lineCost / qty).round();
      if (item.pricePerUnit < 0) item.pricePerUnit = 0;
      if (item.costPerUnit < 0) item.costPerUnit = 0;
    }
  }

  int get _totalRefund {
    int total = 0;
    for (final item in _items) {
      if (item.isSelected) {
        total += item.pricePerUnit * item.returnQuantity;
      }
    }
    return total;
  }

  int get _totalCost {
    int total = 0;
    for (final item in _items) {
      if (item.isSelected) {
        total += item.costPerUnit * item.returnQuantity;
      }
    }
    return total;
  }

  bool get _hasSelection => _items.any((i) => i.isSelected && i.returnQuantity > 0);

  Future<void> _processReturn() async {
    if (_isLoading) {
      return;
    }
    if (!_hasSelection) {
      NotificationService.showSnackBar('Vui lòng chọn sản phẩm cần trả', color: Colors.red);
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận trả hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách: ${widget.sale.customerName}'),
            const SizedBox(height: 8),
            ..._items.where((i) => i.isSelected && i.returnQuantity > 0).map((i) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${ProductConstants.cleanProductName(i.name)} x${i.returnQuantity} — ${MoneyUtils.formatCurrency(i.pricePerUnit * i.returnQuantity)}đ'),
              ),
            ),
            const Divider(),
            Text(
              'Hoàn lại: ${MoneyUtils.formatCurrency(_totalRefund)}đ',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            Text('Phương thức: $_refundMethod'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xác nhận trả hàng'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    // Build return items
    final returnItems = <SalesReturnItem>[];
    for (final item in _items) {
      if (!item.isSelected || item.returnQuantity <= 0) continue;
      returnItems.add(SalesReturnItem(
        productId: item.productId,
        productFirestoreId: item.productFirestoreId,
        productName: item.name,
        productImei: item.imei.isNotEmpty ? item.imei : null,
        quantity: item.returnQuantity,
        price: item.pricePerUnit,
        cost: item.costPerUnit,
        amount: item.pricePerUnit * item.returnQuantity,
      ));
    }

    final result = await SalesReturnService.processReturn(
      salesOrderId: widget.sale.id ?? 0,
      salesOrderFirestoreId: widget.sale.firestoreId,
      customerName: widget.sale.customerName,
      customerPhone: widget.sale.phone,
      refundMethod: _refundMethod,
      items: returnItems,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      NotificationService.showSnackBar(
        'Trả hàng thành công! Hoàn ${MoneyUtils.formatCurrency(_totalRefund)}đ',
        color: Colors.green,
      );
      Navigator.pop(context, true);
    } else {
      NotificationService.showSnackBar(
        'Lỗi: ${result['error']}',
        color: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trả hàng'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: ResponsiveCenter(
        child: _isLoading || _loadingItems
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
                          const SizedBox(height: 16),
                          const Text('Tất cả sản phẩm đã được trả hàng',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Đơn hàng này không còn mặt hàng nào để trả.',
                            style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Quay lại'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSaleInfo(),
                  const SizedBox(height: 16),
                  _buildItemSelection(),
                  const SizedBox(height: 16),
                  _buildRefundMethod(),
                  const SizedBox(height: 12),
                  _buildNoteField(),
                  const SizedBox(height: 16),
                  _buildSummary(),
                  const SizedBox(height: 20),
                  _buildSubmitButton(),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildSaleInfo() {
    final s = widget.sale;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(s.soldAt),
    );
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                const Text('Thông tin đơn gốc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            const Divider(height: 16),
            _infoRow('Khách hàng', s.customerName),
            _infoRow('SĐT', s.phone),
            _infoRow('Ngày bán', dateStr),
            _infoRow('Tổng đơn', '${MoneyUtils.formatCurrency(s.finalPrice)}đ'),
            _infoRow('Thanh toán', s.paymentMethod),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildItemSelection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_return, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Chọn sản phẩm trả', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            const Divider(height: 16),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Không có sản phẩm nào')),
              )
            else
              ..._items.map((item) => _buildItemTile(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(_ReturnableItem item) {
    final isPhone = item.imei.isNotEmpty &&
        !item.imei.toUpperCase().startsWith('PKX') &&
        item.imei != 'NO_IMEI';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: item.isSelected ? Colors.red.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.isSelected ? Colors.red.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: item.isSelected,
                activeColor: Colors.red,
                onChanged: (val) {
                  setState(() {
                    item.isSelected = val ?? false;
                    if (item.isSelected && item.returnQuantity == 0) {
                      item.returnQuantity = isPhone ? 1 : 1;
                    }
                    if (!item.isSelected) item.returnQuantity = 0;
                  });
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductConstants.cleanProductName(item.name),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (isPhone)
                      Text('IMEI: ${item.imei}', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    Text(
                      '${MoneyUtils.formatCurrency(item.pricePerUnit)}đ/cái • Tối đa: ${item.maxQuantity}',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.isSelected && item.maxQuantity > 1)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4),
              child: Row(
                children: [
                  const Text('Số lượng trả: ', style: TextStyle(fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    onPressed: item.returnQuantity > 1
                        ? () => setState(() => item.returnQuantity--)
                        : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Container(
                    width: 40,
                    alignment: Alignment.center,
                    child: Text(
                      '${item.returnQuantity}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    onPressed: item.returnQuantity < item.maxQuantity
                        ? () => setState(() => item.returnQuantity++)
                        : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Text('/ ${item.maxQuantity}', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                ],
              ),
            ),
          if (item.isSelected && item.returnQuantity > 0)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Hoàn: ${MoneyUtils.formatCurrency(item.pricePerUnit * item.returnQuantity)}đ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRefundMethod() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text('Phương thức hoàn tiền', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'].map((method) {
                final isActive = _refundMethod == method;
                return ChoiceChip(
                  label: Text(method, style: TextStyle(fontSize: 14, color: isActive ? Colors.white : null)),
                  selected: isActive,
                  selectedColor: Colors.blue.shade700,
                  onSelected: (val) => setState(() => _refundMethod = method),
                );
              }).toList(),
            ),
            if (_refundMethod == 'CÔNG NỢ')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ Giảm trực tiếp số nợ khách hàng, không chi tiền mặt',
                  style: TextStyle(fontSize: 14, color: Colors.orange.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteField() {
    return TextField(
      controller: _noteController,
      decoration: InputDecoration(
        labelText: 'Ghi chú / Lý do trả hàng',
        hintText: 'Lỗi kỹ thuật, không ưng ý, sai sản phẩm...',
        prefixIcon: const Icon(Icons.note_alt_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      maxLines: 2,
    );
  }

  Widget _buildSummary() {
    return Card(
      elevation: 0,
      color: _hasSelection ? Colors.red.shade50 : Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _hasSelection ? Colors.red.shade300 : Colors.grey.shade300,
          width: _hasSelection ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Sản phẩm trả:', style: TextStyle(fontSize: 16)),
                Text(
                  '${_items.where((i) => i.isSelected && i.returnQuantity > 0).length} mục',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng hoàn lại:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text(
                  '${MoneyUtils.formatCurrency(_totalRefund)}đ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _hasSelection ? Colors.red.shade700 : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: (_hasSelection && !_isLoading) ? _processReturn : null,
        icon: const Icon(Icons.assignment_return),
        label: Text(_isLoading
            ? 'Đang xử lý...'
            : _hasSelection
            ? 'Xác nhận trả hàng — ${MoneyUtils.formatCurrency(_totalRefund)}đ'
            : 'Chọn sản phẩm để trả'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Internal model for UI state
class _ReturnableItem {
  String name;
  String imei;
  int maxQuantity;
  int returnQuantity;
  bool isSelected;
  int pricePerUnit;
  int costPerUnit;
  int referencePrice;
  int referenceCost;
  int? productId;
  String? productFirestoreId;

  _ReturnableItem({
    required this.name,
    required this.imei,
    required this.maxQuantity,
    required this.returnQuantity,
    required this.isSelected,
    this.pricePerUnit = 0,
    this.costPerUnit = 0,
    this.referencePrice = 0,
    this.referenceCost = 0,
    this.productId,
    this.productFirestoreId,
  });
}
