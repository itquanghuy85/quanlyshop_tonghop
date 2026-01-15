import 'package:flutter/material.dart';
import '../models/stock_entry_model.dart';
import '../services/stock_entry_service.dart';
import '../services/notification_service.dart';
import '../services/first_time_guide_service.dart';
import 'smart_stock_in_view.dart';
import 'package:intl/intl.dart';

/// Danh sách hàng chờ xác nhận (DRAFT)
class PendingStockListView extends StatefulWidget {
  const PendingStockListView({super.key});

  @override
  State<PendingStockListView> createState() => _PendingStockListViewState();
}

class _PendingStockListViewState extends State<PendingStockListView> {
  final _service = StockEntryService();
  List<StockEntry> _entries = [];
  bool _isLoading = true;

  // Filter
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keyPendingEntries,
      title: 'Hàng Chờ Xác Nhận',
      icon: Icons.pending_actions,
      color: Colors.orange,
      steps: const [
        GuideStep(
          title: '📋 Phiếu nhập tạm',
          description: 'Danh sách các phiếu đã lưu tạm, chưa vào kho chính thức. Cần bổ sung thông tin để xác nhận.',
          icon: Icons.list_alt,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '✏️ Chỉnh sửa',
          description: 'Nhấn vào phiếu để bổ sung thông tin còn thiếu như: Giá vốn, NCC, Phương thức TT.',
          icon: Icons.edit,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '✅ Xác nhận',
          description: 'Khi đủ thông tin (màu xanh), nhấn nút ✓ để xác nhận. Hàng sẽ vào kho ngay.',
          icon: Icons.check_circle,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '⚠️ Cảnh báo quá hạn',
          description: 'Phiếu >3 ngày sẽ có cảnh báo vàng, >7 ngày sẽ đỏ. Hãy xử lý sớm!',
          icon: Icons.warning,
          iconColor: Colors.red,
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final entries = await _service.getPendingEntries();
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading pending entries: $e');
      setState(() => _isLoading = false);
    }
  }

  List<StockEntry> get _filteredEntries {
    if (_filterType == null) return _entries;
    return _entries.where((e) {
      if (e.items.isEmpty) return false;
      return e.items.first.productType == _filterType;
    }).toList();
  }

  Future<void> _confirmEntry(StockEntry entry) async {
    if (!entry.canConfirm) {
      NotificationService.showSnackBar('Chưa đủ thông tin để xác nhận', color: Colors.red);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận nhập kho?', style: TextStyle(fontSize: 14)),
        content: Text(
          'Xác nhận nhập "${entry.items.first.name}" vào kho?\n\n'
          'Sau khi xác nhận, hàng sẽ được thêm vào kho và ghi sổ kế toán.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Xác nhận', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && entry.firestoreId != null) {
      final success = await _service.confirmEntry(entry.firestoreId!);
      if (success) {
        await _loadData();
      }
    }
  }

  Future<void> _editEntry(StockEntry entry) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SmartStockInView(editEntry: entry),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _cancelEntry(StockEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu nhập?', style: TextStyle(fontSize: 14)),
        content: Text(
          'Bạn có chắc muốn hủy phiếu nhập "${entry.items.first.name}"?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy phiếu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && entry.firestoreId != null) {
      final success = await _service.cancelEntry(entry.firestoreId!);
      if (success) {
        await _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'HÀNG CHỜ XÁC NHẬN',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_filteredEntries.length}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          _buildFilterChips(),
          const Divider(height: 1),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEntries.isEmpty
                    ? _buildEmptyState()
                    : _buildList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const SmartStockInView()),
          );
          if (result == true) {
            await _loadData();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('NHẬP MỚI'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          const Text('Lọc: ', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          _buildFilterChip(null, 'Tất cả'),
          const SizedBox(width: 6),
          _buildFilterChip('DIEN_THOAI', '📱 ĐT'),
          const SizedBox(width: 6),
          _buildFilterChip('PHU_KIEN', '🎧 PK'),
          const SizedBox(width: 6),
          _buildFilterChip('LINH_KIEN', '🔧 LK'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String? type, String label) {
    final isSelected = _filterType == type;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterType = type),
      selectedColor: Colors.orange.shade200,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Không có hàng chờ xác nhận',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Nhấn "NHẬP MỚI" để tạo phiếu nhập',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _filteredEntries.length,
        itemBuilder: (ctx, index) {
          final entry = _filteredEntries[index];
          return _buildEntryCard(entry);
        },
      ),
    );
  }

  Widget _buildEntryCard(StockEntry entry) {
    final item = entry.items.isNotEmpty ? entry.items.first : null;
    if (item == null) return const SizedBox.shrink();

    final dateStr = entry.createdAt != null
        ? DateFormat('dd/MM HH:mm').format(entry.createdAt!)
        : '';

    // Determine card color based on completeness
    final bgColor = entry.canConfirm
        ? Colors.green.shade50
        : entry.daysSinceCreated > 7
            ? Colors.red.shade50
            : Colors.orange.shade50;

    final borderColor = entry.canConfirm
        ? Colors.green.shade300
        : entry.daysSinceCreated > 7
            ? Colors.red.shade300
            : Colors.orange.shade300;

    // Type icon
    String typeIcon = '📦';
    if (item.productType == 'DIEN_THOAI') {
      typeIcon = '📱';
    } else if (item.productType == 'PHU_KIEN') {
      typeIcon = '🎧';
    } else if (item.productType == 'LINH_KIEN') {
      typeIcon = '🔧';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _editEntry(entry),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Text(typeIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.productType == 'DIEN_THOAI' && item.imei != null)
                          Text(
                            'IMEI: ${item.imei}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'x${item.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Info row
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (item.cost != null)
                    _infoChip(
                      '💰 ${NumberFormat.compact(locale: 'vi').format(item.cost)}',
                      Colors.blue.shade100,
                    ),
                  if (entry.supplierName != null)
                    _infoChip(
                      '🏭 ${entry.supplierName}',
                      Colors.purple.shade100,
                    ),
                  if (entry.paymentMethod != null)
                    _infoChip(
                      '💳 ${entry.paymentMethod}',
                      Colors.teal.shade100,
                    ),
                ],
              ),

              // Missing info warning
              if (!entry.canConfirm) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Thiếu: ${entry.missingInfo.join(", ")}',
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Divider(height: 16),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel button
                  TextButton.icon(
                    onPressed: () => _cancelEntry(entry),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Hủy', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Edit button
                  OutlinedButton.icon(
                    onPressed: () => _editEntry(entry),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Sửa', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Confirm button
                  ElevatedButton.icon(
                    onPressed: entry.canConfirm ? () => _confirmEntry(entry) : null,
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Xác nhận', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: entry.canConfirm ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
