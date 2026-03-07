import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/services/daily_financial_analysis_service.dart';

/// Helper to create empty analysis inputs
Map<String, List<Map<String, dynamic>>> emptyInputs() => {
      'sales': [],
      'settlementSales': [],
      'repairs': [],
      'expenses': [],
      'debtPayments': [],
      'supplierPayments': [],
      'repairPartnerPayments': [],
      'supplierImports': [],
      'repairPartsCostFundRows': [],
      'salesReturns': [],
    };

DailyFinancialAnalysis runAnalysis(
  Map<String, List<Map<String, dynamic>>> inputs, {
  bool enableRepair = true,
}) {
  return DailyFinancialAnalysisService.analyze(
    sales: inputs['sales']!,
    settlementSales: inputs['settlementSales']!,
    repairs: inputs['repairs']!,
    expenses: inputs['expenses']!,
    debtPayments: inputs['debtPayments']!,
    supplierPayments: inputs['supplierPayments']!,
    repairPartnerPayments: inputs['repairPartnerPayments']!,
    supplierImports: inputs['supplierImports']!,
    repairPartsCostFundRows: inputs['repairPartsCostFundRows']!,
    salesReturns: inputs['salesReturns']!,
    enableRepair: enableRepair,
  );
}

void main() {
  group('DailyFinancialAnalysisService - empty inputs', () {
    test('returns zero for all fields when no data', () {
      final result = runAnalysis(emptyInputs());
      expect(result.totalIn, 0);
      expect(result.totalOut, 0);
      expect(result.netProfit, 0);
      expect(result.saleProfit, 0);
      expect(result.repairProfit, 0);
      expect(result.cashIn, 0);
      expect(result.cashOut, 0);
      expect(result.bankIn, 0);
      expect(result.bankOut, 0);
    });
  });

  group('DailyFinancialAnalysisService - cash sales', () {
    test('K1: cash sale SIM 170k cost 140k', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 170000,
          'discount': 0,
          'totalCost': 140000,
          'paymentMethod': 'TIỀN MẶT',
          'isInstallment': false,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashIn, 170000);
      expect(r.bankIn, 0);
      expect(r.saleIncome, 170000);
      expect(r.saleCost, 140000);
      expect(r.saleProfit, 30000); // 170k - 140k
      expect(r.totalIn, 170000);
      expect(r.totalOut, 0);
    });

    test('K2: bank sale iPhone 16 Plus 18.71M cost 16M', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 18710000,
          'discount': 0,
          'totalCost': 16000000,
          'paymentMethod': 'CHUYỂN KHOẢN',
          'isInstallment': false,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashIn, 0);
      expect(r.bankIn, 18710000);
      expect(r.saleIncome, 18710000);
      expect(r.saleCost, 16000000);
      expect(r.saleProfit, 2710000);
    });

    test('cash sale with discount', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 5000000,
          'discount': 200000,
          'totalCost': 3500000,
          'paymentMethod': 'TIỀN MẶT',
          'isInstallment': false,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashIn, 4800000);
      expect(r.saleIncome, 4800000);
      expect(r.saleCost, 3500000);
      expect(r.saleProfit, 1300000);
    });
  });

  group('DailyFinancialAnalysisService - CÔNG NỢ sales', () {
    test('K3: credit sale counts income/cost but no cash flow', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 5000000,
          'discount': 0,
          'totalCost': 4000000,
          'paymentMethod': 'CÔNG NỢ',
          'isInstallment': false,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashIn, 0);
      expect(r.bankIn, 0);
      expect(r.saleIncome, 5000000);
      expect(r.saleCost, 4000000);
      expect(r.saleProfit, 1000000);
      expect(r.totalIn, 0, reason: 'CÔNG NỢ sale should not generate cash flow');
    });
  });

  group('DailyFinancialAnalysisService - installment sales', () {
    test('K4: installment iPhone 12 Pro 5M down on 15M total', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 15000000,
          'discount': 0,
          'totalCost': 12000000,
          'paymentMethod': 'TRẢ GÓP',
          'isInstallment': true,
          'downPayment': 5000000,
          'downPaymentMethod': 'TIỀN MẶT',
          'loanAmount': 10000000,
        },
      ];
      final r = runAnalysis(inputs);
      // Only downPayment counted as income
      expect(r.saleIncome, 5000000);
      expect(r.cashIn, 5000000);
      // Cost proportional: 12M * (5M/15M) = 4M
      expect(r.saleCost, 4000000);
      expect(r.saleProfit, 1000000);
    });

    test('installment with bank down payment', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 20000000,
          'discount': 0,
          'totalCost': 16000000,
          'paymentMethod': 'TRẢ GÓP',
          'isInstallment': true,
          'downPayment': 8000000,
          'downPaymentMethod': 'CHUYỂN KHOẢN',
          'loanAmount': 12000000,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.saleIncome, 8000000);
      expect(r.bankIn, 8000000);
      expect(r.cashIn, 0);
      // Cost proportional: 16M * (8M/20M) = 6.4M
      expect(r.saleCost, 6400000);
    });
  });

  group('DailyFinancialAnalysisService - settlement sales', () {
    test('settlement sale adds to settlementIncome and bankIn', () {
      final inputs = emptyInputs();
      inputs['settlementSales'] = [
        {
          'settlementAmount': 10000000,
          'loanAmount': 10000000,
          'loanAmount2': 0,
          'totalPrice': 15000000,
          'discount': 0,
          'totalCost': 12000000,
          'downPayment': 5000000,
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.settlementIncome, 10000000);
      expect(r.bankIn, 10000000);
      // remainRatio = 1 - (5M/15M) = 0.6667; cost = 12M * 0.6667 = 8M
      expect(r.saleCost, 8000000);
      expect(r.saleProfit, 10000000 - 8000000); // settlement - cost
    });

    test('settlement capped at total loan', () {
      final inputs = emptyInputs();
      inputs['settlementSales'] = [
        {
          'settlementAmount': 20000000,
          'loanAmount': 8000000,
          'loanAmount2': 2000000,
          'totalPrice': 15000000,
          'discount': 0,
          'totalCost': 12000000,
          'downPayment': 5000000,
        },
      ];
      final r = runAnalysis(inputs);
      // Capped at loanAmount + loanAmount2 = 10M
      expect(r.settlementIncome, 10000000);
      expect(r.bankIn, 10000000);
    });
  });

  group('DailyFinancialAnalysisService - repairs', () {
    test('cash repair with enableRepair=true', () {
      final inputs = emptyInputs();
      inputs['repairs'] = [
        {
          'price': 500000,
          'totalCost': 150000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs, enableRepair: true);
      expect(r.repairIncome, 500000);
      expect(r.repairCost, 150000);
      expect(r.cashIn, 500000);
      expect(r.repairProfit, 350000);
    });

    test('CÔNG NỢ repair: income counted but no cash flow', () {
      final inputs = emptyInputs();
      inputs['repairs'] = [
        {
          'price': 800000,
          'totalCost': 200000,
          'paymentMethod': 'CÔNG NỢ',
        },
      ];
      final r = runAnalysis(inputs, enableRepair: true);
      expect(r.repairIncome, 800000);
      expect(r.repairCost, 200000);
      expect(r.cashIn, 0);
      expect(r.bankIn, 0);
    });

    test('enableRepair=false: income but no cash flow', () {
      final inputs = emptyInputs();
      inputs['repairs'] = [
        {
          'price': 500000,
          'totalCost': 150000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs, enableRepair: false);
      expect(r.repairIncome, 500000);
      expect(r.repairCost, 150000);
      // When enableRepair=false, no cashIn from repairs
      expect(r.cashIn, 0);
    });
  });

  group('DailyFinancialAnalysisService - expenses', () {
    test('K5: cash expense 200k', () {
      final inputs = emptyInputs();
      inputs['expenses'] = [
        {
          'category': 'Điện nước',
          'amount': 200000,
          'type': 'CHI',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashOut, 200000);
      expect(r.expenseOut, 200000);
      expect(r.totalOut, 200000);
    });

    test('THU expense (miscellaneous income)', () {
      final inputs = emptyInputs();
      inputs['expenses'] = [
        {
          'category': 'Khác',
          'amount': 300000,
          'type': 'THU',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.miscIncome, 300000);
      expect(r.cashIn, 300000);
      expect(r.expenseOut, 0, reason: 'THU type should not count as expense');
    });

    test('import expense does not double-count in expenseOut', () {
      final inputs = emptyInputs();
      inputs['expenses'] = [
        {
          'category': 'NHẬP HÀNG',
          'amount': 1350000,
          'type': 'CHI',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.cashOut, 1350000);
      // Import category should NOT count in expenseOut
      expect(r.expenseOut, 0);
    });
  });

  group('DailyFinancialAnalysisService - debt payments', () {
    test('K6: customer debt collection (CUSTOMER_OWES) 3M cash', () {
      final inputs = emptyInputs();
      inputs['debtPayments'] = [
        {
          'amount': 3000000,
          'paymentMethod': 'TIỀN MẶT',
          'debtType': 'CUSTOMER_OWES',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.debtCollected, 3000000);
      expect(r.cashIn, 3000000);
      expect(r.supplierPaid, 0);
    });

    test('shop owes debt (SHOP_OWES) = supplier payment 3M', () {
      final inputs = emptyInputs();
      inputs['debtPayments'] = [
        {
          'amount': 3000000,
          'paymentMethod': 'TIỀN MẶT',
          'debtType': 'SHOP_OWES',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.supplierPaid, 3000000);
      expect(r.cashOut, 3000000);
      expect(r.debtCollected, 0);
    });

    test('OTHER_SHOP_OWES and OWED also count as shop payment', () {
      final inputs = emptyInputs();
      inputs['debtPayments'] = [
        {
          'amount': 1000000,
          'paymentMethod': 'CHUYỂN KHOẢN',
          'debtType': 'OTHER_SHOP_OWES',
        },
        {
          'amount': 500000,
          'paymentMethod': 'TIỀN MẶT',
          'debtType': 'OWED',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.supplierPaid, 1500000);
      expect(r.bankOut, 1000000);
      expect(r.cashOut, 500000);
      expect(r.debtCollected, 0);
    });

    test('resolvedDebtType takes priority over debtType', () {
      final inputs = emptyInputs();
      inputs['debtPayments'] = [
        {
          'amount': 2000000,
          'paymentMethod': 'TIỀN MẶT',
          'debtType': 'CUSTOMER_OWES',
          'resolvedDebtType': 'SHOP_OWES',
        },
      ];
      final r = runAnalysis(inputs);
      // resolvedDebtType=SHOP_OWES overrides debtType=CUSTOMER_OWES
      expect(r.supplierPaid, 2000000);
      expect(r.cashOut, 2000000);
      expect(r.debtCollected, 0);
    });
  });

  group('DailyFinancialAnalysisService - supplier payments', () {
    test('cash supplier payment 3M', () {
      final inputs = emptyInputs();
      inputs['supplierPayments'] = [
        {
          'amount': 3000000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.supplierPaid, 3000000);
      expect(r.cashOut, 3000000);
    });
  });

  group('DailyFinancialAnalysisService - supplier imports', () {
    test('cash import with no matching expense adds to cashOut', () {
      final inputs = emptyInputs();
      inputs['supplierImports'] = [
        {
          'totalAmount': 1350000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.importOut, 1350000);
      expect(r.cashOut, 1350000);
    });

    test('CÔNG NỢ import skipped entirely', () {
      final inputs = emptyInputs();
      inputs['supplierImports'] = [
        {
          'totalAmount': 5000000,
          'paymentMethod': 'CÔNG NỢ',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.importOut, 0);
      expect(r.cashOut, 0);
    });

    test('import with matching expense does not double cashOut', () {
      final inputs = emptyInputs();
      inputs['expenses'] = [
        {
          'category': 'NHẬP HÀNG',
          'amount': 1350000,
          'type': 'CHI',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      inputs['supplierImports'] = [
        {
          'totalAmount': 1350000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.importOut, 1350000);
      // expense cashOut(1.35M) + import should not double
      // matching expense found → import does NOT add to cashOut
      expect(r.cashOut, 1350000, reason: 'Should only count once');
    });
  });

  group('DailyFinancialAnalysisService - repair partner payments', () {
    test('partner payment with enableRepair=true', () {
      final inputs = emptyInputs();
      inputs['repairPartnerPayments'] = [
        {
          'amount': 500000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs, enableRepair: true);
      expect(r.partnerPaid, 500000);
      expect(r.cashOut, 500000);
    });

    test('partner payment with enableRepair=false: skipped', () {
      final inputs = emptyInputs();
      inputs['repairPartnerPayments'] = [
        {
          'amount': 500000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs, enableRepair: false);
      expect(r.partnerPaid, 0);
      expect(r.cashOut, 0);
    });
  });

  group('DailyFinancialAnalysisService - sales returns', () {
    test('cash refund reduces income and adds to cashOut', () {
      final inputs = emptyInputs();
      inputs['salesReturns'] = [
        {
          'totalReturnAmount': 500000,
          'totalReturnCost': 350000,
          'refundMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.refundOut, 500000);
      expect(r.returnCost, 350000);
      expect(r.saleIncome, -500000); // reduced from 0
      expect(r.saleCost, -350000);
      expect(r.cashOut, 500000);
    });

    test('CÔNG NỢ return skipped', () {
      final inputs = emptyInputs();
      inputs['salesReturns'] = [
        {
          'totalReturnAmount': 500000,
          'totalReturnCost': 350000,
          'refundMethod': 'CÔNG NỢ',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.refundOut, 0);
      expect(r.cashOut, 0);
      expect(r.saleIncome, 0);
    });
  });

  group('DailyFinancialAnalysisService - repair parts cost fund', () {
    test('costRecordedAmount takes priority', () {
      final inputs = emptyInputs();
      inputs['repairPartsCostFundRows'] = [
        {
          'costRecordedAmount': 300000,
          'totalCost': 200000,
          'costPaymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      expect(r.repairPartsCostFund, 300000);
      expect(r.cashOut, 300000);
    });
  });

  group('DailyFinancialAnalysisService - full day scenario', () {
    test('real-world day: multiple transactions', () {
      final inputs = emptyInputs();

      // Sales
      inputs['sales'] = [
        // SIM cash 170k
        {
          'totalPrice': 170000,
          'discount': 0,
          'totalCost': 140000,
          'paymentMethod': 'TIỀN MẶT',
          'isInstallment': false,
        },
        // iPhone 16 Plus bank 18.71M
        {
          'totalPrice': 18710000,
          'discount': 0,
          'totalCost': 16000000,
          'paymentMethod': 'CHUYỂN KHOẢN',
          'isInstallment': false,
        },
        // Installment 15M, down 5M cash
        {
          'totalPrice': 15000000,
          'discount': 0,
          'totalCost': 12000000,
          'paymentMethod': 'TRẢ GÓP',
          'isInstallment': true,
          'downPayment': 5000000,
          'downPaymentMethod': 'TIỀN MẶT',
          'loanAmount': 10000000,
        },
      ];

      // Expenses
      inputs['expenses'] = [
        {
          'category': 'Điện nước',
          'amount': 200000,
          'type': 'CHI',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];

      // Debt collection
      inputs['debtPayments'] = [
        {
          'amount': 3000000,
          'paymentMethod': 'TIỀN MẶT',
          'debtType': 'CUSTOMER_OWES',
        },
      ];

      // Supplier import
      inputs['supplierImports'] = [
        {
          'totalAmount': 1350000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];

      // Supplier payment
      inputs['supplierPayments'] = [
        {
          'amount': 3000000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];

      final r = runAnalysis(inputs);

      // cashIn: SIM 170k + installment down 5M + debt 3M = 8,170,000
      expect(r.cashIn, 8170000);
      // bankIn: iPhone 18.71M
      expect(r.bankIn, 18710000);
      // totalIn
      expect(r.totalIn, 26880000);

      // cashOut: expense 200k + import 1.35M + supplier 3M = 4,550,000
      expect(r.cashOut, 4550000);
      expect(r.bankOut, 0);
      expect(r.totalOut, 4550000);

      // Sale income: 170k + 18.71M + 5M(down) = 23,880,000
      expect(r.saleIncome, 23880000);
      // Sale cost: 140k + 16M + 4M(proportional) = 20,140,000
      expect(r.saleCost, 20140000);
      expect(r.saleProfit, 3740000);

      expect(r.debtCollected, 3000000);
      expect(r.supplierPaid, 3000000);
      expect(r.importOut, 1350000);
      expect(r.expenseOut, 200000);
    });
  });

  group('DailyFinancialAnalysis computed getters', () {
    test('netProfit formula', () {
      final inputs = emptyInputs();
      inputs['sales'] = [
        {
          'totalPrice': 10000000,
          'discount': 0,
          'totalCost': 7000000,
          'paymentMethod': 'TIỀN MẶT',
          'isInstallment': false,
        },
      ];
      inputs['repairs'] = [
        {
          'price': 500000,
          'totalCost': 100000,
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      inputs['expenses'] = [
        {
          'category': 'Thuê mặt bằng',
          'amount': 1000000,
          'type': 'CHI',
          'paymentMethod': 'TIỀN MẶT',
        },
        {
          'category': 'Khác',
          'amount': 200000,
          'type': 'THU',
          'paymentMethod': 'TIỀN MẶT',
        },
      ];
      final r = runAnalysis(inputs);
      // netProfit = saleIncome(10M) + settlementIncome(0) + repairIncome(500k) + miscIncome(200k)
      //           - expenseOut(1M) - saleCost(7M) - repairCost(100k) = 2,600,000
      expect(r.netProfit, 2600000);
    });
  });
}
