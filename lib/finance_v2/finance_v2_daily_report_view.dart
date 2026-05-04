import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import '../services/unified_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../models/attendance_model.dart';
import 'finance_v2_data_service.dart';
import 'finance_v2_theme.dart';
import 'finance_v2_excel_export.dart';
import '../services/label_settings_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../data/db_helper.dart';
import '../views/debt_view.dart';
import '../services/daily_financial_analysis_service.dart';

class FinanceV2DailyReportView extends StatefulWidget {
  final bool embeddedInTab;

  const FinanceV2DailyReportView({
    super.key,
    this.embeddedInTab = false,
  });

  @override
  State<FinanceV2DailyReportView> createState() =>
      _FinanceV2DailyReportViewState();
}

class _FinanceV2DailyReportViewState extends State<FinanceV2DailyReportView> {
  final FinanceV2DataService _service = FinanceV2DataService();
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _customRange;
  FinanceV2Snapshot? _snapshot;
  bool _loading = true;
  _ReportRangeMode _rangeMode = _ReportRangeMode.day;
  final DBHelper _db = DBHelper();
  Map<String, _StaffAttendanceStats> _attendanceByUser = <String, _StaffAttendanceStats>{};
  StreamSubscription<String>? _eventSub;

  final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _dFmt = DateFormat('dd/MM/yyyy');
  final _dayNameFmt = DateFormat('EEEE', 'vi_VN');

  Widget _panel({required Widget child, EdgeInsetsGeometry? margin}) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      decoration: FinanceV2Theme.elevatedPanel(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FinanceV2Theme.radiusPanel),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _eventSub = EventBus().stream.where((event) =>
      event == EventBus.shopChanged ||
      event == EventBus.financialChanged ||
      event == EventBus.syncComplete
    ).listen((_) {
      if (!mounted) return;
      _loadReport();
    });
    _loadReport();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final range = _resolveRange();
    final start = range.$1;
    final end = range.$2;
    
    try {
      final data = await _service.loadSnapshot(start: start, end: end);
      final attendance = await _loadAttendanceSummary(start: start, end: end);
      if (mounted) {
        setState(() {
          _snapshot = data;
          _attendanceByUser = attendance;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải báo cáo: $e')),
          );
        });
      }
    }
  }

  Future<void> _pickDate() async {
    if (_rangeMode == _ReportRangeMode.custom) {
      await _pickCustomRange();
      return;
    }

    DateTime? picked;
    if (_rangeMode == _ReportRangeMode.day) {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('vi', 'VN'),
      );
    } else if (_rangeMode == _ReportRangeMode.month) {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('vi', 'VN'),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        picked = DateTime(picked.year, picked.month, 1);
      }
    } else {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('vi', 'VN'),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        picked = DateTime(picked.year, 1, 1);
      }
    }
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked!);
      _loadReport();
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ?? DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day),
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
      locale: const Locale('vi', 'VN'),
      saveText: 'Áp dụng',
    );
    if (picked != null) {
      setState(() {
        _customRange = DateTimeRange(
          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
          end: DateTime(picked.end.year, picked.end.month, picked.end.day),
        );
      });
      _loadReport();
    }
  }

  void _goPreviousDay() {
    setState(() {
      if (_rangeMode == _ReportRangeMode.day) {
        _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      } else if (_rangeMode == _ReportRangeMode.month) {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
      } else if (_rangeMode == _ReportRangeMode.year) {
        _selectedDate = DateTime(_selectedDate.year - 1, 1, 1);
      } else {
        final range = _customRange;
        if (range != null) {
          final span = range.end.difference(range.start).inDays;
          final nextEnd = range.start.subtract(const Duration(days: 1));
          final nextStart = nextEnd.subtract(Duration(days: span));
          _customRange = DateTimeRange(start: nextStart, end: nextEnd);
        }
      }
    });
    _loadReport();
  }

  void _goNextDay() {
    final now = DateTime.now();
    if (_rangeMode == _ReportRangeMode.month) {
      final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      final currentMonth = DateTime(now.year, now.month, 1);
      if (!nextMonth.isAfter(currentMonth)) {
        setState(() => _selectedDate = nextMonth);
        _loadReport();
      }
      return;
    }

    if (_rangeMode == _ReportRangeMode.year) {
      final nextYear = DateTime(_selectedDate.year + 1, 1, 1);
      final currentYear = DateTime(now.year, 1, 1);
      if (!nextYear.isAfter(currentYear)) {
        setState(() => _selectedDate = nextYear);
        _loadReport();
      }
      return;
    }

    if (_rangeMode == _ReportRangeMode.custom) {
      final range = _customRange;
      if (range == null) return;
      final span = range.end.difference(range.start).inDays;
      final nextStart = range.end.add(const Duration(days: 1));
      final nextEnd = nextStart.add(Duration(days: span));
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      if (!nextEnd.isAfter(todayEnd)) {
        setState(() => _customRange = DateTimeRange(start: nextStart, end: nextEnd));
        _loadReport();
      }
      return;
    }

    final nowStart = DateTime(now.year, now.month, now.day);
    final nextDay = _selectedDate.add(const Duration(days: 1));
    final nextStart = DateTime(nextDay.year, nextDay.month, nextDay.day);
    if (nextStart.isBefore(nowStart) || nextStart == nowStart) {
      setState(() => _selectedDate = nextDay);
      _loadReport();
    }
  }

  bool get _isToday {
    if (_rangeMode == _ReportRangeMode.month) {
      final now = DateTime.now();
      return _selectedDate.year == now.year && _selectedDate.month == now.month;
    }
    if (_rangeMode == _ReportRangeMode.year) {
      final now = DateTime.now();
      return _selectedDate.year == now.year;
    }
    if (_rangeMode == _ReportRangeMode.custom) {
      final range = _customRange;
      if (range == null) return false;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return range.start == today && range.end == today;
    }
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  String get _rangeLabel {
    if (_rangeMode == _ReportRangeMode.month) {
      return DateFormat('MM/yyyy').format(_selectedDate);
    }
    if (_rangeMode == _ReportRangeMode.year) {
      return DateFormat('yyyy').format(_selectedDate);
    }
    if (_rangeMode == _ReportRangeMode.custom) {
      final range = _customRange;
      if (range == null) return 'Chưa chọn khoảng';
      return '${_dFmt.format(range.start)} - ${_dFmt.format(range.end)}';
    }
    return _dFmt.format(_selectedDate);
  }

  String get _periodSuffix {
    switch (_rangeMode) {
      case _ReportRangeMode.day:
        return 'ngày';
      case _ReportRangeMode.month:
        return 'tháng';
      case _ReportRangeMode.year:
        return 'năm';
      case _ReportRangeMode.custom:
        return 'khoảng thời gian';
    }
  }

  String get _periodShortLabel {
    switch (_rangeMode) {
      case _ReportRangeMode.day:
        return 'Theo ngày';
      case _ReportRangeMode.month:
        return 'Theo tháng';
      case _ReportRangeMode.year:
        return 'Theo năm';
      case _ReportRangeMode.custom:
        return 'Khoảng thời gian';
    }
  }

  String _rangeModeLabel(_ReportRangeMode mode) {
    switch (mode) {
      case _ReportRangeMode.day:
        return 'Theo ngày';
      case _ReportRangeMode.month:
        return 'Theo tháng';
      case _ReportRangeMode.year:
        return 'Theo năm';
      case _ReportRangeMode.custom:
        return 'Khoảng thời gian';
    }
  }

  Widget _rangeModeChip(_ReportRangeMode mode) {
    final selected = _rangeMode == mode;
    return ChoiceChip(
      label: Text(
        _rangeModeLabel(mode),
        style: FinanceV2Theme.meta.copyWith(
          color: selected ? Colors.white : FinanceV2Theme.subInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      onSelected: (_) {
        _changeRangeMode(mode);
      },
      showCheckmark: false,
      selectedColor: FinanceV2Theme.accent,
      backgroundColor: const Color(0xFFF3F6FB),
      side: BorderSide(
        color: selected ? FinanceV2Theme.accent : const Color(0xFFE3EAF6),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Future<void> _changeRangeMode(_ReportRangeMode mode) async {
    if (mode == _rangeMode) {
      if (mode == _ReportRangeMode.custom) {
        await _pickCustomRange();
      }
      return;
    }

    setState(() {
      _rangeMode = mode;
      if (mode == _ReportRangeMode.month) {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
      } else if (mode == _ReportRangeMode.year) {
        _selectedDate = DateTime(_selectedDate.year, 1, 1);
      } else if (mode == _ReportRangeMode.custom) {
        final normalized = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        _customRange ??= DateTimeRange(start: normalized, end: normalized);
      }
    });

    if (mode == _ReportRangeMode.custom) {
      await _pickCustomRange();
      return;
    }
    _loadReport();
  }

  (DateTime, DateTime) _resolveRange() {
    if (_rangeMode == _ReportRangeMode.month) {
      return (
        DateTime(_selectedDate.year, _selectedDate.month, 1),
        DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59),
      );
    }
    if (_rangeMode == _ReportRangeMode.year) {
      return (
        DateTime(_selectedDate.year, 1, 1),
        DateTime(_selectedDate.year, 12, 31, 23, 59, 59),
      );
    }
    if (_rangeMode == _ReportRangeMode.custom) {
      final now = DateTime.now();
      final range = _customRange ?? DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day),
      );
      return (
        DateTime(range.start.year, range.start.month, range.start.day),
        DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
      );
    }

    return (
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59),
    );
  }

  Future<Map<String, _StaffAttendanceStats>> _loadAttendanceSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) return <String, _StaffAttendanceStats>{};

      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .get();

      final users = usersSnap.docs
          .where((d) => (d.data()['email'] ?? '').toString().toLowerCase() != 'admin@huluca.com')
          .map((d) {
            final data = d.data();
            final name = (data['name'] ?? '').toString().trim();
            final email = (data['email'] ?? '').toString().trim();
            return (
              id: d.id,
              name: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Nhân viên'),
            );
          })
          .toList();

      final startKey = DateFormat('yyyy-MM-dd').format(start);
      final endKey = DateFormat('yyyy-MM-dd').format(end);
      final records = await _db.getAttendanceByDateRange(startKey, endKey);

      final map = <String, _StaffAttendanceStats>{};
      for (final u in users) {
        map[u.id] = _StaffAttendanceStats(name: u.name);
      }

      final byUser = <String, List<Attendance>>{};
      for (final r in records) {
        byUser.putIfAbsent(r.userId, () => <Attendance>[]).add(r);
      }

      final totalDays = end.difference(start).inDays + 1;
      for (final u in users) {
        final stats = map[u.id]!;
        final recs = byUser[u.id] ?? const <Attendance>[];
        final dateKeys = <String>{};
        for (final r in recs) {
          if (r.checkInAt != null) {
            stats.presentDays += 1;
            if (r.isLate == 1) stats.lateDays += 1;
            dateKeys.add(r.dateKey);
          }
        }
        stats.absentDays = (totalDays - dateKeys.length).clamp(0, totalDays);
      }

      try {
        final swapSnap = await FirebaseFirestore.instance
            .collection('shift_swap_requests')
            .where('shopId', isEqualTo: shopId)
            .where('status', isEqualTo: 'approved')
            .where('deleted', isEqualTo: false)
            .where('requestedDate', isGreaterThanOrEqualTo: startKey)
            .where('requestedDate', isLessThanOrEqualTo: endKey)
            .get();

        for (final doc in swapSnap.docs) {
          final data = doc.data();
          final requesterId = (data['requesterId'] ?? '').toString();
          final targetUserId = (data['targetUserId'] ?? '').toString();
          if (requesterId.isNotEmpty && map.containsKey(requesterId)) {
            map[requesterId]!.swapCount += 1;
          }
          if (targetUserId.isNotEmpty && map.containsKey(targetUserId)) {
            map[targetUserId]!.swapCount += 1;
          }
        }
      } catch (_) {
        // Ignore shift swap query/index errors; attendance summary still usable.
      }

      return map;
    } catch (_) {
      return <String, _StaffAttendanceStats>{};
    }
  }

  Future<void> _openDebtFlow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DebtView()),
    );
    if (!mounted) return;
    _loadReport();
  }

  Future<void> _exportReport() async {
    final range = _resolveRange();
    final start = range.$1;
    final end = range.$2;

    // Always refresh snapshot before export to avoid stale data after shop switch.
    final s = await _service.loadSnapshot(start: start, end: end);
    final attendance = await _loadAttendanceSummary(start: start, end: end);
    if (mounted) {
      setState(() {
        _snapshot = s;
        _attendanceByUser = attendance;
      });
    }

    final shopInfo = await LabelSettingsService().getShopLabelSettings();
    final shopId = await UserService.getCurrentShopId();
    final generatedAt = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
    final analysis = await _buildAuditAnalysis(start, end);
    final inventory = await _buildInventoryAudit(start, end, s, analysis);

    final totalRevenue = s.incomeFromSales + s.incomeFromRepairs + s.incomeOther;
    final totalCost = s.cogsFromSales + s.cogsFromRepairs + s.operatingExpenseOut;
    final totalProfit = totalRevenue - totalCost;

    final summaryRows = <List<dynamic>>[
      ['generated_at', generatedAt, 'Thời điểm xuất file'],
      ['shop_name', shopInfo.shopName.isNotEmpty ? shopInfo.shopName : 'N/A', 'Tên cửa hàng'],
      ['shop_id', (shopId == null || shopId.isEmpty) ? 'N/A' : shopId, 'Mã cửa hàng'],
      ['period_label', _rangeLabel, 'Kỳ báo cáo'],
      ['total_revenue', totalRevenue, 'Doanh thu thuần = bán hàng + sửa chữa + thu khác'],
      ['total_cost', totalCost, 'Tổng giá vốn + chi phí vận hành'],
      ['total_profit', totalProfit, 'Lợi nhuận = total_revenue - total_cost'],
      ['cash_in', analysis.cashIn, 'Tiền mặt vào'],
      ['cash_out', analysis.cashOut, 'Tiền mặt ra'],
      ['net_cash', analysis.cashIn - analysis.cashOut, 'Dòng tiền mặt ròng'],
      ['transfer_in', analysis.bankIn, 'Chuyển khoản vào'],
      ['transfer_out', analysis.bankOut, 'Chuyển khoản ra'],
      ['net_total_flow', s.netCashflow, 'Dòng tiền ròng toàn hệ thống'],
      ['debt_customer_total', s.receivableTotal, 'Tổng phải thu khách hàng cuối kỳ'],
      ['debt_supplier_total', s.payableTotal, 'Tổng phải trả nhà cung cấp cuối kỳ'],
      ['inventory_open', inventory['open'], 'Tồn kho đầu kỳ ước tính = cuối kỳ - biến động'],
      ['inventory_change', inventory['change'], 'Biến động tồn kho trong kỳ'],
      ['inventory_close', inventory['close'], 'Tồn kho cuối kỳ tại thời điểm xuất'],
      ['transactions_count', s.transactionCount, 'Số giao dịch dùng để tổng hợp'],
    ];

    final cashflowRows = <List<dynamic>>[
      ['sale_income', analysis.saleIncome],
      ['settlement_income', analysis.settlementIncome],
      ['repair_income', analysis.repairIncome],
      ['debt_collected', analysis.debtCollected],
      ['misc_income', analysis.miscIncome],
      ['expense_out', analysis.expenseOut],
      ['import_out', analysis.importOut],
      ['supplier_paid', analysis.supplierPaid],
      ['partner_paid', analysis.partnerPaid],
      ['repair_parts_cost_fund', analysis.repairPartsCostFund],
      ['refund_out', analysis.refundOut],
      ['return_cost', analysis.returnCost],
    ];

    final debtRows = <List<dynamic>>[
      ...s.receivables.map((d) => <dynamic>['customer_receivable', d.id, d.name, d.phone ?? '', d.total, d.paid, d.remaining, FinanceV2ExcelExport.fmtDate(d.createdAt)]),
      ...s.payables.map((d) => <dynamic>['supplier_payable', d.id, d.name, d.phone ?? '', d.total, d.paid, d.remaining, FinanceV2ExcelExport.fmtDate(d.createdAt)]),
    ];

    final inventoryRows = <List<dynamic>>[
      ['inventory_import_value', inventory['imports']],
      ['inventory_return_in_value', inventory['returns']],
      ['inventory_sale_out_value', inventory['salesOut']],
      ['inventory_repair_out_value', inventory['repairsOut']],
      ['inventory_salvage_in_value', inventory['salvageIn']],
      ['inventory_close_products', inventory['productsClose']],
      ['inventory_close_repair_parts', inventory['repairPartsClose']],
      ['inventory_close_salvage', inventory['salvageClose']],
      ['inventory_formula', 'open + imports + returns + salvage - salesOut - repairsOut = close'],
    ];

    final breakdownRows = <List<dynamic>>[
      ...s.topExpenseCategories.map((c) => <dynamic>['expense_category', c.label, c.amount]),
      ...s.transactions.map((tx) => <dynamic>[
            FinanceV2ExcelExport.fmtDateTime(tx.createdAt),
            tx.type,
            tx.isIncome ? 'IN' : 'OUT',
            tx.amount,
            tx.costAmount ?? 0,
            tx.grossProfit ?? 0,
            tx.paymentMethod ?? '',
            tx.referenceId ?? '',
            tx.title,
            tx.subtitle,
          ]),
    ];

    if (!mounted) return;
    await FinanceV2ExcelExport.exportWorkbook(
      context,
      filePrefix: 'BaoCaoNgay_Audit',
      sheets: <FinanceV2ExcelSheet>[
        FinanceV2ExcelSheet(
          sheetName: 'summary',
          headers: const ['metric', 'value', 'note'],
          rows: summaryRows,
        ),
        FinanceV2ExcelSheet(
          sheetName: 'cashflow',
          headers: const ['metric', 'value'],
          rows: cashflowRows,
        ),
        FinanceV2ExcelSheet(
          sheetName: 'debts',
          headers: const ['debt_type', 'reference_id', 'name', 'phone', 'total_amount', 'paid_amount', 'remaining_amount', 'created_date'],
          rows: debtRows,
        ),
        FinanceV2ExcelSheet(
          sheetName: 'inventory',
          headers: const ['metric', 'value'],
          rows: inventoryRows,
        ),
        FinanceV2ExcelSheet(
          sheetName: 'breakdown',
          headers: const ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10'],
          rows: breakdownRows,
        ),
      ],
      start: start,
      end: end,
    );
  }

  Future<DailyFinancialAnalysis> _buildAuditAnalysis(DateTime start, DateTime end) async {
    final startMs = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59).millisecondsSinceEpoch;
    final sales = await _db.getSalesByDateRange(startMs, endMs);
    final settlementSales = sales
        .where((sale) => sale.isInstallment && sale.settlementReceivedAt != null && sale.settlementReceivedAt! >= startMs && sale.settlementReceivedAt! <= endMs)
        .map((sale) => sale.toMap())
        .toList();
    final repairs = (await _db.getDeliveredRepairsByDateRange(startMs, endMs)).map((r) => r.toMap()).toList();
    final expenses = await _db.getExpensesByDateRange(startMs, endMs);
    final debtPayments = await _db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs);
    final supplierPayments = await _db.getSupplierPaymentsByDateRange(startMs, endMs);
    final repairPartnerPayments = await _db.getRepairPartnerPaymentsByDateRange(startMs, endMs);
    final supplierImports = await _db.getAllImportHistoryByDateRange(startMs, endMs);
    final salesReturns = await _db.getSalesReturnsByDateRange(startMs, endMs);
    final repairPartsCostFundRows = (await _db.getDeliveredRepairsByDateRange(startMs, endMs))
        .where((repair) => repair.costRecordedInFund && repair.costRecordedAt != null && repair.costRecordedAt! >= startMs && repair.costRecordedAt! <= endMs)
        .map((repair) => <String, dynamic>{
              'costRecordedAmount': repair.costRecordedAmount,
              'totalCost': repair.totalCost,
              'costPaymentMethod': repair.costPaymentMethod,
            })
        .toList();

    return DailyFinancialAnalysisService.analyze(
      sales: sales.map((e) => e.toMap()).toList(),
      settlementSales: settlementSales,
      repairs: repairs,
      expenses: expenses,
      debtPayments: debtPayments,
      supplierPayments: supplierPayments,
      repairPartnerPayments: repairPartnerPayments,
      supplierImports: supplierImports,
      repairPartsCostFundRows: repairPartsCostFundRows,
      salesReturns: salesReturns,
      enableRepair: true,
    );
  }

  Future<Map<String, int>> _buildInventoryAudit(
    DateTime start,
    DateTime end,
    FinanceV2Snapshot snapshot,
    DailyFinancialAnalysis analysis,
  ) async {
    final startMs = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59).millisecondsSinceEpoch;
    final products = await _db.getInStockProducts();
    final repairParts = await _db.getRepairPartsAsProducts();
    final salvage = await _db.getAllSalvagePhones();
    final imports = await _db.getAllImportHistoryByDateRange(startMs, endMs);
    final returns = await _db.getSalesReturnsByDateRange(startMs, endMs);

    final productsClose = products.fold<int>(0, (total, p) => total + (p.cost * p.quantity));
    final repairPartsClose = repairParts.fold<int>(0, (total, p) => total + (p.cost * p.quantity));
    final salvageClose = salvage
        .where((e) => (e['status'] ?? 'STORED').toString().toUpperCase() == 'STORED')
      .fold<int>(0, (total, e) => total + ((e['cost'] as num?)?.toInt() ?? 0));

    final importValue = imports.fold<int>(0, (total, e) => total + ((e['totalAmount'] as num?)?.toInt() ?? 0));
    final returnValue = returns.fold<int>(0, (total, e) => total + ((e['totalReturnCost'] as num?)?.toInt() ?? 0));
    final salvageIn = salvage
        .where((e) {
          final createdAt = (e['createdAt'] as num?)?.toInt() ?? 0;
          return createdAt >= startMs && createdAt <= endMs;
        })
      .fold<int>(0, (total, e) => total + ((e['cost'] as num?)?.toInt() ?? 0));

    final repairInventoryOut = analysis.repairPartsCostFund > 0 ? analysis.repairPartsCostFund : snapshot.cogsFromRepairs;
    final change = importValue + returnValue + salvageIn - snapshot.cogsFromSales - repairInventoryOut;
    final close = productsClose + repairPartsClose + salvageClose;
    final open = close - change;

    return <String, int>{
      'open': open,
      'change': change,
      'close': close,
      'imports': importValue,
      'returns': returnValue,
      'salesOut': snapshot.cogsFromSales,
      'repairsOut': repairInventoryOut,
      'salvageIn': salvageIn,
      'productsClose': productsClose,
      'repairPartsClose': repairPartsClose,
      'salvageClose': salvageClose,
    };
  }

  Future<void> _printReport() async {
    if (_snapshot == null) return;

    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return;
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;

    final s = _snapshot!;
    final lines = StringBuffer();

    // Header: shop info
    final shopInfo = await LabelSettingsService().getShopLabelSettings();
    if (shopInfo.shopName.isNotEmpty) {
      lines.writeln('[C][B]${shopInfo.shopName}');
    }
    if (shopInfo.address.isNotEmpty) {
      lines.writeln('[C]${shopInfo.address}');
    }
    if (shopInfo.hotline.isNotEmpty) {
      lines.writeln('[C]SDT: ${shopInfo.hotline}');
    }
    lines.writeln('');
    lines.writeln('[C][B]BAO CAO ${_periodSuffix.toUpperCase()}');
    lines.writeln('[C]$_rangeLabel');
    lines.writeln('[C]================================');
    lines.writeln('');

    // Tổng quan
    lines.writeln('[C][B]--- TONG QUAN ---');
    lines.writeln('Doanh thu:  ${MoneyUtils.formatCompactCurrency(s.totalIn)}d');
    lines.writeln('Chi phi:    ${MoneyUtils.formatCompactCurrency(s.totalOut)}d');
    lines.writeln('Rong so quy:  ${MoneyUtils.formatCompactCurrency(s.netCashflow)}d');
    lines.writeln('Loi nhuan thuc:  ${MoneyUtils.formatCompactCurrency(s.grossProfitTotal - s.operatingExpenseOut)}d');
    lines.writeln('Giao dich:  ${s.transactionCount}');
    lines.writeln('');

    // Chi tiết doanh thu theo nhóm
    lines.writeln('[C][B]--- DOANH THU CHI TIET ---');
    if (s.incomeFromSales > 0) {
      lines.writeln('Ban hang:   +${MoneyUtils.formatCompactCurrency(s.incomeFromSales)}d');
    }
    if (s.incomeFromRepairs > 0) {
      lines.writeln('Sua chua:   +${MoneyUtils.formatCompactCurrency(s.incomeFromRepairs)}d');
    }
    // Thu nợ (DEBT_COLLECT)
    final debtCollectTxs = s.transactions.where((t) => t.type.toUpperCase() == 'DEBT_COLLECT');
    final totalDebtCollect = debtCollectTxs.fold(0, (acc, t) => acc + t.amount);
    if (totalDebtCollect > 0) {
      lines.writeln('Thu no:     +${MoneyUtils.formatCompactCurrency(totalDebtCollect)}d');
    }
    if (s.incomeOther > 0) {
      lines.writeln('Thu khac:   +${MoneyUtils.formatCompactCurrency(s.incomeOther)}d');
    }
    lines.writeln('');

    // Chi tiết giao dịch bán hàng
    final saleTxs = s.transactions.where((t) => t.type.toUpperCase() == 'SALE').toList();
    if (saleTxs.isNotEmpty) {
      lines.writeln('[C][B]--- BAN HANG (${saleTxs.length}) ---');
      for (final tx in saleTxs.take(15)) {
        final time = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt));
        final name = tx.title.trim().isEmpty ? 'Khach le' : tx.title.trim();
        lines.writeln('  $time $name: ${MoneyUtils.formatCompactCurrency(tx.amount)}d');
        if (tx.subtitle.isNotEmpty) {
          lines.writeln('    ${tx.subtitle}');
        }
      }
      if (saleTxs.length > 15) {
        lines.writeln('  ...+${saleTxs.length - 15} don khac');
      }
      lines.writeln('');
    }

    // Chi tiết giao dịch sửa chữa
    final repairTxs = s.transactions.where((t) => t.type.toUpperCase() == 'REPAIR').toList();
    if (repairTxs.isNotEmpty) {
      lines.writeln('[C][B]--- SUA CHUA DA GIAO (${repairTxs.length}) ---');
      for (final tx in repairTxs.take(15)) {
        final time = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt));
        final name = tx.title.trim().isEmpty ? 'Khach' : tx.title.trim();
        lines.writeln('  $time $name: ${MoneyUtils.formatCompactCurrency(tx.amount)}d');
        if (tx.subtitle.isNotEmpty) {
          lines.writeln('    ${tx.subtitle}');
        }
      }
      if (repairTxs.length > 15) {
        lines.writeln('  ...+${repairTxs.length - 15} don khac');
      }
      lines.writeln('');
    }

    // Chi phí
    final expenseTxs = s.transactions.where((t) => t.type.toUpperCase() == 'EXPENSE').toList();
    if (expenseTxs.isNotEmpty) {
      final totalExp = expenseTxs.fold(0, (acc, t) => acc + t.amount);
      lines.writeln('[C][B]--- CHI PHI (${expenseTxs.length}) ---');
      lines.writeln('Tong chi: ${MoneyUtils.formatCompactCurrency(totalExp)}d');
      for (final tx in expenseTxs.take(10)) {
        final time = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt));
        final name = tx.title.trim().isEmpty ? 'Chi phi' : tx.title.trim();
        lines.writeln('  $time $name: ${MoneyUtils.formatCompactCurrency(tx.amount)}d');
        if (tx.subtitle.isNotEmpty) {
          lines.writeln('    ${tx.subtitle}');
        }
      }
      lines.writeln('');
    }

    // Top danh mục chi phí
    if (s.topExpenseCategories.isNotEmpty) {
      lines.writeln('[C][B]--- TOP DANH MUC CHI ---');
      for (final c in s.topExpenseCategories.take(5)) {
        lines.writeln('  ${c.label}: ${MoneyUtils.formatCompactCurrency(c.amount)}d');
      }
      lines.writeln('');
    }

    // Trả nợ
    final debtPayTxs = s.transactions.where((t) => t.type.toUpperCase() == 'DEBT_PAY').toList();
    if (debtPayTxs.isNotEmpty || debtCollectTxs.isNotEmpty) {
      lines.writeln('[C][B]--- CONG NO TRONG KY ---');
      if (totalDebtCollect > 0) {
        lines.writeln('Thu no KH: +${MoneyUtils.formatCompactCurrency(totalDebtCollect)}d (${debtCollectTxs.length})');
        for (final tx in debtCollectTxs.take(5)) {
          final name = tx.title.trim().isEmpty ? 'KH' : tx.title.trim();
          lines.writeln('  $name: ${MoneyUtils.formatCompactCurrency(tx.amount)}d');
        }
      }
      final totalDebtPay = debtPayTxs.fold(0, (acc, t) => acc + t.amount);
      if (totalDebtPay > 0) {
        lines.writeln('Tra no NCC: -${MoneyUtils.formatCompactCurrency(totalDebtPay)}d (${debtPayTxs.length})');
        for (final tx in debtPayTxs.take(5)) {
          final name = tx.title.trim().isEmpty ? 'NCC' : tx.title.trim();
          lines.writeln('  $name: ${MoneyUtils.formatCompactCurrency(tx.amount)}d');
        }
      }
      lines.writeln('');
    }

    // Công nợ tồn
    if (s.receivables.isNotEmpty || s.payables.isNotEmpty) {
      lines.writeln('[C][B]--- DU NO CON LAI ---');
      lines.writeln('Phai thu: ${s.receivables.length} khoan - ${MoneyUtils.formatCompactCurrency(s.receivableTotal)}d');
      for (final d in s.receivables.take(5)) {
        lines.writeln('  ${d.name}: ${MoneyUtils.formatCompactCurrency(d.remaining)}d');
      }
      lines.writeln('Phai tra: ${s.payables.length} khoan - ${MoneyUtils.formatCompactCurrency(s.payableTotal)}d');
      for (final d in s.payables.take(5)) {
        lines.writeln('  ${d.name}: ${MoneyUtils.formatCompactCurrency(d.remaining)}d');
      }
      lines.writeln('');
    }

    // Luồng tiền cuối
    // Lãi gộp / vốn
    if (s.grossProfitTotal != 0 || s.cogsFromSales != 0 || s.cogsFromRepairs != 0) {
      lines.writeln('[C][B]--- VON & LAI GOT ---');
      if (s.cogsFromSales > 0) {
        lines.writeln('Von ban hang: ${MoneyUtils.formatCompactCurrency(s.cogsFromSales)}d');
      }
      if (s.cogsFromRepairs > 0) {
        lines.writeln('Von sua chua: ${MoneyUtils.formatCompactCurrency(s.cogsFromRepairs)}d');
      }
      lines.writeln('Tong von:     ${MoneyUtils.formatCompactCurrency(s.cogsFromSales + s.cogsFromRepairs)}d');
      if (s.grossProfitFromSales != 0) {
        lines.writeln('Lai ban hang: ${MoneyUtils.formatCompactCurrency(s.grossProfitFromSales)}d');
      }
      if (s.grossProfitFromRepairs != 0) {
        lines.writeln('Lai sua chua: ${MoneyUtils.formatCompactCurrency(s.grossProfitFromRepairs)}d');
      }
      lines.writeln('Tong lai got: ${MoneyUtils.formatCompactCurrency(s.grossProfitTotal)}d');
      lines.writeln('');
    }

    // Nhân sự chấm công
    if (_attendanceByUser.isNotEmpty) {
      lines.writeln('[C][B]--- NHAN SU - CHAM CONG ---');
      final staffList = _attendanceByUser.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final st in staffList) {
        lines.writeln('${st.name}:');
        lines.writeln('  Co mat:${st.presentDays}  Vang:${st.absentDays}  Tre:${st.lateDays}  DoiCa:${st.swapCount}');
      }
      lines.writeln('');
    }

    lines.writeln('[C]================================');
    lines.writeln('[C][B]RONG SO QUY: ${MoneyUtils.formatCompactCurrency(s.netCashflow)}d');
    lines.writeln('[C][B]LOI NHUAN THUC: ${MoneyUtils.formatCompactCurrency(s.grossProfitTotal - s.operatingExpenseOut)}d');
    lines.writeln('[C]================================');
    lines.writeln('');
    lines.writeln('[C]In luc ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}');

    final ok = await UnifiedPrinterService.printTextReceipt(
      lines.toString(),
      paper: PaperSize.mm58,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Đã gửi lệnh in báo cáo ngày' : 'Không thể in, vui lòng kiểm tra máy in'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Excel chi tiết — "Chi Tiết Ngày" sheet với 10 section
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _exportDetailedReport() async {
    if (_snapshot == null) return;
    final range = _resolveRange();
    final start = range.$1;
    final end = range.$2;
    final startMs = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59).millisecondsSinceEpoch;

    final s = _snapshot!;
    final analysis = await _buildAuditAnalysis(start, end);

    // Load raw data
    final sales = await _db.getSalesByDateRange(startMs, endMs);
    final repairs = await _db.getDeliveredRepairsByDateRange(startMs, endMs);
    final imports = await _db.getAllImportHistoryByDateRange(startMs, endMs);
    final expenses = await _db.getExpensesByDateRange(startMs, endMs);
    final debtsInRange = await _db.getDebtsByDateRange(startMs, endMs);

    // Helper: format ms to HH:mm
    String hm(int ms) => ms > 0
        ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms))
        : '';

    // Format number with commas
    String fmtN(num v) => NumberFormat('#,###', 'vi_VN').format(v);

    // ── Section 1: Tổng quan dòng tiền ──────────────────────────────
    final sec1 = FinanceV2DetailedDailySection(
      title: '1. Tổng quan dòng tiền',
      colHeaders: const ['Loại', 'Tiền mặt', 'Chuyển khoản', 'Tổng'],
      rows: [
        ['Thu vào', fmtN(analysis.cashIn), fmtN(analysis.bankIn), fmtN(s.totalIn)],
        ['Chi ra', fmtN(analysis.cashOut), fmtN(analysis.bankOut), fmtN(s.totalOut)],
        ['Ròng sổ quỹ', '', '', fmtN(s.netCashflow)],
      ],
    );

    // ── Section 2: Cơ cấu thu chi ─────────────────────────────────
    final totalIn = s.totalIn > 0 ? s.totalIn : 1;
    final totalOut = s.totalOut > 0 ? s.totalOut : 1;

    // Tính debt collect từ transactions
    final debtCollected = s.transactions
        .where((t) => t.type.toUpperCase() == 'DEBT_COLLECT')
        .fold<int>(0, (acc, t) => acc + t.amount);
    final settlement = analysis.settlementIncome;
    final miscIncome = s.incomeOther;

    final sec2 = FinanceV2DetailedDailySection(
      title: '2. Cơ cấu thu chi',
      colHeaders: const ['Loại', 'Số tiền', '% tổng'],
      rows: [
        ['THU — Bán hàng', fmtN(s.incomeFromSales), '${((s.incomeFromSales / totalIn) * 100).toStringAsFixed(1)}%'],
        ['THU — Sửa chữa', fmtN(s.incomeFromRepairs), '${((s.incomeFromRepairs / totalIn) * 100).toStringAsFixed(1)}%'],
        ['THU — Tất toán NH', fmtN(settlement), '${((settlement / totalIn) * 100).toStringAsFixed(1)}%'],
        ['THU — Thu nợ KH', fmtN(debtCollected), '${((debtCollected / totalIn) * 100).toStringAsFixed(1)}%'],
        ['THU — Thu khác', fmtN(miscIncome), '${((miscIncome / totalIn) * 100).toStringAsFixed(1)}%'],
        ['CHI — Nhập hàng', fmtN(analysis.importOut), '${((analysis.importOut / totalOut) * 100).toStringAsFixed(1)}%'],
        ['CHI — Trả nợ NCC', fmtN(analysis.supplierPaid), '${((analysis.supplierPaid / totalOut) * 100).toStringAsFixed(1)}%'],
        ['CHI — Chi phí', fmtN(analysis.expenseOut), '${((analysis.expenseOut / totalOut) * 100).toStringAsFixed(1)}%'],
        ['CHI — TT đối tác', fmtN(analysis.partnerPaid), '${((analysis.partnerPaid / totalOut) * 100).toStringAsFixed(1)}%'],

      ],
    );

    // ── Section 3: Danh sách đơn bán hàng ────────────────────────
    final sec3Rows = <List<dynamic>>[];
    for (int i = 0; i < sales.length; i++) {
      final sale = sales[i];
      final profit = sale.finalPrice - sale.totalCost;
      sec3Rows.add([
        i + 1,
        hm(sale.soldAt),
        sale.isWalkIn ? (sale.walkInName ?? 'Khách lẻ') : sale.customerName,
        sale.productNamesDisplay,
        sale.productImeis,
        '', // SL — không có field riêng, có thể để trống
        fmtN(sale.finalPrice),
        fmtN(sale.totalCost),
        fmtN(profit),
        sale.paymentMethod,
        'Hoàn thành',
      ]);
    }
    final sec3 = FinanceV2DetailedDailySection(
      title: '3. Danh sách đơn bán hàng (${sales.length})',
      colHeaders: const ['STT', 'Giờ', 'Khách hàng', 'Sản phẩm', 'IMEI', 'SL', 'Giá bán', 'Giá vốn', 'Lãi', 'Hình thức TT', 'Trạng thái'],
      rows: sec3Rows,
    );

    // ── Section 4: Danh sách đơn sửa chữa ───────────────────────
    final sec4Rows = <List<dynamic>>[];
    for (int i = 0; i < repairs.length; i++) {
      final r = repairs[i];
      final partnerCost = r.services.fold<int>(0, (acc, sv) => acc + sv.cost);
      final profit = r.price - r.cost - partnerCost;
      sec4Rows.add([
        i + 1,
        hm(r.deliveredAt ?? r.createdAt),
        r.isWalkIn ? (r.walkInName ?? 'Khách lẻ') : r.customerName,
        r.model,
        r.issue,
        r.services.map((sv) => sv.serviceName).join(', '),
        fmtN(r.price),
        fmtN(r.cost),
        fmtN(partnerCost),
        fmtN(profit),
        r.paymentMethod,
        r.repairedBy ?? '',
      ]);
    }
    final sec4 = FinanceV2DetailedDailySection(
      title: '4. Danh sách đơn sửa chữa (${repairs.length})',
      colHeaders: const ['STT', 'Giờ', 'Khách hàng', 'Model', 'Lỗi', 'Dịch vụ', 'Giá sửa', 'CP LK', 'Chi đối tác', 'Lãi', 'Hình thức TT', 'KTV'],
      rows: sec4Rows,
    );

    // ── Section 5: Danh sách nhập kho ────────────────────────────
    final sec5Rows = <List<dynamic>>[];
    for (int i = 0; i < imports.length; i++) {
      final imp = imports[i];
      sec5Rows.add([
        i + 1,
        hm((imp['importDate'] as num?)?.toInt() ?? 0),
        imp['productName'] ?? '',
        imp['supplierName'] ?? '',
        imp['quantity'] ?? 0,
        fmtN((imp['costPrice'] as num?)?.toInt() ?? 0),
        imp['paymentMethod'] ?? '',
      ]);
    }
    final sec5 = FinanceV2DetailedDailySection(
      title: '5. Danh sách nhập kho (${imports.length})',
      colHeaders: const ['STT', 'Giờ', 'Sản phẩm', 'NCC', 'Số lượng', 'Giá nhập', 'Hình thức TT'],
      rows: sec5Rows,
    );

    // ── Section 6: Thu chi khác ───────────────────────────────────
    final sec6Rows = <List<dynamic>>[];
    int idx6 = 0;
    // Expense transactions
    for (final exp in expenses) {
      final isIncome = (exp['type']?.toString().toUpperCase() ?? 'CHI') == 'THU';
      final ts = (exp['date'] as num?)?.toInt() ?? (exp['createdAt'] as num?)?.toInt() ?? 0;
      sec6Rows.add([
        ++idx6,
        hm(ts),
        isIncome ? 'Thu' : 'Chi',
        exp['title'] ?? '',
        fmtN((exp['amount'] as num?)?.toInt() ?? 0),
        exp['paymentMethod'] ?? '',
      ]);
    }
    final sec6 = FinanceV2DetailedDailySection(
      title: '6. Thu chi khác (${sec6Rows.length})',
      colHeaders: const ['STT', 'Giờ', 'Loại', 'Diễn giải', 'Số tiền', 'Hình thức TT'],
      rows: sec6Rows,
    );

    // ── Section 7: Công nợ khách hàng ────────────────────────────
    // Phát sinh trong ngày từ debtsInRange (type customer/sale debt)
    final customerDebtsToday = debtsInRange
        .where((d) => (d['debtType']?.toString().toUpperCase() ?? '') != 'SUPPLIER' &&
            (d['type']?.toString().toUpperCase() ?? '') != 'SUPPLIER')
        .toList();
    final sec7Rows = <List<dynamic>>[];
    int idx7 = 0;
    for (final d in customerDebtsToday) {
      final total = (d['totalAmount'] as num?)?.toInt() ?? 0;
      final paid = (d['paidAmount'] as num?)?.toInt() ?? 0;
      sec7Rows.add([
        ++idx7,
        d['customerName'] ?? d['name'] ?? '',
        d['phone'] ?? '',
        fmtN(total),
        fmtN(paid),
        fmtN(total - paid),
      ]);
    }
    // Also append snapshot receivables (cuối kỳ)
    for (final r in s.receivables) {
      if (!customerDebtsToday.any((d) =>
          (d['firestoreId'] ?? d['referenceId'] ?? '') == (r.id))) {
        sec7Rows.add([
          ++idx7,
          r.name,
          r.phone ?? '',
          fmtN(r.total),
          fmtN(r.paid),
          fmtN(r.remaining),
        ]);
      }
    }
    final sec7 = FinanceV2DetailedDailySection(
      title: '7. Công nợ khách hàng',
      colHeaders: const ['STT', 'Khách hàng', 'SĐT', 'Phát sinh trong ngày', 'Đã thu', 'Còn lại'],
      rows: sec7Rows,
    );

    // ── Section 8: Công nợ nhà cung cấp ─────────────────────────
    final supplierDebtsToday = debtsInRange
        .where((d) =>
            (d['debtType']?.toString().toUpperCase() ?? '') == 'SUPPLIER' ||
            (d['type']?.toString().toUpperCase() ?? '') == 'SUPPLIER')
        .toList();
    final sec8Rows = <List<dynamic>>[];
    int idx8 = 0;
    for (final d in supplierDebtsToday) {
      final total = (d['totalAmount'] as num?)?.toInt() ?? 0;
      final paid = (d['paidAmount'] as num?)?.toInt() ?? 0;
      sec8Rows.add([
        ++idx8,
        d['supplierName'] ?? d['name'] ?? '',
        fmtN(total),
        fmtN(paid),
        fmtN(total - paid),
      ]);
    }
    for (final p in s.payables) {
      if (!supplierDebtsToday.any((d) =>
          (d['firestoreId'] ?? d['referenceId'] ?? '') == (p.id))) {
        sec8Rows.add([
          ++idx8,
          p.name,
          fmtN(p.total),
          fmtN(p.paid),
          fmtN(p.remaining),
        ]);
      }
    }
    final sec8 = FinanceV2DetailedDailySection(
      title: '8. Công nợ nhà cung cấp',
      colHeaders: const ['STT', 'NCC', 'Phát sinh trong ngày', 'Đã trả', 'Còn lại'],
      rows: sec8Rows,
    );

    // ── Section 9: Vốn & lãi từng đơn bán ────────────────────────
    final sec9Rows = <List<dynamic>>[];
    for (int i = 0; i < sales.length; i++) {
      final sale = sales[i];
      final profit = sale.finalPrice - sale.totalCost;
      final pct = sale.finalPrice > 0
          ? '${((profit / sale.finalPrice) * 100).toStringAsFixed(1)}%'
          : '0.0%';
      sec9Rows.add([
        i + 1,
        sale.productNamesDisplay,
        fmtN(sale.totalCost),
        fmtN(sale.finalPrice),
        fmtN(profit),
        pct,
        sale.paymentMethod,
      ]);
    }
    final sec9 = FinanceV2DetailedDailySection(
      title: '9. Vốn & lãi từng đơn bán (${sales.length})',
      colHeaders: const ['STT', 'Sản phẩm', 'Giá vốn', 'Giá bán', 'Lãi', '% lãi', 'Hình thức TT'],
      rows: sec9Rows,
    );

    // ── Section 10: Tổng kết cuối ngày ───────────────────────────
    final totalRevenue = s.incomeFromSales + s.incomeFromRepairs + s.incomeOther;
    final sec10 = FinanceV2DetailedDailySection(
      title: '10. Tổng kết cuối ngày',
      colHeaders: const ['Chỉ tiêu', 'Giá trị'],
      rows: [
        ['Tổng doanh thu', fmtN(totalRevenue)],
        ['Tổng vốn hàng bán', fmtN(s.cogsFromSales)],
        ['Lãi gộp bán hàng', fmtN(s.grossProfitFromSales)],
        ['Lãi gộp sửa chữa', fmtN(s.grossProfitFromRepairs)],
        ['Lãi tổng', fmtN(s.grossProfitTotal)],
        ['Lãi thực (sau chi phí)', fmtN(s.grossProfitTotal - s.operatingExpenseOut)],
        ['Nợ phải thu cuối kỳ', fmtN(s.receivableTotal)],
        ['Nợ phải trả cuối kỳ', fmtN(s.payableTotal)],
      ],
    );

    if (!mounted) return;
    await FinanceV2DetailedExporter.exportDetailedDailyReport(
      context,
      sections: [sec1, sec2, sec3, sec4, sec5, sec6, sec7, sec8, sec9, sec10],
      filePrefix: 'ChiTietNgay',
      start: start,
      end: end,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  POS in chi tiết — bản in cuộn dài
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _printDetailedReport() async {
    if (_snapshot == null) return;

    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return;
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;

    final s = _snapshot!;
    final range = _resolveRange();
    final start = range.$1;
    final end = range.$2;
    final startMs = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59).millisecondsSinceEpoch;

    final analysis = await _buildAuditAnalysis(start, end);
    final sales = await _db.getSalesByDateRange(startMs, endMs);
    final repairs = await _db.getDeliveredRepairsByDateRange(startMs, endMs);
    final imports = await _db.getAllImportHistoryByDateRange(startMs, endMs);

    final shopInfo = await LabelSettingsService().getShopLabelSettings();

    // Helpers
    String fmtM(int v) => NumberFormat('#,###', 'vi_VN').format(v);
    String hm(int ms) => ms > 0
        ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms))
        : '';
    String sign(int v) => v >= 0 ? '+${fmtM(v)}' : '-${fmtM(v.abs())}';

    final buf = StringBuffer();
    const sep = '================================';
    const dash = '--------------------------------';

    // Header
    buf.writeln('[C]$sep');
    buf.writeln('[C][B]BAO CAO NGAY ${DateFormat('dd/MM/yyyy').format(start)}');
    if (shopInfo.shopName.isNotEmpty) {
      buf.writeln('[C]${shopInfo.shopName}');
    }
    buf.writeln('[C]In luc ${DateFormat('HH:mm').format(DateTime.now())}');
    buf.writeln('[C]$sep');

    // Cash flow
    buf.writeln('THU VAO:     ${fmtM(s.totalIn)}');
    buf.writeln('  Tien mat:  ${fmtM(analysis.cashIn)}');
    buf.writeln('  CK:        ${fmtM(analysis.bankIn)}');
    buf.writeln('CHI RA:      ${fmtM(s.totalOut)}');
    buf.writeln('  Tien mat:  ${fmtM(analysis.cashOut)}');
    buf.writeln('  CK:        ${fmtM(analysis.bankOut)}');
    buf.writeln('RONG:        ${sign(s.netCashflow)}');
    buf.writeln('[C]$sep');

    // Cơ cấu thu
    final totalIn = s.totalIn > 0 ? s.totalIn : 1;
    final debtCollected = s.transactions
        .where((t) => t.type.toUpperCase() == 'DEBT_COLLECT')
        .fold<int>(0, (acc, t) => acc + t.amount);
    final settlement = analysis.settlementIncome;

    buf.writeln('[C][B]CO CAU THU');
    if (s.incomeFromSales > 0) {
      buf.writeln('Ban hang:    ${fmtM(s.incomeFromSales)}  (${((s.incomeFromSales / totalIn) * 100).round()}%)');
    }
    if (s.incomeFromRepairs > 0) {
      buf.writeln('Sua chua:    ${fmtM(s.incomeFromRepairs)}  (${((s.incomeFromRepairs / totalIn) * 100).round()}%)');
    }
    if (settlement > 0) {
      buf.writeln('Tat toan NH: ${fmtM(settlement)}  (${((settlement / totalIn) * 100).round()}%)');
    }
    if (debtCollected > 0) {
      buf.writeln('Thu no KH:   ${fmtM(debtCollected)}  (${((debtCollected / totalIn) * 100).round()}%)');
    }
    if (s.incomeOther > 0) {
      buf.writeln('Thu khac:    ${fmtM(s.incomeOther)}  (${((s.incomeOther / totalIn) * 100).round()}%)');
    }
    buf.writeln('[C]$dash');

    // Cơ cấu chi
    final totalOut = s.totalOut > 0 ? s.totalOut : 1;
    buf.writeln('[C][B]CO CAU CHI');
    if (analysis.importOut > 0) {
      buf.writeln('Nhap hang:   ${fmtM(analysis.importOut)}  (${((analysis.importOut / totalOut) * 100).round()}%)');
    }
    if (analysis.supplierPaid > 0) {
      buf.writeln('Tra no NCC:  ${fmtM(analysis.supplierPaid)}  (${((analysis.supplierPaid / totalOut) * 100).round()}%)');
    }
    if (analysis.expenseOut > 0) {
      buf.writeln('Chi phi:     ${fmtM(analysis.expenseOut)}  (${((analysis.expenseOut / totalOut) * 100).round()}%)');
    }
    if (analysis.partnerPaid > 0) {
      buf.writeln('TT doi tac:  ${fmtM(analysis.partnerPaid)}  (${((analysis.partnerPaid / totalOut) * 100).round()}%)');
    }

    buf.writeln('[C]$sep');

    // Đơn bán hàng
    buf.writeln('[C][B]DON BAN HANG (${sales.length} don)');
    buf.writeln('[C]$dash');
    for (final sale in sales) {
      final profit = sale.finalPrice - sale.totalCost;
      final name = sale.isWalkIn
          ? (sale.walkInName?.isNotEmpty == true ? sale.walkInName! : 'Khach le')
          : sale.customerName;
      buf.writeln('${hm(sale.soldAt)} $name');
      buf.writeln('  ${sale.productNamesDisplay}');
      buf.writeln('  Ban: ${fmtM(sale.finalPrice)} | Von: ${fmtM(sale.totalCost)}');
      buf.writeln('  Lai: ${fmtM(profit)} | ${sale.paymentMethod}');
      buf.writeln('[C]$dash');
    }
    buf.writeln('[C]$sep');

    // Đơn sửa chữa
    buf.writeln('[C][B]DON SUA CHUA (${repairs.length} don)');
    buf.writeln('[C]$dash');
    for (final r in repairs) {
      final partnerCost = r.services.fold<int>(0, (acc, sv) => acc + sv.cost);
      final name = r.isWalkIn
          ? (r.walkInName?.isNotEmpty == true ? r.walkInName! : 'Khach le')
          : r.customerName;
      buf.writeln('${hm(r.deliveredAt ?? r.createdAt)} $name - ${r.model}');
      buf.writeln('  Loi: ${r.issue}');
      buf.writeln('  Gia: ${fmtM(r.price)} | CP: ${fmtM(r.cost + partnerCost)}');
      if (r.repairedBy?.isNotEmpty == true) {
        buf.writeln('  KTV: ${r.repairedBy} | ${r.paymentMethod}');
      } else {
        buf.writeln('  ${r.paymentMethod}');
      }
      buf.writeln('[C]$dash');
    }
    buf.writeln('[C]$sep');

    // Nhập kho
    if (imports.isNotEmpty) {
      buf.writeln('[C][B]NHAP KHO (${imports.length})');
      buf.writeln('[C]$dash');
      for (final imp in imports) {
        final ts = (imp['importDate'] as num?)?.toInt() ?? 0;
        final pName = imp['productName'] ?? '';
        final sName = imp['supplierName'] ?? '';
        final qty = imp['quantity'] ?? 0;
        final price = (imp['costPrice'] as num?)?.toInt() ?? 0;
        final pm = imp['paymentMethod'] ?? '';
        buf.writeln('${hm(ts)} $pName');
        buf.writeln('  NCC: $sName | SL: $qty | ${fmtM(price)}');
        buf.writeln('  $pm');
      }
      buf.writeln('[C]$sep');
    }

    // Công nợ cuối ngày
    buf.writeln('[C][B]CONG NO CUOI NGAY');
    buf.writeln('Phai thu KH:  ${fmtM(s.receivableTotal)}');
    buf.writeln('Phai tra NCC: ${fmtM(s.payableTotal)}');
    buf.writeln('[C]$sep');

    // Vốn & lãi
    buf.writeln('[C][B]VON & LAI');
    buf.writeln('Von BH:   ${fmtM(s.cogsFromSales)}');
    buf.writeln('Lai BH:   ${fmtM(s.grossProfitFromSales)}');
    buf.writeln('Von SC:   ${fmtM(s.cogsFromRepairs)}');
    buf.writeln('Lai SC:   ${fmtM(s.grossProfitFromRepairs)}');
    buf.writeln('Lai tong: ${fmtM(s.grossProfitTotal)}');
    buf.writeln('[C]$sep');
    buf.writeln('[C]KY XAC NHAN: ____________');
    buf.writeln('[C]$sep');

    final ok = await UnifiedPrinterService.printTextReceipt(
      buf.toString(),
      paper: PaperSize.mm58,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Đã gửi lệnh in chi tiết' : 'Không thể in, vui lòng kiểm tra máy in'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netCashflow = _snapshot?.netCashflow ?? 0;
    final realProfit = _snapshot == null
        ? 0
        : (_snapshot!.grossProfitTotal - _snapshot!.operatingExpenseOut);

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _snapshot == null
            ? Center(
                child: Text(
                  'Không có dữ liệu',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => _loadReport(),
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildDateSelector(context),
                    const SizedBox(height: 16),
                    _buildSummaryCards(context, netCashflow, realProfit),
                    const SizedBox(height: 16),
                    _buildCapitalAndGrossProfit(context),
                    _buildStaffSummary(context),
                    _buildAllAppOverview(context),
                    _buildSaleRepairBreakdown(context),
                    _buildDebtSummary(context),
                    _buildTopExpenseCategories(context),
                    if (_snapshot!.transactions.isNotEmpty)
                      _buildCashFlow(context),
                    if (_snapshot!.transactions.isNotEmpty)
                      _buildTransactionsList(context),
                    if (_snapshot!.receivables.isNotEmpty || _snapshot!.payables.isNotEmpty)
                      _buildDebtsList(context),
                    if (_snapshot!.auditLogs.isNotEmpty)
                      _buildAuditLogs(context),
                    const SizedBox(height: 24),
                  ],
                ),
              );

    if (widget.embeddedInTab) {
      return ColoredBox(color: FinanceV2Theme.pageBg, child: body);
    }

    return Scaffold(
      backgroundColor: FinanceV2Theme.pageBg,
      appBar: AppBar(
        title: Text('Báo cáo $_periodSuffix'),
        automaticallyImplyLeading: true,
        backgroundColor: FinanceV2Theme.accent,
        foregroundColor: Colors.white,
        actions: [
          if (_snapshot != null)
            IconButton(
              onPressed: _printReport,
              icon: const Icon(Icons.print_rounded),
              tooltip: 'In báo cáo',
            ),
          if (_snapshot != null)
            IconButton(
              onPressed: _printDetailedReport,
              icon: const Icon(Icons.receipt_long_rounded),
              tooltip: 'In chi tiết',
            ),
          if (_snapshot != null)
            IconButton(
              onPressed: _exportReport,
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Xuất Excel',
            ),
          if (_snapshot != null)
            IconButton(
              onPressed: _exportDetailedReport,
              icon: const Icon(Icons.table_chart_rounded),
              tooltip: 'Excel chi tiết',
            ),
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FinanceV2Theme.radiusControl),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F1F3D).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _goPreviousDay,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Ngày trước',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    children: [
                      Text(
                        _rangeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FinanceV2Theme.titleMd.copyWith(
                          color: FinanceV2Theme.accent,
                        ),
                      ),
                      Text(
                        _rangeMode == _ReportRangeMode.day
                            ? _dayNameFmt.format(_selectedDate)
                            : _periodShortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: FinanceV2Theme.subInk,
                            ),
                      ),
                      if (_isToday)
                        Text(
                          'Hôm nay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _isToday ? null : _goNextDay,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Ngày sau',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _rangeModeChip(_ReportRangeMode.day),
                const SizedBox(width: 6),
                _rangeModeChip(_ReportRangeMode.month),
                const SizedBox(width: 6),
                _rangeModeChip(_ReportRangeMode.year),
                const SizedBox(width: 6),
                _rangeModeChip(_ReportRangeMode.custom),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleRepairBreakdown(BuildContext context) {
    final txs = _snapshot?.transactions ?? const <FinanceV2Txn>[];
    final sales = txs.where((e) => e.type.toUpperCase() == 'SALE').toList();
    final repairs = txs.where((e) => e.type.toUpperCase() == 'REPAIR').toList();

    return _panel(
      child: ExpansionTile(
        title: const Text('Chi tiết bán hàng và sửa chữa'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (sales.isNotEmpty) ...[
            Text(
              'Bán hàng trong kỳ (${sales.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.green[700],
                  ),
            ),
            const SizedBox(height: 6),
            ...sales.take(8).map((tx) => _transactionDetailRow(context, tx, Colors.green)),
            const SizedBox(height: 12),
          ],
          if (repairs.isNotEmpty) ...[
            Text(
              'Sửa chữa trong kỳ (${repairs.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.blue[700],
                  ),
            ),
            const SizedBox(height: 6),
            ...repairs.take(8).map((tx) => _transactionDetailRow(context, tx, Colors.blue)),
          ],
          if (sales.isEmpty && repairs.isEmpty)
            const Text('Không có dữ liệu bán/sửa trong kỳ đã chọn.'),
        ],
      ),
    );
  }

  Widget _transactionDetailRow(BuildContext context, FinanceV2Txn tx, Color color) {
    final staff = (tx.actorName ?? '').trim();
    final subtitle = tx.subtitle.trim();
    final base = _displayTitle(tx);
    final detail = <String>[];
    if (subtitle.isNotEmpty) detail.add(subtitle);
    if (staff.isNotEmpty) detail.add('NV: $staff');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  base,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                MoneyUtils.formatCompactCurrency(tx.amount),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
              ),
            ],
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllAppOverview(BuildContext context) {
    return _panel(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Tổng hợp toàn app theo $_periodSuffix'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _metricRow(context, 'Doanh thu bán hàng', _snapshot!.incomeFromSales, Colors.green),
          _metricRow(context, 'Doanh thu sửa chữa', _snapshot!.incomeFromRepairs, Colors.teal),
          _metricRow(context, 'Thu khác', _snapshot!.incomeOther, Colors.blue),
          _metricRow(context, 'Tổng thu', _snapshot!.totalIn, Colors.indigo),
          _metricRow(context, 'Tổng chi', _snapshot!.totalOut, Colors.red),
          _metricRow(context, 'Dòng tiền ròng (sổ quỹ)', _snapshot!.netCashflow, _snapshot!.netCashflow >= 0 ? Colors.green : Colors.orange),
          _metricRow(context, 'Lợi nhuận thực (lãi gộp - chi vận hành)', _snapshot!.grossProfitTotal - _snapshot!.operatingExpenseOut, (_snapshot!.grossProfitTotal - _snapshot!.operatingExpenseOut) >= 0 ? Colors.green : Colors.red),
          _metricRow(context, 'Doanh thu/GD vào (TB)', _snapshot!.avgIncomePerTransaction, Colors.deepPurple),
        ],
      ),
    );
  }

  Widget _buildDebtSummary(BuildContext context) {
    return _panel(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.orange),
        ),
        title: Text('Tổng quan công nợ theo $_periodSuffix'),
        subtitle: Text(
          'Phải thu: ${MoneyUtils.formatCompactCurrency(_snapshot!.receivableTotal)} | '
          'Phải trả: ${MoneyUtils.formatCompactCurrency(_snapshot!.payableTotal)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildTopExpenseCategories(BuildContext context) {
    if (_snapshot!.topExpenseCategories.isEmpty) {
      return const SizedBox.shrink();
    }
    return _panel(
      child: ExpansionTile(
        title: const Text('Top danh mục chi phí'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: _snapshot!.topExpenseCategories.map((c) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  MoneyUtils.formatCompactCurrency(c.amount),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.red[700],
                      ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _metricRow(BuildContext context, String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              MoneyUtils.formatCompactCurrency(amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    int netCashflow,
    int realProfit,
  ) {
    final netDelta = netCashflow - _snapshot!.previousNetCashflow;
    final netDeltaPrefix = netDelta >= 0 ? '+' : '-';
    final netDeltaText =
        '$netDeltaPrefix${MoneyUtils.formatCompactCurrency(netDelta.abs())}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatCard(
            context: context,
            label: 'Tiền vào',
            value: MoneyUtils.formatCompactCurrency(_snapshot!.totalIn),
            color: Colors.green,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Tiền ra',
            value: MoneyUtils.formatCompactCurrency(_snapshot!.totalOut),
            color: Colors.red,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Ròng sổ quỹ',
            value: MoneyUtils.formatCompactCurrency(netCashflow),
            color: netCashflow >= 0 ? Colors.blue : Colors.orange,
            footerText: 'So với kỳ trước: $netDeltaText',
            footerColor: netDelta >= 0 ? Colors.green[700] : Colors.red[700],
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Lợi nhuận thực',
            value: MoneyUtils.formatCompactCurrency(realProfit),
            color: realProfit >= 0 ? Colors.green : Colors.red,
            footerText: 'Lãi gộp - chi vận hành',
            footerColor: Colors.grey[700],
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Giao dịch',
            value: _snapshot!.transactionCount.toString(),
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
    String? footerText,
    Color? footerColor,
  }) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FinanceV2Theme.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ),
          if (footerText != null) ...[
            const SizedBox(height: 6),
            Text(
              footerText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: footerColor ?? Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashFlow(BuildContext context) {
    final inTxs = _snapshot!.transactions.where((t) => t.isIncome).toList();
    final outTxs = _snapshot!.transactions.where((t) => !t.isIncome).toList();
    final totalIn = inTxs.fold(0, (acc, tx) => acc + tx.amount);
    final totalOut = outTxs.fold(0, (acc, tx) => acc + tx.amount);

    return _panel(
      child: ExpansionTile(
        title: Text('Luồng tiền theo $_periodSuffix'),
        initiallyExpanded: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Tiền vào (${inTxs.length})', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.green[700]))),
                    const SizedBox(width: 8),
                    Text(MoneyUtils.formatCompactCurrency(totalIn), style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.green[700])),
                  ],
                ),
                const SizedBox(height: 8),
                if (inTxs.isEmpty)
                  Text('Không có', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]))
                else
                  Column(
                    children: inTxs.take(10).map((tx) => _cashFlowRow(context, tx, Colors.green)).toList(),
                  ),
                const SizedBox(height: 12),
                Divider(color: Colors.grey[300], height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Tiền ra (${outTxs.length})', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.red[700]))),
                    const SizedBox(width: 8),
                    Text(MoneyUtils.formatCompactCurrency(totalOut), style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.red[700])),
                  ],
                ),
                const SizedBox(height: 8),
                if (outTxs.isEmpty)
                  Text('Không có', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]))
                else
                  Column(
                    children: outTxs.take(10).map((tx) => _cashFlowRow(context, tx, Colors.red)).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashFlowRow(BuildContext context, FinanceV2Txn tx, Color color) {
    final subtitle = tx.subtitle.trim();
    final staff = (tx.actorName ?? '').trim();
    final details = <String>[];
    if (subtitle.isNotEmpty) details.add(subtitle);
    if (staff.isNotEmpty) details.add('NV: $staff');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayTitle(tx),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MoneyUtils.formatCompactCurrency(tx.amount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context) {
    return _panel(
      child: ExpansionTile(
        title: Text('Giao dịch (${_snapshot!.transactions.length})'),
        initiallyExpanded: false,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Thời gian')),
                DataColumn(label: Text('Nhóm')),
                DataColumn(label: Text('Tiêu đề')),
                DataColumn(label: Text('Nội dung')),
                DataColumn(label: Text('Nhân viên')),
                DataColumn(label: Text('Hướng')),
                DataColumn(label: Text('Số tiền'), numeric: true),
                DataColumn(label: Text('Vốn'), numeric: true),
                DataColumn(label: Text('Lãi gộp'), numeric: true),
              ],
              rows: _snapshot!.transactions
                  .map((tx) => DataRow(cells: [
                        DataCell(Text(_dtFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt)), style: Theme.of(context).textTheme.bodySmall)),
                        DataCell(Text(_typeLabel(tx), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(_displayTitle(tx), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(tx.subtitle, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        DataCell(Text((tx.actorName ?? '').trim().isEmpty ? '-' : (tx.actorName ?? ''), style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(tx.isIncome ? 'Vào' : 'Ra', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: tx.isIncome ? Colors.green[700] : Colors.red[700]))),
                        DataCell(Text(MoneyUtils.formatCompactCurrency(tx.amount), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: tx.isIncome ? Colors.green[700] : Colors.red[700]))),
                        DataCell(Text(tx.costAmount == null ? '-' : MoneyUtils.formatCompactCurrency(tx.costAmount!), style: Theme.of(context).textTheme.bodySmall)),
                        DataCell(Text(tx.grossProfit == null ? '-' : MoneyUtils.formatCompactCurrency(tx.grossProfit!), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: (tx.grossProfit ?? 0) >= 0 ? Colors.green[700] : Colors.red[700]))),
                      ]))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapitalAndGrossProfit(BuildContext context) {
    final s = _snapshot!;
    return _panel(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Vốn và lãi gộp bán/sửa'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _metricRow(context, 'Vốn bán hàng', s.cogsFromSales, Colors.deepOrange),
          _metricRow(context, 'Vốn sửa chữa', s.cogsFromRepairs, Colors.orange),
          _metricRow(context, 'Lãi gộp bán hàng', s.grossProfitFromSales, s.grossProfitFromSales >= 0 ? Colors.green : Colors.red),
          _metricRow(context, 'Lãi gộp sửa chữa', s.grossProfitFromRepairs, s.grossProfitFromRepairs >= 0 ? Colors.green : Colors.red),
          const Divider(height: 18),
          _metricRow(context, 'Tổng lãi gộp', s.grossProfitTotal, s.grossProfitTotal >= 0 ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget _buildStaffSummary(BuildContext context) {
    final map = <String, _StaffDaySummary>{};
    for (final tx in _snapshot!.transactions) {
      final name = (tx.actorName ?? '').trim();
      if (name.isEmpty) continue;
      final acc = map.putIfAbsent(name, () => _StaffDaySummary());
      acc.count += 1;
      if (tx.isIncome) {
        acc.income += tx.amount;
      } else {
        acc.out += tx.amount;
      }
      if (tx.type.toUpperCase() == 'SALE' || tx.type.toUpperCase() == 'REPAIR') {
        acc.revenue += tx.amount;
      }
      if (tx.costAmount != null) {
        acc.cost += tx.costAmount!;
      }
    }

    for (final att in _attendanceByUser.values) {
      final acc = map.putIfAbsent(att.name, () => _StaffDaySummary());
      acc.presentDays = att.presentDays;
      acc.absentDays = att.absentDays;
      acc.lateDays = att.lateDays;
      acc.swapCount = att.swapCount;
    }

    if (map.isEmpty) return const SizedBox.shrink();
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));

    final totalPresent = entries.fold<int>(0, (acc, e) => acc + e.value.presentDays);
    final totalAbsent = entries.fold<int>(0, (acc, e) => acc + e.value.absentDays);
    final totalLate = entries.fold<int>(0, (acc, e) => acc + e.value.lateDays);
    final totalSwap = entries.fold<int>(0, (acc, e) => acc + e.value.swapCount);

    return _panel(
      child: ExpansionTile(
        title: Text('Nhân viên theo $_periodSuffix (${entries.length})'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Có mặt: $totalPresent · Vắng: $totalAbsent · Đi trễ: $totalLate · Đổi ca: $totalSwap',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...entries.map((e) {
          final gross = e.value.revenue - e.value.cost;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${e.value.count} giao dịch',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Thu: ${MoneyUtils.formatCompactCurrency(e.value.income)} · Chi: ${MoneyUtils.formatCompactCurrency(e.value.out)} · Doanh thu bán/sửa: ${MoneyUtils.formatCompactCurrency(e.value.revenue)} · Lãi gộp: ${MoneyUtils.formatCompactCurrency(gross)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Có mặt: ${e.value.presentDays} · Vắng: ${e.value.absentDays} · Đi trễ: ${e.value.lateDays} · Đổi ca: ${e.value.swapCount}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                ),
              ],
            ),
          );
        }),
        ],
      ),
    );
  }

  String _displayTitle(FinanceV2Txn tx) {
    final base = (tx.itemName ?? '').trim().isNotEmpty ? tx.itemName!.trim() : tx.title.trim();
    final customer = (tx.customerName ?? '').trim();
    if (customer.isNotEmpty && !base.toLowerCase().contains(customer.toLowerCase())) {
      return '$base · KH: $customer';
    }
    return base.isEmpty ? 'Giao dịch' : base;
  }

  Widget _buildDebtsList(BuildContext context) {
    final receivables = _snapshot!.receivables;
    final payables = _snapshot!.payables;

    return _panel(
      child: ExpansionTile(
        title: Text('Công nợ (${receivables.length + payables.length})'),
        initiallyExpanded: false,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (receivables.isNotEmpty) ...[
                  Text('Phải thu (${receivables.length})', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.blue[700])),
                  const SizedBox(height: 8),
                  ...receivables.map((d) => _debtItem(context, d)),
                  const SizedBox(height: 12),
                ],
                if (payables.isNotEmpty) ...[
                  Text('Phải trả (${payables.length})', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: Colors.orange[700])),
                  const SizedBox(height: 8),
                  ...payables.map((d) => _debtItem(context, d)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _debtItem(BuildContext context, FinanceV2DebtItem debt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _openDebtFlow,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (debt.phone != null)
                      Text(debt.phone!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Còn: ${MoneyUtils.formatCompactCurrency(debt.remaining)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.red[700])),
                    Text('Tổng: ${MoneyUtils.formatCompactCurrency(debt.total)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditLogs(BuildContext context) {
    final logs = _snapshot!.auditLogs;
    return _panel(
      child: ExpansionTile(
        title: Text('Nhật ký tài chính (${logs.length})'),
        initiallyExpanded: false,
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length > 80 ? 80 : logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              final createdAt = (log['createdAt'] as num?)?.toInt() ?? 0;
              final title = (log['title'] ?? 'Hoạt động tài chính').toString();
              final desc = (log['description'] ?? '').toString();
              final type = _activityTypeLabel((log['activityType'] ?? '').toString());
              final direction = (log['direction'] ?? '').toString().toUpperCase();
              final amount = (log['amount'] as num?)?.toInt() ?? 0;
              final color = direction == 'IN'
                  ? Colors.green
                  : (direction == 'OUT' ? Colors.red : Colors.orange);
              final ts = createdAt > 0
                  ? _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(createdAt))
                  : '--';
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Text(
                    direction == 'IN' ? 'V' : (direction == 'OUT' ? 'R' : 'N'),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '$ts · $type${desc.isNotEmpty ? ' · $desc' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  MoneyUtils.formatCompactCurrency(amount),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _typeLabel(FinanceV2Txn tx) {
    switch (tx.type.toUpperCase()) {
      case 'SALE':
        return 'Bán hàng';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'INCOME':
        return 'Thu khác';
      case 'EXPENSE':
        return 'Chi phí';
      case 'DEBT_COLLECT':
        return 'Thu nợ';
      case 'DEBT_PAY':
        return 'Trả nợ';
      default:
        return tx.type.isEmpty ? 'Giao dịch' : tx.type;
    }
  }

  String _activityTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'OTHER_INCOME':
        return 'Thu phát sinh';
      case 'OPERATING_EXPENSE':
        return 'Chi vận hành';
      case 'REPAIR_SERVICE':
        return 'Thu sửa chữa';
      case 'PURCHASE':
        return 'Nhập hàng';
      case 'DEBT_PAYMENT':
      case 'DEBT_COLLECT':
      case 'CUSTOMER_DEBT_COLLECT':
        return 'Thu nợ';
      case 'DEBT_PAY':
      case 'SUPPLIER_DEBT':
      case 'SHOP_DEBT_PAY':
        return 'Trả nợ';
      case 'SALE':
        return 'Bán hàng';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'EXPENSE':
        return 'Chi phí';
      case 'REFUND':
        return 'Trả hàng';
      default:
        return type.isEmpty ? 'Hoạt động tài chính' : type;
    }
  }
}

enum _ReportRangeMode { day, month, year, custom }

class _StaffAttendanceStats {
  final String name;
  int presentDays = 0;
  int absentDays = 0;
  int lateDays = 0;
  int swapCount = 0;

  _StaffAttendanceStats({required this.name});
}

class _StaffDaySummary {
  int count = 0;
  int income = 0;
  int out = 0;
  int revenue = 0;
  int cost = 0;
  int presentDays = 0;
  int absentDays = 0;
  int lateDays = 0;
  int swapCount = 0;
}
