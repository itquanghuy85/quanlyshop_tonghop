import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/custom_app_bar.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../services/user_service.dart';

class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key});
  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  final db = DBHelper();
  static const int _pageSize = 60;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _refresh();
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewRevenue'] ?? false);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = await db.getAuditLogs(limit: _pageSize, offset: 0);
    if (!mounted) return;
    setState(() {
      _logs = data;
      _offset = data.length;
      _hasMore = data.length >= _pageSize;
      _isLoadingMore = false;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final data = await db.getAuditLogs(limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        _logs.addAll(data);
        _offset += data.length;
        _hasMore = data.length >= _pageSize;
      });
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: CustomAppBar.build(
          title: 'NHẬT KÝ HỆ THỐNG',
          accentColor: AppBarAccents.finance,
        ),
        body: const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: CustomAppBar.build(
        title: 'NHẬT KÝ HỆ THỐNG',
        subtitle: '${_logs.length} ghi chép đã tải',
        accentColor: AppBarAccents.finance,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
            splashRadius: 18,
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
            ? _buildEmpty()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _logs.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == _logs.length) {
                    if (_isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!_hasMore) {
                      return const SizedBox(height: 8);
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('Tải thêm'),
                        ),
                      ),
                    );
                  }
                  return _buildLogCard(_logs[i], i + 1);
                },
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 10),
          const Text(
            "Chưa có ghi chép hoạt động nào",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, int index) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(log['createdAt']);
    final Color actionColor = _getActionColor(log['action'] ?? '');
    final String actionLabel = _displayAction(log['action']);
    final String entityType = log['targetType'] ?? log['entityType'] ?? '';
    final String entityId = log['targetId'] ?? log['entityId'] ?? '';
    final String description = log['description'] ?? log['summary'] ?? '';

    return GestureDetector(
      onTap: () => _showLogDetail(log),
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
            // Header row: STT + Action + Time
            Row(
              children: [
                // STT badge
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
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: actionColor.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getActionIcon(log['action'] ?? ''),
                    color: actionColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                // Action name
                Expanded(
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.body1.fontSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Time badge
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
            // Content row: Description
            if (description.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 10),
            // Footer row: User, EntityType, Date
            Row(
              children: [
                // User badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        log['userName'] ?? 'Unknown',
                        style: TextStyle(
                          fontSize: AppTextStyles.caption.fontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // EntityType badge
                if (entityType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getEntityTypeColor(entityType).withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getEntityTypeName(entityType),
                      style: TextStyle(
                        fontSize: AppTextStyles.caption.fontSize,
                        fontWeight: FontWeight.bold,
                        color: _getEntityTypeColor(entityType),
                      ),
                    ),
                  ),
                const Spacer(),
                // Date
                Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: TextStyle(
                    fontSize: AppTextStyles.caption.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLogDetail(Map<String, dynamic> log) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(log['createdAt']);
    final Color actionColor = _getActionColor(log['action'] ?? '');
    final String actionLabel = _displayAction(log['action']);
    final String entityType = log['targetType'] ?? log['entityType'] ?? '';
    final String entityId = log['targetId'] ?? log['entityId'] ?? '';
    final String description = log['description'] ?? log['summary'] ?? '';

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
              // Handle bar
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
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: actionColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getActionIcon(log['action'] ?? ''),
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
                          actionLabel,
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
              // Details
              _buildDetailRow('Người thực hiện', log['userName'] ?? 'Unknown'),
              if (log['email'] != null && log['email'].toString().isNotEmpty)
                _buildDetailRow('Email', log['email'].toString()),
              if (log['role'] != null && log['role'].toString().isNotEmpty)
                _buildDetailRow('Vai trò', log['role'].toString()),
              if (entityType.isNotEmpty)
                _buildDetailRow(
                  'Loại đối tượng',
                  _getEntityTypeName(entityType),
                ),
              if (entityId.isNotEmpty)
                _buildDetailRow('ID đối tượng', entityId),
              if (description.isNotEmpty) _buildDetailRow('Mô tả', description),
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

  Color _getActionColor(String action) {
    final upper = action.toUpperCase();
    if (upper.contains('XÓA') ||
        upper.contains('DELETE') ||
        upper.contains('REMOVE'))
      return Colors.red;
    if (upper.contains('NHẬP') ||
        upper.contains('THÊM') ||
        upper.contains('CREATE') ||
        upper.contains('ADD'))
      return Colors.green;
    if (upper.contains('SỬA') ||
        upper.contains('CẬP NHẬT') ||
        upper.contains('UPDATE') ||
        upper.contains('EDIT'))
      return Colors.orange;
    if (upper.contains('BÁN') || upper.contains('SALE')) return Colors.pink;
    if (upper.contains('THU NỢ') || upper.contains('DEBT_COLLECT'))
      return Colors.teal;
    if (upper.contains('TRẢ NỢ') ||
        upper.contains('DEBT_PAY') ||
        upper.contains('SUPPLIER_PAID'))
      return Colors.deepOrange;
    return Colors.blue;
  }

  IconData _getActionIcon(String action) {
    final upper = action.toUpperCase();
    if (upper.contains('XÓA') ||
        upper.contains('DELETE') ||
        upper.contains('REMOVE'))
      return Icons.delete_forever;
    if (upper.contains('NHẬP') ||
        upper.contains('IMPORT') ||
        upper.contains('ADD'))
      return Icons.add_business;
    if (upper.contains('BÁN') || upper.contains('SALE'))
      return Icons.shopping_cart;
    if (upper.contains('SỬA') ||
        upper.contains('UPDATE') ||
        upper.contains('EDIT'))
      return Icons.edit_note;
    if (upper.contains('DEBT_COLLECT') || upper.contains('THU NỢ'))
      return Icons.call_received;
    if (upper.contains('DEBT_PAY') ||
        upper.contains('SUPPLIER_PAID') ||
        upper.contains('TRẢ NỢ'))
      return Icons.call_made;
    return Icons.info_outline;
  }

  String _displayAction(dynamic actionValue) {
    final raw = (actionValue ?? '').toString().trim();
    if (raw.isEmpty) return 'Nhật ký hệ thống';

    const directMap = {
      'DEBT_COLLECTED': 'Thu nợ khách hàng',
      'DEBT_COLLECT': 'Thu nợ khách hàng',
      'SUPPLIER_PAID': 'Trả nợ nhà cung cấp',
      'PART_IMPORT': 'Nhập kho linh kiện',
      'PART_INFO_UPDATE': 'Cập nhật thông tin linh kiện',
      'PART_ADD_STOCK': 'Bổ sung tồn kho linh kiện',
      'DELETE_PART': 'Xóa linh kiện',
      'PAYMENT_REQUEST_CREATED': 'Tạo yêu cầu đóng tiền',
      'PAYMENT_REQUEST_APPROVED': 'Duyệt yêu cầu đóng tiền',
      'PAYMENT_REQUEST_REJECTED': 'Từ chối yêu cầu đóng tiền',
    };

    final upper = raw.toUpperCase();
    if (directMap.containsKey(upper)) return directMap[upper]!;

    if (!upper.contains('_')) return raw;

    const tokenMap = {
      'DEBT': 'công nợ',
      'COLLECT': 'thu',
      'COLLECTED': 'đã thu',
      'PAY': 'trả',
      'PAID': 'đã trả',
      'SUPPLIER': 'nhà cung cấp',
      'CUSTOMER': 'khách hàng',
      'PART': 'linh kiện',
      'IMPORT': 'nhập kho',
      'ADD': 'thêm',
      'STOCK': 'tồn kho',
      'INFO': 'thông tin',
      'UPDATE': 'cập nhật',
      'DELETE': 'xóa',
      'CREATE': 'tạo',
      'PAYMENT': 'thanh toán',
      'REQUEST': 'yêu cầu',
      'APPROVED': 'đã duyệt',
      'REJECTED': 'đã từ chối',
      'SALE': 'bán hàng',
      'REPAIR': 'sửa chữa',
    };

    final words = upper
        .split('_')
        .where((t) => t.isNotEmpty)
        .map((t) => tokenMap[t] ?? t.toLowerCase())
        .join(' ')
        .trim();
    if (words.isEmpty) return raw;
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  Color _getEntityTypeColor(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PRODUCT':
        return Colors.indigo;
      case 'SALE':
        return Colors.pink;
      case 'SUPPLIER':
        return Colors.teal;
      case 'STAFF':
        return Colors.orange;
      case 'EXPENSE':
        return Colors.red;
      case 'REPAIR':
        return Colors.blue;
      case 'CASH_CLOSE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getEntityTypeName(String entityType) {
    switch (entityType.toUpperCase()) {
      case 'PRODUCT':
        return 'Sản phẩm';
      case 'SALE':
        return 'Đơn bán';
      case 'SUPPLIER':
        return 'NCC';
      case 'STAFF':
        return 'Nhân viên';
      case 'EXPENSE':
        return 'Chi phí';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'CASH_CLOSE':
        return 'Chốt sổ';
      default:
        return entityType;
    }
  }
}
