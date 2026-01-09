import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class MoneyUtils {
  /// Format int VNĐ -> "1.234.567"
  static String formatCurrency(int value) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return formatter.format(value);
  }

  /// Parse chuỗi tiền có . hoặc , -> int VNĐ (mặc định 0 nếu lỗi)
  static int parseCurrency(String input) {
    final clean = input.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  /// Input formatter giữ caret, chấp nhận số và dấu phân tách.
  static TextInputFormatter currencyInputFormatter() {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
      final formatted = digits.isEmpty
          ? ''
          : NumberFormat('#,###', 'vi_VN').format(int.parse(digits));
      // Giữ vị trí caret gần cuối (phổ biến cho nhập tiền)
      final selectionIndex = formatted.length;
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: selectionIndex),
      );
    });
  }

  /// Validator cho trường tiền/số lượng.
  static String? validateAmount(
    String value, {
    int min = 0,
    int? max,
    String? fieldName,
  }) {
    final name = fieldName ?? 'Giá trị';
    final parsed = parseCurrency(value);
    if (parsed < min) return '$name phải ≥ ${formatCurrency(min)}';
    if (max != null && parsed > max) return '$name không được vượt ${formatCurrency(max)}';
    return null;
  }

  // Giữ API cũ cho tương thích
  static int parseMoney(String text) => parseCurrency(text);
  static String formatVND(int amount) => formatCurrency(amount);
}