import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';

import '../data/db_helper.dart';
import '../models/inventory_check_model.dart';
import '../utils/excel_export_helper.dart';
import '../utils/money_utils.dart';
import '../widgets/export_date_filter_dialog.dart';

/// View for browsing saved inventory check history and exporting to Excel.
class InventoryCheckHistoryView extends StatefulWidget {
  const InventoryCheckHistoryView({super.key});

  @override
  State<InventoryCheckHistoryView> createState() =>
      _InventoryCheckHistoryViewState();
}

class _InventoryCheckHistoryViewState extends State<InventoryCheckHistoryView> {
  final _db = DBHelper();
  List<InventoryCheck> _checks = [];
  bool _isLoading = true;
  String? _filterType; // null = all, 'DIEN_THOAI', 'PHỤ KIỆN'

  @override
  void initState() {
    super.initState();
    _loadChecks();
  }

  Future<void> _loadChecks() async {
    setState(() => _isLoading = true);
    try {
      final maps = await _db.getInventoryChecks(checkType: _filterType);
      final checks = maps.map((m) {
        // Parse itemsJson back into InventoryCheckItem list
        List<InventoryCheckItem> items = [];
        if (m['itemsJson'] != null && (m['itemsJson'] as String).isNotEmpty) {
          try {
            final list = jsonDecode(m['itemsJson'] as String) as List;
            items = list
                .map((e) =>
                    InventoryCheckItem.fromMap(e as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }

        return InventoryCheck(
          id: m['id'] as int?,
          firestoreId: m['firestoreId'] as String?,
          checkType: m['type'] as String? ?? '',
          checkDate: m['checkDate'] as int? ?? 0,
          checkedBy: m['createdBy'] as String? ?? '',
          items: items,
          isCompleted: (m['isCompleted'] as int? ?? 0) == 1,
          isSynced: (m['isSynced'] as int? ?? 0) == 1,
          createdAt: m['checkDate'] as int? ?? 0,
        );
      }).toList();

      setState(() {
        _checks = checks;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading inventory checks: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử kiểm kho'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          // Export all to Excel
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Xuất Excel tất cả',
            onPressed: _checks.isEmpty
                ? null
                : () => ExcelExportHelper.exportInventoryCheckList(
                      context,
                      _checks,
                    ),
          ),
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Lọc loại',
            onSelected: (value) {
              setState(() => _filterType = value);
              _loadChecks();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    Icon(Icons.all_inclusive,
                        size: 18,
                        color:
                            _filterType == null ? theme.colorScheme.primary : null),
                    const SizedBox(width: 8),
                    const Text('Tất cả'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'DIEN_THOAI',
                child: Row(
                  children: [
                    Icon(Icons.phone_android,
                        size: 18,
                        color: _filterType == 'DIEN_THOAI'
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 8),
                    const Text('Điện thoại'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'PHỤ KIỆN',
                child: Row(
                  children: [
                    Icon(Icons.cable,
                        size: 18,
                        color: _filterType == 'PHỤ KIỆN'
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 8),
                    const Text('Phụ kiện'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ResponsiveCenter(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _checks.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadChecks,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _checks.length,
                    itemBuilder: (context, index) =>
                        _buildCheckCard(_checks[index]),
                  ),
                )),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Chưa có lịch sử kiểm kho',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lưu kết quả kiểm kho để xem tại đây',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckCard(InventoryCheck check) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(check.checkDate),
    );
    final typeVi =
        check.checkType == 'DIEN_THOAI' ? 'Điện thoại' : 'Phụ kiện';
    final checked = check.items.where((i) => i.isChecked).length;
    final total = check.items.length;
    final missing = total - checked;
    final progress = total > 0 ? checked / total : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCheckDetail(check),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: check.checkType == 'DIEN_THOAI'
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          check.checkType == 'DIEN_THOAI'
                              ? Icons.phone_android
                              : Icons.cable,
                          size: 16,
                          color: check.checkType == 'DIEN_THOAI'
                              ? Colors.blue
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          typeVi,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: check.checkType == 'DIEN_THOAI'
                                ? Colors.blue
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (check.isCompleted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Hoàn thành',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pending, size: 14, color: Colors.amber),
                          SizedBox(width: 4),
                          Text(
                            'Chưa xong',
                            style: TextStyle(
                                color: Colors.amber,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  // Export single check
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    tooltip: 'Xuất Excel',
                    onPressed: () =>
                        ExcelExportHelper.exportInventoryCheck(context, check),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Date and person
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(dateStr, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(width: 16),
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      check.checkedBy,
                      style: const TextStyle(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    progress >= 1.0 ? Colors.green : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat('Tổng', total, Colors.black87),
                  _buildStat('Đã kiểm', checked, Colors.green),
                  _buildStat('Thiếu', missing, Colors.red),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: progress >= 1.0 ? Colors.green : Colors.blue,
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

  Widget _buildStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }

  void _showCheckDetail(InventoryCheck check) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _InventoryCheckDetailSheet(check: check),
    );
  }
}

/// Bottom sheet showing detail of a specific inventory check
class _InventoryCheckDetailSheet extends StatefulWidget {
  final InventoryCheck check;

  const _InventoryCheckDetailSheet({required this.check});

  @override
  State<_InventoryCheckDetailSheet> createState() =>
      _InventoryCheckDetailSheetState();
}

class _InventoryCheckDetailSheetState
    extends State<_InventoryCheckDetailSheet> {
  String _filter = 'all'; // all, checked, missing

  List<InventoryCheckItem> get _filteredItems {
    switch (_filter) {
      case 'checked':
        return widget.check.items.where((i) => i.isChecked).toList();
      case 'missing':
        return widget.check.items.where((i) => !i.isChecked).toList();
      default:
        return widget.check.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(check.checkDate),
    );
    final typeVi =
        check.checkType == 'DIEN_THOAI' ? 'Điện thoại' : 'Phụ kiện';
    final checked = check.items.where((i) => i.isChecked).length;
    final total = check.items.length;
    final missing = total - checked;
    final items = _filteredItems;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chi tiết kiểm kho - $typeVi',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined),
                      tooltip: 'Xuất Excel',
                      onPressed: () => ExcelExportHelper.exportInventoryCheck(
                          context, check),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$dateStr • ${check.checkedBy}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),

                // Summary chips
                Row(
                  children: [
                    _buildChip('Tổng: $total', Colors.blueGrey),
                    const SizedBox(width: 8),
                    _buildChip('Đã kiểm: $checked', Colors.green),
                    const SizedBox(width: 8),
                    _buildChip('Thiếu: $missing', Colors.red),
                  ],
                ),
                const SizedBox(height: 12),

                // Filter tabs
                Row(
                  children: [
                    _buildFilterTab('Tất cả', 'all', total),
                    const SizedBox(width: 8),
                    _buildFilterTab('Đã kiểm', 'checked', checked),
                    const SizedBox(width: 8),
                    _buildFilterTab('Thiếu', 'missing', missing),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items list
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Không có mục nào',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildItemTile(items[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, String value, int count) {
    final isActive = _filter == value;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary.withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(color: theme.colorScheme.primary)
              : null,
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? theme.colorScheme.primary : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile(InventoryCheckItem item, int index) {
    final checkedTime = item.checkedAt > 0
        ? DateFormat('HH:mm dd/MM').format(
            DateTime.fromMillisecondsSinceEpoch(item.checkedAt),
          )
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: item.isChecked
            ? Colors.green.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: item.isChecked
              ? Colors.green.shade200
              : Colors.red.shade200,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: item.isChecked ? Colors.green : Colors.red,
          child: Icon(
            item.isChecked ? Icons.check : Icons.close,
            size: 16,
            color: Colors.white,
          ),
        ),
        title: Text(
          item.itemName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            if (item.imei != null && item.imei!.isNotEmpty) ...[
              Text(
                'IMEI: ${item.imei}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(width: 8),
            ],
            if (item.color != null && item.color!.isNotEmpty)
              Text(
                item.color!,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            if (item.quantity > 1) ...[
              const SizedBox(width: 8),
              Text(
                'SL: ${item.quantity}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
        trailing: item.isChecked
            ? Text(
                checkedTime,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              )
            : const Text(
                'Thiếu',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
      ),
    );
  }
}
