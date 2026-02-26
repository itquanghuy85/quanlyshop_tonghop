import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../constants/product_constants.dart';
import '../models/quick_input_code_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../services/supplier_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/shop_settings_model.dart';
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
  
  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

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
      
      // Load shop settings for terminology
      final settings = await CategoryService().getShopSettings();
      if (mounted) _shopSettings = settings;
      
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
        // Filter by shopId
        var filtered = shopId != null
            ? codes.where((code) => code.shopId == shopId).toList()
            : codes;
        
        // Deduplicate by name+type (keep the one with firestoreId or most recent)
        final Map<String, QuickInputCode> uniqueMap = {};
        for (final code in filtered) {
          final key = '${code.name}_${code.type}'.toUpperCase();
          if (!uniqueMap.containsKey(key)) {
            uniqueMap[key] = code;
          } else {
            final existing = uniqueMap[key]!;
            // Keep the one that is synced, or the most recent
            if (code.firestoreId != null && existing.firestoreId == null) {
              // Delete the one without firestoreId (duplicate)
              if (existing.id != null) await db.deleteQuickInputCode(existing.id!);
              uniqueMap[key] = code;
            } else if (existing.firestoreId != null && code.firestoreId == null) {
              // Delete the duplicate without firestoreId
              if (code.id != null) await db.deleteQuickInputCode(code.id!);
            } else if (code.createdAt > existing.createdAt) {
              // Both have or both lack firestoreId — keep newer, delete older
              if (existing.id != null) await db.deleteQuickInputCode(existing.id!);
              uniqueMap[key] = code;
            } else {
              if (code.id != null) await db.deleteQuickInputCode(code.id!);
            }
          }
        }
        
        setState(() {
          _codes = uniqueMap.values.toList();
          // Sắp xếp: active trước, rồi theo thời gian tạo mới nhất
          _codes.sort((a, b) {
            if (a.isActive != b.isActive) {
              return a.isActive ? -1 : 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });
        });
      }
      debugPrint('Loaded ${_codes.length} quick input codes (deduped)');
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
      // Upload local changes
      await SyncService.syncQuickInputCodesToCloud();
      // Download latest from cloud
      await SyncService.downloadAllFromCloud();
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
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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
        borderRadius: BorderRadius.circular(12),
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
    
    // Determine card color based on sync and active status
    final bgColor = !code.isActive 
        ? Colors.grey.shade100 
        : code.isSynced 
            ? Colors.green.shade50 
            : Colors.orange.shade50;
    final borderColor = !code.isActive 
        ? Colors.grey.shade400 
        : code.isSynced 
            ? Colors.green.shade300 
            : Colors.orange.shade300;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: bgColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: () => _showAddEditDialog(code),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: icon + name + status
              Row(
                children: [
                  Text(
                    isPhone ? '📱' : '🎧',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          code.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: code.isActive ? Colors.black87 : Colors.grey,
                            decoration: code.isActive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((isPhone && (code.brand != null || code.model != null)) ||
                            (!isPhone && code.description != null))
                          Text(
                            isPhone
                                ? '${code.brand ?? ''} ${code.model ?? ''}'.trim()
                                : code.description ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Status + sync badge
                  if (!code.isSynced)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.cloud_off, 
                        size: 14, color: Colors.orange.shade600),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: code.isActive ? mainColor : Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      code.isActive ? 'BẬT' : 'TẮT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Compact info + action row
              const SizedBox(height: 6),
              Row(
                children: [
                  // Price chips
                  if (code.cost != null && code.cost! > 0)
                    _quickCodeInfoChip(
                      'Vốn: ${NumberFormat.compact(locale: 'vi').format(code.cost)}đ',
                      Colors.red.shade100,
                    ),
                  if (code.cost != null && code.cost! > 0)
                    const SizedBox(width: 4),
                  if (code.price != null && code.price! > 0)
                    _quickCodeInfoChip(
                      'Bán: ${NumberFormat.compact(locale: 'vi').format(code.price)}đ',
                      Colors.green.shade100,
                    ),
                  const Spacer(),
                  // Compact action buttons
                  SizedBox(
                    height: 26,
                    child: ElevatedButton(
                      onPressed: code.isActive
                          ? () => _fastImportToInventory(code)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 12),
                          SizedBox(width: 2),
                          Text('Nhanh', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 26,
                    child: OutlinedButton(
                      onPressed: code.isActive
                          ? () => _importToInventory(code)
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Đầy đủ', style: TextStyle(fontSize: 10)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 26,
                    width: 26,
                    child: IconButton(
                      onPressed: () => _deleteCode(code),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.red.shade400,
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
  
  Widget _quickCodeInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10)),
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
  final _labelInfoCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();

  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);
  bool get _isFashion => _shopSettings?.businessType == 'fashion';
  bool get _isElectronics => _shopSettings?.businessType == 'electronics' || _shopSettings == null;

  String _type = 'DIEN_THOAI';
  String? _paymentMethod;
  String? _selectedColor;
  String? _selectedSupplier;
  List<Map<String, dynamic>> _suppliers = [];

  // Danh sách gợi ý - sử dụng constants để đồng bộ
  List<String> get _brandSuggestions => ProductConstants.brands;
  List<String> get _capacitySuggestions => ProductConstants.capacities;
  // Đồng bộ với fast_stock_in_view.dart
  List<String> get _conditionSuggestions => ProductConstants.conditionsShort;
  List<String> get _paymentMethods => ProductConstants.paymentMethods;

  // Danh sách màu sắc với color code - đồng bộ với constants
  final Map<String, Color> _colorOptions = {
    'ĐEN': Colors.black,
    'TRẮNG': Colors.white,
    'XANH': Colors.blue,
    'ĐỎ': Colors.red,
    'VÀNG': Colors.amber,
    'TÍM': Colors.blue,
    'HỒNG': Colors.pink,
    'BẠC': const Color(0xFFC0C0C0),
    'XANH LÁ': Colors.green,
    'CAM': Colors.orange,
    'XANH DƯƠNG': Colors.blue,
    'GOLD': const Color(0xFFFFD700),
    'TITAN TỰ NHIÊN': const Color(0xFF8B7355),
    'TITAN ĐEN': const Color(0xFF2C2C2C),
    'TITAN TRẮNG': const Color(0xFFF5F5F5),
    'TITAN XÁM': const Color(0xFF808080),
    'KHÁC': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _loadSuppliers();
    if (widget.code != null) {
      final code = widget.code!;
      _nameCtrl.text = code.name;
      _type = code.type;
      _brandCtrl.text = code.brand ?? '';
      _modelCtrl.text = code.model ?? '';
      _capacityCtrl.text = code.capacity ?? '';
      _colorCtrl.text = code.color ?? '';
      // Map màu sắc về giá trị chuẩn
      _selectedColor = code.color != null && code.color!.isNotEmpty
          ? (_colorOptions.keys.contains(code.color!.toUpperCase()) 
              ? code.color!.toUpperCase() 
              : ProductConstants.mapColor(code.color))
          : null;
      // Map condition về giá trị chuẩn trong conditionsShort
      if (code.condition != null && code.condition!.isNotEmpty) {
        final mappedCondition = ProductConstants.mapConditionShort(code.condition!);
        _conditionCtrl.text = _conditionSuggestions.contains(mappedCondition) 
            ? mappedCondition 
            : '';
      }
      _costCtrl.text = code.cost?.toString() ?? '';
      _priceCtrl.text = code.price?.toString() ?? '';
      _descriptionCtrl.text = code.description ?? '';
      _labelInfoCtrl.text = code.labelInfo ?? '';
      _supplierCtrl.text = code.supplier ?? '';
      _selectedSupplier = code.supplier;
      // Map payment method về giá trị chuẩn
      _paymentMethod = code.paymentMethod != null && _paymentMethods.contains(code.paymentMethod)
          ? code.paymentMethod
          : null;
    }
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
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
    _labelInfoCtrl.dispose();
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
      labelInfo: _labelInfoCtrl.text.trim(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              padding: const EdgeInsets.all(12),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEditing ? 'SỬA MÃ NHẬP NHANH' : 'THÊM MÃ NHẬP NHANH',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
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
                              _terms.category1,
                              Icons.smartphone,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTypeChip(
                              'PHỤ KIỆN',
                              _terms.category2,
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

                        // Dung lượng/Size và Màu sắc
                        Row(
                          children: [
                            // Dung lượng/Size - chỉ hiện cho electronics hoặc fashion
                            if (_isElectronics || _isFashion)
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
                                            labelText: _isFashion ? 'Size' : 'Dung lượng',
                                            hintText: _isFashion ? 'VD: L, XL, 40' : 'VD: 256GB',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(
                                                12,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                ),
                              )
                            else
                              const Expanded(child: SizedBox()),
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
                                  borderRadius: BorderRadius.circular(12),
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
                          value: _conditionCtrl.text.isNotEmpty &&
                                  _conditionSuggestions.contains(_conditionCtrl.text)
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
                        value: _selectedSupplier != null &&
                                _suppliers.any((s) => s['name'] == _selectedSupplier)
                            ? _selectedSupplier
                            : null,
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
                        value: _paymentMethod != null &&
                                _paymentMethods.contains(_paymentMethod)
                            ? _paymentMethod
                            : null,
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
              padding: const EdgeInsets.all(12),
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
