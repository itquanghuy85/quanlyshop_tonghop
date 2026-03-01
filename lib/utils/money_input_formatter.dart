import 'package:flutter/services.dart';

/// Custom money input formatter
/// - Allows digits only
/// - Formats with dot separators in realtime
/// - Preserves cursor position based on digit count
class MoneyInputFormatter extends TextInputFormatter {
  static final RegExp _digitOnly = RegExp(r'\d');

  /// Format digits string with dot separators (e.g., 1000000 -> 1.000.000)
  static String formatDigits(String digits) {
    if (digits.isEmpty) return '';
    return digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
  }

  /// Format int value to display string with dots
  static String formatValue(int value) {
    if (value == 0) return '0';
    if (value < 0) return '-${formatDigits((-value).toString())}';
    return formatDigits(value.toString());
  }

  /// Parse raw int value from display string
  static int parseRaw(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;

    // Count digits before cursor in new input
    int digitsBeforeCursor = 0;
    final cursorIndex = newValue.selection.end < 0
        ? 0
        : newValue.selection.end;
    for (int i = 0; i < cursorIndex && i < newText.length; i++) {
      if (_digitOnly.hasMatch(newText[i])) {
        digitsBeforeCursor++;
      }
    }

    // Keep digits only
    final digits = newText.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Format digits with dots
    final formatted = formatDigits(digits);

    // Restore cursor position based on digits count
    int newCursor = 0;
    if (digitsBeforeCursor <= 0) {
      newCursor = 0;
    } else if (digitsBeforeCursor >= digits.length) {
      newCursor = formatted.length;
    } else {
      int digitCount = 0;
      for (int i = 0; i < formatted.length; i++) {
        if (_digitOnly.hasMatch(formatted[i])) {
          digitCount++;
          if (digitCount == digitsBeforeCursor) {
            newCursor = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
