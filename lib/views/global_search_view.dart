import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
import '../models/quick_input_code_model.dart';
import '../models/shop_settings_model.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../theme/app_text_styles.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';
import 'inventory_view.dart';
import 'customer_history_view.dart';
import 'quick_input_codes_view.dart';

class GlobalSearchView extends StatefulWidget {
  final String role;

  const GlobalSearchView({super.key, required this.role});

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final db = DBHelper();
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _results = [];
  bool _isLoading = false;
  String _selectedCategory = 'Tất cả';
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

  List<String> get _categories => ['Tất cả', 'Khách hàng', 'Đơn sửa chữa', 'Đơn bán hàng', _terms.productLabel, 'Mã nhập nhanh'];

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _searchCtrl.addListener(_onSearchChanged);
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
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _performSearch(_searchCtrl.text);
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final lowerQuery = query.toLowerCase();
      List<dynamic> allResults = [];

      // Search customers (from repairs)
      final repairs = await db.getAllRepairs();
      final customerResults = repairs.where((repair) {
        return repair.customerName.toLowerCase().contains(lowerQuery) ||
               repair.phone.contains(lowerQuery);
      }).toList();

      // Search repairs
      final repairResults = repairs.where((repair) {
        return repair.model.toLowerCase().contains(lowerQuery) ||
               repair.issue.toLowerCase().contains(lowerQuery) ||
               repair.customerName.toLowerCase().contains(lowerQuery) ||
               repair.phone.contains(lowerQuery);
      }).toList();

      // Search sales
      final sales = await db.getAllSales();
      final saleResults = sales.where((sale) {
        return sale.customerName.toLowerCase().contains(lowerQuery) ||
               sale.phone.contains(lowerQuery) ||
               sale.productNames.toLowerCase().contains(lowerQuery) ||
               (sale.productImeis ?? '').contains(lowerQuery);
      }).toList();

      // Search products
      final products = await db.getAllProducts();
      final productResults = products.where((product) {
        return product.name.toLowerCase().contains(lowerQuery) ||
               (product.imei ?? '').contains(lowerQuery) ||
               product.description.toLowerCase().contains(lowerQuery) ||
               (product.color ?? '').toLowerCase().contains(lowerQuery) ||
               (product.capacity ?? '').toLowerCase().contains(lowerQuery);
      }).toList();

      // Search quick input codes
      final quickInputCodes = await db.getQuickInputCodes();
      final quickInputCodeResults = quickInputCodes.where((code) {
        return code.name.toLowerCase().contains(lowerQuery) ||
               (code.brand ?? '').toLowerCase().contains(lowerQuery) ||
               (code.model ?? '').toLowerCase().contains(lowerQuery) ||
               (code.description ?? '').toLowerCase().contains(lowerQuery) ||
               (code.supplier ?? '').toLowerCase().contains(lowerQuery);
      }).toList();

      // Filter by category
      if (_selectedCategory == 'Khách hàng') {
        allResults = customerResults;
      } else if (_selectedCategory == 'Đơn sửa chữa') {
        allResults = repairResults;
      } else if (_selectedCategory == 'Đơn bán hàng') {
        allResults = saleResults;
      } else if (_selectedCategory == _terms.productLabel) {
        allResults = productResults;
      } else if (_selectedCategory == 'Mã nhập nhanh') {
        allResults = quickInputCodeResults;
      } else {
        allResults = [...customerResults, ...repairResults, ...saleResults, ...productResults, ...quickInputCodeResults];
      }

      setState(() {
        _results = allResults.take(100).toList(); // Limit to 100 results
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

  void _onResultTap(dynamic item) {
    if (item is Repair) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => RepairDetailView(repair: item)));
    } else if (item is SaleOrder) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailView(sale: item)));
    } else if (item is Product) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryView(role: widget.role))).then((_) {
        // Optionally, scroll to the product or something
      });
    } else if (item is QuickInputCode) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickInputCodesView()));
    } else if (item.containsKey('customerName')) {
      // Customer from repair
      Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerHistoryView(phone: item['phone'], name: item['customerName'])));
    }
  }

  Widget _buildResultItem(dynamic item, String type) {
    String title = '';
    String subtitle = '';
    IconData icon = Icons.help;

    if (item is Repair) {
      title = item.customerName;
      subtitle = '${item.phone} - ${item.model}';
      icon = Icons.build;
    } else if (item is SaleOrder) {
      title = item.customerName;
      subtitle = '${item.phone} - ${item.productNames}';
      icon = Icons.shopping_cart;
    } else if (item is Product) {
      title = item.name;
      subtitle = item.imei != null ? '${_terms.specialField1Label}: ${item.imei}' : 'Số lượng: ${item.quantity}';
      icon = Icons.inventory;
    } else if (item is QuickInputCode) {
      title = item.name;
      subtitle = item.type == 'DIEN_THOAI' 
          ? '${item.brand ?? ''} ${item.model ?? ''}'.trim()
          : item.description ?? '';
      icon = item.type == 'DIEN_THOAI' ? Icons.smartphone : Icons.inventory_2;
    } else if (item is Map) {
      title = item['customerName'];
      subtitle = item['phone'];
      icon = Icons.person;
    }

    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => _onResultTap(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TÌM KIẾM TOÀN APP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline2.fontSize)),
            Text('Tìm đơn sửa, đơn bán, ${_terms.productLabel.toLowerCase()}...', style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.white70)),
          ],
        ),
        automaticallyImplyLeading: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Nhập tên, SĐT, model, ${_terms.specialField1Label.toLowerCase()}...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
          // Category filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                        _performSearch(_searchCtrl.text);
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
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty && _searchCtrl.text.isNotEmpty
                    ? const Center(child: Text('Không tìm thấy kết quả'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          String type = '';
                          if (item is Repair) {
                            type = 'Đơn sửa chữa';
                          } else if (item is SaleOrder) {
                            type = 'Đơn bán hàng';
                          } else if (item is Product) {
                            type = _terms.productLabel;
                          } else if (item is QuickInputCode) {
                            type = 'Mã nhập nhanh';
                          } else {
                            type = 'Khách hàng';
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (index == 0 || _getType(_results[index - 1]) != type)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Text(
                                    type,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              _buildResultItem(item, type),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _getType(dynamic item) {
    if (item is Repair) return 'Đơn sửa chữa';
    if (item is SaleOrder) return 'Đơn bán hàng';
    if (item is Product) return _terms.productLabel;
    if (item is QuickInputCode) return 'Mã nhập nhanh';
    return 'Khách hàng';
  }
}