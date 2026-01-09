import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/adjustment_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// View hiển thị lịch sử bút toán điều chỉnh
class AdjustmentHistoryView extends StatefulWidget {
  final String? entityType;
  final String? entityId;

  const AdjustmentHistoryView({
    super.key,
    this.entityType,
    this.entityId,
  });

  @override
  State<AdjustmentHistoryView> createState() => _AdjustmentHistoryViewState();
}

class _AdjustmentHistoryViewState extends State<AdjustmentHistoryView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _adjustments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdjustments();
  }

  Future<void> _loadAdjustments() async {
    setState(() => _isLoading = true);
    
    final adjustments = await AdjustmentService.getAdjustmentHistory(
      entityType: widget.entityType,
      entityId: widget.entityId,
      limit: 100,
    );
    
    if (!mounted) return;
    setState(() {
      _adjustments = adjustments;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "LỊCH SỬ ĐIỀU CHỈNH",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAdjustments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _adjustments.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text(
            "Chưa có bút toán điều chỉnh nào",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _adjustments.length,
      itemBuilder: (ctx, i) => _buildAdjustmentCard(_adjustments[i]),
    );
  }

  Widget _buildAdjustmentCard(Map<String, dynamic> adj) {
    final adjustmentDate = DateTime.fromMillisecondsSinceEpoch(
      adj['adjustmentDate'] as int? ?? 0,
    );
    final originalDate = DateTime.fromMillisecondsSinceEpoch(
      adj['originalDate'] as int? ?? 0,
    );
    final adjustmentType = adj['adjustmentType'] as String? ?? '';
    final description = adj['description'] as String? ?? '';
    final reason = adj['reason'] as String? ?? '';
    final createdBy = adj['createdBy'] as String? ?? 'N/A';
    final costDelta = adj['costDelta'] as int? ?? 0;
    final debtDelta = adj['debtDelta'] as int? ?? 0;
    
    // Parse old/new values
    Map<String, dynamic> oldValues = {};
    Map<String, dynamic> newValues = {};
    try {
      if (adj['oldValues'] != null) {
        oldValues = jsonDecode(adj['oldValues'] as String);
      }
      if (adj['newValues'] != null) {
        newValues = jsonDecode(adj['newValues'] as String);
      }
    } catch (_) {}
    
    final typeColor = _getTypeColor(adjustmentType);
    final typeIcon = _getTypeIcon(adjustmentType);
    final typeLabel = _getTypeLabel(adjustmentType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        description,
                        style: AppTextStyles.body2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dates
                Row(
                  children: [
                    const Icon(Icons.event_note, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      "Ngày gốc: ${DateFormat('dd/MM/yyyy').format(originalDate)}",
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.edit_calendar, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      "Điều chỉnh: ${DateFormat('dd/MM/yyyy HH:mm').format(adjustmentDate)}",
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Reason
                if (reason.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notes, size: 14, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Lý do: $reason",
                            style: AppTextStyles.caption.copyWith(color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Deltas
                if (costDelta != 0 || debtDelta != 0)
                  Row(
                    children: [
                      if (costDelta != 0)
                        _buildDeltaChip(
                          "Chi phí",
                          costDelta,
                          costDelta > 0 ? Colors.red : Colors.green,
                        ),
                      if (costDelta != 0) const SizedBox(width: 8),
                      if (debtDelta != 0)
                        _buildDeltaChip(
                          "Công nợ",
                          debtDelta,
                          debtDelta > 0 ? Colors.orange : Colors.green,
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                // Old -> New values
                if (oldValues.isNotEmpty || newValues.isNotEmpty)
                  _buildValueComparison(oldValues, newValues),
                const SizedBox(height: 8),
                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Người thực hiện: $createdBy",
                      style: AppTextStyles.overline.copyWith(color: Colors.grey),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "ĐÃ DUYỆT",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeltaChip(String label, int delta, Color color) {
    final sign = delta > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        "$label: $sign${NumberFormat('#,###').format(delta)}đ",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildValueComparison(Map<String, dynamic> oldVals, Map<String, dynamic> newVals) {
    final allKeys = {...oldVals.keys, ...newVals.keys};
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Chi tiết thay đổi:",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...allKeys.map((key) {
            final oldVal = oldVals[key];
            final newVal = newVals[key];
            final oldStr = _formatValue(oldVal);
            final newStr = _formatValue(newVal);
            
            if (oldStr == newStr) return const SizedBox.shrink();
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(
                    "${_translateKey(key)}: ",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    oldStr,
                    style: const TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: Colors.red,
                    ),
                  ),
                  const Text(" → ", style: TextStyle(fontSize: 11)),
                  Text(
                    newStr,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is int) {
      return '${NumberFormat('#,###').format(value)}đ';
    }
    return value.toString();
  }

  String _translateKey(String key) {
    switch (key) {
      case 'cost': return 'Giá vốn';
      case 'totalCost': return 'Tổng giá vốn';
      case 'totalAmount': return 'Tổng tiền';
      case 'paidAmount': return 'Đã thanh toán';
      case 'paymentMethod': return 'Hình thức TT';
      default: return key;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'COST_ADJUSTMENT': return Colors.orange;
      case 'PAYMENT_ADJUSTMENT': return Colors.blue;
      case 'DEBT_ADJUSTMENT': return Colors.purple;
      default: return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'COST_ADJUSTMENT': return Icons.price_change;
      case 'PAYMENT_ADJUSTMENT': return Icons.payment;
      case 'DEBT_ADJUSTMENT': return Icons.account_balance_wallet;
      default: return Icons.edit_document;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'COST_ADJUSTMENT': return 'ĐIỀU CHỈNH GIÁ NHẬP';
      case 'PAYMENT_ADJUSTMENT': return 'ĐIỀU CHỈNH THANH TOÁN';
      case 'DEBT_ADJUSTMENT': return 'ĐIỀU CHỈNH CÔNG NỢ';
      default: return 'BÚT TOÁN ĐIỀU CHỈNH';
    }
  }
}
