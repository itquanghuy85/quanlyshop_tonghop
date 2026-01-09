import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/quick_input_code_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../data/db_helper.dart';
import 'stock_in_view.dart';

enum QuickInputFilter { all, unsynced }

class QuickInputManagementView extends StatefulWidget {
  const QuickInputManagementView({super.key});

  @override
  State<QuickInputManagementView> createState() => _QuickInputManagementViewState();
}

class _QuickInputManagementViewState extends State<QuickInputManagementView> {

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
        NotificationService.showSnackBar('Lỗi khởi tạo dữ liệu: $e', color: Colors.red);
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
        });
      }
      debugPrint('Loaded ${_codes.length} quick input codes');
    } catch (e) {
      debugPrint('Error loading codes: $e');
      if (mounted) {
        NotificationService.showSnackBar('Lỗi tải mã nhập nhanh: $e', color: Colors.red);
      }
    }
  }

  List<QuickInputCode> get _filteredCodes {
    List<QuickInputCode> filtered = _codes;

    switch (_currentFilter) {
      case QuickInputFilter.all:
        break;
      case QuickInputFilter.unsynced:
        filtered = filtered.where((code) => !code.isSynced).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((code) {
        final codeStr = code.code?.toLowerCase() ?? '';
        final name = code.name.toLowerCase();
        final type = code.type.toLowerCase();
        return codeStr.contains(query) ||
               name.contains(query) ||
               type.contains(query);
      }).toList();
    }

    return filtered;
  }

  Future<void> _syncToCloud() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    try {
      await SyncService.syncQuickInputCodesToCloud();
      await SyncService.downloadAllFromCloud(); // Download latest data
      NotificationService.showSnackBar('Đã đồng bộ thành công mã nhập nhanh!', color: Colors.green);
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
      NotificationService.showSnackBar('Lỗi cập nhật trạng thái: $e', color: Colors.red);
    }
  }

  Future<void> _deleteCode(QuickInputCode code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa mã nhập nhanh "${code.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Queue delete sync via SyncOrchestrator
        if (code.firestoreId != null && code.firestoreId!.isNotEmpty) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.quickInputCode,
            entityId: code.id!,
            firestoreId: code.firestoreId,
            operation: SyncOperation.delete,
            data: {'firestoreId': code.firestoreId},
          );
        }
        // Sau đó xóa local
        await db.deleteQuickInputCode(code.id!);
        await _loadCodes();
        NotificationService.showSnackBar('Đã xóa mã nhập nhanh', color: Colors.green);
      } catch (e) {
        NotificationService.showSnackBar('Lỗi xóa mã nhập nhanh: $e', color: Colors.red);
      }
    }
  }

  Future<void> _importToInventory(QuickInputCode code) async {
    try {
      final prefilledData = {
        'name': code.name,
        'type': code.type,
        'brand': code.brand,
        'model': code.model,
        'capacity': code.capacity,
        'color': code.color,
        'condition': code.condition,
        'cost': code.cost,
        'price': code.price,
        'supplier': code.supplier,
        'paymentMethod': code.paymentMethod,
        'notes': code.description,
        'quantity': 1,
      };

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StockInView(prefilledData: prefilledData),
          ),
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('Lỗi nhập kho: $e', color: Colors.red);
    }
  }

  void _showCreateDialog() {
    NotificationService.showSnackBar('Tính năng tạo mã mới đang được phát triển', color: Colors.blue);
  }

  Widget _buildLibraryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredCodes = _filteredCodes;

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildFilterChip('Tất cả', QuickInputFilter.all),
              const SizedBox(width: 8),
              _buildFilterChip('Chưa đồng bộ', QuickInputFilter.unsynced),
            ],
          ),
        ),

        if (_codes.any((code) => !code.isSynced))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _syncToCloud,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ lên Cloud'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),

        Expanded(
          child: filteredCodes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.library_books, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Chưa có mã nhập nhanh nào',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filteredCodes.length,
                  itemBuilder: (context, index) {
                    final code = filteredCodes[index];
                    return _buildCodeListTile(code, isLibrary: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildManagementTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredCodes = _filteredCodes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm kiếm mã nhập nhanh...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        Expanded(
          child: filteredCodes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Chưa có mã nhập nhanh nào'
                            : 'Không tìm thấy mã nhập nhanh phù hợp',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filteredCodes.length,
                  itemBuilder: (context, index) {
                    final code = filteredCodes[index];
                    return _buildCodeListTile(code, isLibrary: false);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCodeListTile(QuickInputCode code, {required bool isLibrary}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: code.type == 'PHONE'
                ? Colors.blue.shade100
                : Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            code.type == 'PHONE' ? Icons.smartphone : Icons.devices_other,
            color: code.type == 'PHONE' ? Colors.blue : Colors.green,
          ),
        ),
        title: Text(
          code.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            decoration: !code.isActive ? TextDecoration.lineThrough : null,
            color: !code.isActive ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${code.brand ?? ''} ${code.model ?? ''}'.trim()),
            if (code.price != null)
              Text(
                'Giá: ${NumberFormat('#,###').format(code.price)}đ',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            if (!code.isSynced)
              const Text(
                'Chưa đồng bộ',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
        trailing: isLibrary
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'import':
                      _importToInventory(code);
                      break;
                    case 'toggle':
                      _toggleActive(code);
                      break;
                    case 'delete':
                      _deleteCode(code);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(Icons.inventory, size: 20),
                        SizedBox(width: 8),
                        Text('Nhập kho'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          code.isActive ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(code.isActive ? 'Tắt' : 'Bật'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Xóa'),
                      ],
                    ),
                  ),
                ],
              )
            : IconButton(
                icon: Icon(code.isActive ? Icons.visibility : Icons.visibility_off),
                onPressed: () => _toggleActive(code),
                tooltip: code.isActive ? 'Tắt mã' : 'Bật mã',
              ),
        onTap: isLibrary ? () => _importToInventory(code) : null,
      ),
    );
  }

  Widget _buildFilterChip(String label, QuickInputFilter filter) {
    final isSelected = _currentFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _currentFilter = filter);
        }
      },
      backgroundColor: Colors.grey.shade100,
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Mã Nhập Nhanh'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCodes,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _buildManagementTab(),
      floatingActionButton: FloatingActionButton(
        heroTag: 'quick_input_management_fab',
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
        tooltip: 'Tạo mã mới',
      ),
    );
  }
}