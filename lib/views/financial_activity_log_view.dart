import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import '../widgets/custom_app_bar.dart';
import '../theme/app_text_styles.dart';
import '../utils/excel_export_helper.dart';

/// Trang theo dõi nhật ký tài chính
/// Chỉ xem, không sửa - có tìm kiếm
class FinancialActivityLogView extends StatefulWidget {
  final int initialTab;
  final bool embedded;

  const FinancialActivityLogView({
    super.key,
    this.initialTab = 0,
    this.embedded = false,
  });

  @override
  State<FinancialActivityLogView> createState() =>
      _FinancialActivityLogViewState();
}

class _FinancialActivityLogViewState extends State<FinancialActivityLogView> {
  final db = DBHelper();

  List<FinancialActivity> _activities = [];
  bool _loading = true;

  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    setState(() => _loading = true);
    final data = await db.getFinancialActivities(limit: 500);
    if (!mounted) return;
    setState(() {
      _activities = data.map(FinancialActivity.fromMap).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildEmbeddedContent();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.build(
        title: 'NHẬT KÝ TÀI CHÍNH',
        subtitle: '${_filteredActivities.length} giao dịch',
        accentColor: AppBarAccents.finance,
        actions: [
          IconButton(
            onPressed: _loadActivities,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 20,
              color: Colors.white,
            ),
            tooltip: 'Làm mới',
            splashRadius: 18,
          ),
          IconButton(
            icon: const Icon(
              Icons.file_download_outlined,
              size: 20,
              color: Colors.white,
            ),
            tooltip: 'Xuất Excel nhật ký tài chính',
            splashRadius: 18,
            onPressed: () async {
              final activities = _filteredActivities;
              if (activities.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Không có dữ liệu để xuất')),
                );
                return;
              }
              if (!mounted) return;
              await ExcelExportHelper.exportActivityLog(
                context,
                activities: activities,
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            color: Colors.white,
            child: _buildSearchField(),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: _buildActivityTab(),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(17),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        style: TextStyle(
          color: CustomAppBar.kTextPrimary,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        cursorColor: AppBarAccents.finance,
        decoration: InputDecoration(
          hintText: 'Tìm theo loại, tiêu đề, người tạo, mô tả...',
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: AppTextStyles.subtitle1.fontSize,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppBarAccents.finance,
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.grey.shade500,
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  splashRadius: 14,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
      ),
    );
  }

  Widget _buildEmbeddedContent() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.history, size: 16, color: AppBarAccents.finance),
              const SizedBox(width: 6),
              Text(
                'Nhật ký tài chính',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  color: AppBarAccents.finance,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadActivities,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppBarAccents.finance,
                ),
                tooltip: 'Làm mới',
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          color: Colors.white,
          child: _buildSearchField(),
        ),
        Expanded(
          child: _buildActivityTab(),
        ),
      ],
    );
  }

  List<FinancialActivity> get _filteredActivities {
    if (_searchQuery.isEmpty) return _activities;
    final query = _searchQuery.toLowerCase();
    return _activities.where((activity) {
      return activity.activityType.toLowerCase().contains(query) ||
          activity.activityTypeName.toLowerCase().contains(query) ||
          activity.title.toLowerCase().contains(query) ||
          (activity.description ?? '').toLowerCase().contains(query) ||
          (activity.createdBy ?? '').toLowerCase().contains(query) ||
          (activity.customerName ?? '').toLowerCase().contains(query) ||
          (activity.referenceType ?? '').toLowerCase().contains(query) ||
          (activity.referenceId ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildActivityTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredActivities;
    return Column(
      children: [
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Tìm thấy ${filtered.length} kết quả',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Không tìm thấy kết quả cho "$_searchQuery"'
                            : 'Chưa có giao dịch tài chính nào',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildActivityCard(filtered[index], index + 1),
                ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(FinancialActivity activity, int index) {
    final date = DateTime.fromMillisecondsSinceEpoch(activity.createdAt);
    final actionColor = _getActivityColor(activity);
    final amountPrefix = activity.direction == 'IN'
        ? '+'
        : activity.direction == 'OUT'
            ? '-'
            : '';
    final amountColor = activity.direction == 'IN'
        ? Colors.green
        : activity.direction == 'OUT'
            ? Colors.red
            : Colors.orange;

    return GestureDetector(
      onTap: () => _showActivityDetail(activity),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: actionColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        fontWeight: FontWeight.bold,
                        color: actionColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: actionColor.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getActivityIcon(activity),
                    color: actionColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.activityTypeName,
                        style: TextStyle(
                          color: actionColor,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        activity.title,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: AppTextStyles.caption.fontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$amountPrefix${NumberFormat('#,###').format(activity.amount)}',
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('HH:mm').format(date),
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if ((activity.description ?? '').isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  activity.description ?? '',
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 12,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            activity.createdBy ?? '-',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if ((activity.referenceType ?? '').isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _getReferenceTypeColor(activity.referenceType!)
                          .withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getReferenceTypeName(activity.referenceType!),
                      style: TextStyle(
                        fontSize: AppTextStyles.caption.fontSize,
                        fontWeight: FontWeight.bold,
                        color: _getReferenceTypeColor(activity.referenceType!),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  DateFormat('dd/MM').format(date),
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActivityDetail(FinancialActivity activity) {
    final date = DateTime.fromMillisecondsSinceEpoch(activity.createdAt);
    final actionColor = _getActivityColor(activity);
    final directionLabel = _directionName(activity.direction);
    final amountPrefix = activity.direction == 'IN'
        ? '+'
        : activity.direction == 'OUT'
            ? '-'
            : '';

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: actionColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getActivityIcon(activity),
                      color: actionColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.activityTypeName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextStyles.headline2.fontSize,
                            color: actionColor,
                          ),
                        ),
                        Text(
                          DateFormat('HH:mm - dd/MM/yyyy').format(date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: AppTextStyles.body1.fontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              _buildDetailRow('Loại giao dịch', activity.activityTypeName),
              _buildDetailRow('Tiêu đề', activity.title),
              _buildDetailRow('Chiều', directionLabel),
              _buildDetailRow(
                'Số tiền',
                '$amountPrefix${NumberFormat('#,###').format(activity.amount)}',
              ),
              _buildDetailRow('PT thanh toán', activity.paymentMethod),
              _buildDetailRow('Người thực hiện', activity.createdBy ?? 'Unknown'),
              if ((activity.customerName ?? '').isNotEmpty)
                _buildDetailRow('Khách hàng / NCC', activity.customerName!),
              if ((activity.phone ?? '').isNotEmpty)
                _buildDetailRow('Số điện thoại', activity.phone!),
              if ((activity.productInfo ?? '').isNotEmpty)
                _buildDetailRow('Sản phẩm', activity.productInfo!),
              if ((activity.referenceType ?? '').isNotEmpty)
                _buildDetailRow(
                  'Loại tham chiếu',
                  _getReferenceTypeName(activity.referenceType!),
                ),
              if ((activity.referenceId ?? '').isNotEmpty)
                _buildDetailRow('ID tham chiếu', activity.referenceId!),
              if ((activity.description ?? '').isNotEmpty)
                _buildDetailRow('Mô tả', activity.description!),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: AppTextStyles.body1.fontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: AppTextStyles.body1.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getReferenceTypeColor(String referenceType) {
    switch (referenceType.toUpperCase()) {
      case 'PRODUCT':
        return Colors.indigo;
      case 'SALE':
        return Colors.pink;
      case 'DEBT':
      case 'DEBT_PAYMENT':
        return Colors.deepOrange;
      case 'SUPPLIER':
      case 'SUPPLIER_PAYMENT':
        return Colors.teal;
      case 'STAFF':
        return Colors.orange;
      case 'EXPENSE':
        return Colors.red;
      case 'REPAIR':
        return Colors.blue;
      case 'CASH_CLOSING':
      case 'CASH_CLOSE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getReferenceTypeName(String referenceType) {
    switch (referenceType.toUpperCase()) {
      case 'PRODUCT':
        return 'Sản phẩm';
      case 'SALE':
        return 'Đơn bán';
      case 'DEBT':
      case 'DEBT_PAYMENT':
        return 'Công nợ';
      case 'SUPPLIER':
      case 'SUPPLIER_PAYMENT':
        return 'NCC';
      case 'STAFF':
        return 'Nhân viên';
      case 'EXPENSE':
        return 'Chi phí';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'CASH_CLOSING':
      case 'CASH_CLOSE':
        return 'Chốt sổ';
      default:
        return referenceType;
    }
  }

  Color _getActivityColor(FinancialActivity activity) {
    switch (activity.direction) {
      case 'IN':
        return Colors.green;
      case 'OUT':
        return Colors.red;
      case 'DEBT':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getActivityIcon(FinancialActivity activity) {
    switch (activity.activityType) {
      case 'SALE':
      case 'SALE_PAYMENT':
      case 'SALE_INSTALLMENT':
        return Icons.shopping_cart;
      case 'PURCHASE':
      case 'INVENTORY_PURCHASE':
      case 'SUPPLIER_PURCHASE':
      case 'PARTS_STOCK_IN':
        return Icons.inventory_2;
      case 'EXPENSE':
      case 'OPERATING_EXPENSE':
      case 'UTILITY_EXPENSE':
      case 'OTHER_EXPENSE':
        return Icons.money_off;
      case 'DEBT_COLLECT':
      case 'CUSTOMER_DEBT_COLLECT':
        return Icons.arrow_circle_down_rounded;
      case 'DEBT_PAY':
      case 'SUPPLIER_DEBT':
      case 'REPAIR_PARTNER_DEBT':
      case 'OTHER_DEBT':
        return Icons.arrow_circle_up_rounded;
      case 'SETTLEMENT':
        return Icons.account_balance;
      case 'REPAIR':
      case 'REPAIR_SERVICE':
        return Icons.build;
      case 'REFUND':
      case 'CUSTOMER_REFUND':
        return Icons.undo;
      default:
        return Icons.receipt_long;
    }
  }

  String _directionName(String direction) {
    switch (direction) {
      case 'IN':
        return 'Thu';
      case 'OUT':
        return 'Chi';
      case 'DEBT':
        return 'Công nợ';
      default:
        return direction;
    }
  }
}
