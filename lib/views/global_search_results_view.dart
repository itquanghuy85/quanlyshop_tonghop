import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
import '../utils/ui_constants.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';
import 'inventory_view.dart';

class GlobalSearchResultsView extends StatefulWidget {
  final String query;
  final String role;

  const GlobalSearchResultsView({
    super.key,
    required this.query,
    required this.role,
  });

  @override
  State<GlobalSearchResultsView> createState() => _GlobalSearchResultsViewState();
}

class _GlobalSearchResultsViewState extends State<GlobalSearchResultsView> {
  final db = DBHelper();
  List<dynamic> _results = [];
  bool _isLoading = true;
  String _selectedCategory = 'Tất cả';

  final List<String> _categories = ['Tất cả', 'Khách hàng', 'Đơn sửa chữa', 'Đơn bán hàng', 'Sản phẩm'];

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);

    try {
      final query = widget.query.toLowerCase();
      List<dynamic> allResults = [];

      // Search customers (repairs)
      final repairs = await db.getAllRepairs();
      final customerResults = repairs.where((repair) {
        return repair.customerName.toLowerCase().contains(query) ||
               repair.phone.contains(query) ||
               repair.model.toLowerCase().contains(query);
      }).toList();

      // Search sales
      final sales = await db.getAllSales();
      final saleResults = sales.where((sale) {
        return sale.customerName.toLowerCase().contains(query) ||
               sale.phone.contains(query) ||
               sale.productNames.toLowerCase().contains(query);
      }).toList();

      // Search products
      final products = await db.getAllProducts();
      final productResults = products.where((product) {
        return product.name.toLowerCase().contains(query) ||
               product.description.toLowerCase().contains(query);
      }).toList();

      // Filter by category
      switch (_selectedCategory) {
        case 'Khách hàng':
          allResults = customerResults;
          break;
        case 'Đơn sửa chữa':
          allResults = customerResults.whereType<Repair>().toList();
          break;
        case 'Đơn bán hàng':
          allResults = saleResults;
          break;
        case 'Sản phẩm':
          allResults = productResults;
          break;
        default:
          allResults = [...customerResults, ...saleResults, ...productResults];
      }

      setState(() {
        _results = allResults.take(50).toList(); // Limit to 50 results
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tìm kiếm: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kết quả tìm kiếm: "${widget.query}"'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Column(
        children: [
          // Category filter
          Container(
            padding: UIConstants.padding16,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withAlpha(25),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Lọc theo:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                UIConstants.width12,
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((category) {
                        final isSelected = category == _selectedCategory;
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() => _selectedCategory = category);
                              _performSearch();
                            },
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            selectedColor: Theme.of(context).colorScheme.primary.withAlpha(25),
                            checkmarkColor: Theme.of(context).colorScheme.primary,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: UIConstants.padding16,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          return _buildResultItem(item);
                        },
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
            Icons.search_off_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(128),
          ),
          UIConstants.height16,
          Text(
            'Không tìm thấy kết quả',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          UIConstants.height8,
          Text(
            'Thử tìm với từ khóa khác',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultItem(dynamic item) {
    if (item is Repair) {
      return _buildRepairResultItem(item);
    } else if (item is SaleOrder) {
      return _buildSaleResultItem(item);
    } else if (item is Product) {
      return _buildProductResultItem(item);
    }
    return const SizedBox.shrink();
  }

  Widget _buildRepairResultItem(Repair repair) {
    return Card(
      margin: UIConstants.paddingVertical8,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(25),
            borderRadius: UIConstants.borderRadius8,
          ),
          child: Icon(
            Icons.build_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          '${repair.customerName} - ${repair.model}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SĐT: ${repair.phone}'),
            Text(
              'Ngày: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(repair.createdAt))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: _getStatusChip(repair.status),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RepairDetailView(repair: repair),
          ),
        ),
      ),
    );
  }

  Widget _buildSaleResultItem(SaleOrder sale) {
    return Card(
      margin: UIConstants.paddingVertical8,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary.withAlpha(25),
            borderRadius: UIConstants.borderRadius8,
          ),
          child: Icon(
            Icons.shopping_cart_rounded,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        title: Text(
          '${sale.customerName} - ${sale.productNames}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SĐT: ${sale.phone}'),
            Text(
              'Tổng: ${NumberFormat('#,###').format(sale.totalPrice)}đ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SaleDetailView(sale: sale),
          ),
        ),
      ),
    );
  }

  Widget _buildProductResultItem(Product product) {
    return Card(
      margin: UIConstants.paddingVertical8,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary.withAlpha(25),
            borderRadius: UIConstants.borderRadius8,
          ),
          child: Icon(
            Icons.inventory_2_rounded,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
        title: Text(
          product.name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Giá: ${NumberFormat('#,###').format(product.price)}đ - Tồn: ${product.quantity}',
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InventoryView(role: widget.role),
          ),
        ),
      ),
    );
  }

  Widget _getStatusChip(int status) {
    String text;
    Color color;

    switch (status) {
      case 1:
        text = 'Nhận máy';
        color = Colors.blue;
        break;
      case 2:
        text = 'Đang sửa';
        color = Colors.orange;
        break;
      case 3:
        text = 'Hoàn thành';
        color = Colors.green;
        break;
      case 4:
        text = 'Đã giao';
        color = Colors.grey;
        break;
      default:
        text = 'Chưa xác định';
        color = Colors.grey;
    }

    return Chip(
      label: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}