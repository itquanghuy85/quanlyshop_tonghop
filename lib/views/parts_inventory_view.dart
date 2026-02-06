import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';
import '../services/supplier_service.dart';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../services/adjustment_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/payment_intent_service.dart';
import '../services/financial_activity_service.dart';
import '../models/payment_intent_model.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/gradient_fab.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../core/utils/money_utils.dart';

/// Widget content để embed vào InventoryView tab - Phiên bản chuyên nghiệp
class PartsInventoryViewContent extends StatefulWidget {
  const PartsInventoryViewContent({super.key});
  @override
  State<PartsInventoryViewContent> createState() => _PartsInventoryViewContentState();
}

class _PartsInventoryViewContentState extends State<PartsInventoryViewContent> {
  final db = DBHelper();
  final _supplierService = SupplierService();
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _filteredParts = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  final searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  bool _showOutOfStock = false;
  String _sortBy = 'name'; // name, quantity, cost
  
  // Navigation - filter by model category
  String? _selectedModelCategory;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  
  // Available model categories for quick navigation
  static const List<String> _modelCategories = [
    'IPHONE',
    'SAMSUNG', 
    'XIAOMI',
    'OPPO',
    'VIVO',
    'REALME',
  ];
  
  // Theme colors - đồng bộ với InventoryView
  static const Color _primaryColor = Color(0xFF7B1FA2); // Purple 700
  static const Color _gradientStart = Color(0xFF6A1B9A);
  static const Color _gradientEnd = Color(0xFF9C27B0);
  final Color _backgroundColor = const Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _refreshParts();
    _loadSuppliers();
    // Listen for changes
    EventBus().stream.listen((event) {
      if (event == 'parts_changed' && mounted) _refreshParts();
    });
    // Scroll controller listener for scroll-to-top button
    _scrollController.addListener(_onScroll);
  }
  
  void _onScroll() {
    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToTop) {
      setState(() => _showScrollToTop = showButton);
    }
  }
  
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _isAdmin = perms['allowViewParts'] ?? false);
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
    var filtered = _parts.where((p) {
      // Lọc theo search
      final matchSearch = _searchQuery.isEmpty ||
          (p['partName']?.toString().toUpperCase().contains(_searchQuery.toUpperCase()) ?? false) ||
          (p['compatibleModels']?.toString().toUpperCase().contains(_searchQuery.toUpperCase()) ?? false);
      
      // Lọc hết hàng
      final qty = p['quantity'] as int? ?? 0;
      final matchStock = _showOutOfStock || qty > 0;
      
      // Lọc theo model category (navigation)
      final matchCategory = _selectedModelCategory == null ||
          (p['compatibleModels']?.toString().toUpperCase().contains(_selectedModelCategory!) ?? false) ||
          (p['partName']?.toString().toUpperCase().contains(_selectedModelCategory!) ?? false);
      
      return matchSearch && matchStock && matchCategory;
    }).toList();
    
    // Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'quantity':
          return (b['quantity'] as int? ?? 0).compareTo(a['quantity'] as int? ?? 0);
        case 'cost':
          final costA = (a['cost'] as int? ?? 0) * (a['quantity'] as int? ?? 0);
          final costB = (b['cost'] as int? ?? 0) * (b['quantity'] as int? ?? 0);
          return costB.compareTo(costA);
        default:
          return (a['partName'] ?? '').toString().compareTo((b['partName'] ?? '').toString());
      }
    });
    
    _filteredParts = filtered;
  }

  String _getSupplierName(int? id) {
    if (id == null) return 'Không xác định';
    final s = _suppliers.firstWhere((e) => e['id'] == id, orElse: () => {});
    return s['name']?.toString() ?? 'Không xác định';
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tính tổng
    final partsWithStock = _showOutOfStock ? _parts : _parts.where((p) => (p['quantity'] as int? ?? 0) > 0).toList();
    final totalTypes = partsWithStock.length;
    final totalQty = partsWithStock.fold<int>(0, (s, p) => s + (p['quantity'] as int? ?? 0));
    final totalCost = partsWithStock.fold<int>(0, (s, p) => s + (p['cost'] as int? ?? 0) * (p['quantity'] as int? ?? 0));
    final lowStockCount = _parts.where((p) => (p['quantity'] as int? ?? 0) > 0 && (p['quantity'] as int? ?? 0) <= 2).length;

    return Container(
      color: _backgroundColor,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : Stack(
              children: [
                Column(
                  children: [
                    // Summary Card - đồng bộ style với Kho chính
                    _buildSummaryCard(totalTypes, totalQty, totalCost, lowStockCount),
                    
                    // Navigation chips - Quick filter by model
                    _buildNavigationChips(),
                    
                    // Search & Filter Bar
                    _buildSearchFilterBar(),
                    
                    // Selection mode header
                    if (_isSelectionMode) _buildSelectionHeader(),
                    
                    // List
                    Expanded(
                      child: _filteredParts.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _refreshParts,
                              color: _primaryColor,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                                itemCount: _filteredParts.length,
                                itemBuilder: (ctx, i) => _buildPartCard(_filteredParts[i], i + 1),
                          ),
                        ),
                    ),
                  ],
                ),
                // Scroll to top button
                if (_showScrollToTop)
                  Positioned(
                    bottom: 80,
                    right: 16,
                    child: FloatingActionButton.small(
                      onPressed: _scrollToTop,
                      backgroundColor: _primaryColor,
                      child: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                    ),
                  ),
              ],
            ),
    );
  }
  
  // Navigation chips for quick model filtering
  Widget _buildNavigationChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "Tất cả" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                'Tất cả',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _selectedModelCategory == null ? FontWeight.bold : FontWeight.normal,
                  color: _selectedModelCategory == null ? Colors.white : Colors.black87,
                ),
              ),
              selected: _selectedModelCategory == null,
              onSelected: (_) {
                setState(() {
                  _selectedModelCategory = null;
                  _applyFilter();
                });
              },
              selectedColor: _primaryColor,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _selectedModelCategory == null ? _primaryColor : Colors.grey.shade300,
                ),
              ),
            ),
          ),
          // Model category chips
          ..._modelCategories.map((category) {
            final isSelected = _selectedModelCategory == category;
            // Count parts matching this category
            final count = _parts.where((p) =>
              (p['compatibleModels']?.toString().toUpperCase().contains(category) ?? false) ||
              (p['partName']?.toString().toUpperCase().contains(category) ?? false)
            ).length;
            
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  '$category ($count)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedModelCategory = isSelected ? null : category;
                    _applyFilter();
                  });
                },
                selectedColor: _primaryColor,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? _primaryColor : Colors.grey.shade300,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(int types, int qty, int cost, int lowStock) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_gradientStart, _gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryItem(Icons.category, '$types', 'Loại LK'),
          _verticalDivider(),
          _summaryItem(Icons.inventory_2, '$qty', 'Tổng SL'),
          _verticalDivider(),
          _summaryItem(Icons.account_balance_wallet, MoneyUtils.formatCompact(cost), 'Giá vốn'),
          if (lowStock > 0) ...[
            _verticalDivider(),
            _summaryItem(Icons.warning_amber, '$lowStock', 'Sắp hết', Colors.amber),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label, [Color? iconColor]) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor ?? Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(value, style: TextStyle(
                color: Colors.white,
                fontSize: AppTextStyles.headline3.fontSize,
                fontWeight: FontWeight.bold,
              )),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white70, fontSize: AppTextStyles.caption.fontSize)),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(width: 1, height: 32, color: Colors.white24);
  }

  Widget _buildSearchFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
                ],
              ),
              child: TextField(
                controller: searchCtrl,
                onChanged: (v) {
                  _searchQuery = v;
                  _applyFilter();
                  setState(() {});
                },
                style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                decoration: InputDecoration(
                  hintText: 'Tìm linh kiện, model...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: AppTextStyles.headline5.fontSize),
                  prefixIcon: const Icon(Icons.search, color: _primaryColor, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchCtrl.clear();
                            _searchQuery = '';
                            _applyFilter();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter buttons
          _filterChip(
            icon: _showOutOfStock ? Icons.visibility : Icons.visibility_off,
            label: 'Hết',
            selected: _showOutOfStock,
            onTap: () {
              setState(() {
                _showOutOfStock = !_showOutOfStock;
                _applyFilter();
              });
            },
          ),
          const SizedBox(width: 4),
          // Sort popup
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: _primaryColor, size: 22),
            tooltip: 'Sắp xếp',
            onSelected: (v) {
              setState(() {
                _sortBy = v;
                _applyFilter();
              });
            },
            itemBuilder: (_) => [
              _sortMenuItem('name', 'Tên A-Z', Icons.sort_by_alpha),
              _sortMenuItem('quantity', 'Số lượng', Icons.format_list_numbered),
              _sortMenuItem('cost', 'Giá vốn', Icons.attach_money),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? _primaryColor : Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: isSelected ? _primaryColor : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: _primaryColor),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _primaryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _primaryColor : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? _primaryColor : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: selected ? _primaryColor : Colors.grey,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionHeader() {
    return Container(
      color: _primaryColor.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() {
              _isSelectionMode = false;
              _selectedIds.clear();
            }),
          ),
          Text(
            'Đã chọn ${_selectedIds.length}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _deleteSelectedParts,
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            label: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildPartCard(Map<String, dynamic> p, int index) {
    final id = p['id'] as int;
    final isSelected = _selectedIds.contains(id);
    final qty = p['quantity'] as int? ?? 0;
    final cost = p['cost'] as int? ?? 0;
    final price = p['price'] as int? ?? 0;
    final createdAt = p['createdAt'] as int?;
    final updatedAt = p['updatedAt'] as int?;
    final isLow = qty > 0 && qty <= 2;
    final isOut = qty == 0;
    final supplierName = _getSupplierName(p['supplierId'] as int?);
    final updatedText = updatedAt != null
      ? DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(updatedAt))
      : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected 
            ? const BorderSide(color: _primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(id);
          } else {
            _showPartDetailSheet(p);
          }
        },
        onLongPress: () => _toggleSelection(id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Leading icon/checkbox
              if (_isSelectionMode)
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(id),
                  activeColor: _primaryColor,
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isOut 
                        ? Colors.grey.shade200 
                        : isLow 
                            ? Colors.orange.withOpacity(0.15)
                            : _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOut ? Icons.block : Icons.build_circle,
                    color: isOut ? Colors.grey : isLow ? Colors.orange : _primaryColor,
                    size: 24,
                  ),
                ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p['partName'] ?? 'N/A',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: AppTextStyles.headline4.fontSize,
                              color: isOut ? Colors.grey : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLow && !isOut)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('SẮP HẾT', style: TextStyle(
                              fontSize: AppTextStyles.overlineSize,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            )),
                          ),
                        if (isOut)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('HẾT HÀNG', style: TextStyle(
                              fontSize: AppTextStyles.overlineSize,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            )),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p['compatibleModels'] ?? 'Tương thích: N/A',
                      style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _infoChip(Icons.inventory_2, 'SL: $qty', isLow ? Colors.orange : Colors.blue),
                        const SizedBox(width: 8),
                        _infoChip(Icons.attach_money, NumberFormat.compact().format(cost), Colors.green),
                        const SizedBox(width: 8),
                        _infoChip(Icons.sell, NumberFormat.compact().format(price), Colors.red),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (supplierName != 'Không xác định')
                          _infoChip(Icons.store, supplierName, _primaryColor),
                        if (updatedText != null)
                          _infoChip(Icons.update, 'Cập nhật: $updatedText', Colors.grey.shade700),
                        if (createdAt != null && updatedAt == null)
                          _infoChip(
                            Icons.schedule,
                            'Tạo: ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(createdAt))}',
                            Colors.grey.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Trailing - Giá bán
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${NumberFormat('#,###').format(price)}đ',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline3.fontSize,
                      fontWeight: FontWeight.bold,
                      color: isOut ? Colors.grey : Colors.red.shade700,
                    ),
                  ),
                  Text(
                    'Giá bán',
                    style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.build_circle_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'Không tìm thấy linh kiện' : 'Chưa có linh kiện trong kho',
            style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty 
                ? 'Thử từ khóa khác' 
                : 'Nhấn "THÊM LINH KIỆN" để bắt đầu',
            style: TextStyle(fontSize: AppTextStyles.headline5.fontSize, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  void _showPartDetailSheet(Map<String, dynamic> p) {
    final qty = p['quantity'] as int? ?? 0;
    final cost = p['cost'] as int? ?? 0;
    final price = p['price'] as int? ?? 0;
    final totalCost = cost * qty;
    final supplierName = _getSupplierName(p['supplierId'] as int?);
    final createdAt = p['createdAt'] as int?;
    final updatedAt = p['updatedAt'] as int?;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.build_circle, color: _primaryColor, size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['partName'] ?? 'N/A',
                          style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          p['compatibleModels'] ?? 'N/A',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _detailRow('Số lượng tồn', '$qty', Icons.inventory_2),
                    const Divider(height: 20),
                    _detailRow('Giá vốn/sp', '${NumberFormat('#,###').format(cost)}đ', Icons.attach_money),
                    const Divider(height: 20),
                    _detailRow('Giá bán/sp', '${NumberFormat('#,###').format(price)}đ', Icons.sell),
                    const Divider(height: 20),
                    _detailRow('Tổng vốn tồn', '${NumberFormat('#,###').format(totalCost)}đ', Icons.account_balance_wallet, Colors.green),
                    const Divider(height: 20),
                    _detailRow('Nhà cung cấp', supplierName, Icons.store),
                    if (createdAt != null) ...[
                      const Divider(height: 20),
                      _detailRow('Ngày nhập', DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(createdAt)), Icons.calendar_today),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PartsInventoryView()),
                        ).then((_) => _refreshParts());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Sửa'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: const BorderSide(color: _primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PartsInventoryView()),
                        ).then((_) => _refreshParts());
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Nhập thêm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _detailRow(String label, String value, IconData icon, [Color? valueColor]) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
        Text(value, style: TextStyle(
          fontWeight: FontWeight.bold,
          color: valueColor ?? Colors.black87,
        )),
      ],
    );
  }

  Future<void> _deleteSelectedParts() async {
    if (_selectedIds.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa ${_selectedIds.length} linh kiện đã chọn?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    final database = await db.database;
    for (final id in _selectedIds) {
      await database.delete('repair_parts', where: 'id = ?', whereArgs: [id]);
    }
    
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    
    _refreshParts();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa linh kiện'), backgroundColor: Colors.green),
      );
    }
  }
}

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
        .where(
          (p) => _searchQuery.isEmpty
              ? true
              : (p['partName']?.toString().toUpperCase().contains(
                          _searchQuery.toUpperCase(),
                        ) ??
                        false) ||
                    (p['compatibleModels']?.toString().toUpperCase().contains(
                          _searchQuery.toUpperCase(),
                        ) ??
                        false),
        )
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
            final createdAt =
                part['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
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
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.5),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lock_clock,
                              color: Colors.orange,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ngày đã chốt quỹ. Sửa sẽ cần lý do điều chỉnh và tạo bút toán.',
                                style: TextStyle(
                                  color: Colors.orange,
                                  height: 1.3,
                                ),
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
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Chưa có nhà cung cấp, thêm trong trang NCC.',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int?>(
                        initialValue: selectedSupplierId,
                        decoration: InputDecoration(
                          labelText: "Nhà cung cấp (${_suppliers.length} NCC)",
                          prefixIcon: const Icon(Icons.store),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('-- Chọn NCC --'),
                          ),
                          ..._suppliers.map(
                            (s) => DropdownMenuItem<int?>(
                              value: s['id'] as int?,
                              child: Text(s['name']?.toString() ?? 'N/A'),
                            ),
                          ),
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
                      decoration: const InputDecoration(
                        labelText: "Số lượng nhập",
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim()) ?? 0;
                        if (parsed <= 0) return 'Nhập số lượng hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (part == null) ...[
                      const Text(
                        'Hình thức thanh toán:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'].map((
                          m,
                        ) {
                          final selected = paymentMethod == m;
                          return ChoiceChip(
                            label: Text(
                              m,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.black,
                              ),
                            ),
                            selected: selected,
                            selectedColor: Colors.purple,
                            onSelected: (_) => setS(() => paymentMethod = m),
                          );
                        }).toList(),
                      ),
                      if (paymentMethod == 'CÔNG NỢ' &&
                          selectedSupplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 18,
                              ),
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
                      if (paymentMethod == 'CÔNG NỢ' &&
                          selectedSupplierId == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 18,
                              ),
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
                  // Finalize currency fields trước khi xử lý
                  CurrencyTextField.finalizeAll();

                  if (!(formKey.currentState?.validate() ?? false)) return;
                  try {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final partName = nameC.text.toUpperCase();
                    final cost = CurrencyTextField.parseValueWithMultiply(
                      costC.text,
                    );
                    final price = CurrencyTextField.parseValueWithMultiply(
                      priceC.text,
                    );
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

                      // Generate firestoreId for sync
                      final firestoreId = 'part_${now}_${partName.hashCode}';
                      data['firestoreId'] = firestoreId;
                      data['shopId'] = shopId;

                      final insertedId = await db.insertPart(data);

                      // Queue sync to cloud via SyncOrchestrator
                      await SyncOrchestrator().enqueue(
                        entityType: SyncEntityType.repairPart,
                        entityId: insertedId,
                        firestoreId: firestoreId,
                        operation: SyncOperation.create,
                        data: {...data, 'id': insertedId},
                      );

                      final supplierName = _getSupplierName(selectedSupplierId);
                      await AuditService.logAction(
                        action: 'PART_IMPORT',
                        entityType: 'repair_part',
                        entityId: insertedId.toString(),
                        summary:
                            'Nhập linh kiện: $partName x$qty - ${NumberFormat('#,###').format(cost * qty)}đ ($paymentMethod)',
                        payload: {
                          'partName': partName,
                          'quantity': qty,
                          'cost': cost,
                          'totalCost': cost * qty,
                          'paymentMethod': paymentMethod,
                          'supplierName': supplierName,
                        },
                      );

                      // Ghi lịch sử nhập hàng từ NCC (để hiển thị trong trang chi tiết NCC)
                      if (selectedSupplierId != null) {
                        final user = FirebaseAuth.instance.currentUser;
                        final userName =
                            user?.email?.split('@').first.toUpperCase() ?? "NV";
                        final importHistory = {
                          'supplierId': selectedSupplierId,
                          'supplierName': supplierName,
                          'productName': partName,
                          'productBrand': 'LINH KIỆN',
                          'productModel': modelC.text.toUpperCase(),
                          'imei': null,
                          'quantity': qty,
                          'costPrice': cost,
                          'totalAmount': cost * qty,
                          'paymentMethod': paymentMethod,
                          'importDate': now,
                          'importedBy': userName,
                          'notes': 'Nhập từ kho linh kiện',
                          'shopId': shopId,
                          'isSynced': 0,
                        };
                        final importHistoryId = await db
                            .insertSupplierImportHistory(importHistory);

                        // FIX BUG-001: Enqueue để sync lên Firestore
                        if (importHistoryId > 0) {
                          await SyncOrchestrator().enqueueSupplierImportHistory(
                            importHistoryId,
                            firestoreId:
                                importHistory['firestoreId'] as String?,
                            operation: SyncOperation.create,
                          );
                        }

                        // Cập nhật thống kê nhà cung cấp
                        await db.updateSupplierStats(
                          selectedSupplierId!,
                          cost * qty,
                          qty,
                        );
                        // Emit event để cập nhật UI nhà cung cấp
                        EventBus().emit('suppliers_changed');
                      }

                      // Xử lý thanh toán cho nhập linh kiện
                      final totalCost = cost * qty;
                      if (totalCost > 0) {
                        final user = FirebaseAuth.instance.currentUser;
                        final userName = user?.email?.split('@').first.toUpperCase() ?? 'NV';
                        if (paymentMethod == 'CÔNG NỢ') {
                          // Công nợ NCC → Tạo debt record + PaymentIntent (CHỜ CHI)
                          final debtFId = 'debt_part_${DateTime.now().millisecondsSinceEpoch}_${selectedSupplierId ?? 0}';
                          final debtData = {
                            'firestoreId': debtFId,
                            'personName': supplierName,
                            'phone': '',
                            'totalAmount': totalCost,
                            'paidAmount': 0,
                            'type': 'SHOP_OWES',
                            'status': 'ACTIVE',
                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                            'note': 'Nhập linh kiện: $partName x$qty',
                            'linkedId': null,
                            'isSynced': 0,
                            'shopId': shopId,
                          };
                          final debtId = await db.insertDebt(debtData);
                          
                          if (debtId > 0) {
                            await SyncOrchestrator().enqueue(
                              entityType: SyncEntityType.debt,
                              entityId: debtId,
                              firestoreId: debtFId,
                              operation: SyncOperation.create,
                              data: debtData,
                            );
                          }
                          
                          // Tạo PaymentIntent để trả nợ sau (CHỜ CHI)
                          final intent = PaymentIntent(
                            id: 'pi_part_debt_${DateTime.now().millisecondsSinceEpoch}_$partName',
                            type: PaymentIntentType.supplierDebt,
                            amount: totalCost,
                            description: 'Trả nợ nhập linh kiện: $partName - $supplierName',
                            referenceId: debtFId,
                            referenceType: 'part_debt',
                            personName: supplierName,
                            createdBy: user?.uid ?? 'unknown',
                            createdAt: DateTime.now().millisecondsSinceEpoch,
                            metadata: {
                              'partName': partName,
                              'quantity': qty,
                              'debtId': debtId,
                              'debtFirestoreId': debtFId,
                              'debtType': 'SHOP_OWES',
                            },
                          );
                          await PaymentIntentService.createIntent(intent);
                          debugPrint('💳 Created PaymentIntent for part debt: ${intent.id}');
                          EventBus().emit('debts_changed');
                        } else {
                          // TIỀN MẶT/CHUYỂN KHOẢN → Tạo expense record TRỰC TIẾP
                          final expenseFirestoreId = 'exp_part_${DateTime.now().millisecondsSinceEpoch}_$partName';
                          final expenseData = {
                            'firestoreId': expenseFirestoreId,
                            'title': 'Nhập linh kiện: $partName',
                            'description': 'NCC: $supplierName - SL: $qty',
                            'amount': totalCost,
                            'category': 'NHẬP LINH KIỆN',
                            'date': DateTime.now().millisecondsSinceEpoch,
                            'note': 'Nhập từ kho linh kiện - $paymentMethod',
                            'paymentMethod': paymentMethod,
                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                            'shopId': shopId,
                            'isSynced': 0,
                          };
                          final expenseId = await db.insertExpense(expenseData);
                          if (expenseId > 0) {
                            await SyncOrchestrator().enqueue(
                              entityType: SyncEntityType.expense,
                              entityId: expenseId,
                              firestoreId: expenseFirestoreId,
                              operation: SyncOperation.create,
                              data: expenseData,
                            );
                          }
                          
                          // Log vào financial_activity_log để hiện trong Nhật ký tài chính
                          await FinancialActivityService.logPurchase(
                            firestoreId: expenseFirestoreId,
                            amount: totalCost,
                            productName: partName,
                            quantity: qty,
                            paymentMethod: paymentMethod,
                            supplierName: supplierName,
                          );
                          
                          EventBus().emit('expenses_changed');
                          debugPrint('PartsInventory: Created expense for $paymentMethod: $totalCost');
                        }
                      }
                    } else {
                      final originalDate = part['createdAt'] as int? ?? now;
                      final canEditDirectly =
                          await AdjustmentService.canEditDirectly(originalDate);
                      final oldCost = part['cost'] as int? ?? 0;
                      final oldQty = part['quantity'] as int? ?? 0;
                      final oldPaymentMethod =
                          part['paymentMethod'] as String? ?? 'TIỀN MẶT';
                      final partId = part['id'] as int;
                      
                      // Tính toán chênh lệch để cập nhật expense/debt
                      final oldTotalCost = oldCost * oldQty;
                      final newTotalCost = cost * qty;
                      final costDifference = newTotalCost - oldTotalCost;

                      if (canEditDirectly) {
                        data['isSynced'] = 0;
                        await (await db.database).update(
                          'repair_parts',
                          data,
                          where: 'id = ?',
                          whereArgs: [partId],
                        );

                        // Queue sync update to cloud via SyncOrchestrator
                        final partFirestoreId = part['firestoreId'] as String?;
                        if (partFirestoreId != null &&
                            partFirestoreId.isNotEmpty) {
                          await SyncOrchestrator().enqueue(
                            entityType: SyncEntityType.repairPart,
                            entityId: partId,
                            firestoreId: partFirestoreId,
                            operation: SyncOperation.update,
                            data: {
                              ...data,
                              'id': partId,
                              'firestoreId': partFirestoreId,
                            },
                          );
                        }

                        // *** FIX: Cập nhật expense/debt khi sửa số lượng ***
                        if (costDifference != 0) {
                          final database = await db.database;
                          
                          if (oldPaymentMethod == 'CÔNG NỢ') {
                            // Tìm và cập nhật debt liên quan
                            final debts = await database.query(
                              'debts',
                              where: 'relatedPartId = ?',
                              whereArgs: [partId],
                            );
                            if (debts.isNotEmpty) {
                              final debtId = debts.first['id'] as int;
                              final debtFirestoreId = debts.first['firestoreId'] as String?;
                              await database.update(
                                'debts',
                                {
                                  'totalAmount': newTotalCost,
                                  'note': 'Nhập linh kiện: $partName x$qty',
                                  'updatedAt': now,
                                  'isSynced': 0,
                                },
                                where: 'id = ?',
                                whereArgs: [debtId],
                              );
                              // Enqueue debt sync
                              if (debtFirestoreId != null && debtFirestoreId.isNotEmpty) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.debt,
                                  entityId: debtId,
                                  firestoreId: debtFirestoreId,
                                  operation: SyncOperation.update,
                                );
                              }
                              EventBus().emit('debts_changed');
                            }
                          } else {
                            // Tìm và cập nhật expense liên quan
                            final expenses = await database.query(
                              'expenses',
                              where: 'relatedPartId = ?',
                              whereArgs: [partId],
                            );
                            if (expenses.isNotEmpty) {
                              final expenseId = expenses.first['id'] as int;
                              final expenseFirestoreId = expenses.first['firestoreId'] as String?;
                              final supplierName = _getSupplierName(selectedSupplierId);
                              await database.update(
                                'expenses',
                                {
                                  'amount': newTotalCost,
                                  'description': 'Nhập linh kiện: $partName x$qty${selectedSupplierId != null ? " từ $supplierName" : ""}',
                                  'updatedAt': now,
                                  'isSynced': 0,
                                },
                                where: 'id = ?',
                                whereArgs: [expenseId],
                              );
                              // Enqueue expense sync
                              if (expenseFirestoreId != null && expenseFirestoreId.isNotEmpty) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.expense,
                                  entityId: expenseId,
                                  firestoreId: expenseFirestoreId,
                                  operation: SyncOperation.update,
                                );
                              }
                              EventBus().emit('expenses_changed');
                            }
                          }
                          
                          // Cập nhật thống kê nhà cung cấp nếu có
                          if (selectedSupplierId != null) {
                            await db.updateSupplierStats(
                              selectedSupplierId!,
                              costDifference,
                              qty - oldQty,
                            );
                            EventBus().emit('suppliers_changed');
                          }
                        }

                        await AuditService.logAction(
                          action: 'PART_UPDATE',
                          entityType: 'repair_part',
                          entityId: partId.toString(),
                          summary: 'Cập nhật linh kiện: $partName',
                          payload: {
                            'partName': partName,
                            'quantity': qty,
                            'cost': cost,
                            'price': price,
                            'oldQuantity': oldQty,
                            'oldCost': oldCost,
                            'costDifference': costDifference,
                          },
                        );
                      } else {
                        final reason = await _showAdjustmentReasonDialog(
                          context,
                        );
                        if (reason == null || reason.isEmpty) return;

                        if (cost != oldCost) {
                          final result = await AdjustmentService.adjustPartCost(
                            partId: partId,
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
                                backgroundColor: result.success
                                    ? Colors.green
                                    : Colors.red,
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
                          whereArgs: [partId],
                        );

                        // Queue sync update to cloud via SyncOrchestrator
                        final partFirestoreId = part['firestoreId'] as String?;
                        if (partFirestoreId != null &&
                            partFirestoreId.isNotEmpty) {
                          await SyncOrchestrator().enqueue(
                            entityType: SyncEntityType.repairPart,
                            entityId: partId,
                            firestoreId: partFirestoreId,
                            operation: SyncOperation.update,
                            data: {
                              'id': partId,
                              'firestoreId': partFirestoreId,
                              'partName': partName,
                              'compatibleModels': modelC.text.toUpperCase(),
                              'cost': cost,
                              'price': price,
                              'quantity': qty,
                              'supplierId': selectedSupplierId,
                              'paymentMethod': paymentMethod,
                              'updatedAt': now,
                            },
                          );
                        }

                        // *** FIX (locked day): Cập nhật expense/debt khi sửa số lượng qua adjustment ***
                        // Nếu số lượng thay đổi, tạo bút toán điều chỉnh
                        if (qty != oldQty && costDifference != 0) {
                          final database = await db.database;
                          
                          if (oldPaymentMethod == 'CÔNG NỢ') {
                            // Tìm và cập nhật debt liên quan
                            final debts = await database.query(
                              'debts',
                              where: 'relatedPartId = ?',
                              whereArgs: [partId],
                            );
                            if (debts.isNotEmpty) {
                              final debtId = debts.first['id'] as int;
                              final debtFirestoreId = debts.first['firestoreId'] as String?;
                              await database.update(
                                'debts',
                                {
                                  'totalAmount': newTotalCost,
                                  'note': 'Nhập linh kiện: $partName x$qty (điều chỉnh: $reason)',
                                  'updatedAt': now,
                                  'isSynced': 0,
                                },
                                where: 'id = ?',
                                whereArgs: [debtId],
                              );
                              if (debtFirestoreId != null && debtFirestoreId.isNotEmpty) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.debt,
                                  entityId: debtId,
                                  firestoreId: debtFirestoreId,
                                  operation: SyncOperation.update,
                                );
                              }
                              EventBus().emit('debts_changed');
                            }
                          } else {
                            // Tìm và cập nhật expense liên quan
                            final expenses = await database.query(
                              'expenses',
                              where: 'relatedPartId = ?',
                              whereArgs: [partId],
                            );
                            if (expenses.isNotEmpty) {
                              final expenseId = expenses.first['id'] as int;
                              final expenseFirestoreId = expenses.first['firestoreId'] as String?;
                              final supplierName = _getSupplierName(selectedSupplierId);
                              await database.update(
                                'expenses',
                                {
                                  'amount': newTotalCost,
                                  'description': 'Nhập linh kiện: $partName x$qty (điều chỉnh: $reason)${selectedSupplierId != null ? " từ $supplierName" : ""}',
                                  'updatedAt': now,
                                  'isSynced': 0,
                                },
                                where: 'id = ?',
                                whereArgs: [expenseId],
                              );
                              if (expenseFirestoreId != null && expenseFirestoreId.isNotEmpty) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.expense,
                                  entityId: expenseId,
                                  firestoreId: expenseFirestoreId,
                                  operation: SyncOperation.update,
                                );
                              }
                              EventBus().emit('expenses_changed');
                            }
                          }
                          
                          // Log điều chỉnh số lượng
                          await AuditService.logAction(
                            action: 'PART_QTY_ADJUST',
                            entityType: 'repair_part',
                            entityId: partId.toString(),
                            summary: 'Điều chỉnh số lượng linh kiện: $partName ($oldQty -> $qty)',
                            payload: {
                              'partName': partName,
                              'oldQuantity': oldQty,
                              'newQuantity': qty,
                              'costDifference': costDifference,
                              'reason': reason,
                            },
                          );
                          
                          // Cập nhật thống kê nhà cung cấp nếu có
                          if (selectedSupplierId != null) {
                            await db.updateSupplierStats(
                              selectedSupplierId!,
                              costDifference,
                              qty - oldQty,
                            );
                            EventBus().emit('suppliers_changed');
                          }
                        }
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
        content: Text(
          'Bạn có chắc muốn xóa $count linh kiện đã chọn?\n\nHành động này không thể hoàn tác.',
        ),
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
        SnackBar(content: Text('Lỗi khi xóa: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool allSelected =
        _filteredParts.isNotEmpty &&
        _selectedIds.length == _filteredParts.length;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        flexibleSpace: _isSelectionMode ? null : Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        title: _isSelectionMode
            ? Text(
                '${_selectedIds.length} đã chọn',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline3.fontSize,
                ),
              )
            : Text(
                "KHO LINH KIỆN SỬA CHỮA",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize),
              ),
        backgroundColor: _isSelectionMode ? Colors.red.shade700 : Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    itemCount: _filteredParts.length,
                    itemBuilder: (ctx, i) {
                      final p = _filteredParts[i];
                      final int? partId = p['id'] as int?;
                      final bool isSelected =
                          partId != null && _selectedIds.contains(partId);
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: AppTextStyles.headline4.fontSize,
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
                              ? (partId != null
                                    ? () => _toggleSelection(partId)
                                    : null)
                              : (_isAdmin
                                    ? () => _showAddPartDialog(part: p)
                                    : null),
                          onLongPress:
                              !_isSelectionMode && _isAdmin && partId != null
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
                ? GradientFab.orange(
                    onPressed: () => _showAddPartDialog(),
                    icon: Icons.add,
                    label: 'Nhập LK',
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
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('HỦY'),
          ),
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
