import 'package:intl/intl.dart';
import '../../utils/money_input_formatter.dart';

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
  static final NumberFormat _compactFormat = NumberFormat('#,##0.###', 'en_US');

  /// Formats VNĐ amount to display string with dot separators.
  /// Example: 5000000 -> "5.000.000"
  static String formatVND(int vnd) {
    if (vnd == 0) return '0';
    return _vndFormat.format(vnd).replaceAll(',', '.');
  }

  /// Formats VNĐ amount in compact form (Tr, Tỷ).
  /// Example: 6_350_000_000 -> "6,350 Tr", 30_450_000_000_000 -> "30,450 Tỷ"
  static String formatCompact(int vnd) {
    if (vnd == 0) return '0';
    final abs = vnd.abs();
    final sign = vnd < 0 ? '-' : '';

    if (abs >= 1000000000) {
      final value = abs / 1000000000;
      return '$sign${_compactFormat.format(value)} Tỷ';
    } else if (abs >= 1000000) {
      final value = abs / 1000000;
      return '$sign${_compactFormat.format(value)} Tr';
    }
    return '$sign$abs';
  }

  /// DEPRECATED: Logic nhân 1000 đã bị loại bỏ vì gây bug.
  /// Khi user nhập "50.000" qua formatter, giá trị đã là 50000.
  /// Nếu nhân thêm 1000 sẽ thành 50.000.000 (sai).
  /// Giữ lại method này cho backward compatibility nhưng KHÔNG nhân 1000.
  static int inputToVND(int input) {
    // KHÔNG nhân 1000 - giữ nguyên giá trị đầu vào
    return input;
  }

  /// Parses currency string to VNĐ.
  /// Removes separators and converts to int.
  /// NOTE: KHÔNG nhân 1000 vì user đã nhập số đầy đủ qua formatter.
  static int parseInputToVND(String input) {
    return MoneyInputFormatter.parseRaw(input);
  }

  /// Converts VNĐ to thousand VNĐ for display purposes.
  /// Only use when you need to show thousand VNĐ instead of VNĐ.
  static int vndToThousand(int vnd) {
    return vnd ~/ 1000;
  }

  /// Parses currency string to VNĐ.
  /// NOTE: KHÔNG nhân 1000 vì user đã nhập số đầy đủ qua formatter.
  /// Đây là cách parse CHUẨN - chỉ loại bỏ ký tự không phải số.
  static int parseMoney(String text) {
    return MoneyInputFormatter.parseRaw(text);
  }

  /// Parse raw value from formatted text (no conversion)
  static int parseRaw(String text) {
    return MoneyInputFormatter.parseRaw(text);
  }
}
