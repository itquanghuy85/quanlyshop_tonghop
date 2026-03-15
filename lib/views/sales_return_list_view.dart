import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sales_return_model.dart';
import '../services/sales_return_service.dart';
import '../services/event_bus.dart';
import '../utils/money_utils.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// View to list all sales returns
class SalesReturnListView extends StatefulWidget {
  const SalesReturnListView({super.key});

  @override
  State<SalesReturnListView> createState() => _SalesReturnListViewState();
}

class _SalesReturnListViewState extends State<SalesReturnListView> {
  List<SalesReturn> _returns = [];
  List<SalesReturn> _filtered = [];
  bool _isLoading = true;
  StreamSubscription<String>? _eventSub;
  final _searchController = TextEditingController();
  String _timeFilter = 'month'; // all, today, week, month

  @override
  void initState() {
    super.initState();
    _loadReturns();
    _eventSub = EventBus().on('sales_returns_changed', (_) {
      if (mounted) _loadReturns();
    });
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReturns() async {
    setState(() => _isLoading = true);
    try {
      _returns = await SalesReturnService.getReturns();
    } catch (e) {
      debugPrint('Error loading returns: $e');
    }
    _applyFilter();
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toUpperCase();
    final now = DateTime.now();

    setState(() {
      _filtered = _returns.where((r) {
        // Search filter
        if (query.isNotEmpty) {
          final match = r.customerName.toUpperCase().contains(query) ||
              r.customerPhone.contains(query) ||
              (r.note ?? '').toUpperCase().contains(query);
          if (!match) return false;
        }
        // Time filter
        if (_timeFilter != 'all') {
          final date = DateTime.fromMillisecondsSinceEpoch(r.returnDate);
          switch (_timeFilter) {
            case 'today':
              if (date.day != now.day || date.month != now.month || date.year != now.year) return false;
              break;
            case 'week':
              if (now.difference(date).inDays > 7) return false;
              break;
            case 'month':
              if (date.month != now.month || date.year != now.year) return false;
              break;
          }
        }
        return true;
      }).toList();
    });
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
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm khách hàng, SĐT...',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            // Time filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('Tất cả', 'all'),
                    const SizedBox(width: 6),
                    _filterChip('Hôm nay', 'today'),
                    const SizedBox(width: 6),
                    _filterChip('7 ngày', 'week'),
                    const SizedBox(width: 6),
                    _filterChip('Tháng này', 'month'),
                    const SizedBox(width: 8),
                    // Summary
                    if (_filtered.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_filtered.length} phiếu • ${MoneyUtils.formatCurrency(_filtered.fold(0, (sum, r) => sum + r.totalReturnAmount))}đ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _loadReturns,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildReturnCard(_filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isActive = _timeFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 13, color: isActive ? Colors.white : Colors.grey.shade700)),
      selected: isActive,
      selectedColor: Colors.red.shade600,
      backgroundColor: Colors.grey.shade100,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) {
        setState(() => _timeFilter = value);
        _applyFilter();
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_return, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _searchController.text.isNotEmpty || _timeFilter != 'all'
                ? 'Không tìm thấy phiếu trả hàng phù hợp'
                : 'Chưa có phiếu trả hàng nào',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          if (_searchController.text.isNotEmpty || _timeFilter != 'all') ...[
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Xóa bộ lọc'),
              onPressed: () {
                _searchController.clear();
                setState(() => _timeFilter = 'all');
                _applyFilter();
              },
            ),
          ],
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(dateStr, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${MoneyUtils.formatCurrency(ret.totalReturnAmount)}đ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.red.shade700),
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
                            fontSize: 12,
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
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
              const Text('Sản phẩm trả:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
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
                          Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          if (item.productImei != null && item.productImei!.isNotEmpty)
                            Text('IMEI: ${item.productImei}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Text('x${item.quantity}', style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 12),
                    Text(
                      '${MoneyUtils.formatCurrency(item.amount)}đ',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 14),
                    ),
                  ],
                ),
              )),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TỔNG HOÀN:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
