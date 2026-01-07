import 'package:intl/intl.dart';

/// Utility class for handling Vietnamese Dong (VNĐ) currency operations.
/// This is the ONLY place allowed to handle currency formatting, parsing, and conversions.
///
/// QUY TẮC CHUẨN HÓA NHẬP TIỀN:
/// 1. Trong lúc nhập: không thay đổi giá trị, chỉ cho nhập số
/// 2. Khi nhập xong (mất focus / Enter / Xác nhận): tự động thêm 000 nếu < 100000
/// 3. Hiển thị dạng: x.xxx.xxx (dấu chấm ngăn cách hàng nghìn)
/// 4. Lưu số nguyên đầy đủ (VNĐ)
///
/// Ví dụ:
/// - Nhập "500" → Hiển thị "500.000" → Lưu 500000
/// - Nhập "1500" → Hiển thị "1.500.000" → Lưu 1500000
/// - Nhập "1500000" (>= 100000) → Giữ nguyên "1.500.000" → Lưu 1500000
class MoneyUtils {
  static final NumberFormat _vndFormat = NumberFormat('#,###', 'vi_VN');

  /// Formats VNĐ amount to display string with dot separators.
  /// Example: 5000000 -> "5.000.000"
  static String formatVND(int vnd) {
    if (vnd == 0) return '0';
    return _vndFormat.format(vnd).replaceAll(',', '.');
  }

  /// Formats VNĐ amount in compact form (K, M, B)
  /// Example: 5000000 -> "5M", 1500000 -> "1.5M", 500000 -> "500K"
  static String formatCompact(int vnd) {
    if (vnd == 0) return '0';
    final abs = vnd.abs();
    final sign = vnd < 0 ? '-' : '';
    
    if (abs >= 1000000000) {
      final value = abs / 1000000000;
      return '$sign${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}B';
    } else if (abs >= 1000000) {
      final value = abs / 1000000;
      return '$sign${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}M';
    } else if (abs >= 1000) {
      final value = abs / 1000;
      return '$sign${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}K';
    }
    return '$sign$abs';
  }

  /// Converts user input to VNĐ.
  /// If input < 100,000 → multiplies by 1000 (auto-append 000)
  /// If input >= 100,000 → keeps as-is
  static int inputToVND(int input) {
    if (input > 0 && input < 100000) {
      return input * 1000;
    }
    return input;
  }

  /// Parses currency string to VNĐ.
  /// Removes separators and converts to int, then applies inputToVND logic.
  static int parseInputToVND(String input) {
    final clean = input.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(clean) ?? 0;
    return inputToVND(amount);
  }

  /// Converts VNĐ to thousand VNĐ for display purposes.
  /// Only use when you need to show thousand VNĐ instead of VNĐ.
  static int vndToThousand(int vnd) {
    return vnd ~/ 1000;
  }

  /// Parses currency string to VNĐ with input conversion logic.
  /// Cleans the string, parses to int, then applies inputToVND logic.
  /// This maintains backward compatibility with existing code.
  static int parseMoney(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(clean) ?? 0;
    return inputToVND(amount);
  }
  
  /// Parse raw value from formatted text (no conversion)
  static int parseRaw(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }
}