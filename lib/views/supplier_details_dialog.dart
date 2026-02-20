import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SupplierDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> supplier;

  const SupplierDetailsDialog({super.key, required this.supplier});

  @override
  State<SupplierDetailsDialog> createState() => _SupplierDetailsDialogState();
}

class _SupplierDetailsDialogState extends State<SupplierDetailsDialog> with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;

  List<Map<String, dynamic>> _importHistory = [];
  List<Map<String, dynamic>> _productPrices = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _subscription = EventBus().on('suppliers_changed', _onSuppliersChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _onSuppliersChanged(dynamic data) {
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final supplierId = widget.supplier['id'];
      final supplierName = widget.supplier['name'] as String?;
      if (supplierId != null) {
        // Truyền cả supplierName để tìm theo tên nếu supplierId không khớp
        final history = await db.getSupplierImportHistory(
          supplierId,
          limit: 50,
          supplierName: supplierName,
        );
        final prices = await db.getSupplierProductPrices(supplierId);
        final stats = await db.getSupplierImportStats(supplierId);

        setState(() {
          _importHistory = history;
          _productPrices = prices;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading supplier details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: AppColors.surface,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Header với gradient
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.onPrimary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.business, color: AppColors.onPrimary, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.supplier['name'] ?? 'N/A',
                          style: AppTextStyles.headline5.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: AppColors.onPrimary),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.onPrimary.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                  if (_stats != null) ...[
                    const SizedBox(height: 16),
                    // Stats cards với design mới
                    Row(
                      children: [
                        _buildStatCard(
                          'Tổng nhập',
                          '${_stats!['totalImports'] ?? 0}',
                          'lần',
                          Icons.inventory_2,
                          AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        _buildStatCard(
                          'Tổng tiền',
                          NumberFormat('#,###').format(_stats!['totalAmount'] ?? 0),
                          'đ',
                          Icons.account_balance_wallet,
                          AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildStatCard(
                          'SL sản phẩm',
                          '${_stats!['totalQuantity'] ?? 0}',
                          'cái',
                          Icons.inventory,
                          AppColors.info,
                        ),
                        const SizedBox(width: 8),
                        _buildStatCard(
                          'SP duy nhất',
                          '${_stats!['uniqueProducts'] ?? 0}',
                          'loại',
                          Icons.category,
                          AppColors.secondary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Tab bar với design mới
            Container(
              color: AppColors.surface,
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.onSurface.withOpacity(0.6),
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelStyle: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
                unselectedLabelStyle: AppTextStyles.body2,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history),
                        SizedBox(width: 8),
                        Text('LỊCH SỬ NHẬP'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.price_change),
                        SizedBox(width: 8),
                        Text('GIÁ SẢN PHẨM'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics),
                        SizedBox(width: 8),
                        Text('THỐNG KÊ'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text('Đang tải dữ liệu...', style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildImportHistoryTab(),
                      _buildProductPricesTab(),
                      _buildStatisticsTab(),
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.onPrimary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onPrimary.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        value,
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportHistoryTab() {
    if (_importHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history, size: 48, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có lịch sử nhập hàng',
              style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              'Các lần nhập hàng sẽ hiển thị ở đây',
              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _importHistory.length,
      itemBuilder: (context, index) {
        final item = _importHistory[index];
        final date = DateTime.fromMillisecondsSinceEpoch(item['importDate']);
        final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline.withOpacity(0.3)),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.inventory, color: AppColors.primary, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item['productName'] ?? 'N/A',
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        formattedDate,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailChip(
                        'IMEI/Serial',
                        item['imei'] ?? 'N/A',
                        Icons.qr_code,
                        AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDetailChip(
                        'Số lượng',
                        '${item['quantity'] ?? 0} cái',
                        Icons.numbers,
                        AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailChip(
                        'Giá nhập',
                        '${NumberFormat('#,###').format(item['costPrice'] ?? 0)} đ',
                        Icons.attach_money,
                        AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDetailChip(
                        'Tổng tiền',
                        '${NumberFormat('#,###').format(item['totalAmount'] ?? 0)} đ',
                        Icons.account_balance_wallet,
                        AppColors.error,
                      ),
                    ),
                  ],
                ),
                if (item['notes'] != null && item['notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.outline.withOpacity(0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ghi chú: ${item['notes']}',
                            style: AppTextStyles.body2.copyWith(
                              color: AppColors.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductPricesTab() {
    if (_productPrices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.price_change, size: 48, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có thông tin giá sản phẩm',
              style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              'Giá sản phẩm từ nhà cung cấp sẽ hiển thị ở đây',
              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _productPrices.length,
      itemBuilder: (context, index) {
        final price = _productPrices[index];
        final lastUpdated = DateTime.fromMillisecondsSinceEpoch(price['lastUpdated']);
        final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(lastUpdated);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline.withOpacity(0.3)),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.inventory_2, color: AppColors.primary, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        price['productName'] ?? 'N/A',
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (price['productBrand'] != null) ...[
                      Expanded(
                        child: _buildPriceDetailChip(
                          'Thương hiệu',
                          price['productBrand'],
                          Icons.business,
                          AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (price['productModel'] != null) ...[
                      Expanded(
                        child: _buildPriceDetailChip(
                          'Model',
                          price['productModel'],
                          Icons.devices,
                          AppColors.info,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.attach_money, size: 16, color: AppColors.success),
                                const SizedBox(width: 6),
                                Text(
                                  'Giá nhập',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${NumberFormat('#,###').format(price['costPrice'] ?? 0)} đ',
                              style: AppTextStyles.headline6.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.update, size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Cập nhật',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: AppTextStyles.body2.copyWith(
                                color: AppColors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPriceDetailChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsTab() {
    if (_stats == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.analytics, size: 48, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có dữ liệu thống kê',
              style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            Text(
              'Thống kê sẽ hiển thị sau khi có dữ liệu nhập hàng',
              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tổng quan hoạt động
          _buildStatSection(
            'Tổng quan hoạt động',
            Icons.business_center,
            AppColors.primary,
            [
              _buildStatMetric('Tổng số lần nhập hàng', '${_stats!['totalImports'] ?? 0} lần', Icons.inventory),
              _buildStatMetric('Tổng số lượng sản phẩm', '${_stats!['totalQuantity'] ?? 0} cái', Icons.numbers),
              _buildStatMetric('Tổng giá trị nhập hàng', '${NumberFormat('#,###').format(_stats!['totalAmount'] ?? 0)} đ', Icons.account_balance_wallet),
              _buildStatMetric('Số loại sản phẩm khác nhau', '${_stats!['uniqueProducts'] ?? 0} loại', Icons.category),
            ],
          ),

          const SizedBox(height: 24),

          // Thống kê giá cả
          _buildStatSection(
            'Thống kê giá cả',
            Icons.attach_money,
            AppColors.success,
            [
              _buildStatMetric('Giá nhập trung bình', '${NumberFormat('#,###').format(_stats!['avgPrice'] ?? 0)} đ', Icons.trending_up),
              _buildStatMetric('Giá nhập thấp nhất', '${NumberFormat('#,###').format(_stats!['minPrice'] ?? 0)} đ', Icons.arrow_downward),
              _buildStatMetric('Giá nhập cao nhất', '${NumberFormat('#,###').format(_stats!['maxPrice'] ?? 0)} đ', Icons.arrow_upward),
              _buildStatMetric('Biên độ giá', '${NumberFormat('#,###').format((_stats!['maxPrice'] ?? 0) - (_stats!['minPrice'] ?? 0))} đ', Icons.compare_arrows),
            ],
          ),

          const SizedBox(height: 24),

          // Thời gian hoạt động
          if (_stats!['firstImportDate'] != null && _stats!['lastImportDate'] != null) ...[
            _buildStatSection(
              'Thời gian hoạt động',
              Icons.schedule,
              AppColors.secondary,
              [
                _buildStatMetric('Lần nhập đầu tiên',
                  DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_stats!['firstImportDate'])), Icons.start),
                _buildStatMetric('Lần nhập gần nhất',
                  DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_stats!['lastImportDate'])), Icons.update),
                _buildStatMetric('Thời gian hợp tác', _calculateCooperationPeriod(_stats!['firstImportDate'], _stats!['lastImportDate']), Icons.timeline),
                _buildStatMetric('Tần suất nhập hàng', _calculateImportFrequency(_stats!['totalImports'], _stats!['firstImportDate'], _stats!['lastImportDate']), Icons.repeat),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // Hiệu suất và dòng tiền
          _buildStatSection(
            'Hiệu suất & Dòng tiền',
            Icons.trending_up,
            AppColors.warning,
            [
              _buildStatMetric('Giá trị trung bình/lần nhập',
                '${NumberFormat('#,###').format((_stats!['totalAmount'] ?? 0) / (_stats!['totalImports'] ?? 1))} đ', Icons.calculate),
              _buildStatMetric('Số lượng trung bình/lần nhập',
                '${((_stats!['totalQuantity'] ?? 0) / (_stats!['totalImports'] ?? 1)).toStringAsFixed(1)} cái', Icons.inventory_2),
              _buildStatMetric('Tổng dòng tiền ra', '${NumberFormat('#,###').format(_stats!['totalAmount'] ?? 0)} đ', Icons.money_off),
              _buildStatMetric('Giá trị lớn nhất/lần nhập',
                '${NumberFormat('#,###').format(_stats!['maxSingleImport'] ?? 0)} đ', Icons.emoji_events),
            ],
          ),

          const SizedBox(height: 24),

          // Phân tích xu hướng
          _buildStatSection(
            'Phân tích xu hướng',
            Icons.insights,
            AppColors.info,
            [
              _buildStatMetric('Xu hướng nhập hàng', _calculateImportTrend(), Icons.show_chart),
              _buildStatMetric('Mức độ ổn định giá', _calculatePriceStability(), Icons.straighten),
              _buildStatMetric('Đánh giá tổng thể', _calculateOverallRating(), Icons.star),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatSection(String title, IconData icon, Color color, List<Widget> metrics) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withOpacity(0.3)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTextStyles.headline6.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: metrics),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outline.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _calculateCooperationPeriod(int firstDate, int lastDate) {
    final first = DateTime.fromMillisecondsSinceEpoch(firstDate);
    final last = DateTime.fromMillisecondsSinceEpoch(lastDate);
    final difference = last.difference(first);

    final years = difference.inDays ~/ 365;
    final months = (difference.inDays % 365) ~/ 30;
    final days = difference.inDays % 30;

    final parts = <String>[];
    if (years > 0) parts.add('$years năm');
    if (months > 0) parts.add('$months tháng');
    if (days > 0 || parts.isEmpty) parts.add('$days ngày');

    return parts.join(', ');
  }

  String _calculateImportFrequency(int totalImports, int firstDate, int lastDate) {
    final first = DateTime.fromMillisecondsSinceEpoch(firstDate);
    final last = DateTime.fromMillisecondsSinceEpoch(lastDate);
    final days = last.difference(first).inDays;

    if (days == 0) return '1 lần/ngày';

    final frequency = totalImports / days;
    if (frequency >= 1) {
      return '${frequency.toStringAsFixed(1)} lần/ngày';
    } else if (frequency >= 0.1) {
      return '${(frequency * 7).toStringAsFixed(1)} lần/tuần';
    } else {
      return '${(frequency * 30).toStringAsFixed(1)} lần/tháng';
    }
  }

  String _calculateImportTrend() {
    // Simple trend analysis based on import frequency
    final totalImports = _stats!['totalImports'] ?? 0;
    if (totalImports < 3) return 'Chưa đủ dữ liệu';

    // This would need more sophisticated analysis in a real implementation
    return 'Ổn định';
  }

  String _calculatePriceStability() {
    final minPrice = _stats!['minPrice'] ?? 0;
    final maxPrice = _stats!['maxPrice'] ?? 0;
    final avgPrice = _stats!['avgPrice'] ?? 0;

    if (avgPrice == 0) return 'N/A';

    final variance = ((maxPrice - minPrice) / avgPrice) * 100;
    if (variance < 10) return 'Rất ổn định (<10%)';
    if (variance < 25) return 'Ổn định (10-25%)';
    if (variance < 50) return 'Biến động (25-50%)';
    return 'Rất biến động (>50%)';
  }

  String _calculateOverallRating() {
    final totalImports = _stats!['totalImports'] ?? 0;
    final totalAmount = _stats!['totalAmount'] ?? 0;
    final uniqueProducts = _stats!['uniqueProducts'] ?? 0;

    if (totalImports == 0) return 'N/A';

    // Simple rating based on activity and diversity
    int score = 0;
    if (totalImports > 10) {
      score += 2;
    } else if (totalImports > 5) score += 1;

    if (totalAmount > 10000000) {
      score += 2; // 10M VND
    } else if (totalAmount > 5000000) score += 1; // 5M VND

    if (uniqueProducts > 5) {
      score += 2;
    } else if (uniqueProducts > 2) score += 1;

    if (score >= 5) return '⭐⭐⭐⭐⭐ Xuất sắc';
    if (score >= 4) return '⭐⭐⭐⭐ Tốt';
    if (score >= 3) return '⭐⭐⭐ Khá';
    if (score >= 2) return '⭐⭐ Trung bình';
    return '⭐ Cơ bản';
  }
}
