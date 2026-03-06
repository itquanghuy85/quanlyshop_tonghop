import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';

class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key});
  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = await db.getAuditLogs();
    if (!mounted) return;
    setState(() {
      _logs = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          "NHẬT KÝ HỆ THỐNG",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.headline3.fontSize,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
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
              itemCount: _logs.length,
              itemBuilder: (ctx, i) => _buildLogCard(_logs[i], i + 1),
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
                    log['action'] ?? '',
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
                          log['action'] ?? '',
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
    if (action.contains("XÓA")) return Colors.red;
    if (action.contains("NHẬP") || action.contains("THÊM")) return Colors.green;
    if (action.contains("SỬA") || action.contains("CẬP NHẬT"))
      return Colors.orange;
    if (action.contains("BÁN")) return Colors.pink;
    return Colors.blue;
  }

  IconData _getActionIcon(String action) {
    if (action.contains("XÓA")) return Icons.delete_forever;
    if (action.contains("NHẬP")) return Icons.add_business;
    if (action.contains("BÁN")) return Icons.shopping_cart;
    if (action.contains("SỬA")) return Icons.edit_note;
    return Icons.info_outline;
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
