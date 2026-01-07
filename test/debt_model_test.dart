import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/debt_model.dart';

void main() {
  group('Debt.fromMap', () {
    test('fromMap with paidAmount > totalAmount', () {
      final map = {'personName': 'Test', 'phone': '123', 'totalAmount': 100, 'paidAmount': 150, 'type': 'OWE', 'createdAt': 1234567890};
      final debt = Debt.fromMap(map);
      expect(debt.paidAmount, 100);
    });

    test('fromMap with invalid totalAmount', () {
      final map = {'personName': 'Test', 'phone': '123', 'totalAmount': '200', 'paidAmount': 50, 'type': 'OWE', 'createdAt': 1234567890};
      final debt = Debt.fromMap(map);
      expect(debt.totalAmount, 0);
    });

    test('fromMap with null paidAmount', () {
      final map = {'personName': 'Test', 'phone': '123', 'totalAmount': 100, 'paidAmount': null, 'type': 'OWE', 'createdAt': 1234567890};
      final debt = Debt.fromMap(map);
      expect(debt.paidAmount, 0);
    });
  });

  group('Debt calculations', () {
    test('calculate total debt remain correctly', () {
      final debts = [
        {'totalAmount': 100, 'paidAmount': 50},
        {'totalAmount': 200, 'paidAmount': 200},
        {'totalAmount': 150, 'paidAmount': 100},
        {'totalAmount': 50, 'paidAmount': 60}, // paid > total, should not add negative
      ];
      int totalRemain = 0;
      for (var d in debts) {
        final int total = d['totalAmount'] ?? 0;
        final int paid = d['paidAmount'] ?? 0;
        final int remain = total - paid;
        if (remain > 0) totalRemain += remain;
      }
      expect(totalRemain, 100); // 50 + 0 + 50 = 100
    });
  });
}
