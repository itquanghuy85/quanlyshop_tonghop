import 'package:flutter/services.dart';
import 'money_input_formatter.dart';

class MoneyUtils {
  /// Format int VNĐ -> "1.234.567"
  static String formatCurrency(int value) {
    return MoneyInputFormatter.formatValue(value);
  }

  /// Parse chuỗi tiền có dấu chấm -> int VNĐ (mặc định 0 nếu lỗi)
  static int parseCurrency(String input) {
    return MoneyInputFormatter.parseRaw(input);
  }

  /// Input formatter riêng cho money input (realtime format + giữ cursor)
  static TextInputFormatter currencyInputFormatter() {
    return MoneyInputFormatter();
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