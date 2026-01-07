import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

/// Widget nhập tiền chuẩn hóa cho toàn app.
///
/// QUY TẮC:
/// 1. Trong lúc nhập: không thay đổi giá trị, chỉ cho nhập số
/// 2. Khi nhập xong (mất focus / Enter / Xác nhận): tự động thêm 000
/// 3. Hiển thị dạng: x.xxx.xxx (dấu chấm ngăn cách hàng nghìn)
/// 4. Lưu số nguyên đầy đủ (VNĐ)
///
/// Ví dụ:
/// - Nhập "500" → Hiển thị "500.000" → Lưu 500000
/// - Nhập "1500" → Hiển thị "1.500.000" → Lưu 1500000
/// - Nhập "1500000" (>= 100000) → Hiển thị "1.500.000" → Lưu 1500000 (không nhân)
class CurrencyTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool required;
  final bool enabled;
  final VoidCallback? onSubmitted;
  final Function(String)? onChanged; // Legacy callback - trả về string
  final Function(int)? onValueChanged; // New callback - trả về int
  final bool
  autoMultiply1000; // Mặc định true - tự động nhân 1000 khi số < 100000

  const CurrencyTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.required = false,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.onValueChanged,
    this.autoMultiply1000 = true,
  });

  @override
  State<CurrencyTextField> createState() => _CurrencyTextFieldState();

  /// Lấy giá trị số nguyên (VNĐ) từ controller - CHỈ PARSE, KHÔNG NHÂN 1000
  /// ⚠️ KHÔNG NÊN DÙNG nếu muốn áp dụng rule x1000
  /// Dùng [getValueWithMultiply] thay thế
  static int getValue(TextEditingController controller) {
    final text = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(text) ?? 0;
  }

  /// Lấy giá trị số nguyên (VNĐ) từ controller VỚI RULE NHÂN 1000 nếu < 100000
  /// ✅ PHẢI DÙNG method này khi lưu dữ liệu để đảm bảo nhất quán
  static int getValueWithMultiply(
    TextEditingController controller, {
    bool autoMultiply1000 = true,
  }) {
    final rawAmount = parseValue(controller.text);
    if (autoMultiply1000 && rawAmount < 100000) {
      return rawAmount * 1000;
    }
    return rawAmount;
  }

  /// Format số thành chuỗi hiển thị (x.xxx.xxx)
  static String formatDisplay(int value) {
    if (value == 0) return '';
    return NumberFormat('#,###', 'vi_VN').format(value).replaceAll(',', '.');
  }

  /// Parse chuỗi thành số nguyên - CHỈ PARSE, KHÔNG NHÂN 1000
  /// ⚠️ KHÔNG NÊN DÙNG trực tiếp nếu muốn áp dụng rule x1000
  static int parseValue(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  /// Parse chuỗi thành số nguyên VỚI RULE NHÂN 1000 nếu < 100000
  /// ✅ PHẢI DÙNG method này khi lưu dữ liệu để đảm bảo nhất quán
  static int parseValueWithMultiply(
    String text, {
    bool autoMultiply1000 = true,
  }) {
    final rawAmount = parseValue(text);
    if (autoMultiply1000 && rawAmount < 100000) {
      return rawAmount * 1000;
    }
    return rawAmount;
  }
}

class _CurrencyTextFieldState extends State<CurrencyTextField> {
  String? _errorText;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      // Khi focus: chuyển về số thô để dễ chỉnh sửa
      _isEditing = true;
      final currentValue = CurrencyTextField.parseValue(widget.controller.text);
      if (currentValue > 0) {
        // Hiển thị số gốc (chia 1000 nếu đã nhân trước đó)
        final rawValue = widget.autoMultiply1000 && currentValue >= 1000
            ? (currentValue ~/ 1000).toString()
            : currentValue.toString();
        widget.controller.value = TextEditingValue(
          text: rawValue,
          selection: TextSelection.collapsed(offset: rawValue.length),
        );
      }
    } else {
      // Khi mất focus: finalize input
      if (_isEditing) {
        _finalizeInput();
      }
    }
  }

  void _validate() {
    final value = widget.controller.text;
    String? error;
    if (widget.required && value.trim().isEmpty) {
      error = '${widget.label} không được để trống';
    }
    if (mounted) setState(() => _errorText = error);
  }

  void _onChanged(String value) {
    // Trong lúc nhập: chỉ giữ số, không format
    _validate();
  }

  void _finalizeInput() {
    _isEditing = false;
    final text = widget.controller.text.trim();

    if (text.isEmpty) {
      widget.onChanged?.call('0');
      widget.onValueChanged?.call(0);
      return;
    }

    // Parse số từ text
    final rawAmount = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (rawAmount <= 0) {
      widget.controller.clear();
      widget.onChanged?.call('0');
      widget.onValueChanged?.call(0);
      return;
    }

    // Tính giá trị thực:
    // - Nếu < 100000 và autoMultiply1000 = true → nhân 1000
    // - Ngược lại giữ nguyên
    int actualAmount = rawAmount;
    if (widget.autoMultiply1000 && rawAmount < 100000) {
      actualAmount = rawAmount * 1000;
    }

    // Format và hiển thị
    final formatted = CurrencyTextField.formatDisplay(actualAmount);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    widget.onChanged?.call(actualAmount.toString());
    widget.onValueChanged?.call(actualAmount);
  }

  void _onSubmitted(String value) {
    _finalizeInput();
    widget.onSubmitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          enabled: widget.enabled,
          onChanged: _onChanged,
          onEditingComplete: _finalizeInput,
          onSubmitted: _onSubmitted,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: widget.required ? '${widget.label} *' : widget.label,
            hintText:
                widget.hint ??
                (widget.autoMultiply1000
                    ? 'Nhập số (500 = 500.000đ)'
                    : 'Nhập số tiền'),
            prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
            suffixText: widget.autoMultiply1000 ? '.000' : 'đ',
            suffixStyle: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            errorText: _errorText,
            filled: true,
            fillColor: widget.enabled ? Colors.white : Colors.grey.shade100,
          ),
          style: AppTextStyles.body1.copyWith(
            color: widget.enabled
                ? AppColors.onSurface
                : AppColors.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Widget nhập tiền với các nút chọn nhanh
class EnhancedCurrencyInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool required;
  final bool enabled;
  final VoidCallback? onSubmitted;
  final Function(String)? onChanged;
  final Function(int)? onValueChanged;
  final List<int>? quickAmounts; // Số tiền đầy đủ (VNĐ)

  const EnhancedCurrencyInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.required = false,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.onValueChanged,
    this.quickAmounts,
  });

  @override
  State<EnhancedCurrencyInput> createState() => _EnhancedCurrencyInputState();
}

class _EnhancedCurrencyInputState extends State<EnhancedCurrencyInput> {
  String? _errorText;
  bool _showQuickAmounts = false;
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _showQuickAmounts = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _isEditing = true;
      // Khi focus: hiển thị số thô
      final currentValue = CurrencyTextField.parseValue(widget.controller.text);
      if (currentValue > 0) {
        final rawValue = currentValue.toString();
        widget.controller.value = TextEditingValue(
          text: rawValue,
          selection: TextSelection.collapsed(offset: rawValue.length),
        );
      }
    } else {
      if (_isEditing) {
        _finalizeInput();
      }
    }
  }

  void _validate() {
    final value = widget.controller.text;
    String? error;
    if (widget.required && value.trim().isEmpty) {
      error = '${widget.label} không được để trống';
    }
    if (mounted) setState(() => _errorText = error);
  }

  void _onChanged(String value) {
    _validate();
  }

  void _finalizeInput() {
    _isEditing = false;
    final text = widget.controller.text.trim();

    if (text.isEmpty) {
      widget.onChanged?.call('0');
      widget.onValueChanged?.call(0);
      return;
    }

    final amount = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (amount <= 0) {
      widget.controller.clear();
      widget.onChanged?.call('0');
      widget.onValueChanged?.call(0);
      return;
    }

    final formatted = CurrencyTextField.formatDisplay(amount);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    widget.onChanged?.call(amount.toString());
    widget.onValueChanged?.call(amount);
  }

  void _onSubmitted(String value) {
    _finalizeInput();
    widget.onSubmitted?.call();
  }

  void _selectQuickAmount(int amount) {
    _isEditing = false;
    widget.controller.text = CurrencyTextField.formatDisplay(amount);
    widget.onChanged?.call(amount.toString());
    widget.onValueChanged?.call(amount);
    _focusNode.unfocus();
    _validate();
  }

  @override
  Widget build(BuildContext context) {
    final defaultQuickAmounts =
        widget.quickAmounts ??
        [100000, 200000, 500000, 1000000, 2000000, 5000000];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          enabled: widget.enabled,
          onChanged: _onChanged,
          onEditingComplete: _finalizeInput,
          onSubmitted: _onSubmitted,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: widget.required ? '${widget.label} *' : widget.label,
            hintText: widget.hint ?? 'Nhập số tiền (VNĐ)',
            prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
            suffixText: 'đ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            errorText: _errorText,
            filled: true,
            fillColor: widget.enabled ? Colors.white : Colors.grey.shade100,
          ),
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w500),
        ),
        if (_showQuickAmounts) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: defaultQuickAmounts
                .map(
                  (amount) => ActionChip(
                    label: Text(
                      amount >= 1000000
                          ? '${(amount / 1000000).toStringAsFixed(0)}M'
                          : '${(amount / 1000).toStringAsFixed(0)}K',
                    ),
                    onPressed: () => _selectQuickAmount(amount),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
