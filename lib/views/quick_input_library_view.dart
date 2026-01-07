import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/quick_input_code_model.dart';
import '../models/product_model.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import 'fast_stock_in_view.dart';
import 'quick_input_sync_check_view.dart';
import 'stock_in_view.dart';

enum QuickInputFilter { all, unsynced }

class QuickInputLibraryView extends StatefulWidget {
  const QuickInputLibraryView({super.key});

  @override
  State<QuickInputLibraryView> createState() => _QuickInputLibraryViewState();
}

class _QuickInputLibraryViewState extends State<QuickInputLibraryView> {
  final db = DBHelper();
  List<QuickInputCode> _codes = [];
  bool _isLoading = true;
  QuickInputFilter _currentFilter = QuickInputFilter.all;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() => _isLoading = true);
    try {
      final codes = await db.getQuickInputCodes();
      if (mounted) {
        setState(() {
          _codes = codes;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Load quick input codes error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        NotificationService.showSnackBar('Lỗi tải thư viện mã nhập nhanh: $e', color: Colors.red);
        setState(() => _isLoading = false);
      }
    }
  }

  List<QuickInputCode> get _filteredCodes {
    switch (_currentFilter) {
      case QuickInputFilter.all:
        return _codes;
      case QuickInputFilter.unsynced:
        return _codes.where((code) => !code.isSynced).toList();
    }
  }

  Future<void> _syncToCloud() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    try {
      await SyncService.syncQuickInputCodesToCloud();
      await SyncService.downloadAllFromCloud(); // Download latest data
      NotificationService.showSnackBar('Đã đồng bộ thành công mã nhập nhanh!', color: Colors.green);
      await _loadCodes(); // Refresh list
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
        await db.deleteQuickInputCode(code.id!);
        await _loadCodes();
        NotificationService.showSnackBar('Đã xóa mã nhập nhanh', color: Colors.green);
      } catch (e) {
        NotificationService.showSnackBar('Lỗi xóa mã nhập nhanh: $e', color: Colors.red);
      }
    }
  }

  Future<void> _importToInventory(QuickInputCode code) async {
    // Create prefilled data from QuickInputCode
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
      'quantity': 1, // Default quantity
    };

    // Navigate to StockInView with prefilled data instead of FastStockInView
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockInView(prefilledData: prefilledData),
        ),
      );
    }
  }

  void _showAddEditDialog([QuickInputCode? code]) {
    try {
      showDialog(
        context: context,
        builder: (ctx) => _QuickInputCodeDialog(
          code: code,
          onSave: (newCode) async {
            try {
              if (code == null) {
                await db.insertQuickInputCode(newCode);
                NotificationService.showSnackBar('Đã thêm mã nhập nhanh', color: Colors.green);
              } else {
                await db.updateQuickInputCode(newCode);
                NotificationService.showSnackBar('Đã cập nhật mã nhập nhanh', color: Colors.green);
              }
              await _loadCodes();
            } catch (e) {
              NotificationService.showSnackBar('Lỗi lưu mã nhập nhanh: $e', color: Colors.red);
            }
          },
        ),
      );
    } catch (e) {
      NotificationService.showSnackBar('Lỗi mở dialog: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text(
          "THƯ VIỆN MÃ NHẬP NHANH",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isSyncing ? null : _syncToCloud,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload, color: Colors.blue),
            tooltip: 'Đồng bộ lên Cloud',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuickInputSyncCheckView()),
            ),
            icon: const Icon(Icons.sync, color: Colors.orange),
            tooltip: 'Kiểm tra đồng bộ',
          ),
          IconButton(
            onPressed: _loadCodes,
            icon: const Icon(Icons.refresh, color: Colors.blue),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _codes.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    // Filter chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.white,
                      child: Row(
                        children: [
                          FilterChip(
                            label: Text('Tất cả (${_codes.length})'),
                            selected: _currentFilter == QuickInputFilter.all,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _currentFilter = QuickInputFilter.all);
                              }
                            },
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.blue[100],
                            checkmarkColor: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: Text('Chưa đồng bộ (${_codes.where((c) => !c.isSynced).length})'),
                            selected: _currentFilter == QuickInputFilter.unsynced,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _currentFilter = QuickInputFilter.unsynced);
                              }
                            },
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.orange[100],
                            checkmarkColor: Colors.orange,
                          ),
                        ],
                      ),
                    ),
                    // Code list
                    Expanded(
                      child: _filteredCodes.isEmpty
                          ? _buildEmptyFiltered()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredCodes.length,
                              itemBuilder: (ctx, i) => _buildCodeCard(_filteredCodes[i]),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        label: const Text(
          "THÊM MÃ MỚI",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF2962FF),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined, size: 80, color: Colors.grey[200]),
            const SizedBox(height: 16),
            Text(
              "Chưa có mã nhập nhanh nào",
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              "Tạo mã nhập nhanh để tăng tốc độ nhập kho",
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _buildEmptyFiltered() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentFilter == QuickInputFilter.unsynced ? Icons.check_circle : Icons.filter_list,
              size: 80, 
              color: _currentFilter == QuickInputFilter.unsynced ? Colors.green[200] : Colors.grey[200]
            ),
            const SizedBox(height: 16),
            Text(
              _currentFilter == QuickInputFilter.unsynced 
                ? "Tất cả mã đã được đồng bộ!" 
                : "Không có mã nào phù hợp với bộ lọc",
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _currentFilter == QuickInputFilter.unsynced 
                ? "Không có mã nhập nhanh nào chưa đồng bộ" 
                : "Thử thay đổi bộ lọc để xem các mã khác",
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _buildCodeCard(QuickInputCode code) {
    final isPhone = code.type == 'PHONE';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: !code.isSynced ? Border.all(color: Colors.orange.withAlpha(100), width: 2) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          // Header với thông tin cơ bản
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPhone ? Colors.blue.withAlpha(25) : Colors.orange.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPhone ? Icons.smartphone : Icons.inventory_2,
                    color: isPhone ? Colors.blue : Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: code.isActive ? const Color(0xFF1A237E) : Colors.grey,
                        ),
                      ),
                      Text(
                        isPhone ? "${code.brand ?? ''} ${code.model ?? ''}".trim() : code.description ?? '',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // Sync status indicator
                if (!code.isSynced)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync_problem, size: 10, color: Colors.orange),
                        SizedBox(width: 2),
                        Text(
                          'CHƯA ĐỒNG BỘ',
                          style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (!code.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TẮT',
                      style: TextStyle(fontSize: 8, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),

          // Chi tiết có thể mở rộng
          ExpansionTile(
            title: const Text(
              'Xem chi tiết',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPhone) ...[
                      _buildDetailRow('Thương hiệu', code.brand),
                      _buildDetailRow('Model', code.model),
                      _buildDetailRow('Dung lượng', code.capacity),
                      _buildDetailRow('Màu sắc', code.color),
                      _buildDetailRow('Tình trạng', code.condition),
                    ] else ...[
                      _buildDetailRow('Loại phụ kiện', code.description),
                    ],
                    const SizedBox(height: 8),
                    // Hiển thị 2 giá cho tất cả: vốn và bán
                    Row(
                      children: [
                        if (code.cost != null && code.cost! > 0)
                          _buildPriceChip('Vốn', code.cost!),
                        if (code.price != null && code.price! > 0)
                          _buildPriceChip('Bán', code.price!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Các nút action luôn hiển thị
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _importToInventory(code),
                        icon: const Icon(Icons.inventory, size: 16),
                        label: const Text('NHẬP KHO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddEditDialog(code),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('CHỈNH SỬA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _toggleActive(code),
                        icon: Icon(code.isActive ? Icons.visibility_off : Icons.visibility, size: 16),
                        label: Text(code.isActive ? 'TẮT' : 'BẬT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: code.isActive ? Colors.orange : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _deleteCode(code),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('XÓA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChip(String label, int amount) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50)),
      ),
      child: Text(
        '$label: ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
        style: const TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _QuickInputCodeDialog extends StatefulWidget {
  final QuickInputCode? code;
  final Function(QuickInputCode) onSave;

  const _QuickInputCodeDialog({this.code, required this.onSave});

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

  String _type = 'PHONE';
  String? _paymentMethod;

  @override
  void initState() {
    super.initState();
    if (widget.code != null) {
      final code = widget.code!;
      _nameCtrl.text = code.name;
      _type = code.type;
      _brandCtrl.text = code.brand ?? '';
      _modelCtrl.text = code.model ?? '';
      _capacityCtrl.text = code.capacity ?? '';
      _colorCtrl.text = code.color ?? '';
      _conditionCtrl.text = code.condition ?? '';
      _costCtrl.text = code.cost?.toString() ?? '';
      _priceCtrl.text = code.price?.toString() ?? '';
      _descriptionCtrl.text = code.description ?? '';
      _supplierCtrl.text = code.supplier ?? '';
      _paymentMethod = code.paymentMethod;
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
    if (!_formKey.currentState!.validate()) return;

    final code = QuickInputCode(
      id: widget.code?.id,
      firestoreId: widget.code?.firestoreId,
      name: _nameCtrl.text.trim().toUpperCase(),
      type: _type,
      brand: _type == 'PHONE' ? _brandCtrl.text.trim().toUpperCase() : null,
      model: _type == 'PHONE' ? _modelCtrl.text.trim().toUpperCase() : null,
      capacity: _type == 'PHONE' ? _capacityCtrl.text.trim() : null,
      color: _type == 'PHONE' ? _colorCtrl.text.trim() : null,
      condition: _type == 'PHONE' ? _conditionCtrl.text.trim() : null,
      cost: int.tryParse(_costCtrl.text.replaceAll(',', '')),
      price: int.tryParse(_priceCtrl.text.replaceAll(',', '')),
      description: _descriptionCtrl.text.trim(),
      supplier: _supplierCtrl.text.trim(),
      paymentMethod: _paymentMethod,
      isActive: widget.code?.isActive ?? true,
      createdAt: widget.code?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      isSynced: widget.code?.isSynced ?? false,
    );

    widget.onSave(code);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.code == null ? 'Thêm mã nhập nhanh' : 'Sửa mã nhập nhanh'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Type selector
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Loại sản phẩm'),
                items: const [
                  DropdownMenuItem(value: 'PHONE', child: Text('Điện thoại')),
                  DropdownMenuItem(value: 'ACCESSORY', child: Text('Phụ kiện/Linh kiện')),
                ],
                onChanged: (val) => setState(() => _type = val!),
                validator: (val) => val == null ? 'Vui lòng chọn loại' : null,
              ),
              const SizedBox(height: 12),

              // Name
              ValidatedTextField(
                controller: _nameCtrl,
                label: 'Tên mã nhập nhanh',
                uppercase: true,
                customValidator: (val) => val?.isEmpty ?? true ? 'Vui lòng nhập tên' : null,
              ),
              const SizedBox(height: 12),

              if (_type == 'PHONE') ...[
                // Phone fields
                ValidatedTextField(
                  controller: _brandCtrl,
                  label: 'Thương hiệu',
                  uppercase: true,
                ),
                const SizedBox(height: 12),
                ValidatedTextField(
                  controller: _modelCtrl,
                  label: 'Model',
                  uppercase: true,
                ),
                const SizedBox(height: 12),
                ValidatedTextField(
                  controller: _capacityCtrl,
                  label: 'Dung lượng',
                ),
                const SizedBox(height: 12),
                ValidatedTextField(
                  controller: _colorCtrl,
                  label: 'Màu sắc',
                ),
                const SizedBox(height: 12),
                ValidatedTextField(
                  controller: _conditionCtrl,
                  label: 'Tình trạng',
                ),
              ] else ...[
                // Accessory fields
                ValidatedTextField(
                  controller: _descriptionCtrl,
                  label: 'Mô tả/Loại phụ kiện',
                ),
              ],
              const SizedBox(height: 12),

              // Prices
              CurrencyTextField(
                controller: _costCtrl,
                label: 'Giá nhập (VNĐ)',
              ),
              const SizedBox(height: 12),
              CurrencyTextField(
                controller: _priceCtrl,
                label: 'Giá bán (VNĐ)',
              ),
              const SizedBox(height: 12),

              // Supplier
              ValidatedTextField(
                controller: _supplierCtrl,
                label: 'Nhà cung cấp',
              ),
              const SizedBox(height: 12),

              // Payment method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Phương thức thanh toán'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Chưa chọn')),
                  DropdownMenuItem(value: 'TIỀN MẶT', child: Text('Tiền mặt')),
                  DropdownMenuItem(value: 'CHUYỂN KHOẢN', child: Text('Chuyển khoản')),
                  DropdownMenuItem(value: 'CÔNG NỢ', child: Text('Công nợ')),
                ],
                onChanged: (val) => setState(() => _paymentMethod = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(widget.code == null ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}