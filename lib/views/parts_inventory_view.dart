import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_write_helper.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';
import 'dart:async';
import '../services/event_bus.dart';
import '../services/audit_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/payment_intent_service.dart';
import '../services/financial_activity_service.dart';
import '../models/payment_intent_model.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/gradient_fab.dart';
import '../theme/app_text_styles.dart';
import '../core/utils/money_utils.dart';
import '../models/shop_settings_model.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../utils/vietnamese_utils.dart';
import '../services/supplier_service.dart';
import 'supplier_form_view.dart';

/// Widget content để embed vào InventoryView tab - Phiên bản chuyên nghiệp
class PartsInventoryViewContent extends StatefulWidget {
  const PartsInventoryViewContent({super.key});
  @override
  State<PartsInventoryViewContent> createState() =>
      _PartsInventoryViewContentState();
}

class _PartsInventoryViewContentState extends State<PartsInventoryViewContent> {
  final db = DBHelper();
  // _supplierService reserved for future supplier operations
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _filteredParts = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  final searchCtrl = TextEditingController();
  String _searchQuery = '';
  // ignore: unused_field
  bool _isAdmin =
      false; // Set in _loadPermissions, reserved for UI restrictions
  bool _canViewCostPrice = false; // Phân quyền xem giá vốn
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};
  bool _showOutOfStock = false;
  String _sortBy = 'name'; // name, quantity, cost
  StreamSubscription? _eventBusSub;
  Timer? _partsRefreshDebounce;

  // Dynamic terminology
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

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
  static const Color _primaryColor = Color(0xFF0068FF); // Zalo Blue
  static const Color _gradientStart = Color(0xFF0068FF);
  static const Color _gradientEnd = Color(0xFF0084FF);
  final Color _backgroundColor = const Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _loadPermissions();
    _refreshParts();
    _loadSuppliers();
    // Lắng nghe events: parts_changed, stock_entries_changed, dataRefresh, shopChanged
    _eventBusSub = EventBus().stream
        .where(
          (e) =>
              e == 'parts_changed' ||
              e == 'stock_entries_changed' ||
              e == EventBus.dataRefresh ||
              e == EventBus.shopChanged,
        )
        .listen((event) {
          if (!mounted) return;
          debugPrint(
            '🔧 [PartsInventoryView] Nhận event "$event" → refresh local DB',
          );
          _partsRefreshDebounce?.cancel();
          _partsRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) _refreshParts();
          });
        });
    // Scroll controller listener for scroll-to-top button
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
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
    _partsRefreshDebounce?.cancel();
    _eventBusSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShopSettings() async {
    final settings = await CategoryService().getShopSettings();
    if (mounted) {
      setState(() => _shopSettings = settings);
    }
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewParts'] ?? false;
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
    });
  }

  Future<void> _refreshParts() async {
    if (!mounted) return;
    debugPrint('🔧 [PartsInventoryView] Bắt đầu tải linh kiện từ local DB...');
    setState(() => _isLoading = true);
    try {
      var data = await db.getAllParts();
      debugPrint(
        '🔧 [PartsInventoryView] Local DB trả về ${data.length} linh kiện',
      );

      // Nếu local DB trống, thử sửa bản ghi bị stuck-deleted và đọc lại
      if (data.isEmpty) {
        final fixed = await db.fixStuckDeletedRepairParts();
        if (fixed > 0) {
          debugPrint(
            '🔧 [PartsInventoryView] Đã sửa $fixed linh kiện stuck-deleted, đọc lại...',
          );
          data = await db.getAllParts();
        }
      }

      // Nếu vẫn trống sau fix: SyncService sẽ tự đồng bộ từ cloud theo chu kỳ polling.
      // Không đọc Firestore trực tiếp tại đây để đảm bảo Single Source of Truth = local DB.
      if (data.isEmpty) {
        debugPrint(
          '🔧 [PartsInventoryView] Local DB trống — chờ SyncService đồng bộ từ cloud',
        );
      }

      if (!mounted) return;
      setState(() {
        _parts = data;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('🔧 [PartsInventoryView] Lỗi tải linh kiện: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await SupplierService().getSuppliers();
      if (suppliers.isNotEmpty) {
        if (!mounted) return;
        setState(() => _suppliers = suppliers.map((s) => s.toMap()).toList());
        return;
      }
    } catch (e) {
      debugPrint(
        'PartsInventoryViewContent: Error loading suppliers via service: $e',
      );
    }
    // Fallback: raw local DB (no shopId filter) – always shows local data
    try {
      final s = await db.getSuppliers();
      if (!mounted) return;
      setState(() => _suppliers = s);
    } catch (e) {
      debugPrint(
        'PartsInventoryViewContent: Error loading suppliers from DB: $e',
      );
    }
  }

  void _applyFilter() {
    var filtered = _parts.where((p) {
      // Lọc theo search (hỗ trợ có dấu và không dấu)
      final matchSearch =
          _searchQuery.isEmpty ||
          VietnameseUtils.containsVietnamese(
            p['partName']?.toString() ?? '',
            _searchQuery,
          ) ||
          VietnameseUtils.containsVietnamese(
            p['compatibleModels']?.toString() ?? '',
            _searchQuery,
          );

      // Lọc hết hàng
      final qty = p['quantity'] as int? ?? 0;
      final matchStock = _showOutOfStock || qty > 0;

      // Lọc theo model category (navigation)
      final matchCategory =
          _selectedModelCategory == null ||
          (p['compatibleModels']?.toString().toUpperCase().contains(
                _selectedModelCategory!,
              ) ??
              false) ||
          (p['partName']?.toString().toUpperCase().contains(
                _selectedModelCategory!,
              ) ??
              false);

      return matchSearch && matchStock && matchCategory;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'quantity':
          return (b['quantity'] as int? ?? 0).compareTo(
            a['quantity'] as int? ?? 0,
          );
        case 'cost':
          final costA = (a['cost'] as int? ?? 0) * (a['quantity'] as int? ?? 0);
          final costB = (b['cost'] as int? ?? 0) * (b['quantity'] as int? ?? 0);
          return costB.compareTo(costA);
        default:
          return (a['partName'] ?? '').toString().compareTo(
            (b['partName'] ?? '').toString(),
          );
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
    final partsWithStock = _showOutOfStock
        ? _parts
        : _parts.where((p) => (p['quantity'] as int? ?? 0) > 0).toList();
    final totalTypes = partsWithStock.length;
    final totalQty = partsWithStock.fold<int>(
      0,
      (s, p) => s + (p['quantity'] as int? ?? 0),
    );
    final totalCost = partsWithStock.fold<int>(
      0,
      (s, p) => s + (p['cost'] as int? ?? 0) * (p['quantity'] as int? ?? 0),
    );
    final lowStockCount = _parts
        .where(
          (p) =>
              (p['quantity'] as int? ?? 0) > 0 &&
              (p['quantity'] as int? ?? 0) <= 2,
        )
        .length;

    return Container(
      color: _backgroundColor,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : Stack(
              children: [
                Column(
                  children: [
                    // Summary Card - đồng bộ style với Kho chính
                    _buildSummaryCard(
                      totalTypes,
                      totalQty,
                      totalCost,
                      lowStockCount,
                    ),

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
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                                itemCount: _filteredParts.length,
                                itemBuilder: (ctx, i) =>
                                    _buildPartCard(_filteredParts[i], i + 1),
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
                      child: const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white,
                      ),
                    ),
                  ),
                // Add new part FAB
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'addPartFAB',
                    onPressed: _showAddNewPartDialog,
                    backgroundColor: _primaryColor,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text(
                      'Thêm ${_terms.category3}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                  fontSize: 14,
                  fontWeight: _selectedModelCategory == null
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: _selectedModelCategory == null
                      ? Colors.white
                      : Colors.black87,
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
                  color: _selectedModelCategory == null
                      ? _primaryColor
                      : Colors.grey.shade300,
                ),
              ),
            ),
          ),
          // Model category chips
          ..._modelCategories.map((category) {
            final isSelected = _selectedModelCategory == category;
            // Count parts matching this category
            final count = _parts
                .where(
                  (p) =>
                      (p['compatibleModels']?.toString().toUpperCase().contains(
                            category,
                          ) ??
                          false) ||
                      (p['partName']?.toString().toUpperCase().contains(
                            category,
                          ) ??
                          false),
                )
                .length;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  '$category ($count)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
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
          if (_canViewCostPrice) ...[
            _verticalDivider(),
            _summaryItem(
              Icons.account_balance_wallet,
              MoneyUtils.formatCompact(cost),
              'Giá vốn',
            ),
          ],
          if (lowStock > 0) ...[
            _verticalDivider(),
            _summaryItem(
              Icons.warning_amber,
              '$lowStock',
              'Sắp hết',
              Colors.amber,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(
    IconData icon,
    String value,
    String label, [
    Color? iconColor,
  ]) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor ?? Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTextStyles.headline3.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: AppTextStyles.caption.fontSize,
            ),
          ),
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
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                  ),
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
                  hintText: 'Tìm ${_terms.category3}, model...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: AppTextStyles.headline5.fontSize,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: _primaryColor,
                    size: 20,
                  ),
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
              if (_canViewCostPrice)
                _sortMenuItem('cost', 'Giá vốn', Icons.attach_money),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(
    String value,
    String label,
    IconData icon,
  ) {
    final isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? _primaryColor : Colors.grey),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? _primaryColor : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
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
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: selected ? _primaryColor : Colors.grey,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
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
    final updatedAt = p['updatedAt'] as int?;
    final createdAt = p['createdAt'] as int?;
    final isLow = qty > 0 && qty <= 2;
    final isOut = qty == 0;
    final supplierName = _getSupplierName(p['supplierId'] as int?);
    final dateMs = updatedAt ?? createdAt;
    final dateText = dateMs != null
        ? DateFormat(
            'dd/MM/yy',
          ).format(DateTime.fromMillisecondsSinceEpoch(dateMs))
        : null;
    final isAltRow = index.isEven;

    // Color coding
    final bgColor = isOut
        ? Colors.grey.shade50
        : (isLow
              ? Colors.orange.shade50
              : (isAltRow ? const Color(0xFFF7FAFF) : Colors.white));
    final borderColor = isSelected
        ? _primaryColor
        : (isOut
              ? Colors.grey.shade300
              : (isLow ? Colors.orange.shade200 : Colors.grey.shade200));

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: isSelected ? 3 : 0.5,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
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
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // Leading: index + quantity badge
              if (_isSelectionMode)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(id),
                    activeColor: _primaryColor,
                  ),
                )
              else
                Column(
                  children: [
                    Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    Container(
                      width: 38,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isOut
                            ? Colors.grey.shade200
                            : isLow
                            ? Colors.orange.withOpacity(0.15)
                            : _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'x$qty',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isOut
                                ? Colors.grey
                                : isLow
                                ? Colors.orange
                                : _primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 10),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Name + status badge
                    Row(
                      children: [
                        const Text('🔧 ', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Text(
                            p['partName'] ?? 'N/A',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isOut ? Colors.grey : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLow && !isOut)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SẮP HẾT',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isOut)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'HẾT HÀNG',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Row 2: Compatible models
                    if ((p['compatibleModels'] ?? '').toString().isNotEmpty)
                      Text(
                        'Dùng cho: ${p['compatibleModels']}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    // Row 3: Info chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_canViewCostPrice)
                          _infoChip(
                            Icons.attach_money,
                            'Vốn: ${MoneyUtils.formatCompact(cost)}',
                            Colors.green.shade700,
                          ),
                        _infoChip(
                          Icons.sell,
                          'Bán: ${MoneyUtils.formatCompact(price)}',
                          Colors.red.shade600,
                        ),
                        if (supplierName != 'Không xác định')
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: _infoChip(
                              Icons.local_shipping,
                              supplierName,
                              _primaryColor,
                            ),
                          ),
                      ],
                    ),
                    if (dateText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateText,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Trailing: quick stock-in button
              InkWell(
                onTap: () => _showQuickStockInDialog(p),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_shopping_cart,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      Text(
                        MoneyUtils.formatCompact(price),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
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
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.build_circle_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'Không tìm thấy ${_terms.category3}'
                : 'Chưa có ${_terms.category3} trong kho',
            style: TextStyle(
              fontSize: AppTextStyles.headline3.fontSize,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Thử từ khóa khác'
                : 'Nhấn "THÊM ${_terms.category3.toUpperCase()}" để bắt đầu',
            style: TextStyle(
              fontSize: AppTextStyles.headline5.fontSize,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  /// Quick stock-in dialog for repair parts - nhập thêm số lượng nhanh
  void _showQuickStockInDialog(Map<String, dynamic> p) {
    final partName = p['partName'] as String? ?? '';
    final currentQty = p['quantity'] as int? ?? 0;
    final currentCost = p['cost'] as int? ?? 0;
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(
      text: currentCost > 0 ? CurrencyTextField.formatDisplay(currentCost) : '',
    );
    String paymentMethod = 'TIỀN MẶT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.add_shopping_cart,
                  color: Colors.green.shade700,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NHẬP THÊM',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Part info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text('🔧', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Tồn kho hiện tại: $currentQty',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Quantity
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Số lượng nhập thêm',
                      prefixIcon: const Icon(Icons.add_circle_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cost price
                  CurrencyTextField(
                    controller: costCtrl,
                    label: 'Giá nhập (VNĐ)',
                    icon: Icons.attach_money,
                  ),
                  const SizedBox(height: 12),
                  // Payment method
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: InputDecoration(
                      labelText: 'Phương thức thanh toán',
                      prefixIcon: const Icon(Icons.payment),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'TIỀN MẶT',
                        child: Text('Tiền mặt'),
                      ),
                      DropdownMenuItem(
                        value: 'CHUYỂN KHOẢN',
                        child: Text('Chuyển khoản'),
                      ),
                      DropdownMenuItem(
                        value: 'CÔNG NỢ',
                        child: Text('Công nợ'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => paymentMethod = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('HỦY'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'NHẬP KHO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  CurrencyTextField.finalizeAll();
                  final addQty = int.tryParse(qtyCtrl.text) ?? 0;
                  if (addQty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Vui lòng nhập số lượng hợp lệ'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final cost = CurrencyTextField.parseValueWithMultiply(
                    costCtrl.text,
                  );
                  Navigator.pop(ctx);
                  await _processQuickPartStockIn(
                    p,
                    addQty,
                    cost,
                    paymentMethod,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processQuickPartStockIn(
    Map<String, dynamic> p,
    int addQty,
    int cost,
    String paymentMethod,
  ) async {
    try {
      final partId = p['id'] as int;
      final partName = p['partName'] as String? ?? '';
      final currentQty = p['quantity'] as int? ?? 0;
      final newQty = currentQty + addQty;
      final firestoreId = p['firestoreId'] as String?;
      final supplierId = p['supplierId'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;
      final shopId = await UserService.getCurrentShopId();

      // Update local DB quantity
      await db.updatePart(partId, {
        'quantity': newQty,
        'cost': cost > 0 ? cost : (p['cost'] as int? ?? 0),
        'updatedAt': now,
      });

      // Sync to Firestore immediately
      if (firestoreId != null && firestoreId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('repair_parts')
              .doc(firestoreId)
              .update({
                'quantity': newQty,
                'cost': cost > 0 ? cost : (p['cost'] as int? ?? 0),
                'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
              });
        } catch (e) {
          debugPrint('⚠️ Quick stock-in Firestore sync error: $e');
        }
      }

      // Log audit
      final supplierName = _getSupplierName(supplierId);
      await AuditService.logAction(
        action: 'PART_IMPORT',
        entityType: 'repair_part',
        entityId: firestoreId ?? partId.toString(),
        summary:
            'Nhập thêm ${_terms.category3}: $partName +$addQty (${NumberFormat('#,###').format(cost * addQty)}đ) - $paymentMethod',
        payload: {
          'partName': partName,
          'addQuantity': addQty,
          'newQuantity': newQty,
          'cost': cost,
          'totalCost': cost * addQty,
          'paymentMethod': paymentMethod,
          'supplierName': supplierName,
        },
      );

      // Record financial activity
      if (cost > 0) {
        try {
          final supplierNameForActivity = _getSupplierName(supplierId);
          final expFId = 'exp_part_${now}_$partName';
          await FinancialActivityService.logPurchase(
            firestoreId: expFId,
            amount: cost * addQty,
            productName: partName,
            quantity: addQty,
            paymentMethod: paymentMethod,
            supplierName: supplierNameForActivity,
          );
        } catch (e) {
          debugPrint('⚠️ Financial activity record error: $e');
        }
      }

      // Record supplier import history if applicable
      if (supplierId != null && cost > 0) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          final userName = user?.email?.split('@').first.toUpperCase() ?? 'NV';
          await db.insertSupplierImportHistory({
            'supplierId': supplierId,
            'supplierName': supplierName,
            'productName': partName,
            'productBrand': _terms.category3.toUpperCase(),
            'productModel': p['compatibleModels'] ?? '',
            'quantity': addQty,
            'costPrice': cost,
            'totalAmount': cost * addQty,
            'paymentMethod': paymentMethod,
            'importDate': now,
            'importedBy': userName,
            'notes': 'Nhập thêm vào kho ${_terms.category3}',
            'shopId': shopId,
            'isSynced': 0,
          });
        } catch (e) {
          debugPrint('⚠️ Supplier import history error: $e');
        }
      }

      // Refresh and notify
      _refreshParts();
      EventBus().emit('parts_changed');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã nhập thêm $addQty $partName (tổng: $newQty)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Quick part stock-in error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPartDetailSheet(Map<String, dynamic> p) {
    final qty = p['quantity'] as int? ?? 0;
    final cost = p['cost'] as int? ?? 0;
    final price = p['price'] as int? ?? 0;
    final totalCost = cost * qty;
    final supplierName = _getSupplierName(p['supplierId'] as int?);
    final createdAt = p['createdAt'] as int?;
    // updatedAt tracked but not displayed in current UI

    showAppBottomSheet(
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
          padding: const EdgeInsets.all(12),
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
                    child: const Icon(
                      Icons.build_circle,
                      color: _primaryColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['partName'] ?? 'N/A',
                          style: TextStyle(
                            fontSize: AppTextStyles.headline2.fontSize,
                            fontWeight: FontWeight.bold,
                          ),
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
              const SizedBox(height: 10),
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
                    if (_canViewCostPrice) ...[
                      const Divider(height: 20),
                      _detailRow(
                        'Giá vốn/sp',
                        '${NumberFormat('#,###').format(cost)}đ',
                        Icons.attach_money,
                      ),
                    ],
                    const Divider(height: 20),
                    _detailRow(
                      'Giá bán/sp',
                      '${NumberFormat('#,###').format(price)}đ',
                      Icons.sell,
                    ),
                    if (_canViewCostPrice) ...[
                      const Divider(height: 20),
                      _detailRow(
                        'Tổng vốn tồn',
                        '${NumberFormat('#,###').format(totalCost)}đ',
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ],
                    const Divider(height: 20),
                    _detailRow('Nhà cung cấp', supplierName, Icons.store),
                    if (createdAt != null) ...[
                      const Divider(height: 20),
                      _detailRow(
                        'Ngày nhập',
                        DateFormat('dd/MM/yyyy').format(
                          DateTime.fromMillisecondsSinceEpoch(createdAt),
                        ),
                        Icons.calendar_today,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showEditPartDialog(p);
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
                        _showQuickStockInDialog(p);
                      },
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Nhập thêm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Delete button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Xác nhận xóa'),
                        content: Text(
                          'Bạn có chắc muốn xóa "${p['partName']}"?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('HỦY'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text(
                              'XÓA',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _deleteSinglePart(p);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Xóa linh kiện',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    IconData icon, [
    Color? valueColor,
  ]) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  /// Edit part dialog - chỉ sửa thông tin (tên, dòng máy, giá bán)
  void _showEditPartDialog(Map<String, dynamic> p) {
    final nameC = TextEditingController(text: p['partName']);
    final modelC = TextEditingController(text: p['compatibleModels']);
    final priceC = TextEditingController(
      text: CurrencyTextField.formatDisplay(p['price'] ?? 0),
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("SỬA ${_terms.category3.toUpperCase()}"),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValidatedTextField(
                  controller: nameC,
                  label: "Tên ${_terms.category3}",
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
                // Info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Chỉ sửa thông tin & giá bán. Muốn nhập thêm số lượng → dùng nút NHẬP THÊM.',
                          style: TextStyle(
                            color: Colors.blue,
                            height: 1.3,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Read-only cost
                if (_canViewCostPrice)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_money,
                          size: 18,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Giá vốn: ${NumberFormat('#,###').format(p['cost'] ?? 0)}đ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                CurrencyTextField(
                  controller: priceC,
                  label: "Giá bán",
                  icon: Icons.sell,
                ),
                const SizedBox(height: 8),
                // Read-only quantity
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2,
                        size: 18,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tồn kho: ${p['quantity'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
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
              CurrencyTextField.finalizeAll();
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                final partId = p['id'] as int;
                final partName = nameC.text.toUpperCase();
                final price = CurrencyTextField.parseValueWithMultiply(
                  priceC.text,
                );
                final now = DateTime.now().millisecondsSinceEpoch;

                final editData = {
                  'partName': partName,
                  'compatibleModels': modelC.text.toUpperCase(),
                  'price': price,
                  'updatedAt': now,
                  'isSynced': 0,
                };
                await (await db.database).update(
                  'repair_parts',
                  editData,
                  where: 'id = ?',
                  whereArgs: [partId],
                );

                // Sync to cloud
                final firestoreId = p['firestoreId'] as String?;
                if (firestoreId != null && firestoreId.isNotEmpty) {
                  await SyncOrchestrator().enqueue(
                    entityType: SyncEntityType.repairPart,
                    entityId: partId,
                    firestoreId: firestoreId,
                    operation: SyncOperation.update,
                    data: {
                      ...editData,
                      'id': partId,
                      'firestoreId': firestoreId,
                    },
                  );
                }

                await AuditService.logAction(
                  action: 'PART_INFO_UPDATE',
                  entityType: 'repair_part',
                  entityId: partId.toString(),
                  summary: 'Cập nhật ${_terms.category3}: $partName',
                  payload: {
                    'partName': partName,
                    'price': price,
                    'oldPrice': p['price'],
                  },
                );

                if (!mounted) return;
                Navigator.pop(ctx);
                _refreshParts();
                EventBus().emit('parts_changed');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Đã cập nhật $partName'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("LƯU"),
          ),
        ],
      ),
    );
  }

  /// Add new part dialog - nhập linh kiện mới đầy đủ
  void _showAddNewPartDialog() {
    final nameC = TextEditingController();
    final modelC = TextEditingController();
    final costC = TextEditingController();
    final priceC = TextEditingController();
    final qtyC = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    int? selectedSupplierId;
    String paymentMethod = 'TIỀN MẶT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text("NHẬP ${_terms.category3.toUpperCase()} MỚI"),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValidatedTextField(
                      controller: nameC,
                      label: "Tên ${_terms.category3} (VD: PIN IPHONE 11)",
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
                    // Supplier
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
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(child: Text('Chưa có nhà cung cấp.')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) => const SupplierFormView(),
                                    ),
                                  );
                                  if (result == true) {
                                    await _loadSuppliers();
                                    setS(() {});
                                  }
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('THÊM NCC MỚI'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SupplierSearchField(
                            suppliers: _suppliers,
                            selectedSupplierId: selectedSupplierId,
                            onChanged: (v) =>
                                setS(() => selectedSupplierId = v),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => const SupplierFormView(),
                                  ),
                                );
                                if (result == true) {
                                  await _loadSuppliers();
                                  setS(() {});
                                }
                              },
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 16,
                              ),
                              label: const Text(
                                'Thêm NCC mới',
                                style: TextStyle(fontSize: 14),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_canViewCostPrice)
                          Expanded(
                            child: CurrencyTextField(
                              controller: costC,
                              label: "Giá vốn",
                              icon: Icons.attach_money,
                            ),
                          ),
                        if (_canViewCostPrice) const SizedBox(width: 10),
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
                          selectedColor: Colors.blue,
                          onSelected: (_) => setS(() => paymentMethod = m),
                        );
                      }).toList(),
                    ),
                    if (paymentMethod == 'CÔNG NỢ' &&
                        selectedSupplierId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
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
                        padding: EdgeInsets.only(top: 8),
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

                    final shopId = await UserService.getCurrentShopId();
                    final firestoreId = 'part_${now}_${partName.hashCode}';
                    final data = {
                      'partName': partName,
                      'compatibleModels': modelC.text.toUpperCase(),
                      'cost': cost,
                      'price': price,
                      'quantity': qty,
                      'supplierId': selectedSupplierId,
                      'paymentMethod': paymentMethod,
                      'updatedAt': now,
                      'firestoreId': firestoreId,
                      'shopId': shopId,
                    };

                    final insertedId = await db.insertPart(data);

                    // Queue sync
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
                          'Nhập ${_terms.category3}: $partName x$qty - ${NumberFormat('#,###').format(cost * qty)}đ ($paymentMethod)',
                      payload: {
                        'partName': partName,
                        'quantity': qty,
                        'cost': cost,
                        'totalCost': cost * qty,
                        'paymentMethod': paymentMethod,
                        'supplierName': supplierName,
                      },
                    );

                    // Supplier import history
                    if (selectedSupplierId != null) {
                      final user = FirebaseAuth.instance.currentUser;
                      final userName =
                          user?.email?.split('@').first.toUpperCase() ?? 'NV';
                      final importHistory = {
                        'supplierId': selectedSupplierId,
                        'supplierName': supplierName,
                        'productName': partName,
                        'productBrand': _terms.category3.toUpperCase(),
                        'productModel': modelC.text.toUpperCase(),
                        'quantity': qty,
                        'costPrice': cost,
                        'totalAmount': cost * qty,
                        'paymentMethod': paymentMethod,
                        'importDate': now,
                        'importedBy': userName,
                        'notes': 'Nhập từ kho ${_terms.category3}',
                        'shopId': shopId,
                        'isSynced': 0,
                      };
                      final importHistoryId = await db
                          .insertSupplierImportHistory(importHistory);
                      if (importHistoryId > 0) {
                        await SyncOrchestrator().enqueueSupplierImportHistory(
                          importHistoryId,
                          firestoreId: importHistory['firestoreId'] as String?,
                          operation: SyncOperation.create,
                        );
                      }
                      await db.updateSupplierStats(
                        selectedSupplierId!,
                        cost * qty,
                        qty,
                      );
                      EventBus().emit('suppliers_changed');
                    }

                    // Financial records
                    final totalCost = cost * qty;
                    if (totalCost > 0) {
                      if (paymentMethod == 'CÔNG NỢ') {
                        final debtFId =
                            'debt_part_${now}_${selectedSupplierId ?? 0}';
                        final debtData = {
                          'firestoreId': debtFId,
                          'personName': supplierName,
                          'phone': '',
                          'totalAmount': totalCost,
                          'paidAmount': 0,
                          'type': 'SHOP_OWES',
                          'status': 'ACTIVE',
                          'createdAt': now,
                          'note': 'Nhập ${_terms.category3}: $partName x$qty',
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
                        EventBus().emit('debts_changed');
                      } else {
                        final expFId = 'exp_part_${now}_$partName';
                        final expenseData = {
                          'firestoreId': expFId,
                          'title': 'Nhập ${_terms.category3}: $partName',
                          'description': 'NCC: $supplierName - SL: $qty',
                          'amount': totalCost,
                          'category': 'NHẬP ${_terms.category3.toUpperCase()}',
                          'date': now,
                          'note':
                              'Nhập từ kho ${_terms.category3} - $paymentMethod',
                          'paymentMethod': paymentMethod,
                          'createdAt': now,
                          'shopId': shopId,
                          'isSynced': 0,
                        };
                        final expenseId = await db.insertExpense(expenseData);
                        if (expenseId > 0) {
                          await SyncOrchestrator().enqueue(
                            entityType: SyncEntityType.expense,
                            entityId: expenseId,
                            firestoreId: expFId,
                            operation: SyncOperation.create,
                            data: expenseData,
                          );
                        }
                        await FinancialActivityService.logPurchase(
                          firestoreId: expFId,
                          amount: totalCost,
                          productName: partName,
                          quantity: qty,
                          paymentMethod: paymentMethod,
                          supplierName: supplierName,
                        );
                        EventBus().emit('expenses_changed');
                      }
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    _refreshParts();
                    EventBus().emit('parts_changed');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Đã nhập $partName x$qty'),
                        backgroundColor: Colors.green,
                      ),
                    );
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

  /// Soft delete single part
  Future<void> _deleteSinglePart(Map<String, dynamic> p) async {
    try {
      final partId = p['id'] as int;
      final database = await db.database;
      await database.update(
        'repair_parts',
        {
          'deleted': 1,
          'isSynced': 0,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [partId],
      );

      await AuditService.logAction(
        action: 'DELETE_PART',
        entityType: 'repair_parts',
        entityId: p['firestoreId'] ?? partId.toString(),
        summary: 'Xóa ${_terms.category3}: ${p['partName']}',
      );

      _refreshParts();
      EventBus().emit('repair_parts_changed');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa ${p['partName']}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteSelectedParts() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc muốn xóa $count ${_terms.category3} đã chọn?\n\nHành động này không thể hoàn tác.',
        ),
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

    try {
      final database = await db.database;
      int deletedCount = 0;

      for (final id in _selectedIds) {
        // Soft delete - đánh dấu deleted để sync lên cloud
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
            summary: 'Xóa ${_terms.category3}: ${part['partName']}',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });

      _refreshParts();
      EventBus().emit('repair_parts_changed');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa $deletedCount ${_terms.category3}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa: $e'), backgroundColor: Colors.red),
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
  // _supplierService reserved for future supplier operations
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _filteredParts = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  final searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;
  bool _canViewCostPrice = false; // Phân quyền xem giá vốn

  StreamSubscription? _eventBusSub2;
  Timer? _partsRefreshDebounce2;

  // Multi-select mode
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  // Theme colors cho màn hình phụ tùng
  final Color _primaryColor = Colors.blue; // Màu chính cho phụ tùng
  final Color _backgroundColor = const Color(0xFFF8FAFF);

  // Dynamic terminology
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _loadPermissions();
    _refreshParts();
    _loadSuppliers();
    // Lắng nghe events inventory cho _PartsInventoryViewState
    _eventBusSub2 = EventBus().stream
        .where(
          (e) =>
              e == 'parts_changed' ||
              e == 'stock_entries_changed' ||
              e == EventBus.dataRefresh ||
              e == EventBus.shopChanged,
        )
        .listen((event) {
          if (!mounted) return;
          debugPrint(
            '🔧 [PartsInventoryView] Nhận event "$event" → refresh local DB',
          );
          _partsRefreshDebounce2?.cancel();
          _partsRefreshDebounce2 = Timer(const Duration(milliseconds: 300), () {
            if (mounted) _refreshParts();
          });
        });
    super.dispose();
  }

  Future<void> _loadShopSettings() async {
    final settings = await CategoryService().getShopSettings();
    if (mounted) {
      setState(() => _shopSettings = settings);
    }
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewParts'] ?? false;
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
    });
  }

  Future<void> _refreshParts() async {
    if (!mounted) return;
    debugPrint('🔧 [PartsInventoryView] Bắt đầu tải linh kiện từ local DB...');
    setState(() => _isLoading = true);
    try {
      var data = await db.getAllParts();
      debugPrint(
        '🔧 [PartsInventoryView] Local DB trả về ${data.length} linh kiện',
      );

      if (data.isEmpty) {
        final fixed = await db.fixStuckDeletedRepairParts();
        if (fixed > 0) {
          debugPrint(
            '🔧 [PartsInventoryView] Đã sửa $fixed linh kiện stuck-deleted, đọc lại...',
          );
          data = await db.getAllParts();
        }
      }

      // Nếu vẫn trống: SyncService sẽ tự đồng bộ từ cloud theo chu kỳ polling.
      if (data.isEmpty) {
        debugPrint(
          '🔧 [PartsInventoryView] Local DB trống — chờ SyncService đồng bộ từ cloud',
        );
      }

      if (!mounted) return;
      setState(() {
        _parts = data;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('🔧 [PartsInventoryView] Lỗi tải linh kiện: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await SupplierService().getSuppliers();
      if (suppliers.isNotEmpty) {
        if (!mounted) return;
        setState(() => _suppliers = suppliers.map((s) => s.toMap()).toList());
        return;
      }
    } catch (e) {
      debugPrint('PartsInventoryView: Error loading suppliers via service: $e');
    }
    // Fallback: raw local DB (no shopId filter) – always shows local data
    try {
      final s = await db.getSuppliers();
      if (!mounted) return;
      setState(() => _suppliers = s);
    } catch (e) {
      debugPrint('PartsInventoryView: Error loading suppliers from DB: $e');
    }
  }

  void _applyFilter() {
    _filteredParts = _parts
        .where(
          (p) => _searchQuery.isEmpty
              ? true
              : VietnameseUtils.containsVietnamese(
                    p['partName']?.toString() ?? '',
                    _searchQuery,
                  ) ||
                  VietnameseUtils.containsVietnamese(
                    p['compatibleModels']?.toString() ?? '',
                    _searchQuery,
                  ),
        )
        .toList();
  }

  String _getSupplierName(int? id) {
    if (id == null) return 'Không xác định';
    final s = _suppliers.firstWhere((e) => e['id'] == id, orElse: () => {});
    return s['name']?.toString() ?? 'Không xác định';
  }

  void _showAddPartDialog({Map<String, dynamic>? part}) {
    final isEdit = part != null;
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

    // Flag tránh đăng ký listener nhiều lần trong StatefulBuilder
    bool _listenerAdded = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (!_listenerAdded) {
            _listenerAdded = true;
            nameC.addListener(() => setS(() {}));
          }
          return AlertDialog(
            title: Text(
              isEdit
                  ? "SỬA ${_terms.category3.toUpperCase()}"
                  : "NHẬP ${_terms.category3.toUpperCase()} MỚI",
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValidatedTextField(
                      controller: nameC,
                      label: "Tên ${_terms.category3} (VD: PIN IPHONE 11)",
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
                    // Edit mode: banner hướng dẫn nhập thêm
                    if (isEdit)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Chỉ sửa thông tin & giá bán. Muốn nhập thêm số lượng → dùng nút NHẬP THÊM ở danh sách.',
                                style: TextStyle(
                                  color: Colors.blue,
                                  height: 1.3,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!isEdit && _suppliers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(child: Text('Chưa có nhà cung cấp.')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) => const SupplierFormView(),
                                    ),
                                  );
                                  if (result == true) {
                                    await _loadSuppliers();
                                    setS(() {});
                                  }
                                },
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('THÊM NCC MỚI'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (!isEdit)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Supplier search & select
                          _SupplierSearchField(
                            suppliers: _suppliers,
                            selectedSupplierId: selectedSupplierId,
                            onChanged: (v) =>
                                setS(() => selectedSupplierId = v),
                          ),
                          const SizedBox(height: 6),
                          // Shortcut to add new supplier
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) => const SupplierFormView(),
                                  ),
                                );
                                if (result == true) {
                                  await _loadSuppliers();
                                  setS(() {});
                                }
                              },
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 16,
                              ),
                              label: const Text(
                                'Thêm NCC mới',
                                style: TextStyle(fontSize: 14),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    // Edit mode: show read-only supplier info
                    if (isEdit && selectedSupplierId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_shipping,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'NCC: ${_getSupplierName(selectedSupplierId)}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_canViewCostPrice)
                          Expanded(
                            child: CurrencyTextField(
                              controller: costC,
                              label: isEdit ? "Giá vốn (không sửa)" : "Giá vốn",
                              icon: Icons.attach_money,
                              enabled: !isEdit,
                            ),
                          ),
                        if (_canViewCostPrice) const SizedBox(width: 10),
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
                    if (isEdit)
                      // Edit mode: show quantity as read-only info
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.inventory_2,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tồn kho: ${part?['quantity'] ?? 0}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
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
                            selectedColor: Colors.blue,
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
                    if (!isEdit && qty <= 0) return;

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
                            'Nhập ${_terms.category3}: $partName x$qty - ${NumberFormat('#,###').format(cost * qty)}đ ($paymentMethod)',
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
                          'productBrand': _terms.category3.toUpperCase(),
                          'productModel': modelC.text.toUpperCase(),
                          'imei': null,
                          'quantity': qty,
                          'costPrice': cost,
                          'totalAmount': cost * qty,
                          'paymentMethod': paymentMethod,
                          'importDate': now,
                          'importedBy': userName,
                          'notes': 'Nhập từ kho ${_terms.category3}',
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

                      // Xử lý thanh toán cho nhập hàng
                      final totalCost = cost * qty;
                      if (totalCost > 0) {
                        final user = FirebaseAuth.instance.currentUser;
                        if (paymentMethod == 'CÔNG NỢ') {
                          // Công nợ NCC → Tạo debt record + PaymentIntent (CHỜ CHI)
                          final debtFId =
                              'debt_part_${DateTime.now().millisecondsSinceEpoch}_${selectedSupplierId ?? 0}';
                          final debtData = {
                            'firestoreId': debtFId,
                            'personName': supplierName,
                            'phone': '',
                            'totalAmount': totalCost,
                            'paidAmount': 0,
                            'type': 'SHOP_OWES',
                            'status': 'ACTIVE',
                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                            'note': 'Nhập ${_terms.category3}: $partName x$qty',
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

                          // Công nợ đã ghi nhận ở bảng debts - không cần PaymentIntent
                          debugPrint(
                            '✅ Part debt recorded (no PaymentIntent needed)',
                          );
                          EventBus().emit('debts_changed');
                        } else {
                          // TIỀN MẶT/CHUYỂN KHOẢN → Tạo expense record TRỰC TIẾP
                          final expenseFirestoreId =
                              'exp_part_${DateTime.now().millisecondsSinceEpoch}_$partName';
                          final expenseData = {
                            'firestoreId': expenseFirestoreId,
                            'title': 'Nhập ${_terms.category3}: $partName',
                            'description': 'NCC: $supplierName - SL: $qty',
                            'amount': totalCost,
                            'category':
                                'NHẬP ${_terms.category3.toUpperCase()}',
                            'date': DateTime.now().millisecondsSinceEpoch,
                            'note':
                                'Nhập từ kho ${_terms.category3} - $paymentMethod',
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
                          debugPrint(
                            'PartsInventory: Created expense for $paymentMethod: $totalCost',
                          );
                        }
                      }
                    } else {
                      // ===== EDIT MODE: Chỉ cập nhật thông tin & giá bán =====
                      // Không cho sửa giá vốn, số lượng, NCC, hình thức TT
                      // Muốn nhập thêm → dùng _showAddStockDialog
                      final partId = part['id'] as int;
                      final editData = {
                        'partName': partName,
                        'compatibleModels': modelC.text.toUpperCase(),
                        'price': price,
                        'updatedAt': now,
                        'isSynced': 0,
                      };
                      await (await db.database).update(
                        'repair_parts',
                        editData,
                        where: 'id = ?',
                        whereArgs: [partId],
                      );

                      // Queue sync update to cloud
                      final partFirestoreId = part['firestoreId'] as String?;
                      if (partFirestoreId != null &&
                          partFirestoreId.isNotEmpty) {
                        await SyncOrchestrator().enqueue(
                          entityType: SyncEntityType.repairPart,
                          entityId: partId,
                          firestoreId: partFirestoreId,
                          operation: SyncOperation.update,
                          data: {
                            ...editData,
                            'id': partId,
                            'firestoreId': partFirestoreId,
                          },
                        );
                      }

                      await AuditService.logAction(
                        action: 'PART_INFO_UPDATE',
                        entityType: 'repair_part',
                        entityId: partId.toString(),
                        summary:
                            'Cập nhật thông tin ${_terms.category3}: $partName',
                        payload: {
                          'partName': partName,
                          'price': price,
                          'oldPrice': part['price'],
                        },
                      );
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
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

  /// Dialog nhập thêm số lượng cho linh kiện đã có - tạo bản ghi tài chính mới ngày hôm nay
  void _showAddStockDialog(Map<String, dynamic> part) {
    final partName = part['partName'] as String? ?? '';
    final currentQty = part['quantity'] as int? ?? 0;
    final currentCost = part['cost'] as int? ?? 0;
    final partId = part['id'] as int;

    final addQtyC = TextEditingController(text: '1');
    final costC = TextEditingController(
      text: CurrencyTextField.formatDisplay(currentCost),
    );
    final formKey = GlobalKey<FormState>();
    int? selectedSupplierId = part['supplierId'] as int?;
    String paymentMethod = 'TIỀN MẶT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text('NHẬP THÊM: $partName'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info hiện tại
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.inventory_2,
                            size: 18,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Tồn kho hiện tại: $currentQty',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Số lượng nhập thêm
                    TextFormField(
                      controller: addQtyC,
                      decoration: const InputDecoration(
                        labelText: 'Số lượng nhập thêm',
                        prefixIcon: Icon(Icons.add_shopping_cart),
                      ),
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim()) ?? 0;
                        if (parsed <= 0) return 'Nhập số lượng hợp lệ (> 0)';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_canViewCostPrice)
                      CurrencyTextField(
                        controller: costC,
                        label: 'Giá vốn / đơn vị',
                        icon: Icons.attach_money,
                      ),
                    const SizedBox(height: 12),
                    // Supplier
                    if (_suppliers.isNotEmpty) ...[
                      _SupplierSearchField(
                        suppliers: _suppliers,
                        selectedSupplierId: selectedSupplierId,
                        onChanged: (v) => setS(() => selectedSupplierId = v),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              ctx,
                              MaterialPageRoute(
                                builder: (_) => const SupplierFormView(),
                              ),
                            );
                            if (result == true) {
                              await _loadSuppliers();
                              setS(() {});
                            }
                          },
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text(
                            'Thêm NCC mới',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Payment method
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
                          selectedColor: Colors.blue,
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
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('HỦY'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  CurrencyTextField.finalizeAll();
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  try {
                    final now = DateTime.now().millisecondsSinceEpoch;
                    final addQty = int.tryParse(addQtyC.text.trim()) ?? 0;
                    if (addQty <= 0) return;
                    final cost = CurrencyTextField.parseValueWithMultiply(
                      costC.text,
                    );
                    final totalCost = cost * addQty;
                    final newQty = currentQty + addQty;
                    final supplierName = _getSupplierName(selectedSupplierId);
                    final shopId = await UserService.getCurrentShopId();

                    // 1. Cập nhật số lượng trong bảng repair_parts
                    await (await db.database).update(
                      'repair_parts',
                      {
                        'quantity': newQty,
                        'cost': cost, // cập nhật giá vốn mới nhất
                        'updatedAt': now,
                        'isSynced': 0,
                      },
                      where: 'id = ?',
                      whereArgs: [partId],
                    );

                    // Queue sync
                    final partFirestoreId = part['firestoreId'] as String?;
                    if (partFirestoreId != null && partFirestoreId.isNotEmpty) {
                      await SyncOrchestrator().enqueue(
                        entityType: SyncEntityType.repairPart,
                        entityId: partId,
                        firestoreId: partFirestoreId,
                        operation: SyncOperation.update,
                        data: {
                          'id': partId,
                          'firestoreId': partFirestoreId,
                          'quantity': newQty,
                          'cost': cost,
                          'updatedAt': now,
                        },
                      );
                    }

                    // 2. Audit log
                    await AuditService.logAction(
                      action: 'PART_ADD_STOCK',
                      entityType: 'repair_part',
                      entityId: partId.toString(),
                      summary:
                          'Nhập thêm ${_terms.category3}: $partName +$addQty (${NumberFormat('#,###').format(totalCost)}đ) - $paymentMethod',
                      payload: {
                        'partName': partName,
                        'addedQuantity': addQty,
                        'newQuantity': newQty,
                        'cost': cost,
                        'totalCost': totalCost,
                        'paymentMethod': paymentMethod,
                        'supplierName': supplierName,
                      },
                    );

                    // 3. Lịch sử nhập hàng NCC
                    if (selectedSupplierId != null) {
                      final user = FirebaseAuth.instance.currentUser;
                      final userName =
                          user?.email?.split('@').first.toUpperCase() ?? 'NV';
                      final importHistory = {
                        'supplierId': selectedSupplierId,
                        'supplierName': supplierName,
                        'productName': partName,
                        'productBrand': _terms.category3.toUpperCase(),
                        'productModel': part['compatibleModels'] ?? '',
                        'imei': null,
                        'quantity': addQty,
                        'costPrice': cost,
                        'totalAmount': totalCost,
                        'paymentMethod': paymentMethod,
                        'importDate': now,
                        'importedBy': userName,
                        'notes': 'Nhập thêm vào kho ${_terms.category3}',
                        'shopId': shopId,
                        'isSynced': 0,
                      };
                      final importHistoryId = await db
                          .insertSupplierImportHistory(importHistory);
                      if (importHistoryId > 0) {
                        await SyncOrchestrator().enqueueSupplierImportHistory(
                          importHistoryId,
                          firestoreId: importHistory['firestoreId'] as String?,
                          operation: SyncOperation.create,
                        );
                      }

                      await db.updateSupplierStats(
                        selectedSupplierId!,
                        totalCost,
                        addQty,
                      );
                      EventBus().emit('suppliers_changed');
                    }

                    // 4. Tài chính — tạo BẢN GHI MỚI ngày hôm nay
                    if (totalCost > 0) {
                      final user = FirebaseAuth.instance.currentUser;
                      if (paymentMethod == 'CÔNG NỢ') {
                        // Công nợ NCC
                        final debtFId =
                            'debt_part_${now}_${selectedSupplierId ?? 0}';
                        final debtData = {
                          'firestoreId': debtFId,
                          'personName': supplierName,
                          'phone': '',
                          'totalAmount': totalCost,
                          'paidAmount': 0,
                          'type': 'SHOP_OWES',
                          'status': 'ACTIVE',
                          'createdAt': now,
                          'note':
                              'Nhập thêm ${_terms.category3}: $partName x$addQty',
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

                        // Công nợ đã ghi nhận ở bảng debts - không cần PaymentIntent
                        debugPrint(
                          '✅ Add-stock debt recorded (no PaymentIntent needed)',
                        );
                        EventBus().emit('debts_changed');
                      } else {
                        // TIỀN MẶT / CHUYỂN KHOẢN → expense
                        final expFId = 'exp_part_${now}_$partName';
                        final expenseData = {
                          'firestoreId': expFId,
                          'title': 'Nhập thêm ${_terms.category3}: $partName',
                          'description': 'NCC: $supplierName - SL: $addQty',
                          'amount': totalCost,
                          'category': 'NHẬP ${_terms.category3.toUpperCase()}',
                          'date': now,
                          'note':
                              'Nhập thêm vào kho ${_terms.category3} - $paymentMethod',
                          'paymentMethod': paymentMethod,
                          'createdAt': now,
                          'shopId': shopId,
                          'isSynced': 0,
                        };
                        final expenseId = await db.insertExpense(expenseData);
                        if (expenseId > 0) {
                          await SyncOrchestrator().enqueue(
                            entityType: SyncEntityType.expense,
                            entityId: expenseId,
                            firestoreId: expFId,
                            operation: SyncOperation.create,
                            data: expenseData,
                          );
                        }

                        await FinancialActivityService.logPurchase(
                          firestoreId: expFId,
                          amount: totalCost,
                          productName: partName,
                          quantity: addQty,
                          paymentMethod: paymentMethod,
                          supplierName: supplierName,
                        );

                        EventBus().emit('expenses_changed');
                        debugPrint(
                          'PartsInventory: Created expense for add-stock $paymentMethod: $totalCost',
                        );
                      }
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    await _refreshParts();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã nhập thêm $addQty $partName (tổng: $newQty)',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('NHẬP THÊM'),
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
          'Bạn có chắc muốn xóa $count ${_terms.category3} đã chọn?\n\nHành động này không thể hoàn tác.',
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
            summary: 'Xóa ${_terms.category3}: ${part['partName']}',
          );
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa $deletedCount ${_terms.category3}'),
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
        flexibleSpace: _isSelectionMode
            ? null
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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
                "KHO ${_terms.category3.toUpperCase()} SỬA CHỮA",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline3.fontSize,
                ),
              ),
        backgroundColor: _isSelectionMode
            ? Colors.red.shade700
            : Colors.transparent,
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
      body: ResponsiveCenter(
        child: _isLoading
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
                        hintText: 'Tìm ${_terms.category3} theo tên / dòng máy',
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
                    child: _filteredParts.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Chưa có ${_terms.category3} nào',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'Không tìm thấy kết quả cho "$_searchQuery"'
                                        : 'Nhấn nút Nhập LK để thêm ${_terms.category3} mới\nhoặc đợi dữ liệu đồng bộ từ Firestore',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade400,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (_searchQuery.isEmpty) ...[
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: _refreshParts,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Tải lại'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _primaryColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 8,
                            ),
                            itemCount: _filteredParts.length,
                            itemBuilder: (ctx, i) {
                              final p = _filteredParts[i];
                              final int? partId = p['id'] as int?;
                              final bool isSelected =
                                  partId != null &&
                                  _selectedIds.contains(partId);
                              final bool isLow =
                                  (p['quantity'] as int? ?? 0) < 3;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  side: isSelected
                                      ? BorderSide(
                                          color: Colors.red.shade700,
                                          width: 2,
                                        )
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
                                            color: isLow
                                                ? Colors.red
                                                : _primaryColor,
                                          ),
                                        ),
                                  title: Text(
                                    p['partName'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          AppTextStyles.headline4.fontSize,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "Dùng cho: ${p['compatibleModels'] ?? 'N/A'}\nSố lượng: ${p['quantity'] ?? 0}${p['supplierId'] != null ? "\nNCC: ${_getSupplierName(p['supplierId'] as int?)}" : ''}",
                                  ),
                                  trailing: _isSelectionMode
                                      ? null
                                      : _isAdmin
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Nút nhập thêm
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add_shopping_cart,
                                                color: Colors.teal,
                                                size: 20,
                                              ),
                                              tooltip: 'Nhập thêm',
                                              onPressed: () =>
                                                  _showAddStockDialog(p),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "${NumberFormat('#,###').format(p['price'] ?? 0)} đ",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        )
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
                                      !_isSelectionMode &&
                                          _isAdmin &&
                                          partId != null
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
}

/// Widget chọn NCC - mở bottom sheet thay vì dropdown inline
/// (Tránh bug layout trắng do nested ListView inside SingleChildScrollView inside AlertDialog)
class _SupplierSearchField extends StatelessWidget {
  final List<Map<String, dynamic>> suppliers;
  final int? selectedSupplierId;
  final ValueChanged<int?> onChanged;

  const _SupplierSearchField({
    required this.suppliers,
    required this.selectedSupplierId,
    required this.onChanged,
  });

  String _getSelectedName() {
    if (selectedSupplierId == null) return '';
    final s = suppliers.firstWhere(
      (e) => e['id'] == selectedSupplierId,
      orElse: () => {},
    );
    return s['name']?.toString() ?? '';
  }

  void _openSupplierPicker(BuildContext context) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _SupplierPickerSheet(
        suppliers: suppliers,
        selectedSupplierId: selectedSupplierId,
        onSelected: (id) {
          onChanged(id);
          Navigator.pop(sheetCtx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = _getSelectedName();
    return InkWell(
      onTap: () => _openSupplierPicker(context),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: "Nhà cung cấp (${suppliers.length} NCC)",
          prefixIcon: const Icon(Icons.store),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        child: Text(
          selectedName.isEmpty ? '-- Chọn NCC --' : selectedName,
          style: TextStyle(
            color: selectedName.isEmpty ? Colors.grey : Colors.black87,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for supplier selection with search
class _SupplierPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> suppliers;
  final int? selectedSupplierId;
  final ValueChanged<int?> onSelected;

  const _SupplierPickerSheet({
    required this.suppliers,
    required this.selectedSupplierId,
    required this.onSelected,
  });

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.suppliers;
    return widget.suppliers.where((s) {
      final name = s['name']?.toString() ?? '';
      return VietnameseUtils.containsVietnamese(name, _query);
    }).toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 8),
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
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.store, color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Chọn nhà cung cấp (${widget.suppliers.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Clear selection
                  if (widget.selectedSupplierId != null)
                    TextButton(
                      onPressed: () => widget.onSelected(null),
                      child: const Text(
                        'Bỏ chọn',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Tìm NCC (có dấu hoặc không dấu)...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            // Supplier list
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Không tìm thấy NCC',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, i) {
                        final s = _filtered[i];
                        final id = s['id'] as int?;
                        final name = s['name']?.toString() ?? 'N/A';
                        final phone = s['phone']?.toString() ?? '';
                        final isSelected = id == widget.selectedSupplierId;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.08),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? Colors.blue.withOpacity(0.15)
                                : Colors.grey.withOpacity(0.1),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.store_outlined,
                              size: 18,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: phone.isNotEmpty
                              ? Text(
                                  phone,
                                  style: const TextStyle(fontSize: 14),
                                )
                              : null,
                          onTap: () => widget.onSelected(id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
