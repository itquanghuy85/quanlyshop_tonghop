import 'package:flutter/material.dart';
import '../models/stock_entry_model.dart';
import '../services/stock_entry_service.dart';
import '../services/notification_service.dart';
import '../services/first_time_guide_service.dart';
import '../widgets/gradient_fab.dart';
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
          description:
              'Danh sách các phiếu đã lưu tạm, chưa vào kho chính thức. Cần bổ sung thông tin để xác nhận.',
          icon: Icons.list_alt,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '✏️ Chỉnh sửa',
          description:
              'Nhấn vào phiếu để bổ sung thông tin còn thiếu như: Giá vốn, NCC, Phương thức TT.',
          icon: Icons.edit,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '✅ Xác nhận',
          description:
              'Khi đủ thông tin (màu xanh), nhấn nút ✓ để xác nhận. Hàng sẽ vào kho ngay.',
          icon: Icons.check_circle,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '⚠️ Cảnh báo quá hạn',
          description:
              'Phiếu >3 ngày sẽ có cảnh báo vàng, >7 ngày sẽ đỏ. Hãy xử lý sớm!',
          icon: Icons.warning,
          iconColor: Colors.red,
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('📋 PendingStockListView._loadData: START');
      final entries = await _service.getPendingEntries();
      debugPrint(
        '📋 PendingStockListView._loadData: got ${entries.length} entries',
      );
      for (final e in entries) {
        debugPrint(
          '   - entry ${e.firestoreId}: items=${e.items.length}, itemName=${e.items.isNotEmpty ? e.items.first.name : "N/A"}',
        );
      }
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
      debugPrint(
        '📋 PendingStockListView._loadData: DONE, _entries.length=${_entries.length}',
      );
    } catch (e) {
      debugPrint('❌ Error loading pending entries: $e');
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
      NotificationService.showSnackBar(
        'Chưa đủ thông tin để xác nhận',
        color: Colors.red,
      );
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
            child: const Text(
              'Xác nhận',
              style: TextStyle(color: Colors.white),
            ),
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
      MaterialPageRoute(builder: (_) => SmartStockInView(editEntry: entry)),
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
            child: const Text(
              'Hủy phiếu',
              style: TextStyle(color: Colors.white),
            ),
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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_filteredEntries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
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
      floatingActionButton: GradientFab.info(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const SmartStockInView()),
          );
          if (result == true) {
            await _loadData();
          }
        },
        icon: Icons.add_circle_outline,
        label: 'Nhập mới',
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
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
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
    
    // Hiển thị card lỗi nếu không có items
    if (item == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.red.shade300),
        ),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text(
            'Phiếu nhập bị lỗi',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          subtitle: Text(
            'ID: ${entry.firestoreId ?? "N/A"}\nKhông có sản phẩm trong phiếu',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              if (entry.firestoreId != null) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Xóa phiếu lỗi?', style: TextStyle(fontSize: 14)),
                    content: const Text('Phiếu này không có sản phẩm và cần được xóa.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Xóa', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _service.cancelEntry(entry.firestoreId!);
                  await _loadData();
                }
              }
            },
          ),
        ),
      );
    }

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
                        // Product details line
                        if (item.productType == 'DIEN_THOAI') ...[
                          if (item.brand != null ||
                              item.model != null ||
                              item.capacity != null)
                            Text(
                              [item.brand, item.model, item.capacity]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' • '),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (item.imei != null && item.imei!.isNotEmpty)
                            Text(
                              'IMEI: ${item.imei}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ] else if (item.sku != null && item.sku!.isNotEmpty)
                          Text(
                            'SKU: ${item.sku}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'x${item.quantity}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
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

              const SizedBox(height: 6),

              // Info chips row
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (item.cost != null)
                    _infoChip(
                      'Vốn: ${NumberFormat.compact(locale: 'vi').format(item.cost)}đ',
                      Colors.orange.shade100,
                    ),
                  if (item.price != null)
                    _infoChip(
                      'Bán: ${NumberFormat.compact(locale: 'vi').format(item.price)}đ',
                      Colors.green.shade100,
                    ),
                  if (item.color != null && item.color!.isNotEmpty)
                    _infoChip('🎨 ${item.color}', Colors.pink.shade50),
                  if (item.condition != null && item.condition!.isNotEmpty)
                    _infoChip('📦 ${item.condition}', Colors.cyan.shade50),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: Colors.orange,
                      ),
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

              const Divider(height: 8),

              // Action buttons - compact icons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cancel button
                  SizedBox(
                    height: 32,
                    child: TextButton(
                      onPressed: () => _cancelEntry(entry),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 14),
                          SizedBox(width: 4),
                          Text('Hủy', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Edit button
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => _editEntry(entry),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 14),
                          SizedBox(width: 4),
                          Text('Sửa', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Confirm button
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: entry.canConfirm
                          ? () => _confirmEntry(entry)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: entry.canConfirm
                            ? Colors.green
                            : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 14),
                          SizedBox(width: 4),
                          Text('OK', style: TextStyle(fontSize: 11)),
                        ],
                      ),
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
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
