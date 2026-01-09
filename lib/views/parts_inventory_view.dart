import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';
import '../services/supplier_service.dart';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../services/adjustment_service.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';

class PartsInventoryView extends StatefulWidget {
  const PartsInventoryView({super.key});

  @override
  State<PartsInventoryView> createState() => _PartsInventoryViewState();
}

class _PartsInventoryViewState extends State<PartsInventoryView> {
  final db = DBHelper();
  final _supplierService = SupplierService();
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _filteredParts = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  final searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;
  
  // Multi-select mode
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  // Theme colors cho màn hình phụ tùng
  final Color _primaryColor = Colors.purple; // Màu chính cho phụ tùng
  final Color _backgroundColor = const Color(0xFFF8FAFF);

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _refreshParts();
    _loadSuppliers();
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewParts'] ?? false;
    });
  }

  Future<void> _refreshParts() async {
    setState(() => _isLoading = true);
    final data = await db.getAllParts();
    setState(() {
      _parts = data;
      _applyFilter();
      _isLoading = false;
    });
  }

  Future<void> _loadSuppliers() async {
    final s = await db.getSuppliers();
    if (!mounted) return;
    setState(() => _suppliers = s);
  }

  void _applyFilter() {
    _filteredParts = _parts
        .where((p) => _searchQuery.isEmpty
            ? true
            : (p['partName']?.toString().toUpperCase().contains(_searchQuery.toUpperCase()) ?? false) ||
                (p['compatibleModels']?.toString().toUpperCase().contains(_searchQuery.toUpperCase()) ?? false))
        .toList();
  }

  String _getSupplierName(int? id) {
    if (id == null) return 'Không xác định';
    final s = _suppliers.firstWhere((e) => e['id'] == id, orElse: () => {});
    return s['name']?.toString() ?? 'Không xác định';
  }

  void _showAddPartDialog({Map<String, dynamic>? part}) {
    final nameC = TextEditingController(text: part?['partName']);
    final modelC = TextEditingController(text: part?['compatibleModels']);
    final costC = TextEditingController(
      text: part != null ? CurrencyTextField.formatDisplay(part['cost']) : "",
    );
    final priceC = TextEditingController(
      text: part != null ? CurrencyTextField.formatDisplay(part['price']) : "",
    );
    final qtyC = TextEditingController(
      text: part != null ? part['quantity'].toString() : "1",
    );
    final formKey = GlobalKey<FormState>();
    int? selectedSupplierId = part?['supplierId'] as int?;
    String paymentMethod = 'TIỀN MẶT';
    bool isLockedDay = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          nameC.addListener(() => setS(() {}));
          // Check locked day for edit
          if (part != null) {
            final createdAt = part['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
            AdjustmentService.canEditDirectly(createdAt).then((can) {
              if (!mounted) return;
              if (isLockedDay != !can) {
                setS(() => isLockedDay = !can);
              }
            });
          }
          return AlertDialog(
            title: Text(part == null ? "NHẬP LINH KIỆN MỚI" : "SỬA LINH KIỆN"),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValidatedTextField(
                      controller: nameC,
                      label: "Tên linh kiện (VD: PIN IPHONE 11)",
                      icon: Icons.inventory,
                      uppercase: true,
                      required: true,
                    ),
                    ValidatedTextField(
                      controller: modelC,
                      label: "Dòng máy tương thích",
                      icon: Icons.phone_android,
                      uppercase: true,
                    ),
                    const SizedBox(height: 12),
                    if (isLockedDay)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.lock_clock, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ngày đã chốt quỹ. Sửa sẽ cần lý do điều chỉnh và tạo bút toán.',
                                style: TextStyle(color: Colors.orange, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_suppliers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Expanded(child: Text('Chưa có nhà cung cấp, thêm trong trang NCC.')),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int?>(
                        value: selectedSupplierId,
                        decoration: InputDecoration(
                          labelText: "Nhà cung cấp (${_suppliers.length} NCC)",
                          prefixIcon: const Icon(Icons.store),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('-- Chọn NCC --')),
                          ..._suppliers.map((s) => DropdownMenuItem<int?>(
                                value: s['id'] as int?,
                                child: Text(s['name']?.toString() ?? 'N/A'),
                              )),
                        ],
                        onChanged: (v) => setS(() => selectedSupplierId = v),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CurrencyTextField(
                            controller: costC,
                            label: "Giá vốn",
                            icon: Icons.attach_money,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CurrencyTextField(
                            controller: priceC,
                            label: "Giá bán",
                            icon: Icons.sell,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: qtyC,
                      decoration: const InputDecoration(labelText: "Số lượng nhập"),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim()) ?? 0;
                        if (parsed <= 0) return 'Nhập số lượng hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (part == null) ...[
                      const Text('Hình thức thanh toán:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'].map((m) {
                          final selected = paymentMethod == m;
                          return ChoiceChip(
                            label: Text(m, style: TextStyle(color: selected ? Colors.white : Colors.black)),
                            selected: selected,
                            selectedColor: Colors.purple,
                            onSelected: (_) => setS(() => paymentMethod = m),
                          );
                        }).toList(),
                      ),
                      if (paymentMethod == 'CÔNG NỢ' && selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sẽ tạo công nợ với: ${_getSupplierName(selectedSupplierId)}',
                                  style: const TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (paymentMethod == 'CÔNG NỢ' && selectedSupplierId == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: const [
                              Icon(Icons.error_outline, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Chọn nhà cung cấp để ghi nhận công nợ.',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  try {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final partName = nameC.text.toUpperCase();
                    final cost = CurrencyTextField.parseValueWithMultiply(costC.text);
                    final price = CurrencyTextField.parseValueWithMultiply(priceC.text);
                    final qty = int.tryParse(qtyC.text) ?? 0;
                    if (qty <= 0) return;

                    final data = {
                      'partName': partName,
                      'compatibleModels': modelC.text.toUpperCase(),
                      'cost': cost,
                      'price': price,
                      'quantity': qty,
                      'supplierId': selectedSupplierId,
                      'paymentMethod': paymentMethod,
                      'updatedAt': now,
                    };

                    if (part == null) {
                      final shopId = await UserService.getCurrentShopId();
                      final insertedId = await db.insertPart(data);

                      final supplierName = _getSupplierName(selectedSupplierId);
                      await AuditService.logAction(
                        action: 'PART_IMPORT',
                        entityType: 'repair_part',
                        entityId: insertedId.toString(),
                        summary: 'Nhập linh kiện: $partName x$qty - ${NumberFormat('#,###').format(cost * qty)}đ ($paymentMethod)',
                        payload: {
                          'partName': partName,
                          'quantity': qty,
                          'cost': cost,
                          'totalCost': cost * qty,
                          'paymentMethod': paymentMethod,
                          'supplierName': supplierName,
                        },
                      );

                      if (paymentMethod == 'CÔNG NỢ') {
                        // BUG-005: Block save nếu CÔNG NỢ nhưng không chọn NCC
                        if (selectedSupplierId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ CÔNG NỢ phải chọn Nhà cung cấp!'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        await db.insertDebt({
                          'firestoreId': 'debt_part_${now}_$insertedId',
                          'type': 'SHOP_OWES',
                          'personName': supplierName,
                          'phone': _suppliers.firstWhere((s) => s['id'] == selectedSupplierId, orElse: () => {})['phone'] ?? '',
                          'totalAmount': cost * qty,
                          'paidAmount': 0,
                          'note': 'Nhập linh kiện: $partName x$qty',
                          'status': 'unpaid',
                          'createdAt': now,
                          'shopId': shopId,
                          'isSynced': 0,
                          'relatedPartId': insertedId,
                        });
                        EventBus().emit('debts_changed');
                      } else {
                        await db.insertExpense({
                          'firestoreId': 'exp_part_${now}_$insertedId',
                          'category': 'NHẬP LINH KIỆN',
                          'description': 'Nhập linh kiện: $partName x$qty${selectedSupplierId != null ? " từ $supplierName" : ""}',
                          'amount': cost * qty,
                          'date': now,
                          'paymentMethod': paymentMethod,
                          'createdAt': now,
                          'shopId': shopId,
                          'isSynced': 0,
                          'relatedPartId': insertedId,
                        });
                        EventBus().emit('expenses_changed');
                      }
                    } else {
                      final originalDate = part['createdAt'] as int? ?? now;
                      final canEditDirectly = await AdjustmentService.canEditDirectly(originalDate);
                      final oldCost = part['cost'] as int? ?? 0;
                      final oldQty = part['quantity'] as int? ?? 0;
                      final oldPaymentMethod = part['paymentMethod'] as String? ?? 'TIỀN MẶT';

                      if (canEditDirectly) {
                        data['isSynced'] = 0;
                        await (await db.database).update(
                          'repair_parts',
                          data,
                          where: 'id = ?',
                          whereArgs: [part['id']],
                        );
                        await AuditService.logAction(
                          action: 'PART_UPDATE',
                          entityType: 'repair_part',
                          entityId: part['id'].toString(),
                          summary: 'Cập nhật linh kiện: $partName',
                          payload: {
                            'partName': partName,
                            'quantity': qty,
                            'cost': cost,
                            'price': price,
                          },
                        );
                      } else {
                        final reason = await _showAdjustmentReasonDialog(context);
                        if (reason == null || reason.isEmpty) return;

                        if (cost != oldCost) {
                          final result = await AdjustmentService.adjustPartCost(
                            partId: part['id'] as int,
                            partName: partName,
                            oldCost: oldCost,
                            newCost: cost,
                            quantity: oldQty,
                            originalDate: originalDate,
                            reason: reason,
                            supplierId: selectedSupplierId,
                            supplierName: _getSupplierName(selectedSupplierId),
                            paymentMethod: oldPaymentMethod,
                          );

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result.message),
                                backgroundColor: result.success ? Colors.green : Colors.red,
                              ),
                            );
                          }

                          if (!result.success) return;
                        }

                        await (await db.database).update(
                          'repair_parts',
                          {
                            'partName': partName,
                            'compatibleModels': modelC.text.toUpperCase(),
                            'cost': cost,
                            'price': price,
                            'quantity': qty,
                            'supplierId': selectedSupplierId,
                            'paymentMethod': paymentMethod,
                            'updatedAt': now,
                            'isSynced': 0,
                          },
                          where: 'id = ?',
                          whereArgs: [part['id']],
                        );
                      }
                    }

                    if (!mounted) return;
                    Navigator.of(context).pop();
                    await _refreshParts();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text("XÁC NHẬN"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      // Exit selection mode if no items selected
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _filteredParts.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        for (var p in _filteredParts) {
          if (p['id'] != null) {
            _selectedIds.add(p['id'] as int);
          }
        }
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa $count linh kiện đã chọn?\n\nHành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final database = await db.database;
      int deletedCount = 0;
      
      for (var id in _selectedIds) {
        // Soft delete - mark as deleted
        await database.update(
          'repair_parts',
          {
            'deleted': 1,
            'isSynced': 0,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        deletedCount++;
        
        // Log audit
        final part = _parts.firstWhere((p) => p['id'] == id, orElse: () => {});
        if (part.isNotEmpty) {
          await AuditService.logAction(
            action: 'DELETE_PART',
            entityType: 'repair_parts',
            entityId: part['firestoreId'] ?? id.toString(),
            summary: 'Xóa linh kiện: ${part['partName']}',
          );
        }
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa $deletedCount linh kiện'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _isSelectionMode = false;
        _selectedIds.clear();
      });
      
      await _refreshParts();
      EventBus().emit('repair_parts_changed');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi xóa: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool allSelected = _filteredParts.isNotEmpty && 
        _selectedIds.length == _filteredParts.length;
    
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        title: _isSelectionMode
            ? Text(
                '${_selectedIds.length} đã chọn',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              )
            : const Text(
                "KHO LINH KIỆN SỬA CHỮA",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
        backgroundColor: _isSelectionMode ? Colors.red.shade700 : _primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        automaticallyImplyLeading: !_isSelectionMode,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                  tooltip: allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả',
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Xóa đã chọn',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                ),
              ]
            : _isAdmin
                ? [
                    IconButton(
                      icon: const Icon(Icons.checklist),
                      tooltip: 'Chọn nhiều',
                      onPressed: _toggleSelectionMode,
                    ),
                  ]
                : null,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v.trim();
                        _applyFilter();
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Tìm linh kiện theo tên / dòng máy',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    itemCount: _filteredParts.length,
                    itemBuilder: (ctx, i) {
                      final p = _filteredParts[i];
                      final int? partId = p['id'] as int?;
                      final bool isSelected = partId != null && _selectedIds.contains(partId);
                      final bool isLow = (p['quantity'] as int? ?? 0) < 3;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: isSelected 
                              ? BorderSide(color: Colors.red.shade700, width: 2)
                              : BorderSide.none,
                        ),
                        color: isSelected ? Colors.red.shade50 : null,
                        child: ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  activeColor: Colors.red.shade700,
                                  onChanged: partId != null 
                                      ? (_) => _toggleSelection(partId)
                                      : null,
                                )
                              : CircleAvatar(
                                  backgroundColor: isLow
                                      ? Colors.red.withAlpha(25)
                                      : _primaryColor.withAlpha(25),
                                  child: Icon(
                                    Icons.settings_input_component,
                                    color: isLow ? Colors.red : _primaryColor,
                                  ),
                                ),
                          title: Text(
                            p['partName'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            "Dùng cho: ${p['compatibleModels'] ?? 'N/A'}\nSố lượng: ${p['quantity'] ?? 0}${p['supplierId'] != null ? "\nNCC: ${_getSupplierName(p['supplierId'] as int?)}" : ''}",
                          ),
                          trailing: _isSelectionMode
                              ? null
                              : Text(
                                  "${NumberFormat('#,###').format(p['price'] ?? 0)} đ",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                          onTap: _isSelectionMode
                              ? (partId != null ? () => _toggleSelection(partId) : null)
                              : (_isAdmin ? () => _showAddPartDialog(part: p) : null),
                          onLongPress: !_isSelectionMode && _isAdmin && partId != null
                              ? () {
                                  setState(() {
                                    _isSelectionMode = true;
                                    _selectedIds.add(partId);
                                  });
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _isSelectionMode
          ? null
          : (_isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddPartDialog(),
                  label: const Text("NHẬP LINH KIỆN"),
                  icon: const Icon(Icons.add),
                  backgroundColor: _primaryColor,
                )
              : null),
    );
  }

  Future<String?> _showAdjustmentReasonDialog(BuildContext ctx) async {
    final reasonC = TextEditingController();
    return showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        title: const Text('Lý do điều chỉnh sau ngày chốt quỹ'),
        content: TextField(
          controller: reasonC,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Nhập lý do điều chỉnh'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () {
              final val = reasonC.text.trim();
              if (val.isEmpty) return;
              Navigator.pop(dCtx, val);
            },
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );
  }
}
