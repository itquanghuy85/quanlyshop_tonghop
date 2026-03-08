import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/shop_deduction_settings.dart';
import '../../theme/app_text_styles.dart';
import '../../services/salary_calculation_service.dart';
import '../../services/firestore_service.dart';
import '../../services/user_service.dart';

/// Dialog để thêm khoản thưởng/trừ tùy chỉnh cho nhân viên
class AddCustomAdjustmentDialog extends StatefulWidget {
  final String staffId;
  final String staffName;
  final int month;
  final int year;

  const AddCustomAdjustmentDialog({
    super.key,
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.year,
  });

  @override
  State<AddCustomAdjustmentDialog> createState() =>
      _AddCustomAdjustmentDialogState();
}

class _AddCustomAdjustmentDialogState extends State<AddCustomAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _type = 'bonus'; // bonus | deduction
  bool _isSaving = false;

  // Staff selection (when opened from settings without pre-selected staff)
  List<Map<String, dynamic>> _staffList = [];
  String? _selectedStaffId;
  String? _selectedStaffName;
  bool get _needStaffPicker => widget.staffId.isEmpty;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  final List<String> _bonusPresets = [
    'Thưởng sinh nhật',
    'Thưởng năng suất',
    'Thưởng tháng 13',
    'Thưởng lễ/tết',
    'Thưởng dự án',
    'Thưởng đột xuất',
    'Hỗ trợ đặc biệt',
  ];

  final List<String> _deductionPresets = [
    'Tạm ứng lương',
    'Phạt vi phạm',
    'Trừ đồ thất lạc',
    'Trừ hư hỏng thiết bị',
    'Khấu trừ khác',
  ];

  @override
  void initState() {
    super.initState();
    if (_needStaffPicker) _loadStaff();
  }

  Future<void> _loadStaff() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return;
    final staff = await FirestoreService.getShopStaffList(shopId);
    if (mounted) setState(() => _staffList = staff);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final cleanedAmount = _amountController.text.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final amount = double.tryParse(cleanedAmount) ?? 0;

      final finalStaffId = _needStaffPicker ? (_selectedStaffId ?? '') : widget.staffId;
      final finalStaffName = _needStaffPicker ? (_selectedStaffName ?? '') : widget.staffName;

      if (finalStaffId.isEmpty || finalStaffName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng chọn nhân viên'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final adjustment = CustomSalaryAdjustment(
        id: '',
        staffId: finalStaffId,
        staffName: finalStaffName,
        shopId: '', // Will be set in service
        month: widget.month,
        year: widget.year,
        type: _type,
        name: _nameController.text.trim(),
        amount: amount,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      final success = await SalaryCalculationService.addCustomAdjustment(
        adjustment,
      );

      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _type == 'bonus'
                    ? '✅ Đã thêm khoản thưởng'
                    : '✅ Đã thêm khoản khấu trừ',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Lỗi khi lưu'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _type == 'bonus'
                            ? Icons.card_giftcard
                            : Icons.remove_circle,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thêm khoản thưởng/trừ',
                            style: TextStyle(
                              fontSize: AppTextStyles.headline2.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _needStaffPicker
                                ? 'T${widget.month}/${widget.year}'
                                : 'Cho ${widget.staffName} - T${widget.month}/${widget.year}',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1.fontSize,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Type selector
                Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton(
                        'bonus',
                        'Thưởng',
                        Icons.add_circle,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeButton(
                        'deduction',
                        'Khấu trừ',
                        Icons.remove_circle,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Staff picker (only when no staff pre-selected)
                if (_needStaffPicker) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedStaffId,
                    decoration: const InputDecoration(
                      labelText: 'Chọn nhân viên *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                      isDense: true,
                    ),
                    items: _staffList.map((s) {
                      final String id = (s['uid'] ?? s['id'] ?? '').toString();
                      final String name = (s['name'] ?? s['displayName'] ?? 'NV').toString();
                      return DropdownMenuItem<String>(value: id, child: Text(name, style: const TextStyle(fontSize: 14)));
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedStaffId = v;
                        final match = _staffList.where(
                          (s) => (s['uid'] ?? s['id']).toString() == v,
                        );
                        if (match.isNotEmpty) {
                          _selectedStaffName = (match.first['name'] ?? match.first['displayName'] ?? '').toString();
                        }
                      });
                    },
                    validator: (v) => v == null || v.isEmpty ? 'Vui lòng chọn nhân viên' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Quick select presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      (_type == 'bonus' ? _bonusPresets : _deductionPresets)
                          .map(
                            (preset) => ActionChip(
                              label: Text(
                                preset,
                                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                              ),
                              onPressed: () {
                                _nameController.text = preset;
                              },
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 16),

                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên khoản *',
                    hintText: 'VD: Thưởng sinh nhật',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập tên'
                      : null,
                ),
                const SizedBox(height: 16),

                // Amount field
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số tiền *',
                    hintText: 'VD: 500,000',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                    suffixText: 'đ',
                    suffixStyle: TextStyle(
                      color: _type == 'bonus' ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Vui lòng nhập số tiền';
                    final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                    final amount = double.tryParse(cleaned) ?? 0;
                    if (amount <= 0) return 'Số tiền phải lớn hơn 0';
                    return null;
                  },
                  onChanged: (v) {
                    // Format currency as user types
                    final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                    final amount = double.tryParse(cleaned) ?? 0;
                    if (amount > 0) {
                      final formatted = _currencyFormat.format(amount);
                      if (formatted != v) {
                        _amountController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Note field
                TextFormField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    hintText: 'Lý do/mô tả...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_type == 'bonus' ? Icons.add : Icons.remove),
                      label: Text(
                        _type == 'bonus' ? 'Thêm thưởng' : 'Thêm khấu trừ',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _type == 'bonus'
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton(
    String type,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _type == type;
    return InkWell(
      onTap: () => setState(() => _type = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(30) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function để hiển thị dialog
Future<bool?> showAddCustomAdjustmentDialog(
  BuildContext context, {
  required String staffId,
  required String staffName,
  required int month,
  required int year,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AddCustomAdjustmentDialog(
      staffId: staffId,
      staffName: staffName,
      month: month,
      year: year,
    ),
  );
}
