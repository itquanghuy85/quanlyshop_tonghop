import 'package:flutter/material.dart';
import '../../widgets/responsive_wrapper.dart';
import '../../widgets/custom_app_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product_model.dart';
import '../../models/product_variant_model.dart';
import '../../models/shop_settings_model.dart';
import '../../services/variant_service.dart';
import '../../services/category_service.dart';
import '../../services/business_type_helper.dart';
import '../../data/db_helper.dart';
import '../../widgets/variant_selector.dart';

/// Màn hình quản lý phân loại sản phẩm (size, color)
/// Module Thời trang - Phase 3 Multi-Industry
class VariantManagementView extends StatefulWidget {
  const VariantManagementView({super.key});

  @override
  State<VariantManagementView> createState() => _VariantManagementViewState();
}

class _VariantManagementViewState extends State<VariantManagementView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final VariantService _variantService = VariantService();
  final DBHelper _dbHelper = DBHelper();

  List<Product> _productsWithVariants = [];
  List<ProductVariant> _allVariants = [];
  List<ProductVariant> _outOfStock = [];
  List<ProductVariant> _lowStock = [];
  VariantWarningCounts? _warnings;
  bool _isLoading = true;

  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadShopSettings();
    _loadData();
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _variantService.getAllVariants(),
        _variantService.getOutOfStockVariants(),
        _variantService.getLowStockVariants(),
        _variantService.getWarningCounts(),
        _loadProductsWithVariants(),
      ]);

      setState(() {
        _allVariants = results[0] as List<ProductVariant>;
        _outOfStock = results[1] as List<ProductVariant>;
        _lowStock = results[2] as List<ProductVariant>;
        _warnings = results[3] as VariantWarningCounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  Future<List<Product>> _loadProductsWithVariants() async {
    try {
      final db = await _dbHelper.database;
      final results = await db.rawQuery('''
        SELECT DISTINCT p.* FROM products p
        INNER JOIN product_variants pv ON pv.productId = p.firestoreId
        WHERE pv.isActive = 1
        ORDER BY p.name
      ''');
      
      _productsWithVariants = results.map((r) => Product.fromMap(r)).toList();
      return _productsWithVariants;
    } catch (e) {
      debugPrint('Error loading products with variants: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar.build(
        title: 'Quản lý phân loại',
        accentColor: AppBarAccents.inventory,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📊 Tổng quan'),
                  if (_warnings != null && _warnings!.hasWarnings) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_warnings!.total}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⛔ Hết hàng'),
                  if (_outOfStock.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_outOfStock.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⚠️ Sắp hết'),
                  if (_lowStock.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_lowStock.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: '📦 Theo ${_terms.productLabel.toLowerCase()}'),
          ],
        ),
      ),
      body: ResponsiveCenter(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildOutOfStockTab(),
                _buildLowStockTab(),
                _buildByProductTab(),
              ],
            )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddVariantDialog,
        icon: const Icon(Icons.add),
        label: const Text('Thêm phân loại'),
      ),
    );
  }

  /// Tab 1: Tổng quan
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats cards
            _buildStatsCards(),
            const SizedBox(height: 24),

            // Quick actions
            const Text(
              'Thao tác nhanh',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildQuickActions(),
            const SizedBox(height: 24),

            // Inventory matrix preview
            const Text(
              'Ma trận tồn kho',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInventoryMatrixPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Tổng phân loại',
          '${_allVariants.length}',
          Icons.style,
          Colors.blue,
        ),
        _buildStatCard(
          _terms.productLabel,
          '${_productsWithVariants.length}',
          Icons.inventory_2,
          Colors.blue,
        ),
        _buildStatCard(
          'Hết hàng',
          '${_outOfStock.length}',
          Icons.error_outline,
          Colors.red,
        ),
        _buildStatCard(
          'Sắp hết',
          '${_lowStock.length}',
          Icons.warning_amber,
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Thêm phân loại mới'),
          onPressed: _showAddVariantDialog,
        ),
        ActionChip(
          avatar: const Icon(Icons.inventory, size: 18),
          label: const Text('Nhập hàng theo phân loại'),
          onPressed: _showBulkImportDialog,
        ),
        ActionChip(
          avatar: const Icon(Icons.print, size: 18),
          label: const Text('In barcode phân loại'),
          onPressed: _showPrintBarcodeDialog,
        ),
        ActionChip(
          avatar: const Icon(Icons.file_download, size: 18),
          label: const Text('Xuất Excel'),
          onPressed: _exportToExcel,
        ),
      ],
    );
  }

  Widget _buildInventoryMatrixPreview() {
    if (_productsWithVariants.isEmpty) {
      return Card(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: const Center(
            child: Column(
              children: [
                Icon(Icons.grid_off, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Chưa có phân loại nào',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show first 3 products only
    final preview = _productsWithVariants.take(3).toList();

    return Column(
      children: [
        ...preview.map((product) => _buildProductMatrixCard(product)),
        if (_productsWithVariants.length > 3)
          TextButton(
            onPressed: () => _tabController.animateTo(3),
            child: Text('Xem thêm ${_productsWithVariants.length - 3} ${_terms.productLabel.toLowerCase()} →'),
          ),
      ],
    );
  }

  Widget _buildProductMatrixCard(Product product) {
    return FutureBuilder<List<ProductVariant>>(
      future: _variantService.getVariantsByProduct(product.firestoreId ?? ''),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final variants = snapshot.data!;
        final summary = VariantSummary.fromVariants(product.firestoreId ?? '', variants);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: const Icon(Icons.checkroom),
            title: Text(product.name),
            subtitle: Text(
              '${summary.totalVariants} phân loại • ${summary.totalStock} tồn kho',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (variants.any((v) => v.isOutOfStock))
                  const Icon(Icons.error, color: Colors.red, size: 20),
                if (variants.any((v) => v.isLowStock))
                  const Icon(Icons.warning, color: Colors.orange, size: 20),
                const Icon(Icons.expand_more),
              ],
            ),
            children: [
              _buildVariantMatrix(variants, summary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVariantMatrix(List<ProductVariant> variants, VariantSummary summary) {
    // Group by size and color
    final sizes = summary.availableSizes;
    final colors = summary.availableColors;

    if (sizes.isEmpty && colors.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: variants.map((v) => _buildSimpleVariantRow(v)).toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 40,
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('Size')),
            ...colors.map((c) => DataColumn(
              label: Text(c, style: const TextStyle(fontSize: 12)),
            )),
          ],
          rows: sizes.map((size) {
            return DataRow(
              cells: [
                DataCell(Text(size, style: const TextStyle(fontWeight: FontWeight.bold))),
                ...colors.map((color) {
                  final variant = variants.firstWhere(
                    (v) => v.size == size && v.color == color,
                    orElse: () => ProductVariant(
                      shopId: '', productId: '', size: size, color: color,
                    ),
                  );
                  
                  return DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: variant.isOutOfStock
                            ? Colors.red.withOpacity(0.1)
                            : variant.isLowStock
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        variant.firestoreId.isNotEmpty ? '${variant.quantity}' : '-',
                        style: TextStyle(
                          color: variant.isOutOfStock
                              ? Colors.red
                              : variant.isLowStock
                                  ? Colors.orange
                                  : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSimpleVariantRow(ProductVariant variant) {
    return ListTile(
      dense: true,
      title: Text(variant.displayName),
      subtitle: Text('SKU: ${variant.sku ?? "N/A"}'),
      trailing: Chip(
        label: Text('${variant.quantity}'),
        backgroundColor: variant.isOutOfStock
            ? Colors.red.withOpacity(0.2)
            : variant.isLowStock
                ? Colors.orange.withOpacity(0.2)
                : Colors.green.withOpacity(0.2),
      ),
    );
  }

  /// Tab 2: Hết hàng
  Widget _buildOutOfStockTab() {
    if (_outOfStock.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Không có phân loại nào hết hàng! 🎉',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _outOfStock.length,
        itemBuilder: (context, index) {
          return _buildVariantCard(_outOfStock[index], Colors.red);
        },
      ),
    );
  }

  /// Tab 3: Sắp hết
  Widget _buildLowStockTab() {
    if (_lowStock.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Không có phân loại nào sắp hết! 🎉',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _lowStock.length,
        itemBuilder: (context, index) {
          return _buildVariantCard(_lowStock[index], Colors.orange);
        },
      ),
    );
  }

  Widget _buildVariantCard(ProductVariant variant, Color statusColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Text(
            variant.size ?? 'V',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(variant.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${variant.sku ?? "N/A"}'),
            if (variant.barcode != null) Text('Barcode: ${variant.barcode}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${variant.quantity}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const Text('tồn kho', style: TextStyle(fontSize: 10)),
          ],
        ),
        onTap: () => _showEditVariantDialog(variant),
      ),
    );
  }

  /// Tab 4: Theo sản phẩm
  Widget _buildByProductTab() {
    if (_productsWithVariants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.checkroom_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Chưa có ${_terms.productLabel.toLowerCase()} nào có phân loại',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm phân loại size/màu cho ${_terms.productLabel.toLowerCase()}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _productsWithVariants.length,
        itemBuilder: (context, index) {
          return _buildProductMatrixCard(_productsWithVariants[index]);
        },
      ),
    );
  }

  // === DIALOGS ===

  void _showAddVariantDialog() async {
    // First select product
    final selectedProduct = await showAppBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSelectorSheet(dbHelper: _dbHelper),
    );

    if (selectedProduct == null || !mounted) return;

    // Then add variant
    final result = await showDialog<ProductVariant>(
      context: context,
      builder: (context) => _AddVariantDialog(
        product: selectedProduct,
        variantService: _variantService,
      ),
    );

    if (result != null) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã thêm phân loại thành công!')),
        );
      }
    }
  }

  void _showEditVariantDialog(ProductVariant variant) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _EditVariantDialog(
        variant: variant,
        variantService: _variantService,
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  void _showBulkImportDialog() async {
    // First select product
    final selectedProduct = await showAppBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSelectorSheet(dbHelper: _dbHelper),
    );

    if (selectedProduct == null || !mounted) return;

    // Show bulk import dialog
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _BulkImportDialog(
        product: selectedProduct,
        variantService: _variantService,
      ),
    );

    if (result == true) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã nhập hàng theo phân loại thành công!')),
        );
      }
    }
  }

  void _showPrintBarcodeDialog() async {
    if (_allVariants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có phân loại nào để in barcode!')),
      );
      return;
    }

    // Show dialog to select variants to print
    final result = await showDialog<List<ProductVariant>>(
      context: context,
      builder: (context) => _PrintBarcodeDialog(variants: _allVariants),
    );

    if (result != null && result.isNotEmpty && mounted) {
      // TODO: Integrate with printer service
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã chọn ${result.length} phân loại để in barcode')),
      );
    }
  }

  void _exportToExcel() async {
    if (_allVariants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có phân loại nào để xuất!')),
      );
      return;
    }

    // Generate CSV content for easy export
    final buffer = StringBuffer();
    buffer.writeln('Sản phẩm,Size,Màu,Số lượng,Giá bán,SKU,Barcode');
    
    for (final variant in _allVariants) {
      // Get product name
      final product = _productsWithVariants.firstWhere(
        (p) => p.firestoreId == variant.productId,
        orElse: () => Product(name: 'N/A', brand: '', model: '', type: '', createdAt: DateTime.now().millisecondsSinceEpoch),
      );
      buffer.writeln(
        '${product.name},'
        '${variant.size ?? ""},'
        '${variant.color ?? ""},'
        '${variant.quantity},'
        '${variant.salePrice},'
        '${variant.sku ?? ""},'
        '${variant.barcode ?? ""}'
      );
    }

    // For now, show the data - full Excel export would need a file picker
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã tạo dữ liệu ${_allVariants.length} phân loại. Sao chép hoặc chia sẻ?'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }
}

/// Bottom sheet chọn sản phẩm
class _ProductSelectorSheet extends StatefulWidget {
  final DBHelper dbHelper;

  const _ProductSelectorSheet({required this.dbHelper});

  @override
  State<_ProductSelectorSheet> createState() => _ProductSelectorSheetState();
}

class _ProductSelectorSheetState extends State<_ProductSelectorSheet> {
  List<Product> _products = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final db = await widget.dbHelper.database;
      final results = await db.query(
        'products',
        where: 'status = 1',
        orderBy: 'name',
      );
      setState(() {
        _products = results.map((r) => Product.fromMap(r)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    return _products.where((p) =>
      p.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn sản phẩm',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2),
                          title: Text(product.name),
                          subtitle: Text(product.brand),
                          onTap: () => Navigator.pop(context, product),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Dialog thêm phân loại mới
class _AddVariantDialog extends StatefulWidget {
  final Product product;
  final VariantService variantService;

  const _AddVariantDialog({
    required this.product,
    required this.variantService,
  });

  @override
  State<_AddVariantDialog> createState() => _AddVariantDialogState();
}

class _AddVariantDialogState extends State<_AddVariantDialog> {
  String? _selectedSize;
  String? _selectedColor;
  final _quantityController = TextEditingController(text: '0');
  final _priceController = TextEditingController();
  final _skuController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedSize == null && _selectedColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn size hoặc màu')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final variant = ProductVariant(
      shopId: '', // Will be set by service
      productId: widget.product.firestoreId ?? '',
      size: _selectedSize,
      color: _selectedColor,
      sku: _skuController.text.isEmpty
          ? null
          : _skuController.text,
      quantity: int.tryParse(_quantityController.text) ?? 0,
      salePrice: int.tryParse(_priceController.text) ?? 0,
    );

    final id = await widget.variantService.createVariant(variant);

    setState(() => _isSaving = false);

    if (id != null && mounted) {
      Navigator.pop(context, variant.copyWith(firestoreId: id));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lỗi khi thêm phân loại!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Thêm phân loại: ${widget.product.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Size selector
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Size',
                border: OutlineInputBorder(),
              ),
              value: _selectedSize,
              items: CommonSizes.clothing.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s),
              )).toList(),
              onChanged: (v) => setState(() => _selectedSize = v),
            ),
            const SizedBox(height: 12),

            // Color selector
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Màu sắc',
                border: OutlineInputBorder(),
              ),
              value: _selectedColor,
              items: CommonColors.all.map((c) => DropdownMenuItem(
                value: c,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _hexToColor(CommonColors.hexCodes[c] ?? '#808080'),
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Text(c),
                  ],
                ),
              )).toList(),
              onChanged: (v) => setState(() => _selectedColor = v),
            ),
            const SizedBox(height: 12),

            // Quantity
            TextField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'Số lượng',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            // Price (optional)
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Giá bán riêng (để trống = theo SP gốc)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            // SKU (optional)
            TextField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'Mã SKU (tùy chọn)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Thêm'),
        ),
      ],
    );
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

/// Dialog chỉnh sửa phân loại
class _EditVariantDialog extends StatefulWidget {
  final ProductVariant variant;
  final VariantService variantService;

  const _EditVariantDialog({
    required this.variant,
    required this.variantService,
  });

  @override
  State<_EditVariantDialog> createState() => _EditVariantDialogState();
}

class _EditVariantDialogState extends State<_EditVariantDialog> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late TextEditingController _minQuantityController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.variant.quantity.toString(),
    );
    _priceController = TextEditingController(
      text: widget.variant.salePrice > 0
          ? widget.variant.salePrice.toString()
          : '',
    );
    _minQuantityController = TextEditingController(
      text: widget.variant.minQuantity.toString(),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _minQuantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final updated = widget.variant.copyWith(
      quantity: int.tryParse(_quantityController.text) ?? 0,
      salePrice: int.tryParse(_priceController.text) ?? 0,
      minQuantity: int.tryParse(_minQuantityController.text) ?? 0,
    );

    final success = await widget.variantService.updateVariant(updated);

    setState(() => _isSaving = false);

    if (success && mounted) {
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lỗi khi cập nhật!')),
      );
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa phân loại?'),
        content: Text('Bạn có chắc muốn xóa "${widget.variant.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await widget.variantService.deleteVariant(
      widget.variant.firestoreId,
      widget.variant.productId,
    );

    if (success && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa phân loại!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.variant.displayName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: 'Số lượng tồn',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            decoration: const InputDecoration(
              labelText: 'Giá bán riêng (để trống = theo SP gốc)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minQuantityController,
            decoration: const InputDecoration(
              labelText: 'Ngưỡng cảnh báo tồn kho',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('SKU: '),
              Text(
                widget.variant.sku ?? 'N/A',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (widget.variant.barcode != null)
            Row(
              children: [
                const Text('Barcode: '),
                Text(
                  widget.variant.barcode!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _delete,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Xóa'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}

/// Dialog nhập hàng hàng loạt theo phân loại
class _BulkImportDialog extends StatefulWidget {
  final Product product;
  final VariantService variantService;

  const _BulkImportDialog({
    required this.product,
    required this.variantService,
  });

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  List<ProductVariant> _existingVariants = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  @override
  void dispose() {
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVariants() async {
    final productId = widget.product.firestoreId ?? '';
    if (productId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final variants = await widget.variantService.getVariantsByProduct(productId);
    
    for (final v in variants) {
      _qtyControllers[v.firestoreId] = TextEditingController(text: '0');
    }

    setState(() {
      _existingVariants = variants;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    int successCount = 0;
    for (final variant in _existingVariants) {
      final addQty = int.tryParse(_qtyControllers[variant.firestoreId]?.text ?? '0') ?? 0;
      if (addQty > 0) {
        final updated = variant.copyWith(quantity: variant.quantity + addQty);
        final success = await widget.variantService.updateVariant(updated);
        if (success) successCount++;
      }
    }

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context, successCount > 0);
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cập nhật $successCount phân loại!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nhập hàng: ${widget.product.name}'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _existingVariants.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có phân loại.\nHãy thêm phân loại trước khi nhập hàng.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _existingVariants.length,
                    itemBuilder: (context, index) {
                      final variant = _existingVariants[index];
                      return Card(
                        child: ListTile(
                          title: Text(variant.displayName),
                          subtitle: Text('Tồn: ${variant.quantity}'),
                          trailing: SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _qtyControllers[variant.firestoreId],
                              decoration: const InputDecoration(
                                labelText: '+SL',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving || _existingVariants.isEmpty ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Nhập hàng'),
        ),
      ],
    );
  }
}

/// Dialog chọn phân loại để in barcode
class _PrintBarcodeDialog extends StatefulWidget {
  final List<ProductVariant> variants;

  const _PrintBarcodeDialog({required this.variants});

  @override
  State<_PrintBarcodeDialog> createState() => _PrintBarcodeDialogState();
}

class _PrintBarcodeDialogState extends State<_PrintBarcodeDialog> {
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedIds.addAll(widget.variants.map((v) => v.firestoreId));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn phân loại để in barcode'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Select all checkbox
            CheckboxListTile(
              title: const Text('Chọn tất cả'),
              value: _selectAll,
              onChanged: (_) => _toggleSelectAll(),
            ),
            const Divider(),
            // Variants list
            Expanded(
              child: ListView.builder(
                itemCount: widget.variants.length,
                itemBuilder: (context, index) {
                  final variant = widget.variants[index];
                  final isSelected = _selectedIds.contains(variant.firestoreId);
                  return CheckboxListTile(
                    title: Text(variant.displayName),
                    subtitle: Text('SKU: ${variant.sku ?? "N/A"} • Tồn: ${variant.quantity}'),
                    value: isSelected,
                    onChanged: (_) => _toggle(variant.firestoreId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = widget.variants
                      .where((v) => _selectedIds.contains(v.firestoreId))
                      .toList();
                  Navigator.pop(context, selected);
                },
          child: Text('In (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
