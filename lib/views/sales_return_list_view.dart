import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sales_return_model.dart';
import '../services/sales_return_service.dart';
import '../utils/money_utils.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_colors.dart';

/// View to list all sales returns
class SalesReturnListView extends StatefulWidget {
  const SalesReturnListView({super.key});

  @override
  State<SalesReturnListView> createState() => _SalesReturnListViewState();
}

class _SalesReturnListViewState extends State<SalesReturnListView> {
  List<SalesReturn> _returns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReturns();
  }

  Future<void> _loadReturns() async {
    setState(() => _isLoading = true);
    try {
      _returns = await SalesReturnService.getReturns();
    } catch (e) {
      debugPrint('Error loading returns: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách trả hàng'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: ResponsiveCenter(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _returns.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: _loadReturns,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _returns.length,
                      itemBuilder: (_, i) => _buildReturnCard(_returns[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_return, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Chưa có phiếu trả hàng nào', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildReturnCard(SalesReturn ret) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(ret.returnDate),
    );
    final isDebt = ret.refundMethod == 'CÔNG NỢ';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade100),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReturnDetail(ret),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.assignment_return, size: 18, color: Colors.red.shade700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ret.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${MoneyUtils.formatCurrency(ret.totalReturnAmount)}đ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade700),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDebt ? Colors.orange.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ret.refundMethod,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDebt ? Colors.orange.shade800 : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (ret.note != null && ret.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.note, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ret.note!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (ret.createdBy != null) ...[
                const SizedBox(height: 4),
                Text(
                  'NV: ${ret.createdBy}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReturnDetail(SalesReturn ret) async {
    final items = await SalesReturnService.getReturnItems(ret.id!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(ret.returnDate),
        );
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.assignment_return, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text('Chi tiết phiếu trả hàng',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow('Khách hàng', ret.customerName),
              _detailRow('SĐT', ret.customerPhone),
              _detailRow('Ngày trả', dateStr),
              _detailRow('Phương thức hoàn', ret.refundMethod),
              _detailRow('NV xử lý', ret.createdBy ?? '-'),
              _detailRow('Trạng thái', ret.status == 'APPROVED' ? '✅ Đã duyệt' : ret.status),
              if (ret.note != null && ret.note!.isNotEmpty)
                _detailRow('Ghi chú', ret.note!),
              const Divider(height: 24),
              const Text('Sản phẩm trả:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              ...items.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          if (item.productImei != null && item.productImei!.isNotEmpty)
                            Text('IMEI: ${item.productImei}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Text('x${item.quantity}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    Text(
                      '${MoneyUtils.formatCurrency(item.amount)}đ',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 13),
                    ),
                  ],
                ),
              )),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TỔNG HOÀN:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    '${MoneyUtils.formatCurrency(ret.totalReturnAmount)}đ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
