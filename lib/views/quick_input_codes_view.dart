import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/quick_input_code_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../services/supplier_service.dart';
import '../data/db_helper.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/gradient_fab.dart';
import 'smart_stock_in_view.dart';
import 'fast_stock_in_view.dart';

enum QuickInputFilter { all, active, inactive, unsynced }

class QuickInputCodesView extends StatefulWidget {
  const QuickInputCodesView({super.key});

  @override
  State<QuickInputCodesView> createState() => _QuickInputCodesViewState();
}

class _QuickInputCodesViewState extends State<QuickInputCodesView> {
  final db = DBHelper();
  String? shopId;
  bool _isLoading = true;
  List<QuickInputCode> _codes = [];
  QuickInputFilter _currentFilter = QuickInputFilter.all;
  bool _isSyncing = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      setState(() => _isLoading = true);
      shopId = await UserService.getCurrentShopId();
      await _loadCodes();
    } catch (e) {
      debugPrint('Error initializing data: $e');
      if (mounted) {
        NotificationService.showSnackBar(
          'Lỗi khởi tạo dữ liệu: $e',
          color: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCodes() async {
    try {
      final codes = await db.getQuickInputCodes();
      if (mounted) {
        setState(() {
          _codes = shopId != null
              ? codes.where((code) => code.shopId == shopId).toList()
              : codes;
          // Sắp xếp: active trước, rồi theo thời gian tạo mới nhất
          _codes.sort((a, b) {
            if (a.isActive != b.isActive) {
              return a.isActive ? -1 : 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });
        });
      }
      debugPrint('Loaded ${_codes.length} quick input codes');
    } catch (e) {
      debugPrint('Error loading codes: $e');
      if (mounted) {
        NotificationService.showSnackBar(
          'Lỗi tải mã nhập nhanh: $e',
          color: Colors.red,
        );
      }
    }
  }

  List<QuickInputCode> get _filteredCodes {
    List<QuickInputCode> filtered = _codes;

    // Apply filter
    switch (_currentFilter) {
      case QuickInputFilter.all:
        break;
      case QuickInputFilter.active:
        filtered = filtered.where((code) => code.isActive).toList();
        break;
      case QuickInputFilter.inactive:
        filtered = filtered.where((code) => !code.isActive).toList();
        break;
      case QuickInputFilter.unsynced:
        filtered = filtered.where((code) => !code.isSynced).toList();
        break;
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((code) {
        final name = code.name.toLowerCase();
        final brand = code.brand?.toLowerCase() ?? '';
        final model = code.model?.toLowerCase() ?? '';
        final supplier = code.supplier?.toLowerCase() ?? '';
        return name.contains(query) ||
            brand.contains(query) ||
            model.contains(query) ||
            supplier.contains(query);
      }).toList();
    }

    return filtered;
  }

  int get _activeCount => _codes.where((c) => c.isActive).length;
  int get _inactiveCount => _codes.where((c) => !c.isActive).length;
  int get _unsyncedCount => _codes.where((c) => !c.isSynced).length;

  Future<void> _syncToCloud() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    try {
      await SyncService.syncQuickInputCodesToCloud();
      NotificationService.showSnackBar(
        'Đã đồng bộ thành công!',
        color: Colors.green,
      );
      await _loadCodes();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi đồng bộ: $e', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _toggleActive(QuickInputCode code) async {
    try {
      await db.toggleQuickInputCodeActive(code.id!, !code.isActive);
      await _loadCodes();
      NotificationService.showSnackBar(
        code.isActive ? 'Đã tắt mã nhập nhanh' : 'Đã bật mã nhập nhanh',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi cập nhật trạng thái: $e',
        color: Colors.red,
      );
    }
  }

  Future<void> _deleteCode(QuickInputCode code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 10),
            const Text('XÁC NHẬN XÓA'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn xóa mã nhập nhanh:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    code.type == 'DIEN_THOAI'
                        ? Icons.smartphone
                        : Icons.inventory_2,
                    color: code.type == 'DIEN_THOAI'
                        ? Colors.blue
                        : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      code.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // XÓA FIRESTORE TRƯỚC để tránh sync lại
        if (code.firestoreId != null && code.firestoreId!.isNotEmpty) {
          await FirestoreService.deleteQuickInputCode(code.firestoreId!);
        }
        // Sau đó xóa local
        await db.deleteQuickInputCode(code.id!);
        // Refresh list ngay lập tức
        if (mounted) {
          setState(() {
            _codes.removeWhere((c) => c.id == code.id);
          });
        }
        NotificationService.showSnackBar(
          'Đã xóa mã nhập nhanh',
          color: Colors.green,
        );
      } catch (e) {
        NotificationService.showSnackBar(
          'Lỗi xóa mã nhập nhanh: $e',
          color: Colors.red,
        );
      }
    }
  }

  void _showAddEditDialog([QuickInputCode? code]) {
    showDialog(
      context: context,
      builder: (ctx) => _QuickInputCodeDialog(
        code: code,
        shopId: shopId,
        onSave: (newCode) async {
          try {
            if (code == null) {
              await db.insertQuickInputCode(newCode);
              NotificationService.showSnackBar(
                'Đã thêm mã nhập nhanh',
                color: Colors.green,
              );
            } else {
              await db.updateQuickInputCode(newCode);
              NotificationService.showSnackBar(
                'Đã cập nhật mã nhập nhanh',
                color: Colors.green,
              );
            }
            await _loadCodes();
          } catch (e) {
            NotificationService.showSnackBar(
              'Lỗi lưu mã nhập nhanh: $e',
              color: Colors.red,
            );
          }
        },
      ),
    );
  }

  void _importToInventory(QuickInputCode code) {
    // Chuyển tới SmartStockInView với dữ liệu từ QuickInputCode
    // SmartStockInView không cần prefilledData, thay vào đó dùng QuickInputCode
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartStockInView(quickInputCode: code),
      ),
    ).then((_) => _loadCodes());
  }

  void _fastImportToInventory(QuickInputCode code) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FastStockInView(quickInputCode: code)),
    ).then((_) => _loadCodes());
  }

  void _copyCode(QuickInputCode code) {
    final info =
        '${code.name}\n'
        '${code.type == 'DIEN_THOAI' ? '${code.brand ?? ''} ${code.model ?? ''}'.trim() : code.description ?? ''}\n'
        'Giá nhập: ${code.cost != null ? NumberFormat('#,###').format(code.cost) : 'N/A'}đ\n'
        'Giá bán: ${code.price != null ? NumberFormat('#,###').format(code.price) : 'N/A'}đ';
    Clipboard.setData(ClipboardData(text: info));
    NotificationService.showSnackBar(
      'Đã sao chép thông tin',
      color: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'MÃ NHẬP NHANH',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Sync button với badge
          Stack(
            children: [
              IconButton(
                onPressed: _isSyncing ? null : _syncToCloud,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_sync),
                tooltip: 'Đồng bộ lên Cloud',
              ),
              if (_unsyncedCount > 0 && !_isSyncing)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unsyncedCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _loadCodes,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search bar
                Container(
                  color: Colors.blue.shade700,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm mã nhập nhanh...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.toLowerCase()),
                  ),
                ),

                // Filter chips
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: Colors.white,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          label: 'Tất cả (${_codes.length})',
                          filter: QuickInputFilter.all,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Đang bật ($_activeCount)',
                          filter: QuickInputFilter.active,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Đang tắt ($_inactiveCount)',
                          filter: QuickInputFilter.inactive,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Chưa đồng bộ ($_unsyncedCount)',
                          filter: QuickInputFilter.unsynced,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),

                // List
                Expanded(
                  child: _filteredCodes.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadCodes,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredCodes.length,
                            itemBuilder: (ctx, i) =>
                                _buildCodeCard(_filteredCodes[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: GradientFab.teal(
        onPressed: () => _showAddEditDialog(),
        icon: Icons.add,
        label: 'Thêm mã',
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required QuickInputFilter filter,
    required Color color,
  }) {
    final isSelected = _currentFilter == filter;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _currentFilter = filter),
      backgroundColor: color.withOpacity(0.1),
      selectedColor: color,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;
    Color color;

    switch (_currentFilter) {
      case QuickInputFilter.active:
        message = 'Không có mã nào đang bật';
        icon = Icons.toggle_off;
        color = Colors.green;
        break;
      case QuickInputFilter.inactive:
        message = 'Không có mã nào đang tắt';
        icon = Icons.toggle_on;
        color = Colors.grey;
        break;
      case QuickInputFilter.unsynced:
        message = 'Tất cả mã đã được đồng bộ!';
        icon = Icons.cloud_done;
        color = Colors.green;
        break;
      default:
        if (_searchQuery.isNotEmpty) {
          message = 'Không tìm thấy mã phù hợp';
          icon = Icons.search_off;
          color = Colors.grey;
        } else {
          message = 'Chưa có mã nhập nhanh nào';
          icon = Icons.qr_code_2;
          color = Colors.blue;
        }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: color.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          if (_currentFilter == QuickInputFilter.all &&
              _searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tạo mã để nhập kho nhanh hơn',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('TẠO MÃ ĐẦU TIÊN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCodeCard(QuickInputCode code) {
    final isPhone = code.type == 'DIEN_THOAI';
    final mainColor = isPhone ? Colors.blue : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: !code.isSynced
            ? Border.all(color: Colors.orange.withOpacity(0.5), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon loại sản phẩm
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mainColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPhone ? Icons.smartphone : Icons.inventory_2,
                    color: mainColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Thông tin chính
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: code.isActive ? Colors.black87 : Colors.grey,
                          decoration: code.isActive
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPhone
                            ? '${code.brand ?? ''} ${code.model ?? ''}'.trim()
                            : code.description ?? 'Phụ kiện/Linh kiện',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Status badges
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Active/Inactive badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: code.isActive
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            code.isActive
                                ? Icons.check_circle
                                : Icons.pause_circle,
                            size: 12,
                            color: code.isActive ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            code.isActive ? 'BẬT' : 'TẮT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: code.isActive ? Colors.green : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!code.isSynced) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 10,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'CHƯA SYNC',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Chi tiết (expandable)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Xem chi tiết',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      // Thông tin chi tiết
                      if (isPhone) ...[
                        _buildDetailRow('Thương hiệu', code.brand),
                        _buildDetailRow('Model', code.model),
                        _buildDetailRow('Dung lượng', code.capacity),
                        _buildDetailRow('Màu sắc', code.color),
                        _buildDetailRow('Tình trạng', code.condition),
                      ],
                      if (code.description?.isNotEmpty == true && !isPhone)
                        _buildDetailRow('Mô tả', code.description),
                      _buildDetailRow('Nhà cung cấp', code.supplier),
                      _buildDetailRow('Thanh toán', code.paymentMethod),

                      const SizedBox(height: 12),

                      // Giá
                      Row(
                        children: [
                          if (code.cost != null && code.cost! > 0)
                            Expanded(
                              child: _buildPriceBox(
                                'Giá nhập',
                                code.cost!,
                                Colors.red,
                              ),
                            ),
                          if (code.cost != null && code.price != null)
                            const SizedBox(width: 12),
                          if (code.price != null && code.price! > 0)
                            Expanded(
                              child: _buildPriceBox(
                                'Giá bán',
                                code.price!,
                                Colors.green,
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

          // Action buttons
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // Nút nhập kho
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: code.isActive
                            ? () => _fastImportToInventory(code)
                            : null,
                        icon: const Icon(Icons.bolt, size: 18),
                        label: const Text('NHẬP NHANH'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: code.isActive
                            ? () => _importToInventory(code)
                            : null,
                        icon: const Icon(Icons.inventory, size: 18),
                        label: const Text('NHẬP ĐẦY ĐỦ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide(color: Colors.blue.shade300),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Nút quản lý
                Row(
                  children: [
                    _buildActionButton(
                      icon: code.isActive ? Icons.pause : Icons.play_arrow,
                      label: code.isActive ? 'TẮT' : 'BẬT',
                      color: code.isActive ? Colors.orange : Colors.green,
                      onTap: () => _toggleActive(code),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.edit,
                      label: 'SỬA',
                      color: Colors.blue,
                      onTap: () => _showAddEditDialog(code),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.copy,
                      label: 'COPY',
                      color: Colors.purple,
                      onTap: () => _copyCode(code),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.delete,
                      label: 'XÓA',
                      color: Colors.red,
                      onTap: () => _deleteCode(code),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBox(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(height: 2),
          Text(
            '${NumberFormat('#,###').format(amount)}đ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dialog thêm/sửa mã nhập nhanh
class _QuickInputCodeDialog extends StatefulWidget {
  final QuickInputCode? code;
  final String? shopId;
  final Function(QuickInputCode) onSave;

  const _QuickInputCodeDialog({this.code, this.shopId, required this.onSave});

  @override
  State<_QuickInputCodeDialog> createState() => _QuickInputCodeDialogState();
}

class _QuickInputCodeDialogState extends State<_QuickInputCodeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _conditionCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();

  String _type = 'DIEN_THOAI';
  String? _paymentMethod;
  String? _selectedColor;
  String? _selectedSupplier;
  List<Map<String, dynamic>> _suppliers = [];

  // Danh sách gợi ý
  final List<String> _brandSuggestions = [
    'IPHONE',
    'SAMSUNG',
    'XIAOMI',
    'OPPO',
    'VIVO',
    'REALME',
    'HUAWEI',
    'NOKIA',
    'ASUS',
    'GOOGLE',
  ];
  final List<String> _capacitySuggestions = [
    '32GB',
    '64GB',
    '128GB',
    '256GB',
    '512GB',
    '1TB',
  ];
  // Đồng bộ với fast_stock_in_view.dart
  final List<String> _conditionSuggestions = ['MỚI', '99', 'KHÁC'];
  final List<String> _paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];

  // Danh sách màu sắc với color code - đồng bộ với fast_stock_in_view.dart
  final Map<String, Color> _colorOptions = {
    'ĐEN': Colors.black,
    'TRẮNG': Colors.white,
    'XANH DƯƠNG': Colors.blue,
    'XANH LÁ': Colors.green,
    'ĐỎ': Colors.red,
    'VÀNG': Colors.amber,
    'TÍM': Colors.purple,
    'HỒNG': Colors.pink,
    'CAM': Colors.orange,
    'XÁM': Colors.grey,
    'BẠC': const Color(0xFFC0C0C0),
    'VÀNG ĐỒNG': const Color(0xFFB8860B),
  };

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    if (widget.code != null) {
      final code = widget.code!;
      _nameCtrl.text = code.name;
      _type = code.type;
      _brandCtrl.text = code.brand ?? '';
      _modelCtrl.text = code.model ?? '';
      _capacityCtrl.text = code.capacity ?? '';
      _colorCtrl.text = code.color ?? '';
      _selectedColor = code.color;
      _conditionCtrl.text = code.condition ?? '';
      _costCtrl.text = code.cost?.toString() ?? '';
      _priceCtrl.text = code.price?.toString() ?? '';
      _descriptionCtrl.text = code.description ?? '';
      _supplierCtrl.text = code.supplier ?? '';
      _selectedSupplier = code.supplier;
      _paymentMethod = code.paymentMethod;
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final supplierService = SupplierService();
      final suppliers = await supplierService.getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers.map((s) => s.toMap()).toList();
          // Nếu đang edit và có supplier, kiểm tra xem có trong list không
          if (_supplierCtrl.text.isNotEmpty) {
            final exists = _suppliers.any(
              (s) => s['name'] == _supplierCtrl.text,
            );
            if (exists) {
              _selectedSupplier = _supplierCtrl.text;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _capacityCtrl.dispose();
    _colorCtrl.dispose();
    _conditionCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  void _save() {
    // Finalize currency fields trước khi xử lý
    CurrencyTextField.finalizeAll();

    if (!_formKey.currentState!.validate()) return;

    final code = QuickInputCode(
      id: widget.code?.id,
      firestoreId: widget.code?.firestoreId,
      shopId: widget.code?.shopId ?? widget.shopId,
      name: _nameCtrl.text.trim().toUpperCase(),
      type: _type,
      brand: _type == 'DIEN_THOAI'
          ? _brandCtrl.text.trim().toUpperCase()
          : null,
      model: _type == 'DIEN_THOAI'
          ? _modelCtrl.text.trim().toUpperCase()
          : null,
      capacity: _type == 'DIEN_THOAI' ? _capacityCtrl.text.trim() : null,
      color: _type == 'DIEN_THOAI' ? _colorCtrl.text.trim() : null,
      condition: _type == 'DIEN_THOAI' ? _conditionCtrl.text.trim() : null,
      cost: CurrencyTextField.parseValue(_costCtrl.text),
      price: CurrencyTextField.parseValue(_priceCtrl.text),
      description: _descriptionCtrl.text.trim(),
      supplier: _supplierCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      isActive: widget.code?.isActive ?? true,
      createdAt:
          widget.code?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      isSynced: false, // Đánh dấu chưa sync khi tạo/sửa
    );

    widget.onSave(code);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.code != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'SỬA MÃ NHẬP NHANH' : 'THÊM MÃ NHẬP NHANH',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Loại sản phẩm
                      const Text(
                        'LOẠI SẢN PHẨM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTypeChip(
                              'DIEN_THOAI',
                              'Điện thoại',
                              Icons.smartphone,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTypeChip(
                              'PHỤ KIỆN',
                              'Phụ kiện',
                              Icons.inventory_2,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Tên mã
                      ValidatedTextField(
                        controller: _nameCtrl,
                        label: 'Tên mã nhập nhanh *',
                        hint: 'VD: IPHONE 15 PRO MAX 256GB',
                        uppercase: true,
                        customValidator: (val) =>
                            val.isEmpty ?? true ? 'Vui lòng nhập tên' : null,
                      ),
                      const SizedBox(height: 16),

                      if (_type == 'DIEN_THOAI') ...[
                        // Thương hiệu với gợi ý
                        Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return _brandSuggestions;
                            }
                            return _brandSuggestions.where(
                              (brand) => brand.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                            );
                          },
                          onSelected: (selection) {
                            _brandCtrl.text = selection;
                          },
                          fieldViewBuilder:
                              (context, controller, focusNode, onSubmitted) {
                                // Sync với _brandCtrl
                                controller.text = _brandCtrl.text;
                                controller.addListener(
                                  () => _brandCtrl.text = controller.text,
                                );
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    labelText: 'Thương hiệu',
                                    hintText: 'VD: APPLE, SAMSUNG',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                        ),
                        const SizedBox(height: 16),

                        // Model
                        ValidatedTextField(
                          controller: _modelCtrl,
                          label: 'Model',
                          hint: 'VD: IPHONE 15 PRO MAX',
                          uppercase: true,
                        ),
                        const SizedBox(height: 16),

                        // Dung lượng và Màu sắc
                        Row(
                          children: [
                            Expanded(
                              child: Autocomplete<String>(
                                optionsBuilder: (textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return _capacitySuggestions;
                                  }
                                  return _capacitySuggestions.where(
                                    (cap) => cap.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase(),
                                    ),
                                  );
                                },
                                onSelected: (selection) {
                                  _capacityCtrl.text = selection;
                                },
                                fieldViewBuilder:
                                    (
                                      context,
                                      controller,
                                      focusNode,
                                      onSubmitted,
                                    ) {
                                      controller.text = _capacityCtrl.text;
                                      controller.addListener(
                                        () => _capacityCtrl.text =
                                            controller.text,
                                      );
                                      return TextFormField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        decoration: InputDecoration(
                                          labelText: 'Dung lượng',
                                          hintText: 'VD: 256GB',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Màu sắc - Color Chips Selector
                        const Text(
                          'Màu sắc',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _colorOptions.entries.map((entry) {
                            final colorName = entry.key;
                            final color = entry.value;
                            final isSelected = _selectedColor == colorName;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColor = colorName;
                                  _colorCtrl.text = colorName;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.2)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: color == Colors.white
                                              ? Colors.grey
                                              : Colors.transparent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      colorName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? color
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Tình trạng - Dropdown để tránh nhập sai
                        DropdownButtonFormField<String>(
                          initialValue: _conditionCtrl.text.isNotEmpty
                              ? _conditionCtrl.text
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Tình trạng',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Chưa chọn'),
                            ),
                            ..._conditionSuggestions.map(
                              (c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _conditionCtrl.text = val ?? '';
                            });
                          },
                        ),
                      ] else ...[
                        // Mô tả cho phụ kiện
                        ValidatedTextField(
                          controller: _descriptionCtrl,
                          label: 'Mô tả / Loại phụ kiện',
                          hint: 'VD: Ốp lưng silicon iPhone 15',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),

                        // Màu sắc cho phụ kiện - Color Chips Selector
                        const Text(
                          'Màu sắc (nếu có)',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _colorOptions.entries.map((entry) {
                            final colorName = entry.key;
                            final color = entry.value;
                            final isSelected = _selectedColor == colorName;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColor = colorName;
                                  _colorCtrl.text = colorName;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.2)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: color == Colors.white
                                              ? Colors.grey
                                              : Colors.transparent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      colorName,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? color
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Giá
                      const Text(
                        'GIÁ TIỀN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: CurrencyTextField(
                              controller: _costCtrl,
                              label: 'Giá nhập (VNĐ)',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CurrencyTextField(
                              controller: _priceCtrl,
                              label: 'Giá bán (VNĐ)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Nhà cung cấp & Thanh toán
                      const Text(
                        'THÔNG TIN KHÁC',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Nhà cung cấp - Dropdown từ danh sách NCC
                      DropdownButtonFormField<String>(
                        value: _selectedSupplier,
                        decoration: InputDecoration(
                          labelText: 'Nhà cung cấp',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _loadSuppliers,
                            tooltip: 'Tải lại danh sách NCC',
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('-- Chọn nhà cung cấp --'),
                          ),
                          ..._suppliers.map(
                            (supplier) => DropdownMenuItem<String>(
                              value: supplier['name'] as String,
                              child: Text(
                                supplier['name'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedSupplier = val;
                            _supplierCtrl.text = val ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phương thức thanh toán
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: 'Phương thức thanh toán',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Chưa chọn'),
                          ),
                          ..._paymentMethods.map(
                            (method) => DropdownMenuItem(
                              value: method,
                              child: Text(method),
                            ),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _paymentMethod = val),
                      ),

                      if (_type != 'DIEN_THOAI') ...[
                        const SizedBox(height: 16),
                        ValidatedTextField(
                          controller: _descriptionCtrl,
                          label: 'Ghi chú thêm',
                          hint: 'Thông tin bổ sung...',
                          maxLines: 2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('HỦY'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: Icon(isEditing ? Icons.save : Icons.add),
                      label: Text(isEditing ? 'LƯU THAY ĐỔI' : 'THÊM MÃ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _type == value;
    return InkWell(
      onTap: () => setState(() => _type = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
