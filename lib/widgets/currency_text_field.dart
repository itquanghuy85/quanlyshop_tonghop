import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/money_utils.dart';
import '../utils/money_input_formatter.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

/// Widget nhập tiền chuẩn hóa cho toàn app.
///
/// QUY TẮC ĐƠN GIẢN:
/// 1. Người dùng nhập số tiền đầy đủ (VD: 500000 cho 500k)
/// 2. Hiển thị dạng: x.xxx.xxx (dấu chấm ngăn cách hàng nghìn)
/// 3. Lưu số nguyên đầy đủ (VNĐ)
///
/// Ví dụ:
/// - Nhập "500000" → Hiển thị "500.000" → Lưu 500000
/// - Nhập "1500000" → Hiển thị "1.500.000" → Lưu 1500000
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
  final bool autoMultiply1000; // DEPRECATED - Không còn sử dụng, luôn = false
  final String? Function(String?)? validator;

  /// Global key registry để finalize tất cả currency fields trước khi submit
  static final Map<TextEditingController, GlobalKey<_CurrencyTextFieldState>>
  _stateKeys = {};

  /// Đăng ký state key cho controller
  static void _registerState(
    TextEditingController controller,
    GlobalKey<_CurrencyTextFieldState> key,
  ) {
    _stateKeys[controller] = key;
  }

  /// Hủy đăng ký state key
  static void _unregisterState(TextEditingController controller) {
    _stateKeys.remove(controller);
  }

  /// ✅ GỌI TRƯỚC KHI SUBMIT FORM để đảm bảo tất cả currency fields được finalize
  /// Giải quyết vấn đề: nhập số rồi bấm save ngay mà không blur field
  static void finalizeAll() {
    for (final key in _stateKeys.values) {
      key.currentState?._finalizeInput();
    }
  }

  /// Finalize một controller cụ thể
  static void finalizeController(TextEditingController controller) {
    _stateKeys[controller]?.currentState?._finalizeInput();
  }

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
    this.autoMultiply1000 =
        false, // DEPRECATED - mặc định false, không còn auto multiply
    this.validator,
  });

  @override
  State<CurrencyTextField> createState() => _CurrencyTextFieldState();

  /// Lấy giá trị số nguyên (VNĐ) từ controller
  static int getValue(TextEditingController controller) {
    return MoneyInputFormatter.parseRaw(controller.text);
  }

  /// Alias theo yêu cầu: rawValue (int không dấu)
  static int getRawValue(TextEditingController controller) {
    return getValue(controller);
  }

  /// Set raw value (int) và tự format hiển thị
  static void setRawValue(TextEditingController controller, int value) {
    final formatted = MoneyInputFormatter.formatValue(value);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Lấy giá trị số nguyên (VNĐ) từ controller
  /// NOTE: autoMultiply1000 không còn sử dụng - luôn trả về giá trị đã nhập
  static int getValueWithMultiply(
    TextEditingController controller, {
    bool autoMultiply1000 = false,
  }) {
    return getValue(controller);
  }

  /// Format số thành chuỗi hiển thị (x.xxx.xxx)
  static String formatDisplay(int value) {
    if (value == 0) return '';
    return MoneyInputFormatter.formatValue(value);
  }

  /// Parse chuỗi thành số nguyên
  static int parseValue(String text) {
    return MoneyInputFormatter.parseRaw(text);
  }

  /// Parse chuỗi thành số nguyên
  /// NOTE: autoMultiply1000 không còn sử dụng - luôn trả về giá trị đã nhập
  static int parseValueWithMultiply(
    String text, {
    bool autoMultiply1000 = false,
  }) {
    return parseValue(text);
  }
}

/// Controller chuyên cho money input
/// - getRawValue(): int không dấu
/// - setRawValue(int): set và format hiển thị
class MoneyInputController extends TextEditingController {
  MoneyInputController({super.text});

  int get rawValue => MoneyInputFormatter.parseRaw(text);

  int getRawValue() => rawValue;

  void setRawValue(int value) {
    value = value < 0 ? 0 : value;
    final formatted = MoneyInputFormatter.formatValue(value);
    this.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CurrencyTextFieldState extends State<CurrencyTextField> {
  late final GlobalKey<_CurrencyTextFieldState> _stateKey;

  @override
  void initState() {
    super.initState();
    // Tạo và đăng ký state key
    _stateKey = GlobalKey<_CurrencyTextFieldState>();
    CurrencyTextField._registerState(widget.controller, _stateKey);
  }

  @override
  void dispose() {
    // Hủy đăng ký state key
    CurrencyTextField._unregisterState(widget.controller);
    super.dispose();
  }

  void _finalizeInput() {
    final raw = CurrencyTextField.getValue(widget.controller);
    final formatted = CurrencyTextField.formatDisplay(raw);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    widget.onChanged?.call(formatted);
    widget.onValueChanged?.call(raw);
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
        TextFormField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          enabled: widget.enabled,
          onChanged: (value) {
            final raw = CurrencyTextField.getValue(widget.controller);
            widget.onChanged?.call(value);
            widget.onValueChanged?.call(raw);
          },
          onEditingComplete: _finalizeInput,
          onFieldSubmitted: _onSubmitted,
          inputFormatters: [MoneyInputFormatter()],
          validator: (value) {
            if (widget.required && (value == null || value.trim().isEmpty)) {
              return '${widget.label} không được để trống';
            }
            return widget.validator?.call(value);
          },
          decoration: InputDecoration(
            labelText: widget.required ? '${widget.label} *' : widget.label,
            hintText: widget.hint ?? 'Nhập số tiền đầy đủ (VD: 500000)',
            prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
            suffixText: 'đ',
            suffixStyle: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
    final raw = MoneyInputFormatter.parseRaw(value);
    widget.onChanged?.call(value);
    widget.onValueChanged?.call(raw);
  }

  void _finalizeInput() {
    final text = widget.controller.text.trim();

    if (text.isEmpty) {
      widget.onChanged?.call('0');
      widget.onValueChanged?.call(0);
      return;
    }

    final amount = MoneyInputFormatter.parseRaw(text);

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
          inputFormatters: [MoneyInputFormatter()],
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
