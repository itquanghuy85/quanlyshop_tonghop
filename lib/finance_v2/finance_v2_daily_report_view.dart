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

  Widget _topIconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE1E9F7)),
          ),
          child: Icon(icon, size: 18, color: FinanceV2Theme.accent),
        ),
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

    final rows = <List<dynamic>>[
      ['BÁO CÁO ${_periodSuffix.toUpperCase()} $_rangeLabel'],
      ['Cửa hàng', shopInfo.shopName.isNotEmpty ? shopInfo.shopName : 'N/A'],
      ['Shop ID', (shopId == null || shopId.isEmpty) ? 'N/A' : shopId],
      ['Xuất lúc', generatedAt],
      [''],
      ['TỔNG QUAN'],
      ['Doanh thu vào', MoneyUtils.formatVND(s.totalIn)],
      ['Chi phí ra', MoneyUtils.formatVND(s.totalOut)],
      ['Ròng sổ quỹ', MoneyUtils.formatVND(s.totalIn - s.totalOut)],
      ['Lợi nhuận thực', MoneyUtils.formatVND(s.grossProfitTotal - s.operatingExpenseOut)],
      ['Số giao dịch', s.transactionCount.toString()],
      ['Doanh thu bán hàng', MoneyUtils.formatVND(s.incomeFromSales)],
      ['Doanh thu sửa chữa', MoneyUtils.formatVND(s.incomeFromRepairs)],
      ['Thu khác', MoneyUtils.formatVND(s.incomeOther)],
      ['Phải thu', MoneyUtils.formatVND(s.receivableTotal)],
      ['Phải trả', MoneyUtils.formatVND(s.payableTotal)],
      [''],
      ['LÃI GỘP & VỐN'],
      ['Vốn bán hàng', MoneyUtils.formatVND(s.cogsFromSales)],
      ['Vốn sửa chữa', MoneyUtils.formatVND(s.cogsFromRepairs)],
      ['Tổng vốn', MoneyUtils.formatVND(s.cogsFromSales + s.cogsFromRepairs)],
      ['Lãi gộp bán hàng', MoneyUtils.formatVND(s.grossProfitFromSales)],
      ['Lãi gộp sửa chữa', MoneyUtils.formatVND(s.grossProfitFromRepairs)],
      ['Tổng lãi gộp', MoneyUtils.formatVND(s.grossProfitTotal)],
      [''],
    ];

    if (s.topExpenseCategories.isNotEmpty) {
      rows.add(['CHI PHÍ THEO DANH MỤC']);
      rows.add(['Danh mục', 'Số tiền']);
      for (final c in s.topExpenseCategories) {
        rows.add([c.label, MoneyUtils.formatVND(c.amount)]);
      }
      rows.add(['']);
    }

    // Transactions
    if (s.transactions.isNotEmpty) {
      rows.add(['GIAO DỊCH']);
      rows.add(['Thời gian', 'Tiêu đề', 'Chi tiết', 'Loại', 'Hướng', 'Số tiền', 'Vốn', 'Lãi gộp', 'Nhân viên', 'PT thanh toán']);
      for (final tx in s.transactions) {
        rows.add([
          _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(tx.createdAt)),
          _displayTitle(tx),
          tx.subtitle,
          tx.type,
          tx.isIncome ? 'Vào' : 'Ra',
          MoneyUtils.formatVND(tx.amount),
          tx.costAmount == null ? '' : MoneyUtils.formatVND(tx.costAmount!),
          tx.grossProfit == null ? '' : MoneyUtils.formatVND(tx.grossProfit!),
          tx.actorName ?? '',
          tx.paymentMethod ?? '',
        ]);
      }
      rows.add(['']);
    }

    // Staff attendance
    if (attendance.isNotEmpty) {
      rows.add(['NHÂN SỰ - CHẤM CÔNG']);
      rows.add(['Nhân viên', 'Có mặt', 'Vắng mặt', 'Đi trễ', 'Đổi ca']);
      final entries = attendance.entries.toList()
        ..sort((a, b) => a.value.name.compareTo(b.value.name));
      for (final e in entries) {
        final st = e.value;
        rows.add([st.name, st.presentDays, st.absentDays, st.lateDays, st.swapCount]);
      }
      rows.add(['']);
    }

    // Receivables
    if (s.receivables.isNotEmpty) {
      rows.add(['CÔNG NỢ PHẢI THU']);
      rows.add(['Tên', 'SĐT', 'Tổng (đ)', 'Đã TT (đ)', 'Còn lại (đ)']);
      for (final debt in s.receivables) {
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
    if (s.payables.isNotEmpty) {
      rows.add(['CÔNG NỢ PHẢI TRẢ']);
      rows.add(['Tên', 'SĐT', 'Tổng (đ)', 'Đã TT (đ)', 'Còn lại (đ)']);
      for (final debt in s.payables) {
        rows.add([
          debt.name,
          debt.phone ?? '',
          MoneyUtils.formatVND(debt.total),
          MoneyUtils.formatVND(debt.paid),
          MoneyUtils.formatVND(debt.remaining),
        ]);
      }
    }

    if (s.auditLogs.isNotEmpty) {
      rows.add(['']);
      rows.add(['NHẬT KÝ TÀI CHÍNH']);
      rows.add(['Thời gian', 'Loại', 'Hướng', 'Tiêu đề', 'Mô tả', 'Số tiền']);
      for (final log in s.auditLogs.take(300)) {
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
      headers: ['Báo cáo $_periodSuffix $_rangeLabel'],
      rows: rows,
      start: start,
      end: end,
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
      return ColoredBox(
        color: FinanceV2Theme.pageBg,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4EAF6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_alt_rounded, size: 18, color: FinanceV2Theme.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _rangeModeLabel(_rangeMode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FinanceV2Theme.meta.copyWith(
                                color: FinanceV2Theme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_snapshot != null) ...[
                    _topIconAction(
                      icon: Icons.print_rounded,
                      tooltip: 'In',
                      onTap: _printReport,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_snapshot != null) ...[
                    _topIconAction(
                      icon: Icons.download_rounded,
                      tooltip: 'Xuất Excel',
                      onTap: _exportReport,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _topIconAction(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Làm mới',
                    onTap: _loadReport,
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
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
    final totalIn = inTxs.fold(0, (sum, tx) => sum + tx.amount);
    final totalOut = outTxs.fold(0, (sum, tx) => sum + tx.amount);

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

    final totalPresent = entries.fold<int>(0, (sum, e) => sum + e.value.presentDays);
    final totalAbsent = entries.fold<int>(0, (sum, e) => sum + e.value.absentDays);
    final totalLate = entries.fold<int>(0, (sum, e) => sum + e.value.lateDays);
    final totalSwap = entries.fold<int>(0, (sum, e) => sum + e.value.swapCount);

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
