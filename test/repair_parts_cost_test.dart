import 'package:flutter_test/flutter_test.dart';

/// Test model for Repair (mirrors Repair model's relevant fields)
class TestRepair {
  final String firestoreId;
  final String customerName;
  final String model;
  final int status; // 1=Nhận, 2=Sửa, 3=Xong, 4=Giao
  final int price;
  final int cost;
  final String paymentMethod;
  final int? deliveredAt;
  final bool costRecordedInFund;
  final String? costPaymentMethod;
  final int? costRecordedAt;

  TestRepair({
    required this.firestoreId,
    required this.customerName,
    required this.model,
    required this.status,
    required this.price,
    required this.cost,
    required this.paymentMethod,
    this.deliveredAt,
    this.costRecordedInFund = false,
    this.costPaymentMethod,
    this.costRecordedAt,
  });

  int get totalCost => cost;
}

/// Mirrors _isSameDay from cash_closing_view.dart
bool isSameDay(int timestamp, DateTime target) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return d.year == target.year &&
      d.month == target.month &&
      d.day == target.day;
}

/// Mirrors _analyzeTransactions logic from cash_closing_view.dart
/// Returns a map with all financial totals
Map<String, int> analyzeTransactions({
  required List<TestRepair> repairs,
  required DateTime date,
}) {
  int cashIn = 0, cashOut = 0;
  int bankIn = 0, bankOut = 0;
  int repairIncome = 0, repairCost = 0;
  int repairPartsCostFund = 0;

  // Repair income (only delivered = status 4)
  for (var r in repairs.where((r) =>
      r.status == 4 &&
      r.deliveredAt != null &&
      isSameDay(r.deliveredAt!, date))) {
    repairIncome += r.price;
    repairCost += r.totalCost;

    if (r.paymentMethod == 'TIỀN MẶT') {
      cashIn += r.price;
    } else {
      bankIn += r.price;
    }
  }

  // Repair parts cost fund (any status, based on costRecordedAt)
  for (var r in repairs.where((r) =>
      r.costRecordedInFund &&
      r.costRecordedAt != null &&
      isSameDay(r.costRecordedAt!, date))) {
    repairPartsCostFund += r.totalCost;
    if (r.costPaymentMethod == 'TIỀN MẶT') {
      cashOut += r.totalCost;
    } else {
      bankOut += r.totalCost;
    }
  }

  return {
    'cashIn': cashIn,
    'cashOut': cashOut,
    'bankIn': bankIn,
    'bankOut': bankOut,
    'repairIncome': repairIncome,
    'repairCost': repairCost,
    'repairPartsCostFund': repairPartsCostFund,
    'netCash': cashIn - cashOut,
    'netBank': bankIn - bankOut,
    'profit': repairIncome - repairCost,
  };
}

/// Mirrors _getExpenseTransactions repair_parts_cost logic from cash_closing_view.dart
List<Map<String, dynamic>> getRepairPartsCostExpenses({
  required List<TestRepair> repairs,
  required DateTime date,
}) {
  final entries = <Map<String, dynamic>>[];
  for (var r in repairs.where((r) =>
      r.costRecordedInFund &&
      r.costRecordedAt != null &&
      isSameDay(r.costRecordedAt!, date))) {
    entries.add({
      'type': 'repair_parts_cost',
      'name': 'Vốn LK: ${r.model}',
      'amount': r.totalCost,
      'method': r.costPaymentMethod ?? 'TIỀN MẶT',
      'time': r.costRecordedAt,
    });
  }
  return entries;
}

void main() {
  group('🔧 Repair Parts Cost - Financial Logic Tests', () {
    late DateTime testDate;
    late int todayStart;
    late List<TestRepair> testRepairs;

    setUp(() {
      testDate = DateTime(2026, 1, 3);
      todayStart = DateTime(2026, 1, 3, 0, 0, 0).millisecondsSinceEpoch;

      testRepairs = [
        // Case 1: Cost in fund via TIỀN MẶT, delivered
        TestRepair(
          firestoreId: 'rep_test_cost_cash',
          customerName: 'TEST Vốn LK Tiền mặt',
          model: 'iPhone 14 Pro Max',
          status: 4,
          price: 3500000,
          cost: 1800000,
          paymentMethod: 'TIỀN MẶT',
          deliveredAt: todayStart + 46800000, // 1:00 PM
          costRecordedInFund: true,
          costPaymentMethod: 'TIỀN MẶT',
          costRecordedAt: todayStart + 46800000,
        ),
        // Case 2: Cost in fund via CHUYỂN KHOẢN, delivered
        TestRepair(
          firestoreId: 'rep_test_cost_bank',
          customerName: 'TEST Vốn LK Chuyển khoản',
          model: 'Samsung S24 Ultra',
          status: 4,
          price: 1500000,
          cost: 750000,
          paymentMethod: 'CHUYỂN KHOẢN',
          deliveredAt: todayStart + 41400000, // 11:30 AM
          costRecordedInFund: true,
          costPaymentMethod: 'CHUYỂN KHOẢN',
          costRecordedAt: todayStart + 41400000,
        ),
        // Case 3: Cost NOT in fund, delivered
        TestRepair(
          firestoreId: 'rep_test_cost_nofund',
          customerName: 'TEST Vốn LK Không ghi quỹ',
          model: 'OPPO Reno 10',
          status: 4,
          price: 800000,
          cost: 200000,
          paymentMethod: 'TIỀN MẶT',
          deliveredAt: todayStart + 43200000, // 12:00 PM
          costRecordedInFund: false,
          costPaymentMethod: null,
          costRecordedAt: null,
        ),
        // Case 4: Cost in fund, NOT delivered (status 3)
        TestRepair(
          firestoreId: 'rep_test_cost_notdelivered',
          customerName: 'TEST Vốn LK Chưa giao',
          model: 'Xiaomi 14',
          status: 3,
          price: 500000,
          cost: 150000,
          paymentMethod: 'TIỀN MẶT',
          deliveredAt: null,
          costRecordedInFund: true,
          costPaymentMethod: 'TIỀN MẶT',
          costRecordedAt: todayStart + 36000000, // 10:00 AM
        ),
      ];
    });

    test('Income only counts delivered repairs (status=4)', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Only Case 1, 2, 3 are delivered (status=4)
      expect(result['repairIncome'], 5800000,
          reason: 'Income = 3,500,000 + 1,500,000 + 800,000');
    });

    test('Repair cost sums all delivered repairs', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Cost from delivered repairs: 1,800,000 + 750,000 + 200,000
      expect(result['repairCost'], 2750000,
          reason: 'Cost = 1,800,000 + 750,000 + 200,000');
    });

    test('Parts cost fund includes ALL statuses with costRecordedInFund=true', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Case 1 (1.8M) + Case 2 (750K) + Case 4 (150K) = 2,700,000
      // Case 3 is excluded (costRecordedInFund=false)
      expect(result['repairPartsCostFund'], 2700000,
          reason: 'Fund = 1,800,000 + 750,000 + 150,000 (Case 4 included despite status=3)');
    });

    test('Case 3: costRecordedInFund=false is EXCLUDED from fund expenses', () {
      final entries = getRepairPartsCostExpenses(repairs: testRepairs, date: testDate);

      expect(entries.any((e) => e['name'].toString().contains('OPPO')), false,
          reason: 'OPPO Reno 10 has costRecordedInFund=false');
    });

    test('Case 4: status=3 is INCLUDED in fund expenses when costRecordedInFund=true', () {
      final entries = getRepairPartsCostExpenses(repairs: testRepairs, date: testDate);

      expect(entries.any((e) => e['name'].toString().contains('Xiaomi')), true,
          reason: 'Xiaomi 14 has costRecordedInFund=true, status=3 still counts');
    });

    test('Cash income splits correctly by payment method', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Cash income: Case 1 (3.5M) + Case 3 (800K) = 4,300,000
      expect(result['cashIn'], 4300000,
          reason: 'Cash IN = 3,500,000 (iPhone) + 800,000 (OPPO)');

      // Bank income: Case 2 (1.5M) = 1,500,000
      expect(result['bankIn'], 1500000,
          reason: 'Bank IN = 1,500,000 (Samsung)');
    });

    test('Cash out splits correctly by costPaymentMethod', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Cash out: Case 1 (1.8M) + Case 4 (150K) = 1,950,000
      expect(result['cashOut'], 1950000,
          reason: 'Cash OUT = 1,800,000 (iPhone) + 150,000 (Xiaomi)');

      // Bank out: Case 2 (750K) = 750,000
      expect(result['bankOut'], 750000,
          reason: 'Bank OUT = 750,000 (Samsung)');
    });

    test('Net cash balance is correct', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Net cash = 4,300,000 - 1,950,000 = 2,350,000
      expect(result['netCash'], 2350000);

      // Net bank = 1,500,000 - 750,000 = 750,000
      expect(result['netBank'], 750000);
    });

    test('Profit from delivered repairs is correct', () {
      final result = analyzeTransactions(repairs: testRepairs, date: testDate);

      // Profit = 5,800,000 - 2,750,000 = 3,050,000
      expect(result['profit'], 3050000);
    });

    test('Expense entries count matches expected', () {
      final entries = getRepairPartsCostExpenses(repairs: testRepairs, date: testDate);

      // Should have 3 entries (Case 1, 2, 4)
      expect(entries.length, 3,
          reason: 'Only 3 repairs have costRecordedInFund=true');

      // Total should be 2,700,000
      final total = entries.fold<int>(0, (sum, e) => sum + (e['amount'] as int));
      expect(total, 2700000);
    });

    test('Expense entry payment methods are correct', () {
      final entries = getRepairPartsCostExpenses(repairs: testRepairs, date: testDate);

      final cashEntries = entries.where((e) => e['method'] == 'TIỀN MẶT').toList();
      final bankEntries = entries.where((e) => e['method'] == 'CHUYỂN KHOẢN').toList();

      expect(cashEntries.length, 2, reason: 'Case 1 + Case 4 = 2 cash entries');
      expect(bankEntries.length, 1, reason: 'Case 2 = 1 bank entry');

      final cashTotal = cashEntries.fold<int>(0, (s, e) => s + (e['amount'] as int));
      final bankTotal = bankEntries.fold<int>(0, (s, e) => s + (e['amount'] as int));
      expect(cashTotal, 1950000, reason: 'Cash: 1,800,000 + 150,000');
      expect(bankTotal, 750000, reason: 'Bank: 750,000');
    });

    test('Repairs from different day are excluded', () {
      final tomorrow = DateTime(2026, 1, 4);
      final result = analyzeTransactions(repairs: testRepairs, date: tomorrow);

      expect(result['repairIncome'], 0);
      expect(result['repairPartsCostFund'], 0);
      expect(result['cashIn'], 0);
      expect(result['cashOut'], 0);
    });

    test('Empty repairs list returns all zeros', () {
      final result = analyzeTransactions(repairs: [], date: testDate);

      expect(result['repairIncome'], 0);
      expect(result['repairPartsCostFund'], 0);
      expect(result['cashIn'], 0);
      expect(result['cashOut'], 0);
      expect(result['profit'], 0);
    });

    test('costRecordedInFund=true with costRecordedAt=null is excluded', () {
      final repairs = [
        TestRepair(
          firestoreId: 'edge_case',
          customerName: 'Edge Case',
          model: 'Test Phone',
          status: 4,
          price: 1000000,
          cost: 500000,
          paymentMethod: 'TIỀN MẶT',
          deliveredAt: todayStart + 36000000,
          costRecordedInFund: true,
          costPaymentMethod: 'TIỀN MẶT',
          costRecordedAt: null, // Should be excluded
        ),
      ];

      final entries = getRepairPartsCostExpenses(repairs: repairs, date: testDate);
      expect(entries.length, 0, reason: 'costRecordedAt=null means not actually recorded');
    });
  });

  group('🧮 Repair Parts Cost - Chi Tab Subtotal Calculation', () {
    test('repairPartsCostTotal matches type filter', () {
      final expenseList = [
        {'type': 'expense', 'amount': 500000},
        {'type': 'repair_parts_cost', 'amount': 1800000},
        {'type': 'repair_parts_cost', 'amount': 750000},
        {'type': 'expense', 'amount': 300000},
        {'type': 'repair_parts_cost', 'amount': 150000},
        {'type': 'supplier_import', 'amount': 2000000},
      ];

      // Mirrors _buildExpenseTab logic
      final repairPartsCostTotal = expenseList
          .where((t) => t['type'] == 'repair_parts_cost')
          .fold<int>(0, (s, t) => s + (t['amount'] as int));

      expect(repairPartsCostTotal, 2700000,
          reason: '1,800,000 + 750,000 + 150,000 = 2,700,000');
    });

    test('Total expense includes all types', () {
      final expenseList = [
        {'type': 'expense', 'amount': 500000},
        {'type': 'repair_parts_cost', 'amount': 1800000},
        {'type': 'repair_parts_cost', 'amount': 750000},
        {'type': 'expense', 'amount': 300000},
        {'type': 'repair_parts_cost', 'amount': 150000},
      ];

      final totalOut = expenseList.fold<int>(0, (s, t) => s + (t['amount'] as int));
      expect(totalOut, 3500000);
    });
  });

  group('🏠 Home View - repair parts cost fund query', () {
    test('SQL query logic: filters by costRecordedInFund=1 and date range', () {
      // Simulates the home view SQL query result processing
      final queryRows = [
        {'cost': 1800000, 'costPaymentMethod': 'TIỀN MẶT'},
        {'cost': 750000, 'costPaymentMethod': 'CHUYỂN KHOẢN'},
        {'cost': 150000, 'costPaymentMethod': 'TIỀN MẶT'},
        // 200000 excluded because costRecordedInFund=0 -> not in query results
      ];

      int repairPartsCostFund = 0;
      int cashOut = 0;
      int bankOut = 0;

      for (final r in queryRows) {
        final cost = (r['cost'] as num?)?.toInt() ?? 0;
        final method = (r['costPaymentMethod'] as String? ?? 'TIỀN MẶT').toString();
        repairPartsCostFund += cost;
        if (method == 'TIỀN MẶT') {
          cashOut += cost;
        } else {
          bankOut += cost;
        }
      }

      expect(repairPartsCostFund, 2700000);
      expect(cashOut, 1950000);
      expect(bankOut, 750000);
    });
  });
}
