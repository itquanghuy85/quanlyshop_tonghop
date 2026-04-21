import 'package:flutter/services.dart';
import 'money_input_formatter.dart';

class MoneyUtils {
  /// Format int VNĐ -> "1.234.567"
  static String formatCurrency(int value) {
    return MoneyInputFormatter.formatValue(value);
  }

  /// Format rút gọn cho số tiền lớn: 1.200.000 -> 1.2 M, 1.000.000.000 -> 1 B
  static String formatCompactCurrency(int value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';

    if (abs >= 1000000000000) {
      return '$sign${_formatCompactNumber(abs / 1000000000000)} T';
    }
    if (abs >= 1000000000) {
      return '$sign${_formatCompactNumber(abs / 1000000000)} B';
    }
    if (abs >= 1000000) {
      return '$sign${_formatCompactNumber(abs / 1000000)} M';
    }
    if (abs >= 1000) {
      return '$sign${_formatCompactNumber(abs / 1000)} K';
    }
    return formatCurrency(value);
  }

  static String _formatCompactNumber(double value) {
    final raw = value >= 100
        ? value.toStringAsFixed(0)
        : value >= 10
        ? value.toStringAsFixed(1)
        : value.toStringAsFixed(2);
    return raw
        .replaceFirst(RegExp(r'([.]0+)$'), '')
        .replaceFirst(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
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
    if (max != null && parsed > max)
      return '$name không được vượt ${formatCurrency(max)}';
    return null;
  }

  // Giữ API cũ cho tương thích
  static int parseMoney(String text) => parseCurrency(text);
  static String formatVND(int amount) => formatCurrency(amount);
}
