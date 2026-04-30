import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import '../services/unified_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import 'finance_v2_data_service.dart';
import 'finance_v2_theme.dart';
import 'finance_v2_excel_export.dart';
import '../services/label_settings_service.dart';
import '../views/debt_view.dart';

class FinanceV2DailyReportView extends StatefulWidget {
  const FinanceV2DailyReportView({super.key});

  @override
  State<FinanceV2DailyReportView> createState() =>
      _FinanceV2DailyReportViewState();
}

class _FinanceV2DailyReportViewState extends State<FinanceV2DailyReportView> {
  final FinanceV2DataService _service = FinanceV2DataService();
  DateTime _selectedDate = DateTime.now();
  FinanceV2Snapshot? _snapshot;
  bool _loading = true;
  _ReportRangeMode _rangeMode = _ReportRangeMode.day;

  final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  final _dFmt = DateFormat('dd/MM/yyyy');
  final _dayNameFmt = DateFormat('EEEE', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final start = _rangeMode == _ReportRangeMode.day
        ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
        : DateTime(_selectedDate.year, _selectedDate.month, 1);
    final end = _rangeMode == _ReportRangeMode.day
        ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59)
        : DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);
    
    try {
      final data = await _service.loadSnapshot(start: start, end: end);
      if (mounted) {
        setState(() {
          _snapshot = data;
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
    DateTime? picked;
    if (_rangeMode == _ReportRangeMode.day) {
      picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        locale: const Locale('vi', 'VN'),
      );
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
        picked = DateTime(picked.year, picked.month, 1);
      }
    }
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked!);
      _loadReport();
    }
  }

  void _goPreviousDay() {
    setState(() {
      _selectedDate = _rangeMode == _ReportRangeMode.day
          ? _selectedDate.subtract(const Duration(days: 1))
          : DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
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
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  String get _rangeLabel {
    if (_rangeMode == _ReportRangeMode.month) {
      return DateFormat('MM/yyyy').format(_selectedDate);
    }
    return _dFmt.format(_selectedDate);
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
    if (_snapshot == null) return;
    
    final rows = <List<dynamic>>[
      ['BÁO CÁO NGÀY ${_dFmt.format(_selectedDate)} (${_dayNameFmt.format(_selectedDate)})'],
      [''],
      ['TỔNG QUAN'],
      ['Doanh thu vào', MoneyUtils.formatVND(_snapshot!.totalIn)],
      ['Chi phí ra', MoneyUtils.formatVND(_snapshot!.totalOut)],
      ['Ròng', MoneyUtils.formatVND(_snapshot!.totalIn - _snapshot!.totalOut)],
      ['Số giao dịch', _snapshot!.transactionCount.toString()],
      ['Doanh thu bán hàng', MoneyUtils.formatVND(_snapshot!.incomeFromSales)],
      ['Doanh thu sửa chữa', MoneyUtils.formatVND(_snapshot!.incomeFromRepairs)],
      ['Thu khác', MoneyUtils.formatVND(_snapshot!.incomeOther)],
      ['Phải thu', MoneyUtils.formatVND(_snapshot!.receivableTotal)],
      ['Phải trả', MoneyUtils.formatVND(_snapshot!.payableTotal)],
      [''],
    ];

    if (_snapshot!.topExpenseCategories.isNotEmpty) {
      rows.add(['CHI PHÍ THEO DANH MỤC']);
      rows.add(['Danh mục', 'Số tiền']);
      for (final c in _snapshot!.topExpenseCategories) {
        rows.add([c.label, MoneyUtils.formatVND(c.amount)]);
      }
      rows.add(['']);
    }

    // Transactions
    if (_snapshot!.transactions.isNotEmpty) {
      rows.add(['GIAO DỊCH']);
      rows.add(['Thời gian', 'Tiêu đề', 'Chi tiết', 'Loại', 'Hướng', 'Số tiền', 'Nhân viên', 'PT thanh toán']);
      for (final tx in _snapshot!.transactions.take(500)) {
        rows.add([
          _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt)),
          tx.title,
          tx.subtitle,
          tx.type,
          tx.isIncome ? 'Vào' : 'Ra',
          MoneyUtils.formatVND(tx.amount),
          tx.actorName ?? '',
          tx.paymentMethod ?? '',
        ]);
      }
      rows.add(['']);
    }

    // Receivables
    if (_snapshot!.receivables.isNotEmpty) {
      rows.add(['CÔNG NỢ PHẢI THU']);
      rows.add(['Tên', 'SĐT', 'Tổng (đ)', 'Đã TT (đ)', 'Còn lại (đ)']);
      for (final debt in _snapshot!.receivables) {
        rows.add([
          debt.name,
          debt.phone ?? '',
          MoneyUtils.formatVND(debt.total),
          MoneyUtils.formatVND(debt.paid),
          MoneyUtils.formatVND(debt.remaining),
        ]);
      }
      rows.add(['']);
    }

    // Payables
    if (_snapshot!.payables.isNotEmpty) {
      rows.add(['CÔNG NỢ PHẢI TRẢ']);
      rows.add(['Tên', 'SĐT', 'Tổng (đ)', 'Đã TT (đ)', 'Còn lại (đ)']);
      for (final debt in _snapshot!.payables) {
        rows.add([
          debt.name,
          debt.phone ?? '',
          MoneyUtils.formatVND(debt.total),
          MoneyUtils.formatVND(debt.paid),
          MoneyUtils.formatVND(debt.remaining),
        ]);
      }
    }

    if (_snapshot!.auditLogs.isNotEmpty) {
      rows.add(['']);
      rows.add(['NHẬT KÝ TÀI CHÍNH']);
      rows.add(['Thời gian', 'Loại', 'Hướng', 'Tiêu đề', 'Mô tả', 'Số tiền']);
      for (final log in _snapshot!.auditLogs.take(300)) {
        final createdAt = (log['createdAt'] as num?)?.toInt() ?? 0;
        final ts = createdAt > 0
            ? _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(createdAt))
            : '';
        rows.add([
          ts,
          (log['activityType'] ?? '').toString(),
          (log['direction'] ?? '').toString(),
          (log['title'] ?? '').toString(),
          (log['description'] ?? '').toString(),
          MoneyUtils.formatVND((log['amount'] as num?)?.toInt() ?? 0),
        ]);
      }
    }

    await FinanceV2ExcelExport.exportTable(
      context,
      sheetName: 'Báo cáo ngày',
      filePrefix: 'BaoCaoNgay',
      headers: ['Báo cáo ngày ${_dFmt.format(_selectedDate)}'],
      rows: rows,
      start: _selectedDate,
      end: _selectedDate,
    );
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
    lines.writeln('[C][B]BAO CAO NGAY');
    lines.writeln('[C]$_rangeLabel');
    lines.writeln('[C]================================');
    lines.writeln('');

    // Tổng quan
    lines.writeln('[C][B]--- TONG QUAN ---');
    lines.writeln('Doanh thu:  ${MoneyUtils.formatCompactCurrency(s.totalIn)}d');
    lines.writeln('Chi phi:    ${MoneyUtils.formatCompactCurrency(s.totalOut)}d');
    lines.writeln('Loi nhuan:  ${MoneyUtils.formatCompactCurrency(s.netCashflow)}d');
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
    final totalDebtCollect = debtCollectTxs.fold(0, (sum, t) => sum + t.amount);
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
      final totalExp = expenseTxs.fold(0, (sum, t) => sum + t.amount);
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
      final totalDebtPay = debtPayTxs.fold(0, (sum, t) => sum + t.amount);
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
    lines.writeln('[C]================================');
    lines.writeln('[C][B]LOI NHUAN: ${MoneyUtils.formatCompactCurrency(s.netCashflow)}d');
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

  @override
  Widget build(BuildContext context) {
    final net = _snapshot?.totalIn == null ? 0 : _snapshot!.totalIn - _snapshot!.totalOut;

    return Scaffold(
      backgroundColor: FinanceV2Theme.pageBg,
      appBar: AppBar(
        title: const Text('Báo cáo ngày'),
        automaticallyImplyLeading: false,
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
              onPressed: _exportReport,
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Xuất Excel',
            ),
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _loading
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
                      _buildRangeSelector(context),
                      const SizedBox(height: 8),
                      _buildDateSelector(context),
                      const SizedBox(height: 16),
                      _buildSummaryCards(context, net),
                      const SizedBox(height: 16),
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
                ),
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: FinanceV2Theme.accent,
                        ),
                  ),
                  Text(
                    _rangeMode == _ReportRangeMode.day
                        ? _dayNameFmt.format(_selectedDate)
                        : 'Theo tháng',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
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
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Theo ngày'),
          selected: _rangeMode == _ReportRangeMode.day,
          onSelected: (v) {
            if (!v) return;
            setState(() => _rangeMode = _ReportRangeMode.day);
            _loadReport();
          },
        ),
        ChoiceChip(
          label: const Text('Theo tháng'),
          selected: _rangeMode == _ReportRangeMode.month,
          onSelected: (v) {
            if (!v) return;
            setState(() {
              _rangeMode = _ReportRangeMode.month;
              _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
            });
            _loadReport();
          },
        ),
      ],
    );
  }

  Widget _buildSaleRepairBreakdown(BuildContext context) {
    final txs = _snapshot?.transactions ?? const <FinanceV2Txn>[];
    final sales = txs.where((e) => e.type.toUpperCase() == 'SALE').toList();
    final repairs = txs.where((e) => e.type.toUpperCase() == 'REPAIR').toList();

    final saleMap = <String, int>{};
    for (final s in sales) {
      final key = s.title.trim().isEmpty ? 'Bán lẻ' : s.title.trim();
      saleMap[key] = (saleMap[key] ?? 0) + s.amount;
    }

    final repairMap = <String, int>{};
    for (final r in repairs) {
      final key = r.subtitle.trim().isEmpty ? 'Sửa chữa khác' : r.subtitle.trim();
      repairMap[key] = (repairMap[key] ?? 0) + r.amount;
    }

    final saleItems = saleMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final repairItems = repairMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: const Text('Tổng hợp chi tiết bán/sửa'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (saleItems.isNotEmpty) ...[
            Text(
              'Bán gì trong kỳ (${saleItems.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.green[700],
                  ),
            ),
            const SizedBox(height: 6),
            ...saleItems.take(8).map((e) => _nameAmountRow(context, e.key, e.value, Colors.green)),
            const SizedBox(height: 12),
          ],
          if (repairItems.isNotEmpty) ...[
            Text(
              'Sửa gì trong kỳ (${repairItems.length})',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.blue[700],
                  ),
            ),
            const SizedBox(height: 6),
            ...repairItems.take(8).map((e) => _nameAmountRow(context, e.key, e.value, Colors.blue)),
          ],
          if (saleItems.isEmpty && repairItems.isEmpty)
            const Text('Không có dữ liệu bán/sửa trong kỳ đã chọn.'),
        ],
      ),
    );
  }

  Widget _nameAmountRow(BuildContext context, String name, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MoneyUtils.formatCompactCurrency(amount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllAppOverview(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text('Tổng hợp toàn app trong ngày'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _metricRow(context, 'Doanh thu bán hàng', _snapshot!.incomeFromSales, Colors.green),
          _metricRow(context, 'Doanh thu sửa chữa', _snapshot!.incomeFromRepairs, Colors.teal),
          _metricRow(context, 'Thu khác', _snapshot!.incomeOther, Colors.blue),
          _metricRow(context, 'Tổng thu', _snapshot!.totalIn, Colors.indigo),
          _metricRow(context, 'Tổng chi', _snapshot!.totalOut, Colors.red),
          _metricRow(context, 'Dòng tiền ròng', _snapshot!.netCashflow, _snapshot!.netCashflow >= 0 ? Colors.green : Colors.orange),
          _metricRow(context, 'Doanh thu/GD vào (TB)', _snapshot!.avgIncomePerTransaction, Colors.deepPurple),
        ],
      ),
    );
  }

  Widget _buildDebtSummary(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.orange),
        ),
        title: const Text('Tổng quan công nợ trong ngày'),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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

  Widget _buildSummaryCards(BuildContext context, int net) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatCard(
            context: context,
            label: 'Doanh thu',
            value: MoneyUtils.formatCompactCurrency(_snapshot!.totalIn),
            color: Colors.green,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Chi phí',
            value: MoneyUtils.formatCompactCurrency(_snapshot!.totalOut),
            color: Colors.red,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            context: context,
            label: 'Ròng',
            value: MoneyUtils.formatCompactCurrency(net),
            color: net >= 0 ? Colors.blue : Colors.orange,
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
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
        ],
      ),
    );
  }

  Widget _buildCashFlow(BuildContext context) {
    final inTxs = _snapshot!.transactions.where((t) => t.isIncome).toList();
    final outTxs = _snapshot!.transactions.where((t) => !t.isIncome).toList();
    final totalIn = inTxs.fold(0, (sum, tx) => sum + tx.amount);
    final totalOut = outTxs.fold(0, (sum, tx) => sum + tx.amount);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: const Text('Luồng tiền'),
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
                    children: inTxs.take(10).map((tx) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(tx.title, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(MoneyUtils.formatCompactCurrency(tx.amount), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.green)),
                      ]),
                    )).toList(),
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
                    children: outTxs.take(10).map((tx) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(tx.title, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(MoneyUtils.formatCompactCurrency(tx.amount), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.red)),
                      ]),
                    )).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                DataColumn(label: Text('Hướng')),
                DataColumn(label: Text('Số tiền'), numeric: true),
              ],
              rows: _snapshot!.transactions
                  .map((tx) => DataRow(cells: [
                        DataCell(Text(_dtFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt)), style: Theme.of(context).textTheme.bodySmall)),
                        DataCell(Text(_typeLabel(tx), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(tx.title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(tx.subtitle, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        DataCell(Text(tx.isIncome ? 'Vào' : 'Ra', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: tx.isIncome ? Colors.green[700] : Colors.red[700]))),
                        DataCell(Text(MoneyUtils.formatCompactCurrency(tx.amount), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: tx.isIncome ? Colors.green[700] : Colors.red[700]))),
                      ]))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtsList(BuildContext context) {
    final receivables = _snapshot!.receivables;
    final payables = _snapshot!.payables;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
      default:
        return type.isEmpty ? 'Hoạt động tài chính' : type;
    }
  }
}

enum _ReportRangeMode { day, month }
