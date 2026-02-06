import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/expense_model.dart';

void main() {
  group('Expense Model Tests', () {
    test('fromMap creates Expense correctly', () {
      final map = {
        'id': 1,
        'firestoreId': 'exp_123',
        'category': 'NHẬP HÀNG',
        'title': 'Nhập iPhone 15',
        'amount': 9000000,
        'paymentMethod': 'TIỀN MẶT',
        'date': 1700000000000,
        'note': 'Điện thoại',
        'isSynced': 1,
      };

      final expense = Expense.fromMap(map);

      expect(expense.id, 1);
      expect(expense.firestoreId, 'exp_123');
      expect(expense.category, 'NHẬP HÀNG');
      expect(expense.title, 'Nhập iPhone 15');
      expect(expense.amount, 9000000);
      expect(expense.paymentMethod, 'TIỀN MẶT');
    });

    test('toMap converts Expense correctly', () {
      final expense = Expense(
        id: 1,
        firestoreId: 'exp_123',
        category: 'NHẬP HÀNG',
        title: 'Nhập iPhone 15',
        amount: 9000000,
        paymentMethod: 'TIỀN MẶT',
        date: 1700000000000,
        note: 'Điện thoại',
        isSynced: true,
      );

      final map = expense.toMap();

      expect(map['category'], 'NHẬP HÀNG');
      expect(map['amount'], 9000000);
      expect(map['paymentMethod'], 'TIỀN MẶT');
    });

    test('Expense with NHẬP HÀNG category', () {
      final expense = Expense(
        category: 'NHẬP HÀNG',
        title: 'Nhập iPhone 15 Pro Max',
        amount: 25000000,
        paymentMethod: 'CHUYỂN KHOẢN',
        date: DateTime.now().millisecondsSinceEpoch,
      );

      expect(expense.category, 'NHẬP HÀNG');
      expect(expense.amount, 25000000);
      expect(expense.paymentMethod, 'CHUYỂN KHOẢN');
    });

    test('Expense with NHẬP LINH KIỆN category', () {
      final expense = Expense(
        category: 'NHẬP LINH KIỆN',
        title: 'Nhập màn hình iPhone 15',
        amount: 5000000,
        paymentMethod: 'TIỀN MẶT',
        date: DateTime.now().millisecondsSinceEpoch,
      );

      expect(expense.category, 'NHẬP LINH KIỆN');
      expect(expense.amount, 5000000);
    });
  });

  group('Stock Import Cost Calculation Logic', () {
    // Giả lập logic tính chi phí nhập kho từ home_view
    bool isStockImportCategory(String category) {
      final upper = category.toUpperCase();
      return upper.contains('NHẬP HÀNG') ||
          upper.contains('NHẬP LINH KIỆN') ||
          upper.contains('NHẬP NGUYÊN LIỆU');
    }

    test('identifies NHẬP HÀNG as stock import', () {
      expect(isStockImportCategory('NHẬP HÀNG'), true);
      expect(isStockImportCategory('nhập hàng'), true);
      expect(isStockImportCategory('Chi phí NHẬP HÀNG'), true);
    });

    test('identifies NHẬP LINH KIỆN as stock import', () {
      expect(isStockImportCategory('NHẬP LINH KIỆN'), true);
      expect(isStockImportCategory('nhập linh kiện'), true);
    });

    test('identifies NHẬP NGUYÊN LIỆU as stock import', () {
      expect(isStockImportCategory('NHẬP NGUYÊN LIỆU'), true);
    });

    test('does NOT identify regular expenses as stock import', () {
      expect(isStockImportCategory('ĐIỆN NƯỚC'), false);
      expect(isStockImportCategory('LƯƠNG NHÂN VIÊN'), false);
      expect(isStockImportCategory('THUÊ MẶT BẰNG'), false);
      expect(isStockImportCategory('VẬN CHUYỂN'), false);
      expect(isStockImportCategory('KHÁC'), false);
    });

    test('calculates stock import cost correctly', () {
      final expenses = [
        Expense(
          category: 'NHẬP HÀNG',
          title: 'Nhập iPhone',
          amount: 9000000,
          paymentMethod: 'TIỀN MẶT',
          date: DateTime.now().millisecondsSinceEpoch,
        ),
        Expense(
          category: 'ĐIỆN NƯỚC',
          title: 'Tiền điện',
          amount: 500000,
          paymentMethod: 'TIỀN MẶT',
          date: DateTime.now().millisecondsSinceEpoch,
        ),
        Expense(
          category: 'NHẬP LINH KIỆN',
          title: 'Nhập màn hình',
          amount: 3000000,
          paymentMethod: 'CHUYỂN KHOẢN',
          date: DateTime.now().millisecondsSinceEpoch,
        ),
        Expense(
          category: 'LƯƠNG NHÂN VIÊN',
          title: 'Lương T1',
          amount: 8000000,
          paymentMethod: 'CHUYỂN KHOẢN',
          date: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      int stockInCost = 0;
      int regularExpense = 0;

      for (final e in expenses) {
        if (isStockImportCategory(e.category)) {
          stockInCost += e.amount;
        } else {
          regularExpense += e.amount;
        }
      }

      // NHẬP HÀNG (9tr) + NHẬP LINH KIỆN (3tr) = 12tr
      expect(stockInCost, 12000000);
      // ĐIỆN NƯỚC (500k) + LƯƠNG (8tr) = 8.5tr
      expect(regularExpense, 8500000);
    });

    test('filters expenses by today', () {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;

      final expenses = [
        Expense(
          category: 'NHẬP HÀNG',
          title: 'Nhập iPhone',
          amount: 9000000,
          paymentMethod: 'TIỀN MẶT',
          date: startOfToday + 3600000, // Hôm nay, 1h sáng
        ),
        Expense(
          category: 'NHẬP HÀNG',
          title: 'Nhập Samsung',
          amount: 5000000,
          paymentMethod: 'TIỀN MẶT',
          date: startOfToday - 86400000, // Hôm qua
        ),
      ];

      final todayExpenses = expenses.where((e) {
        final ts = e.date;
        return ts >= startOfToday && ts <= endOfToday;
      }).toList();

      expect(todayExpenses.length, 1);
      expect(todayExpenses.first.amount, 9000000);
    });
  });

  group('Payment method validation', () {
    test('validates cash payment', () {
      final expense = Expense(
        category: 'NHẬP HÀNG',
        title: 'Nhập iPhone',
        amount: 9000000,
        paymentMethod: 'TIỀN MẶT',
        date: DateTime.now().millisecondsSinceEpoch,
      );

      expect(expense.paymentMethod, 'TIỀN MẶT');
    });

    test('validates bank transfer payment', () {
      final expense = Expense(
        category: 'NHẬP HÀNG',
        title: 'Nhập iPhone',
        amount: 9000000,
        paymentMethod: 'CHUYỂN KHOẢN',
        date: DateTime.now().millisecondsSinceEpoch,
      );

      expect(expense.paymentMethod, 'CHUYỂN KHOẢN');
    });
  });

  group('Negative amount validation', () {
    test('fromMap converts negative amount to 0', () {
      final map = {
        'title': 'Test',
        'amount': -5000000,
        'category': 'KHÁC',
        'date': DateTime.now().millisecondsSinceEpoch,
      };

      final expense = Expense.fromMap(map);
      expect(expense.amount, 0);
    });

    test('fromMap handles zero amount', () {
      final map = {
        'title': 'Test',
        'amount': 0,
        'category': 'KHÁC',
        'date': DateTime.now().millisecondsSinceEpoch,
      };

      final expense = Expense.fromMap(map);
      expect(expense.amount, 0);
    });
  });
}
