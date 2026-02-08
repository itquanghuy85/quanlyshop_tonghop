import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product_model.dart';
import '../../services/expiry_alert_service.dart';
import '../../widgets/expiry_badge.dart';

/// Màn hình quản lý hạn sử dụng sản phẩm
/// Module Thực phẩm - Phase 2 Multi-Industry
class ExpiryManagementView extends StatefulWidget {
  const ExpiryManagementView({super.key});

  @override
  State<ExpiryManagementView> createState() => _ExpiryManagementViewState();
}

class _ExpiryManagementViewState extends State<ExpiryManagementView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExpiryAlertService _expiryService = ExpiryAlertService();

  ExpiryStats? _stats;
  List<Product> _expiredProducts = [];
  List<Product> _nearExpiryProducts = [];
  List<Product> _goodProducts = [];
  List<BatchInfo> _batches = [];
  bool _isLoading = true;
  int _warningDays = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _warningDays = await _expiryService.getWarningDays();
      
      final results = await Future.wait([
        _expiryService.getExpiryStats(),
        _expiryService.getExpiredProducts(),
        _expiryService.getNearExpiryProducts(),
        _expiryService.getAllProductsWithExpiry(includeExpired: false),
        _expiryService.getBatchList(),
      ]);

      if (mounted) {
        setState(() {
          _stats = results[0] as ExpiryStats;
          _expiredProducts = results[1] as List<Product>;
          _nearExpiryProducts = results[2] as List<Product>;
          
          // Filter to get only "good" products (not expired, not near expiry)
          final allProducts = results[3] as List<Product>;
          final nearExpiryIds = _nearExpiryProducts.map((p) => p.id).toSet();
          _goodProducts = allProducts
              .where((p) => !nearExpiryIds.contains(p.id))
              .toList();
          
          _batches = results[4] as List<BatchInfo>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý hạn sử dụng'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'Cài đặt cảnh báo',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: loc.refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            _buildTab('⛔ Hết hạn', _expiredProducts.length, Colors.red),
            _buildTab('⚠️ Sắp hết', _nearExpiryProducts.length, Colors.orange),
            _buildTab('✅ Còn hạn', _goodProducts.length, Colors.green),
            _buildTab('📦 Theo lô', _batches.length, Colors.blue),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats summary
                if (_stats != null) _buildStatsSummary(),
                
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildProductList(_expiredProducts, ExpiryStatus.expired),
                      _buildProductList(_nearExpiryProducts, ExpiryStatus.nearExpiry),
                      _buildProductList(_goodProducts, ExpiryStatus.good),
                      _buildBatchList(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTab(String label, int count, MaterialColor color) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tổng quan',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_stats!.totalWithExpiry} sản phẩm có HSD',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_stats!.valueAtRisk > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Rủi ro: ${_formatCurrency(_stats!.valueAtRisk)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '${_stats!.atRiskCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'cần xử lý',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(List<Product> products, ExpiryStatus filterStatus) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filterStatus == ExpiryStatus.expired
                  ? Icons.check_circle
                  : filterStatus == ExpiryStatus.nearExpiry
                      ? Icons.thumb_up
                      : Icons.inventory_2,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              filterStatus == ExpiryStatus.expired
                  ? 'Không có sản phẩm hết hạn 🎉'
                  : filterStatus == ExpiryStatus.nearExpiry
                      ? 'Không có sản phẩm sắp hết hạn'
                      : 'Không có sản phẩm',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final expiryDate = product.expiryDate != null
        ? DateTime.fromMillisecondsSinceEpoch(product.expiryDate!)
        : null;
    final days = _expiryService.daysUntilExpiry(product);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showProductActions(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.inventory_2,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${product.quantity} ${product.unit ?? 'cái'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.attach_money,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text(
                          _formatCurrency(product.cost * product.quantity),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    if (product.batchNumber != null &&
                        product.batchNumber!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.qr_code,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            'Lô: ${product.batchNumber}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Expiry info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ExpiryBadge(
                    product: product,
                    warningDays: _warningDays,
                  ),
                  if (expiryDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatDate(expiryDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchList() {
    if (_batches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Chưa có lô hàng nào',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _batches.length,
        itemBuilder: (context, index) {
          final batch = _batches[index];
          return _buildBatchCard(batch);
        },
      ),
    );
  }

  Widget _buildBatchCard(BatchInfo batch) {
    MaterialColor statusColor;
    String statusText;
    IconData statusIcon;

    if (batch.hasExpired) {
      statusColor = Colors.red;
      statusText = 'Có SP hết hạn';
      statusIcon = Icons.error;
    } else if (batch.isNearExpiry) {
      statusColor = Colors.orange;
      statusText = 'Sắp hết hạn';
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.green;
      statusText = 'Còn hạn';
      statusIcon = Icons.check_circle;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.shade100),
      ),
      child: InkWell(
        onTap: () => _viewBatchProducts(batch),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor.shade700, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lô: ${batch.batchNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${batch.productCount} SP • ${batch.totalQuantity} đơn vị',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (batch.earliestExpiry != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'HSD: ${_formatDate(batch.earliestExpiry!)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatCurrency(batch.totalValue),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
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

  void _showSettingsDialog() {
    int tempDays = _warningDays;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, size: 24),
            SizedBox(width: 12),
            Text('Cài đặt cảnh báo'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cảnh báo trước khi hết hạn:'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: tempDays.toDouble(),
                        min: 1,
                        max: 30,
                        divisions: 29,
                        label: '$tempDays ngày',
                        onChanged: (value) {
                          setDialogState(() => tempDays = value.round());
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$tempDays ngày',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sản phẩm sẽ được cảnh báo khi còn $tempDays ngày đến HSD',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _expiryService.updateWarningDays(tempDays);
              if (mounted) {
                Navigator.pop(ctx);
                setState(() => _warningDays = tempDays);
                _loadData();
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showProductActions(Product product) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExpiryInfoCard(product: product, warningDays: _warningDays),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // TODO: Navigate to product edit
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Sửa SP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // TODO: Mark as processed/sold
                      },
                      icon: const Icon(Icons.check),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Đã xử lý'),
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

  void _viewBatchProducts(BatchInfo batch) async {
    final products = await _expiryService.getProductsByBatch(batch.batchNumber);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lô: ${batch.batchNumber}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  return _buildProductCard(products[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatCurrency(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '${amount}đ';
  }
}
