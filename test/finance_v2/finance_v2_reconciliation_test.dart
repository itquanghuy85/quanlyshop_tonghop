import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/finance_v2/finance_v2_reconciliation.dart';

Map<String, dynamic> _entry({
  required String action,
  int cashIn = 0,
  int cashOut = 0,
  int transferIn = 0,
  int transferOut = 0,
  int lineAmount = 0,
  int lineCostTotal = 0,
  int debtCustomerChange = 0,
  int debtSupplierChange = 0,
}) {
  return <String, dynamic>{
    'actionType': action,
    'cashIn': cashIn,
    'cashOut': cashOut,
    'transferIn': transferIn,
    'transferOut': transferOut,
    'lineAmount': lineAmount,
    'lineCostTotal': lineCostTotal,
    'debtCustomerChange': debtCustomerChange,
    'debtSupplierChange': debtSupplierChange,
  };
}

void main() {
  group('FinanceV2 reconciliation', () {
    test('PASS import kho co/no debt', () {
      final entries = <Map<String, dynamic>>[
        _entry(action: 'IMPORT', cashOut: 300),
        _entry(action: 'IMPORT', debtSupplierChange: 500),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 0,
          totalOut: 300,
          net: -300,
          totalRevenue: 0,
          totalCost: 0,
          totalProfit: 0,
          totalDebtCustomer: 0,
          totalDebtSupplier: 500,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('PASS sale cash/debt/installment', () {
      final entries = <Map<String, dynamic>>[
        _entry(
          action: 'SALE',
          cashIn: 100,
          lineAmount: 100,
          lineCostTotal: 60,
        ),
        _entry(
          action: 'SALE',
          debtCustomerChange: 200,
          lineAmount: 0,
          lineCostTotal: 0,
        ),
        _entry(
          action: 'SALE',
          cashIn: 50,
          transferIn: 30,
          debtCustomerChange: 70,
          lineAmount: 80,
          lineCostTotal: 48,
        ),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 180,
          totalOut: 0,
          net: 180,
          totalRevenue: 180,
          totalCost: 108,
          totalProfit: 72,
          totalDebtCustomer: 270,
          totalDebtSupplier: 0,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('PASS return full/partial', () {
      final entries = <Map<String, dynamic>>[
        _entry(
          action: 'RETURN',
          cashOut: 100,
          lineAmount: 100,
          lineCostTotal: 60,
        ),
        _entry(
          action: 'RETURN',
          debtCustomerChange: -40,
          lineAmount: 40,
          lineCostTotal: 20,
        ),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 0,
          totalOut: 100,
          net: -100,
          totalRevenue: -140,
          totalCost: -80,
          totalProfit: -60,
          totalDebtCustomer: -40,
          totalDebtSupplier: 0,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('PASS debt collect/pay', () {
      final entries = <Map<String, dynamic>>[
        _entry(action: 'DEBT_COLLECT', cashIn: 70, debtCustomerChange: -70),
        _entry(action: 'DEBT_PAY', transferOut: 50, debtSupplierChange: -50),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 70,
          totalOut: 50,
          net: 20,
          totalRevenue: 0,
          totalCost: 0,
          totalProfit: 0,
          totalDebtCustomer: -70,
          totalDebtSupplier: -50,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('PASS debt closing from opening plus flow', () {
      final entries = <Map<String, dynamic>>[
        _entry(action: 'SALE', debtCustomerChange: 300),
        _entry(action: 'DEBT_COLLECT', cashIn: 120, debtCustomerChange: -120),
        _entry(action: 'IMPORT', debtSupplierChange: 500),
        _entry(action: 'DEBT_PAY', cashOut: 200, debtSupplierChange: -200),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 120,
          totalOut: 200,
          net: -80,
          totalRevenue: 0,
          totalCost: 0,
          totalProfit: 0,
          openingDebtCustomer: 1000,
          openingDebtSupplier: 700,
          totalDebtCustomer: 1180,
          totalDebtSupplier: 1000,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('FAIL khi report lech', () {
      final entries = <Map<String, dynamic>>[
        _entry(action: 'SALE', cashIn: 100, lineAmount: 100, lineCostTotal: 70),
      ];

      final result = FinanceV2ReconciliationEngine.compute(
        entries: entries,
        report: const FinanceV2ReconciliationReportInput(
          totalIn: 100,
          totalOut: 0,
          net: 100,
          totalRevenue: 100,
          totalCost: 60,
          totalProfit: 40,
          totalDebtCustomer: 0,
          totalDebtSupplier: 0,
        ),
      );

      expect(result.passed, isFalse);
      expect(result.failures.any((f) => f.key == 'TOTAL_COST'), isTrue);
      expect(result.failures.any((f) => f.key == 'TOTAL_PROFIT'), isTrue);
    });
  });
}
