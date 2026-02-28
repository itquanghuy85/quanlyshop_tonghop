import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Dialog for selecting date range filter before Excel export.
/// Returns a map with 'startMs' and 'endMs' (milliseconds) or null if cancelled.
class ExportDateFilterDialog extends StatefulWidget {
  final String title;

  const ExportDateFilterDialog({
    super.key,
    this.title = 'Xuất Excel',
  });

  /// Show the dialog and return date range or null
  static Future<Map<String, int>?> show(
    BuildContext context, {
    String title = 'Xuất Excel',
  }) {
    return showDialog<Map<String, int>?>(
      context: context,
      builder: (_) => ExportDateFilterDialog(title: title),
    );
  }

  @override
  State<ExportDateFilterDialog> createState() =>
      _ExportDateFilterDialogState();
}

class _ExportDateFilterDialogState extends State<ExportDateFilterDialog> {
  // 0 = Tất cả, 1 = Hôm nay, 2 = Tuần này, 3 = Tháng này, 4 = Tuỳ chọn
  int _selectedFilter = 0;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.file_download_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chọn khoảng thời gian:',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            _buildFilterOption(0, 'Tất cả', Icons.all_inclusive),
            _buildFilterOption(1, 'Hôm nay', Icons.today),
            _buildFilterOption(2, 'Tuần này', Icons.date_range),
            _buildFilterOption(3, 'Tháng này', Icons.calendar_month),
            _buildFilterOption(4, 'Tháng trước', Icons.calendar_view_month),
            _buildFilterOption(5, 'Tuỳ chọn...', Icons.edit_calendar),
            if (_selectedFilter == 5) ...[
              const SizedBox(height: 16),
              _buildDatePicker(
                label: 'Từ ngày',
                date: _startDate,
                onTap: () => _pickDate(true),
              ),
              const SizedBox(height: 8),
              _buildDatePicker(
                label: 'Đến ngày',
                date: _endDate,
                onTap: () => _pickDate(false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          onPressed: _onExport,
          icon: const Icon(Icons.file_download, size: 18),
          label: const Text('Xuất Excel'),
        ),
      ],
    );
  }

  Widget _buildFilterOption(int value, String label, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedFilter == value;

    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 8),
            Text(
              date != null
                  ? DateFormat('dd/MM/yyyy').format(date)
                  : label,
              style: TextStyle(
                color: date != null ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? now),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _onExport() {
    final now = DateTime.now();
    int? startMs;
    int? endMs;

    switch (_selectedFilter) {
      case 0: // Tất cả
        break;
      case 1: // Hôm nay
        final today = DateTime(now.year, now.month, now.day);
        startMs = today.millisecondsSinceEpoch;
        endMs = today
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1))
            .millisecondsSinceEpoch;
        break;
      case 2: // Tuần này
        final weekday = now.weekday; // 1=Mon -> 7=Sun
        final startOfWeek = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        startMs = startOfWeek.millisecondsSinceEpoch;
        endMs = now.millisecondsSinceEpoch;
        break;
      case 3: // Tháng này
        final startOfMonth = DateTime(now.year, now.month, 1);
        startMs = startOfMonth.millisecondsSinceEpoch;
        endMs = now.millisecondsSinceEpoch;
        break;
      case 4: // Tháng trước
        final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
        final endOfLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        startMs = startOfLastMonth.millisecondsSinceEpoch;
        endMs = endOfLastMonth.millisecondsSinceEpoch;
        break;
      case 5: // Tuỳ chọn
        if (_startDate == null || _endDate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng chọn cả ngày bắt đầu và kết thúc')),
          );
          return;
        }
        startMs = _startDate!.millisecondsSinceEpoch;
        endMs = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
          23,
          59,
          59,
          999,
        ).millisecondsSinceEpoch;
        break;
    }

    if (startMs != null && endMs != null) {
      Navigator.pop(context, {'startMs': startMs, 'endMs': endMs});
    } else {
      Navigator.pop(context, <String, int>{});
    }
  }
}
