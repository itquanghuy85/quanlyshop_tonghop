import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/core/utils/money_utils.dart';

void main() {
  group('MoneyUtils', () {
    test('parseMoney with empty string', () {
      expect(MoneyUtils.parseMoney(''), 0);
    });

    // FIX: parseMoney KHÔNG nhân 1000 nữa - chỉ parse số thuần
    test('parseMoney with integer (no multiplication)', () {
      expect(MoneyUtils.parseMoney('123'), 123);
    });

    test('parseMoney with dots and spaces', () {
      // 50.000 → remove dots → 50000
      expect(MoneyUtils.parseMoney('50.000'), 50000);
    });

    test('parseMoney with mixed characters', () {
      expect(MoneyUtils.parseMoney('abc123def'), 123);
    });

    test('parseMoney with negative', () {
      expect(MoneyUtils.parseMoney('-123'), 123); // since RegExp removes -
    });
    
    test('parseMoney with formatted currency', () {
      // User nhập 1.500.000 (1.5 triệu) → parse ra 1500000
      expect(MoneyUtils.parseMoney('1.500.000'), 1500000);
    });
  });
}
