import 'package:flutter/foundation.dart';

class DailyFinancialAnalysis {
  final int cashIn;
  final int cashOut;
  final int bankIn;
  final int bankOut;
  final int saleIncome;
  final int settlementIncome;
  final int repairIncome;
  final int debtCollected;
  final int miscIncome;
  final int expenseOut;
  final int importOut;
  final int supplierPaid;
  final int partnerPaid;
  final int repairPartsCostFund;
  final int saleCost;
  final int repairCost;
  final int refundOut;
  final int returnCost;

  const DailyFinancialAnalysis({
    required this.cashIn,
    required this.cashOut,
    required this.bankIn,
    required this.bankOut,
    required this.saleIncome,
    required this.settlementIncome,
    required this.repairIncome,
    required this.debtCollected,
    required this.miscIncome,
    required this.expenseOut,
    required this.importOut,
    required this.supplierPaid,
    required this.partnerPaid,
    required this.repairPartsCostFund,
    required this.saleCost,
    required this.repairCost,
    required this.refundOut,
    required this.returnCost,
  });

  int get totalIn => cashIn + bankIn;
  int get totalOut => cashOut + bankOut;
  int get netProfit =>
      saleIncome +
      settlementIncome +
      repairIncome +
      miscIncome -
      expenseOut -
      saleCost -
      repairCost;

  int get saleProfit => saleIncome + settlementIncome - saleCost;
  int get repairProfit => repairIncome - repairCost;
}

class DailyFinancialAnalysisService {
  static DailyFinancialAnalysis analyze({
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> settlementSales,
    required List<Map<String, dynamic>> repairs,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> debtPayments,
    required List<Map<String, dynamic>> supplierPayments,
    required List<Map<String, dynamic>> repairPartnerPayments,
    required List<Map<String, dynamic>> supplierImports,
    required List<Map<String, dynamic>> repairPartsCostFundRows,
    required List<Map<String, dynamic>> salesReturns,
    required bool enableRepair,
    bool logDebug = false,
  }) {
    int cashIn = 0;
    int cashOut = 0;
    int bankIn = 0;
    int bankOut = 0;
    int saleIncome = 0;
    int repairIncome = 0;
    int debtCollected = 0;
    int miscIncome = 0;
    int expenseOut = 0;
    int importOut = 0;
    int supplierPaid = 0;
    int partnerPaid = 0;
    int repairPartsCostFund = 0;
    int saleCost = 0;
    int repairCost = 0;
    int settlementIncome = 0;
    int saleDebt = 0;
    int repairDebt = 0;
    int refundOut = 0;
    int returnCostTotal = 0;

    for (final sale in sales) {
      final paymentMethod = _asString(sale['paymentMethod']);
      final totalPrice = _asInt(sale['totalPrice']);
      final discount = _asInt(sale['discount']);
      final finalPrice = totalPrice - discount > 0 ? totalPrice - discount : 0;
      final totalCost = _asInt(sale['totalCost']);
      final isInstallment = _asBool(sale['isInstallment']);

      if (paymentMethod == 'CÔNG NỢ') {
        saleIncome += finalPrice;
        saleCost += totalCost;
        saleDebt += finalPrice;
        continue;
      }

      if (isInstallment) {
        final downPaid = _asInt(sale['downPayment']);
        saleIncome += downPaid;

        final ratio = finalPrice > 0 ? downPaid / finalPrice : 0.0;
        saleCost += (totalCost * ratio).round();

        final downMethod = _asString(
          sale['downPaymentMethod'] ?? sale['paymentMethod'],
        );
        if (downMethod == 'TIỀN MẶT') {
          cashIn += downPaid;
        } else {
          bankIn += downPaid;
        }
      } else {
        saleIncome += finalPrice;
        saleCost += totalCost;
        if (paymentMethod == 'TIỀN MẶT') {
          cashIn += finalPrice;
        } else {
          bankIn += finalPrice;
        }
      }
    }

    for (final sale in settlementSales) {
      final settlementAmount = _asInt(sale['settlementAmount']);
      final loanAmount = _asInt(sale['loanAmount']);
      final loanAmount2 = _asInt(sale['loanAmount2']);
      final totalLoan = loanAmount + loanAmount2;
      final amount = settlementAmount.clamp(0, totalLoan);
      if (amount <= 0) continue;

      settlementIncome += amount;
      bankIn += amount;

      final totalPrice = _asInt(sale['totalPrice']);
      final discount = _asInt(sale['discount']);
      final finalPrice = totalPrice - discount > 0 ? totalPrice - discount : 0;
      final totalCost = _asInt(sale['totalCost']);
      final downPaid = _asInt(sale['downPayment']);
      final downRatio = finalPrice > 0 ? downPaid / finalPrice : 0.0;
      final remainRatio = 1.0 - downRatio;
      saleCost += (totalCost * remainRatio).round();
    }

    if (enableRepair) {
      for (final repair in repairs) {
        final price = _asInt(repair['price']);
        final totalCost = _repairCostValue(repair);
        final paymentMethod = _asString(repair['paymentMethod']);

        if (paymentMethod == 'CÔNG NỢ') {
          repairIncome += price;
          repairCost += totalCost;
          repairDebt += price;
          continue;
        }

        repairIncome += price;
        repairCost += totalCost;
        if (paymentMethod == 'TIỀN MẶT') {
          cashIn += price;
        } else {
          bankIn += price;
        }
      }
    } else {
      for (final repair in repairs) {
        repairIncome += _asInt(repair['price']);
        repairCost += _repairCostValue(repair);
      }
    }

    for (final expense in expenses) {
      final category = _asString(expense['category']).toUpperCase();
      final amount = _asInt(expense['amount']);
      final type = _asString(expense['type'], fallback: 'CHI').toUpperCase();
      final method = _asString(
        expense['paymentMethod'],
        fallback: 'TIỀN MẶT',
      );

      if (type == 'THU') {
        miscIncome += amount;
        if (method == 'TIỀN MẶT') {
          cashIn += amount;
        } else {
          bankIn += amount;
        }
        continue;
      }

      final isImport =
          category.contains('NHẬP') ||
          category.contains('LINH KIỆN') ||
          category.contains('PURCHASE');

      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }

      if (!isImport) {
        expenseOut += amount;
      }
    }

    for (final import in supplierImports) {
      final method = _asString(import['paymentMethod'], fallback: 'TIỀN MẶT');
      if (method == 'CÔNG NỢ') continue;

      final amount = _asInt(import['totalAmount']) > 0
          ? _asInt(import['totalAmount'])
          : _asInt(import['costPrice']);
      importOut += amount;

      final hasMatchingExpense = expenses.any((expense) {
        final category = _asString(expense['category']).toUpperCase();
        if (!category.contains('NHẬP') &&
            !category.contains('LINH KIỆN') &&
            !category.contains('PURCHASE')) {
          return false;
        }
        final expenseAmount = _asInt(expense['amount']);
        return (expenseAmount - amount).abs() < 1000;
      });

      if (!hasMatchingExpense) {
        if (method == 'TIỀN MẶT') {
          cashOut += amount;
        } else {
          bankOut += amount;
        }
      }
    }

    for (final payment in supplierPayments) {
      final amount = _asInt(payment['amount']);
      final method = _asString(
        payment['paymentMethod'],
        fallback: 'TIỀN MẶT',
      );
      supplierPaid += amount;

      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }

    if (enableRepair) {
      for (final payment in repairPartnerPayments) {
        final amount = _asInt(payment['amount']);
        final method = _asString(
          payment['paymentMethod'],
          fallback: 'TIỀN MẶT',
        );
        partnerPaid += amount;

        if (method == 'TIỀN MẶT') {
          cashOut += amount;
        } else {
          bankOut += amount;
        }
      }
    }

    for (final payment in debtPayments) {
      final amount = _asInt(payment['amount']);
      final method = _asString(
        payment['paymentMethod'],
        fallback: 'TIỀN MẶT',
      );
      final debtType = _resolvedDebtType(payment);

      if (_isShopOwesDebt(debtType)) {
        supplierPaid += amount;
        if (method == 'TIỀN MẶT') {
          cashOut += amount;
        } else {
          bankOut += amount;
        }
      } else {
        debtCollected += amount;
        if (method == 'TIỀN MẶT') {
          cashIn += amount;
        } else {
          bankIn += amount;
        }
      }
    }

    for (final repairCostRow in repairPartsCostFundRows) {
      final cost = _asInt(repairCostRow['costRecordedAmount']) > 0
          ? _asInt(repairCostRow['costRecordedAmount'])
          : _repairCostValue(repairCostRow);
      final method = _asString(
        repairCostRow['costPaymentMethod'] ?? repairCostRow['paymentMethod'],
        fallback: 'TIỀN MẶT',
      );

      repairPartsCostFund += cost;
      if (method == 'TIỀN MẶT') {
        cashOut += cost;
      } else {
        bankOut += cost;
      }
    }

    for (final salesReturn in salesReturns) {
      final amount = _asInt(salesReturn['totalReturnAmount']);
      final returnCost = _asInt(salesReturn['totalReturnCost']);
      final method = _asString(
        salesReturn['refundMethod'],
        fallback: 'TIỀN MẶT',
      );
      if (method == 'CÔNG NỢ') continue;

      refundOut += amount;
      returnCostTotal += returnCost;
      saleIncome -= amount;
      saleCost -= returnCost;

      if (method == 'TIỀN MẶT') {
        cashOut += amount;
      } else {
        bankOut += amount;
      }
    }

    if (logDebug) {
      debugPrint('=== DAILY FINANCIAL ANALYSIS ===');
      debugPrint('💵 cashIn=$cashIn, cashOut=$cashOut');
      debugPrint('🏦 bankIn=$bankIn, bankOut=$bankOut');
      debugPrint('📊 saleIncome=$saleIncome (debt=$saleDebt)');
      debugPrint('🔧 repairIncome=$repairIncome (debt=$repairDebt)');
      debugPrint('💳 debtCollected=$debtCollected');
      debugPrint('📤 expenseOut=$expenseOut, importOut=$importOut, supplierPaid=$supplierPaid, partnerPaid=$partnerPaid');
      debugPrint('💰 saleCost=$saleCost, repairCost=$repairCost, repairPartsCostFund=$repairPartsCostFund');
    }

    return DailyFinancialAnalysis(
      cashIn: cashIn,
      cashOut: cashOut,
      bankIn: bankIn,
      bankOut: bankOut,
      saleIncome: saleIncome,
      settlementIncome: settlementIncome,
      repairIncome: repairIncome,
      debtCollected: debtCollected,
      miscIncome: miscIncome,
      expenseOut: expenseOut,
      importOut: importOut,
      supplierPaid: supplierPaid,
      partnerPaid: partnerPaid,
      repairPartsCostFund: repairPartsCostFund,
      saleCost: saleCost,
      repairCost: repairCost,
      refundOut: refundOut,
      returnCost: returnCostTotal,
    );
  }

  static bool _isShopOwesDebt(String? debtType) {
    if (debtType == null) return false;
    return debtType == 'SHOP_OWES' ||
        debtType == 'OTHER_SHOP_OWES' ||
        debtType == 'OWED';
  }

  static String _resolvedDebtType(Map<String, dynamic> payment) {
    final resolved = _asString(payment['resolvedDebtType']);
    if (resolved.isNotEmpty) return resolved;
    return _asString(payment['debtType']);
  }

  static int _repairCostValue(Map<String, dynamic> repair) {
    final totalCost = _asInt(repair['totalCost']);
    if (totalCost > 0) return totalCost;
    return _asInt(repair['cost']);
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? 0;
    }
    return 0;
  }

  static bool _asBool(dynamic value) {
    return value == true || value == 1 || value == '1';
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }
}