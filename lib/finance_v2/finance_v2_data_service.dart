import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';

enum FinanceV2Aggregation { day, month, year }

class FinanceV2MetricCard {
  final String label;
  final int amount;
  final int? previousAmount; // For period comparison

  const FinanceV2MetricCard({
    required this.label,
    required this.amount,
    this.previousAmount,
  });

  /// Calculate % change: positive = increase, negative = decrease
  /// Returns null if no previous amount
  double? get percentChange {
    if (previousAmount == null || previousAmount == 0) return null;
    return ((amount - previousAmount!) / previousAmount!) * 100;
  }
}

class FinanceV2Txn {
  final String id;
  final int createdAt;
  final String type;
  final String title;
  final String subtitle;
  final int amount;
  final bool isIncome;
  final String? avatarUrl;
  final String? actorName;
  final String? paymentMethod;
  final String? referenceId;
  final String? customerName;
  final String? itemName;
  final int? costAmount;
  final int? grossProfit;

  const FinanceV2Txn({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isIncome,
    this.avatarUrl,
    this.actorName,
    this.paymentMethod,
    this.referenceId,
    this.customerName,
    this.itemName,
    this.costAmount,
    this.grossProfit,
  });
}

class FinanceV2DebtItem {
  final String id;
  final String type;
  final String name;
  final int total;
  final int paid;
  final int remaining;
  final String? avatarUrl;
  final int createdAt;
  final String? phone;

  const FinanceV2DebtItem({
    required this.id,
    required this.type,
    required this.name,
    required this.total,
    required this.paid,
    required this.remaining,
    this.avatarUrl,
    required this.createdAt,
    this.phone,
  });
}

class FinanceV2PeriodBucket {
  final String key;
  final String label;
  final int totalIn;
  final int totalOut;
  final int txCount;

  const FinanceV2PeriodBucket({
    required this.key,
    required this.label,
    required this.totalIn,
    required this.totalOut,
    required this.txCount,
  });

  int get net => totalIn - totalOut;
}

class FinanceV2CategoryStat {
  final String label;
  final int amount;

  const FinanceV2CategoryStat({required this.label, required this.amount});
}

class FinanceV2Snapshot {
  final int totalIn;
  final int totalOut;
  /// Tiền ra thuần (không tính trả nợ NCC/đối tác)
  final int operatingExpenseOut;
  /// Tiền trả nợ nhà cung cấp / đối tác (SHOP_OWES)
  final int debtRepayOut;
  final int receivableTotal;
  final int payableTotal;
  final int netCashflow;
  final int incomeFromSales;
  final int incomeFromRepairs;
  final int cogsFromSales;
  final int cogsFromRepairs;
  final int grossProfitFromSales;
  final int grossProfitFromRepairs;
  final int grossProfitTotal;
  final int incomeOther;
  final int transactionCount;
  final int avgIncomePerTransaction;
  final int previousTotalIn;
  final int previousTotalOut;
  final int previousNetCashflow;
  final int previousCogsFromSales;
  final int previousCogsFromRepairs;
  final int previousGrossProfitFromSales;
  final int previousGrossProfitFromRepairs;
  final List<FinanceV2MetricCard> dashboardCards;
  final List<FinanceV2CategoryStat> topExpenseCategories;
  final List<FinanceV2Txn> transactions;
  final List<FinanceV2DebtItem> receivables;
  final List<FinanceV2DebtItem> payables;
  final List<FinanceV2PeriodBucket> byDay;
  final List<FinanceV2PeriodBucket> byMonth;
  final List<FinanceV2PeriodBucket> byYear;
  final List<Map<String, dynamic>> auditLogs;
  final Map<String, int> debtAging; // {'0-30': 1000000, '30-60': 500000, '>60': 2000000}

  const FinanceV2Snapshot({
    required this.totalIn,
    required this.totalOut,
    required this.operatingExpenseOut,
    required this.debtRepayOut,
    required this.receivableTotal,
    required this.payableTotal,
    required this.netCashflow,
    required this.incomeFromSales,
    required this.incomeFromRepairs,
    required this.cogsFromSales,
    required this.cogsFromRepairs,
    required this.grossProfitFromSales,
    required this.grossProfitFromRepairs,
    required this.grossProfitTotal,
    required this.incomeOther,
    required this.transactionCount,
    required this.avgIncomePerTransaction,
    required this.previousTotalIn,
    required this.previousTotalOut,
    required this.previousNetCashflow,
    required this.previousCogsFromSales,
    required this.previousCogsFromRepairs,
    required this.previousGrossProfitFromSales,
    required this.previousGrossProfitFromRepairs,
    required this.dashboardCards,
    required this.topExpenseCategories,
    required this.transactions,
    required this.receivables,
    required this.payables,
    required this.byDay,
    required this.byMonth,
    required this.byYear,
    required this.auditLogs,
    required this.debtAging,
  });

  List<FinanceV2PeriodBucket> buckets(FinanceV2Aggregation aggregation) {
    switch (aggregation) {
      case FinanceV2Aggregation.day:
        return byDay;
      case FinanceV2Aggregation.month:
        return byMonth;
      case FinanceV2Aggregation.year:
        return byYear;
    }
  }

  /// Get total debt aging amount (sum of all aging buckets)
  int get totalDebtAging {
    return (debtAging['0-30'] ?? 0) +
        (debtAging['30-60'] ?? 0) +
        (debtAging['>60'] ?? 0);
  }
}

class FinanceV2DataService {
  final DBHelper _db;

  FinanceV2DataService({DBHelper? dbHelper}) : _db = dbHelper ?? DBHelper();

  Future<FinanceV2Snapshot> loadSnapshot({
    DateTime? start,
    DateTime? end,
    DateTime? previousStart,
    DateTime? previousEnd,
  }) async {
    final now = DateTime.now();
    final rangeStart = DateTime(
      (start ?? DateTime(now.year, now.month, 1)).year,
      (start ?? DateTime(now.year, now.month, 1)).month,
      (start ?? DateTime(now.year, now.month, 1)).day,
    );
    final rangeEnd = DateTime(
      (end ?? now).year,
      (end ?? now).month,
      (end ?? now).day,
      23,
      59,
      59,
    );

    final startMs = rangeStart.millisecondsSinceEpoch;
    final endMs = rangeEnd.millisecondsSinceEpoch;
    final periodMs = endMs - startMs + 1;

    // Tính khoảng kỳ trước: ưu tiên tham số truyền vào, nếu không thì dùng độ dài tương đương
    final int previousStartMs;
    final int previousEndMs;
    if (previousStart != null && previousEnd != null) {
      previousStartMs = DateTime(previousStart.year, previousStart.month, previousStart.day).millisecondsSinceEpoch;
      previousEndMs = DateTime(previousEnd.year, previousEnd.month, previousEnd.day, 23, 59, 59).millisecondsSinceEpoch;
    } else {
      previousEndMs = startMs - 1;
      previousStartMs = previousEndMs - periodMs + 1;
    }

    final sales = await _db.getSalesByDateRange(startMs, endMs);
    final repairs = await _db.getDeliveredRepairsByDateRange(startMs, endMs);
    final expenses = await _db.getExpensesByDateRange(startMs, endMs);
    final repairPartnerPayments = await _db.getRepairPartnerPaymentsByDateRange(
      startMs,
      endMs,
    );
    final debtPayments = await _db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs);
    // Chỉ lấy công nợ được tạo trong khoảng kỳ đã chọn — dùng query có date range thay vì tải toàn bộ
    final debts = await _db.getDebtsByDateRange(startMs, endMs);
    final activities = await _db.getFinancialActivities(
      startDate: startMs,
      endDate: endMs,
      limit: 500,
    );

    final previousSales = await _db.getSalesByDateRange(previousStartMs, previousEndMs);
    final previousRepairs = await _db.getDeliveredRepairsByDateRange(previousStartMs, previousEndMs);
    final previousExpenses = await _db.getExpensesByDateRange(previousStartMs, previousEndMs);
    final previousRepairPartnerPayments = await _db.getRepairPartnerPaymentsByDateRange(
      previousStartMs,
      previousEndMs,
    );
    final suppliers = await _db.getSuppliers();
    final partners = await _db.getRepairPartners();
    final customers = await _db.getCustomers();

    final supplierAvatarByName = <String, String>{};
    final supplierPhoneByName = <String, String>{};
    for (final row in suppliers) {
      final key = _normalizeName(row['name']);
      if (key.isEmpty) continue;
      final avatar = (row['avatarUrl'] ?? '').toString();
      final phone = (row['phone'] ?? '').toString();
      if (avatar.isNotEmpty) supplierAvatarByName[key] = avatar;
      if (phone.isNotEmpty) supplierPhoneByName[key] = phone;
    }

    final partnerAvatarByName = <String, String>{};
    final partnerPhoneByName = <String, String>{};
    for (final row in partners) {
      final key = _normalizeName(row['name']);
      if (key.isEmpty) continue;
      final avatar = (row['avatarUrl'] ?? '').toString();
      final phone = (row['phone'] ?? '').toString();
      if (avatar.isNotEmpty) partnerAvatarByName[key] = avatar;
      if (phone.isNotEmpty) partnerPhoneByName[key] = phone;
    }

    final customerAvatarByName = <String, String>{};
    final customerPhoneByName = <String, String>{};
    for (final row in customers) {
      final key = _normalizeName(row['name']);
      if (key.isEmpty) continue;
      final avatar = (row['avatarUrl'] ?? '').toString();
      final phone = (row['phone'] ?? '').toString();
      if (avatar.isNotEmpty) customerAvatarByName[key] = avatar;
      if (phone.isNotEmpty) customerPhoneByName[key] = phone;
    }

    int saleIn = 0;
    int repairIn = 0;
    int expenseOut = 0;
    int debtRepayOut = 0; // Trả nợ NCC/đối tác (SHOP_OWES) — tách riêng để hiển thị
    int extraIn = 0;
    int saleCogs = 0;
    int repairCogs = 0;

    final transactions = <FinanceV2Txn>[];

    for (final SaleOrder sale in sales) {
      final bool isCongNo = sale.paymentMethod.toUpperCase() == 'CÔNG NỢ';
      final int actualPaid;
      if (sale.isInstallment) {
        actualPaid = sale.downPayment + sale.settlementAmount;
      } else if (isCongNo) {
        actualPaid = 0;
      } else {
        actualPaid = sale.finalPrice;
      }

      // Vốn/Lãi bán hàng theo accrual: ghi nhận theo ngày bán, độc lập với thời điểm NH giải ngân.
      final int accrualRevenue = sale.finalPrice > 0 ? sale.finalPrice : 0;
      if (accrualRevenue > 0) {
        saleCogs += sale.totalCost > 0 ? sale.totalCost : 0;
      }

      if (actualPaid > 0) {
        // recognizedCost chỉ dùng cho hiển thị per-transaction (cashflow basis).
        // saleCogs đã được tính theo accrual (toàn bộ totalCost) ở block trên.
        int recognizedCost = 0;
        if (sale.totalCost > 0) {
          if (sale.finalPrice > 0) {
            recognizedCost = ((sale.totalCost * actualPaid) / sale.finalPrice).round();
          } else {
            recognizedCost = sale.totalCost;
          }
          if (recognizedCost < 0) recognizedCost = 0;
          if (recognizedCost > actualPaid) recognizedCost = actualPaid;
        }
        saleIn += actualPaid;
        transactions.add(
          FinanceV2Txn(
            id: 'sale_${sale.id ?? sale.firestoreId ?? sale.soldAt}',
            createdAt: sale.soldAt,
            type: 'SALE',
            title: sale.productNames.trim().isNotEmpty
                ? sale.productNames.trim()
                : 'Sản phẩm bán lẻ',
            subtitle:
                'Khách: ${sale.customerName.isNotEmpty ? sale.customerName : 'Khách lẻ'}'
                '${sale.paymentMethod.isNotEmpty ? ' · ${sale.paymentMethod}' : ''}',
            amount: actualPaid,
            isIncome: true,
            avatarUrl: customerAvatarByName[_normalizeName(sale.customerName)],
            actorName: sale.sellerName.trim().isEmpty ? null : sale.sellerName,
            paymentMethod: sale.paymentMethod,
            referenceId: sale.firestoreId ?? sale.id?.toString(),
            customerName: sale.customerName,
            itemName: sale.productNames,
            costAmount: recognizedCost,
            grossProfit: actualPaid - recognizedCost,
          ),
        );
      }
    }

    for (final Repair repair in repairs) {
      if (repair.paymentMethod.toUpperCase() == 'CÔNG NỢ') {
        continue;
      }
      final amount = repair.price;
      if (amount > 0) {
        final repairCost = repair.totalCost > 0 ? repair.totalCost : 0;
        repairCogs += repairCost;
        repairIn += amount;
        transactions.add(
          FinanceV2Txn(
            id: 'repair_${repair.id ?? repair.firestoreId ?? repair.createdAt}',
            createdAt: repair.deliveredAt ?? repair.createdAt,
            type: 'REPAIR',
            title: repair.customerName,
            subtitle:
                'Sửa ${repair.model.isNotEmpty ? repair.model : 'thiết bị'}'
                '${repair.issue.isNotEmpty ? ' · ${repair.issue}' : ''}'
                '${repair.paymentMethod.isNotEmpty ? ' · ${repair.paymentMethod}' : ''}',
            amount: amount,
            isIncome: true,
            avatarUrl: customerAvatarByName[_normalizeName(repair.customerName)],
            actorName: (repair.repairedBy ?? repair.createdBy ?? '').trim().isEmpty
                ? null
                : (repair.repairedBy ?? repair.createdBy ?? '').trim(),
            paymentMethod: repair.paymentMethod,
            referenceId: repair.firestoreId ?? repair.id?.toString(),
            customerName: repair.customerName,
            itemName: repair.model,
            costAmount: repairCost,
            grossProfit: amount - repairCost,
          ),
        );
      }
      // Chi phí linh kiện/dịch vụ nội bộ (service không qua đối tác, partnerId == null)
      // Đây là chi phí nhân công/linh kiện tự ghi trong đơn sửa, không trùng với repair_partner_payments
      final nonPartnerCost = repair.services
          .where((s) => s.partnerId == null)
          .fold<int>(0, (sum, s) => sum + s.cost);
      if (nonPartnerCost > 0) {
        expenseOut += nonPartnerCost;
        transactions.add(
          FinanceV2Txn(
            id: 'repair_cost_${repair.id ?? repair.firestoreId ?? repair.createdAt}',
            createdAt: repair.deliveredAt ?? repair.createdAt,
            type: 'EXPENSE',
            title: 'Giá vốn: ${repair.customerName}',
            subtitle:
                'Chi phí sửa ${repair.model.isNotEmpty ? repair.model : "thiết bị"}'
                '${repair.issue.isNotEmpty ? " · ${repair.issue}" : ""}',
            amount: nonPartnerCost,
            isIncome: false,
            avatarUrl: customerAvatarByName[_normalizeName(repair.customerName)],
            actorName: (repair.repairedBy ?? repair.createdBy ?? '').trim().isEmpty
                ? null
                : (repair.repairedBy ?? repair.createdBy ?? '').trim(),
            referenceId: repair.firestoreId ?? repair.id?.toString(),
          ),
        );
      }
    }

    for (final e in expenses) {
      final amount = _toInt(e['amount']);
      final type = (e['type'] ?? 'CHI').toString().toUpperCase();
      final ts = _toInt(e['date']) > 0 ? _toInt(e['date']) : _toInt(e['createdAt']);
      final title = (e['title'] ?? e['category'] ?? 'Giao dịch').toString();
      final isIncome = type == 'THU';
      if (isIncome) {
        extraIn += amount;
      } else {
        expenseOut += amount;
      }
      transactions.add(
        FinanceV2Txn(
          id: 'expense_${e['id'] ?? e['firestoreId'] ?? ts}',
          createdAt: ts,
          type: isIncome ? 'INCOME' : 'EXPENSE',
          title: title.isEmpty ? (isIncome ? 'Khoản thu' : 'Khoản chi') : title,
          subtitle:
              '${isIncome ? 'Thu phát sinh' : 'Chi phát sinh'}'
              '${(e['category'] ?? '').toString().trim().isNotEmpty ? ' · ${(e['category'] ?? '').toString().trim()}' : ''}'
              '${(e['paymentMethod'] ?? '').toString().trim().isNotEmpty ? ' · ${(e['paymentMethod'] ?? '').toString().trim()}' : ''}',
          amount: amount,
          isIncome: isIncome,
          actorName: (e['createdBy'] ?? '').toString().trim().isEmpty
              ? null
              : (e['createdBy'] ?? '').toString().trim(),
          paymentMethod: (e['paymentMethod'] ?? '').toString(),
          referenceId: (e['firestoreId'] ?? e['id'] ?? '').toString(),
        ),
      );
    }

    final expenseFirestoreIds = <String>{
      ...expenses.map(
        (e) => (e['firestoreId'] ?? '').toString().trim(),
      ).where((id) => id.isNotEmpty),
    };
    for (final p in repairPartnerPayments) {
      final paymentFid = (p['firestoreId'] ?? '').toString().trim();
      if (paymentFid.isEmpty) continue;

      final expectedExpenseFid = paymentFid.startsWith('rpp_')
          ? 'exp_partner_${paymentFid.substring(4)}'
          : 'exp_partner_$paymentFid';
      if (expenseFirestoreIds.contains(expectedExpenseFid)) {
        continue;
      }

      final amount = _toInt(p['amount']);
      if (amount <= 0) continue;
      final ts = _toInt(p['paidAt']);
      final partnerName = (p['partnerName'] ?? '').toString().trim();
      final method = (p['paymentMethod'] ?? '').toString().trim();

      expenseOut += amount;
      transactions.add(
        FinanceV2Txn(
          id: 'partner_payment_${p['id'] ?? paymentFid}',
          createdAt: ts,
          type: 'EXPENSE',
          title: partnerName.isEmpty ? 'Thanh toán đối tác sửa chữa' : partnerName,
          subtitle:
              'Chi đối tác sửa chữa${method.isNotEmpty ? ' · $method' : ''}',
          amount: amount,
          isIncome: false,
          paymentMethod: method,
          referenceId: paymentFid,
        ),
      );
    }

    for (final p in debtPayments) {
      final amount = _toInt(p['amount']);
      if (amount <= 0) continue;
      final resolvedType = (p['resolvedDebtType'] ?? p['debtType'] ?? 'CUSTOMER_OWES').toString();
      // SHOP_OWES / OTHER_SHOP_OWES / OWED = cửa hàng nợ → trả nợ = tiền ra
      final isShopOwes = resolvedType == 'SHOP_OWES' ||
          resolvedType == 'OTHER_SHOP_OWES' ||
          resolvedType == 'OWED';
      final isIncome = !isShopOwes; // Thu nợ từ khách = tiền vào
      final name = (p['debtPersonName'] ?? '').toString().trim();
      final ts = _toInt(p['paidAt']);
      final method = (p['paymentMethod'] ?? '').toString().trim();

      if (isIncome) {
        extraIn += amount;
      } else {
        expenseOut += amount;
        debtRepayOut += amount; // Ghi nhận riêng phần trả nợ NCC/đối tác
      }

      transactions.add(
        FinanceV2Txn(
          id: 'debtpay_${p['id'] ?? p['firestoreId'] ?? ts}',
          createdAt: ts,
          type: isIncome ? 'DEBT_COLLECT' : 'DEBT_PAY',
          title: name.isNotEmpty ? name : (isIncome ? 'Thu nợ' : 'Trả nợ'),
          subtitle: isIncome
              ? 'Thu nợ${method.isNotEmpty ? ' · $method' : ''}'
              : 'Trả nợ${method.isNotEmpty ? ' · $method' : ''}',
          amount: amount,
          isIncome: isIncome,
          paymentMethod: method,
          referenceId: (p['debtFirestoreId'] ?? p['firestoreId'] ?? '').toString(),
        ),
      );
    }

    int previousSaleIn = 0;
    int previousRepairIn = 0;
    int previousExtraIn = 0;
    int previousExpenseOut = 0;
    int previousSaleCogs = 0;
    int previousRepairCogs = 0;

    for (final SaleOrder sale in previousSales) {
      final bool isCongNo = sale.paymentMethod.toUpperCase() == 'CÔNG NỢ';
      final int actualPaid;
      if (sale.isInstallment) {
        actualPaid = sale.downPayment + sale.settlementAmount;
      } else if (isCongNo) {
        actualPaid = 0;
      } else {
        actualPaid = sale.finalPrice;
      }

      final int accrualRevenue = sale.finalPrice > 0 ? sale.finalPrice : 0;
      if (accrualRevenue > 0) {
        previousSaleCogs += sale.totalCost > 0 ? sale.totalCost : 0;
      }

      if (actualPaid > 0) {
        previousSaleIn += actualPaid;
      }
    }

    for (final Repair repair in previousRepairs) {
      if (repair.paymentMethod.toUpperCase() == 'CÔNG NỢ') {
        continue;
      }
      if (repair.price > 0) {
        previousRepairIn += repair.price;
        previousRepairCogs += repair.totalCost > 0 ? repair.totalCost : 0;
      }
      final prevNonPartnerCost = repair.services
          .where((s) => s.partnerId == null)
          .fold<int>(0, (sum, s) => sum + s.cost);
      if (prevNonPartnerCost > 0) {
        previousExpenseOut += prevNonPartnerCost;
      }
    }

    for (final e in previousExpenses) {
      final amount = _toInt(e['amount']);
      final type = (e['type'] ?? 'CHI').toString().toUpperCase();
      if (type == 'THU') {
        previousExtraIn += amount;
      } else {
        previousExpenseOut += amount;
      }
    }

    final previousExpenseFirestoreIds = <String>{
      ...previousExpenses.map(
        (e) => (e['firestoreId'] ?? '').toString().trim(),
      ).where((id) => id.isNotEmpty),
    };
    for (final p in previousRepairPartnerPayments) {
      final paymentFid = (p['firestoreId'] ?? '').toString().trim();
      if (paymentFid.isEmpty) continue;
      final expectedExpenseFid = paymentFid.startsWith('rpp_')
          ? 'exp_partner_${paymentFid.substring(4)}'
          : 'exp_partner_$paymentFid';
      if (previousExpenseFirestoreIds.contains(expectedExpenseFid)) {
        continue;
      }
      final amount = _toInt(p['amount']);
      if (amount > 0) {
        previousExpenseOut += amount;
      }
    }

    int receivableTotal = 0;
    int payableTotal = 0;
    final receivables = <FinanceV2DebtItem>[];
    final payables = <FinanceV2DebtItem>[];

    for (final d in debts) {
      final total = _toInt(d['totalAmount']);
      final paid = _toInt(d['paidAmount']);
      final remaining = total - paid;
      if (remaining <= 0) continue;

      final debtType = (d['type'] ?? 'CUSTOMER_OWES').toString();
      final isPayable = debtType == 'SHOP_OWES' ||
          debtType == 'OTHER_SHOP_OWES' ||
          debtType == 'OWED';

      final item = FinanceV2DebtItem(
        id: (d['firestoreId'] ?? d['id'] ?? debtType).toString(),
        type: debtType,
        name: (d['personName'] ?? d['partnerName'] ?? 'Không rõ').toString(),
        total: total,
        paid: paid,
        remaining: remaining,
        avatarUrl: isPayable
          ? (supplierAvatarByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())] ??
            partnerAvatarByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())])
          : customerAvatarByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())],
        createdAt: _toInt(d['createdAt']),
        phone: isPayable
          ? (supplierPhoneByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())] ??
            partnerPhoneByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())])
          : customerPhoneByName[_normalizeName((d['personName'] ?? d['partnerName']).toString())],
      );

      if (isPayable) {
        payableTotal += remaining;
        payables.add(item);
      } else {
        receivableTotal += remaining;
        receivables.add(item);
      }
    }

    transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final totalIn = saleIn + repairIn + extraIn;
    final totalOut = expenseOut;
    final operatingExpenseOut = expenseOut - debtRepayOut; // chi vận hành thuần (không tính trả nợ NCC)
    final netCashflow = totalIn - totalOut;
    final recognizedSalesRevenue = sales.fold<int>(
      0,
      (sum, sale) => sum + (sale.finalPrice > 0 ? sale.finalPrice : 0),
    );
    final grossProfitFromSales = recognizedSalesRevenue - saleCogs;
    final grossProfitFromRepairs = repairIn - repairCogs;
    final grossProfitTotal = grossProfitFromSales + grossProfitFromRepairs;
    final previousTotalIn = previousSaleIn + previousRepairIn + previousExtraIn;
    final previousTotalOut = previousExpenseOut;
    final previousNetCashflow = previousTotalIn - previousTotalOut;
    final previousRecognizedSalesRevenue = previousSales.fold<int>(
      0,
      (sum, sale) => sum + (sale.finalPrice > 0 ? sale.finalPrice : 0),
    );
    final previousGrossProfitFromSales =
        previousRecognizedSalesRevenue - previousSaleCogs;
    final previousGrossProfitFromRepairs = previousRepairIn - previousRepairCogs;
    final incomeTxCount = transactions.where((t) => t.isIncome).length;
    final avgIncomePerTransaction = incomeTxCount > 0 ? (totalIn ~/ incomeTxCount) : 0;

    final Map<String, int> expenseByCategory = {};
    for (final e in expenses) {
      final type = (e['type'] ?? 'CHI').toString().toUpperCase();
      if (type == 'THU') continue;
      final category = (e['category'] ?? 'Khác').toString().trim();
      final amount = _toInt(e['amount']);
      final key = category.isEmpty ? 'Khác' : category;
      expenseByCategory[key] = (expenseByCategory[key] ?? 0) + amount;
    }
    for (final p in repairPartnerPayments) {
      final paymentFid = (p['firestoreId'] ?? '').toString().trim();
      if (paymentFid.isEmpty) continue;
      final expectedExpenseFid = paymentFid.startsWith('rpp_')
          ? 'exp_partner_${paymentFid.substring(4)}'
          : 'exp_partner_$paymentFid';
      if (expenseFirestoreIds.contains(expectedExpenseFid)) {
        continue;
      }
      final amount = _toInt(p['amount']);
      if (amount <= 0) continue;
      expenseByCategory['Đối tác sửa chữa'] =
          (expenseByCategory['Đối tác sửa chữa'] ?? 0) + amount;
    }
    // Thêm chi phí linh kiện nội bộ (non-partner) vào category stats
    for (final Repair repair in repairs) {
      if (repair.paymentMethod.toUpperCase() == 'CÔNG NỢ') continue;
      final nonPartnerCost = repair.services
          .where((s) => s.partnerId == null)
          .fold<int>(0, (sum, s) => sum + s.cost);
      if (nonPartnerCost > 0) {
        expenseByCategory['Linh kiện sửa chữa'] =
            (expenseByCategory['Linh kiện sửa chữa'] ?? 0) + nonPartnerCost;
      }
    }
    final topExpenseCategories = expenseByCategory.entries
        .map((e) => FinanceV2CategoryStat(label: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final cards = <FinanceV2MetricCard>[
      FinanceV2MetricCard(
        label: 'Tiền vào',
        amount: totalIn,
        previousAmount: previousTotalIn,
      ),
      FinanceV2MetricCard(
        label: 'Tiền ra',
        amount: totalOut,
        previousAmount: previousTotalOut,
      ),
      FinanceV2MetricCard(
        label: 'Phải thu',
        amount: receivableTotal,
      ),
      FinanceV2MetricCard(
        label: 'Phải trả',
        amount: payableTotal,
      ),
      FinanceV2MetricCard(
        label: 'Dòng tiền ròng',
        amount: netCashflow,
        previousAmount: previousNetCashflow,
      ),
    ];

    final byDay = _buildBuckets(transactions, 'day');
    final byMonth = _buildBuckets(transactions, 'month');
    final byYear = _buildBuckets(transactions, 'year');

    // Calculate debt aging (khách nợ / phải thu only)
    final debtAging = <String, int>{'0-30': 0, '30-60': 0, '>60': 0};
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final d in debts) {
      final total = _toInt(d['totalAmount']);
      final paid = _toInt(d['paidAmount']);
      final remaining = total - paid;
      if (remaining <= 0) continue;

      final debtType = (d['type'] ?? 'CUSTOMER_OWES').toString();
      // Only count receivables (khách nợ), not payables
      if (debtType != 'CUSTOMER_OWES' && debtType != 'CUSTOMER_DEPOSIT') continue;

      final createdAt = _toInt(d['createdAt']);
      final daysSinceCreation = ((nowMs - createdAt) / (1000 * 60 * 60 * 24)).floor();

      if (daysSinceCreation <= 30) {
        debtAging['0-30'] = (debtAging['0-30'] ?? 0) + remaining;
      } else if (daysSinceCreation <= 60) {
        debtAging['30-60'] = (debtAging['30-60'] ?? 0) + remaining;
      } else {
        debtAging['>60'] = (debtAging['>60'] ?? 0) + remaining;
      }
    }

    return FinanceV2Snapshot(
      totalIn: totalIn,
      totalOut: totalOut,
      operatingExpenseOut: operatingExpenseOut,
      debtRepayOut: debtRepayOut,
      receivableTotal: receivableTotal,
      payableTotal: payableTotal,
      netCashflow: netCashflow,
      incomeFromSales: saleIn,
      incomeFromRepairs: repairIn,
      cogsFromSales: saleCogs,
      cogsFromRepairs: repairCogs,
      grossProfitFromSales: grossProfitFromSales,
      grossProfitFromRepairs: grossProfitFromRepairs,
      grossProfitTotal: grossProfitTotal,
      incomeOther: extraIn,
      transactionCount: transactions.length,
      avgIncomePerTransaction: avgIncomePerTransaction,
      previousTotalIn: previousTotalIn,
      previousTotalOut: previousTotalOut,
      previousNetCashflow: previousNetCashflow,
      previousCogsFromSales: previousSaleCogs,
      previousCogsFromRepairs: previousRepairCogs,
      previousGrossProfitFromSales: previousGrossProfitFromSales,
      previousGrossProfitFromRepairs: previousGrossProfitFromRepairs,
      dashboardCards: cards,
      topExpenseCategories: topExpenseCategories.take(4).toList(),
      transactions: transactions,
      receivables: receivables,
      payables: payables,
      byDay: byDay,
      byMonth: byMonth,
      byYear: byYear,
      auditLogs: activities,
      debtAging: debtAging,
    );
  }

  List<FinanceV2PeriodBucket> _buildBuckets(
    List<FinanceV2Txn> txns,
    String mode,
  ) {
    final bucketMap = <String, _BucketAcc>{};
    for (final tx in txns) {
      final dt = DateTime.fromMillisecondsSinceEpoch(tx.createdAt);
      late final String key;
      late final String label;
      if (mode == 'year') {
        key = '${dt.year}';
        label = '${dt.year}';
      } else if (mode == 'month') {
        final m = dt.month.toString().padLeft(2, '0');
        key = '${dt.year}-$m';
        label = '$m/${dt.year}';
      } else {
        final m = dt.month.toString().padLeft(2, '0');
        final d = dt.day.toString().padLeft(2, '0');
        key = '${dt.year}-$m-$d';
        label = '$d/$m';
      }
      final acc = bucketMap.putIfAbsent(key, () => _BucketAcc(label: label));
      if (tx.isIncome) {
        acc.totalIn += tx.amount;
      } else {
        acc.totalOut += tx.amount;
      }
      acc.txCount += 1;
    }

    final keys = bucketMap.keys.toList()..sort();
    return keys
        .map((k) {
          final acc = bucketMap[k]!;
          return FinanceV2PeriodBucket(
            key: k,
            label: acc.label,
            totalIn: acc.totalIn,
            totalOut: acc.totalOut,
            txCount: acc.txCount,
          );
        })
        .toList();
  }

  String _normalizeName(dynamic input) {
    final text = (input ?? '').toString().trim().toUpperCase();
    if (text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class _BucketAcc {
  final String label;
  int totalIn = 0;
  int totalOut = 0;
  int txCount = 0;

  _BucketAcc({required this.label});
}
