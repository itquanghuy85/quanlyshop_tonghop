import 'package:intl/intl.dart';

class MoneyUtils {
  static int parseMoney(String text) {
    final clean = text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(clean) ?? 0;
  }

  static String formatVND(int amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return formatter.format(amount);
  }
}