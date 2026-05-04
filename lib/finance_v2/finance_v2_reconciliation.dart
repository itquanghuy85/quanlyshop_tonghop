class FinanceV2ReconciliationReportInput {
  final int totalIn;
  final int totalOut;
  final int net;
  final int totalRevenue;
  final int totalCost;
  final int totalProfit;
  final int openingDebtCustomer;
  final int openingDebtSupplier;
  final int totalDebtCustomer;
  final int totalDebtSupplier;

  const FinanceV2ReconciliationReportInput({
    required this.totalIn,
    required this.totalOut,
    required this.net,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalProfit,
    this.openingDebtCustomer = 0,
    this.openingDebtSupplier = 0,
    required this.totalDebtCustomer,
    required this.totalDebtSupplier,
  });
}

class FinanceV2ReconciliationMetric {
  final String key;
  final int logValue;
  final int reportValue;
  final String detail;

  const FinanceV2ReconciliationMetric({
    required this.key,
    required this.logValue,
    required this.reportValue,
    required this.detail,
  });

  int get diff => logValue - reportValue;
  bool get passed => diff == 0;
}

class FinanceV2ReconciliationResult {
  final List<FinanceV2ReconciliationMetric> metrics;

  const FinanceV2ReconciliationResult({required this.metrics});

  bool get passed => metrics.every((m) => m.passed);

  List<FinanceV2ReconciliationMetric> get failures =>
      metrics.where((m) => !m.passed).toList(growable: false);

  List<List<dynamic>> toSheetRows() {
    final rows = <List<dynamic>>[
      <dynamic>['STATUS', passed ? 'PASS' : 'FAIL', '', '', '', ''],
      <dynamic>['RULE', 'DIFF != 0 => FAIL', '', '', '', ''],
      <dynamic>['', '', '', '', '', ''],
      <dynamic>['metric', 'log_value', 'report_value', 'diff', 'status', 'detail'],
    ];

    for (final m in metrics) {
      rows.add(<dynamic>[
        m.key,
        m.logValue,
        m.reportValue,
        m.diff,
        m.passed ? 'PASS' : 'FAIL',
        m.detail,
      ]);
    }

    if (failures.isNotEmpty) {
      rows.add(<dynamic>['', '', '', '', '', '']);
      rows.add(<dynamic>['FAIL_REASON', 'Lệch dữ liệu', '', '', '', '']);
      for (final f in failures) {
        rows.add(<dynamic>[
          f.key,
          'Lệch ${f.diff.abs()}',
          '',
          f.diff,
          'FAIL',
          f.detail,
        ]);
      }
    }

    return rows;
  }
}

class FinanceV2ReconciliationEngine {
  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static FinanceV2ReconciliationResult compute({
    required List<Map<String, dynamic>> entries,
    required FinanceV2ReconciliationReportInput report,
  }) {
    int totalIn = 0;
    int totalOut = 0;
    int revenue = 0;
    int cost = 0;
    int debtCustomerFlow = 0;
    int debtSupplierFlow = 0;

    for (final e in entries) {
      final action = (e['actionType'] ?? '').toString().toUpperCase();
      final cashIn = _toInt(e['cashIn']);
      final cashOut = _toInt(e['cashOut']);
      final transferIn = _toInt(e['transferIn']);
      final transferOut = _toInt(e['transferOut']);
      final lineAmount = _toInt(e['lineAmount']);
      final lineCostTotal = _toInt(e['lineCostTotal']);
      final debtCustomerChange = _toInt(e['debtCustomerChange']);
      final debtSupplierChange = _toInt(e['debtSupplierChange']);

      totalIn += cashIn + transferIn;
      totalOut += cashOut + transferOut;
      debtCustomerFlow += debtCustomerChange;
      debtSupplierFlow += debtSupplierChange;

      if (action == 'SALE' || action == 'REPAIR') {
        revenue += lineAmount;
        cost += lineCostTotal;
        continue;
      }
      if (action == 'RETURN') {
        revenue -= lineAmount;
        cost -= lineCostTotal;
        continue;
      }
      if (action == 'OTHER_EXPENSE' || action == 'EXPENSE') {
        cost += cashOut + transferOut;
      }
    }

    final net = totalIn - totalOut;
    final profit = revenue - cost;
    final debtCustomerClosing = report.openingDebtCustomer + debtCustomerFlow;
    final debtSupplierClosing = report.openingDebtSupplier + debtSupplierFlow;

    final metrics = <FinanceV2ReconciliationMetric>[
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_IN',
        logValue: totalIn,
        reportValue: report.totalIn,
        detail: 'SUM(cash_in + transfer_in)',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_OUT',
        logValue: totalOut,
        reportValue: report.totalOut,
        detail: 'SUM(cash_out + transfer_out)',
      ),
      FinanceV2ReconciliationMetric(
        key: 'NET',
        logValue: net,
        reportValue: report.net,
        detail: 'TOTAL_IN - TOTAL_OUT',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_REVENUE',
        logValue: revenue,
        reportValue: report.totalRevenue,
        detail: 'SALE + REPAIR - RETURN (line_amount)',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_COST',
        logValue: cost,
        reportValue: report.totalCost,
        detail: 'COGS from log + OTHER_EXPENSE',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_PROFIT',
        logValue: profit,
        reportValue: report.totalProfit,
        detail: 'TOTAL_REVENUE - TOTAL_COST',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_DEBT_CUSTOMER',
        logValue: debtCustomerClosing,
        reportValue: report.totalDebtCustomer,
        detail: 'OPENING_DEBT_CUSTOMER + SUM(debt_customer_change)',
      ),
      FinanceV2ReconciliationMetric(
        key: 'TOTAL_DEBT_SUPPLIER',
        logValue: debtSupplierClosing,
        reportValue: report.totalDebtSupplier,
        detail: 'OPENING_DEBT_SUPPLIER + SUM(debt_supplier_change)',
      ),
    ];

    return FinanceV2ReconciliationResult(metrics: metrics);
  }
}
