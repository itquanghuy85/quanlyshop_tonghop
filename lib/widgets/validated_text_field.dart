import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_service.dart';

class ValidatedTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool required;
  final String? Function(String)? customValidator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int? maxLines;
  final bool enabled;
  final VoidCallback? onSubmitted;
  final Function(String)? onChanged;
  final bool autoValidate;
  final bool uppercase; // New parameter for uppercase conversion

  const ValidatedTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.required = false,
    this.customValidator,
    this.inputFormatters,
    this.maxLength,
    this.maxLines,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
    this.autoValidate = false,
    this.uppercase = false, // Default to false
  });

  @override
  State<ValidatedTextField> createState() => _ValidatedTextFieldState();
}

class _ValidatedTextFieldState extends State<ValidatedTextField> {
  String? _errorText;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    if (!widget.autoValidate && !_hasFocus) return;

    final value = widget.controller.text;
    String? error;

    // Required check
    if (widget.required && value.trim().isEmpty) {
      error = '${widget.label} không được để trống';
    }
    // Custom validation
    else if (widget.customValidator != null) {
      error = widget.customValidator!(value);
    }
    // Built-in validations
    else if (widget.keyboardType == TextInputType.phone) {
      error = UserService.validatePhone(value);
    }
    else if (widget.label.toLowerCase().contains('email')) {
      // Simple email validation
      final emailReg = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (value.isNotEmpty && !emailReg.hasMatch(value)) {
        error = 'Email không hợp lệ';
      }
    }
    else if (widget.label.toLowerCase().contains('tên') || widget.label.toLowerCase().contains('name')) {
      error = UserService.validateName(value);
    }
    else if (widget.label.toLowerCase().contains('imei') || widget.label.toLowerCase().contains('serial')) {
      error = UserService.validateIMEI(value);
    }
    else if (widget.label.toLowerCase().contains('model')) {
      error = UserService.validateModel(value);
    }
    else if (widget.label.toLowerCase().contains('địa chỉ') || widget.label.toLowerCase().contains('address')) {
      error = UserService.validateAddress(value);
    }

    setState(() => _errorText = error);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() => _hasFocus = hasFocus);
        if (!hasFocus && widget.autoValidate) {
          _validate();
        }
      },
      child: TextField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        inputFormatters: widget.inputFormatters,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        enabled: widget.enabled,
        onChanged: (value) {
          // Convert to uppercase if enabled
          if (widget.uppercase) {
            final upperValue = value.toUpperCase();
            if (upperValue != value) {
              widget.controller.value = TextEditingValue(
                text: upperValue,
                selection: TextSelection.collapsed(offset: upperValue.length),
              );
              value = upperValue;
            }
          }

          widget.onChanged?.call(value);
          if (widget.autoValidate) {
            _validate();
          }
        },
        onSubmitted: widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
        decoration: InputDecoration(
          labelText: widget.required ? '${widget.label} *' : widget.label,
          hintText: widget.hint,
          prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _errorText != null ? Colors.red : Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _errorText != null ? Colors.red : Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _errorText != null ? Colors.red : Theme.of(context).primaryColor),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          errorText: _errorText,
          errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
          counterText: widget.maxLength != null ? null : '',
          filled: true,
          fillColor: widget.enabled ? Colors.white : Colors.grey.shade100,
        ),
        style: TextStyle(
          fontSize: 16,
          color: widget.enabled ? Colors.black87 : Colors.grey,
        ),
      ),
    );
  }
}
