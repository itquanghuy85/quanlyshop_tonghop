// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:intl/intl.dart';

import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/repair_model.dart';
import '../utils/money_utils.dart';
import '../views/cash_closing_view.dart';
import '../views/debt_view.dart';
import '../views/expense_view.dart';
import '../views/repair_detail_view.dart';
import '../views/sale_detail_view.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/printer_selection_dialog.dart';
import '../widgets/responsive_wrapper.dart';
import '../services/event_bus.dart';
import '../services/label_settings_service.dart';
import '../services/unified_printer_service.dart';
import '../models/printer_types.dart';
import 'finance_v2_data_service.dart';
import 'finance_v2_excel_export.dart';
import 'finance_v2_theme.dart';
import 'finance_v2_daily_report_view.dart';

class _TLEntry {
  final int ts;
  final String type;
  final String title;
  final String subtitle;
  final int amount;
  final bool isIncome;
  final String? avatarUrl;
  final String? actorName;
  final String? paymentMethod;
  final String? referenceId;
  const _TLEntry({required this.ts, required this.type, required this.title,
    required this.subtitle, required this.amount, required this.isIncome,
    this.avatarUrl, this.actorName, this.paymentMethod, this.referenceId});
}

enum _TimeFilter { today, sevenDays, thirtyDays, custom }

enum _ToolbarAction { print, exportExcel, reload }

class FinanceV2View extends StatefulWidget {
  const FinanceV2View({super.key});
  @override
  State<FinanceV2View> createState() => _FinanceV2ViewState();
}

class _FinanceV2ViewState extends State<FinanceV2View>
    with SingleTickerProviderStateMixin {
  static const int _txPageSize = 20;
  static const int _debtPageSize = 15;
  static const int _timelinePageSize = 20;
  static const double _tabStripHeight = 48;

  static const List<String> _financeTabs = <String>[
    'Tổng quan',
    'Giao dịch',
    'Công nợ',
    'Nhật ký',
    'Báo cáo',
  ];

  late TabController _tabController;
  final FinanceV2DataService _service = FinanceV2DataService();
  final DBHelper _db = DBHelper();
  final _txCtrl = TextEditingController();
  final _tlCtrl = TextEditingController();
  bool _loading = true;
  FinanceV2Snapshot? _snap;
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _end = DateTime.now();
  _TimeFilter _timeFilter = _TimeFilter.today;
  String _txFilter = 'ALL';
  String _txQuery = '';
  final String _txPm = '';
  bool _showRec = true;
  final String _tlSrc = 'ALL';
  final String _tlDir = 'ALL';
  String _tlQ = '';
  final bool _tlHigh = false;
  final String _tlActor = '';
  final String _tlPm = '';
  List<_TLEntry> _timelineCache = const [];
  int _txPage = 1;
  int _debtPage = 1;
  int _timelinePage = 1;
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _txCtrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _txQuery = _txCtrl.text;
        _txPage = 1;
      });
    });
    _tlCtrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _tlQ = _tlCtrl.text;
        _timelinePage = 1;
      });
    });
    _eventSub = EventBus().stream.where((event) =>
      event == EventBus.shopChanged ||
      event == EventBus.financialChanged ||
      event == EventBus.syncComplete
    ).listen((_) {
      if (!mounted) return;
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _tabController.dispose();
    _txCtrl.dispose();
    _tlCtrl.dispose();
    super.dispose();
  }

  String? _loadError;

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final prev = _previousPeriod();
      final d = await _service.loadSnapshot(
        start: _start, end: _end,
        previousStart: prev.$1, previousEnd: prev.$2,
      );
      if (!mounted) return;
      final cachedTimeline = _timeline(d);
      setState(() {
        _snap = d;
        _timelineCache = cachedTimeline;
        _loading = false;
        _txPage = 1;
        _debtPage = 1;
        _timelinePage = 1;
      });
    } catch (e, st) {
      debugPrint('FinanceV2 _load error: $e\n$st');
      if (!mounted) return;
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  /// Tính khoảng kỳ trước theo đúng độ dài kỳ hiện tại.
  (DateTime?, DateTime?) _previousPeriod() {
    if (_timeFilter == _TimeFilter.today) {
      final y = _start.subtract(const Duration(days: 1));
      return (DateTime(y.year, y.month, y.day), DateTime(y.year, y.month, y.day));
    }
    final periodDays = _end.difference(_start).inDays + 1;
    final prevEnd = _start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: periodDays - 1));
    return (
      DateTime(prevStart.year, prevStart.month, prevStart.day),
      DateTime(prevEnd.year, prevEnd.month, prevEnd.day),
    );
  }

  /// Nhãn hiển thị kỳ trước trong mục So sánh
  String get _compLabel {
    if (_timeFilter == _TimeFilter.today) return 'hôm qua';
    if (_timeFilter == _TimeFilter.sevenDays) return '7 ngày trước';
    if (_timeFilter == _TimeFilter.thirtyDays) return '30 ngày trước';
    if (_isSingle) return 'ngày trước';
    return 'kỳ trước';
  }

  bool get _isSingle => _timeFilter == _TimeFilter.custom &&
      _start.year == _end.year && _start.month == _end.month && _start.day == _end.day;

  String get _sub {
    switch (_timeFilter) {
      case _TimeFilter.today:
        return 'Hôm nay';
      case _TimeFilter.sevenDays:
        return '7 ngày gần nhất';
      case _TimeFilter.thirtyDays:
        return '30 ngày gần nhất';
      case _TimeFilter.custom:
        if (_isSingle) return DateFormat('dd/MM/yyyy').format(_start);
        return '${DateFormat('dd/MM').format(_start)} - ${DateFormat('dd/MM/yyyy').format(_end)}';
    }
  }

  void _setToday() {
    final n = DateTime.now();
    setState(() {
      _timeFilter = _TimeFilter.today;
      _start = DateTime(n.year, n.month, n.day);
      _end = n;
    });
    _load();
  }

  void _setSevenDays() {
    final n = DateTime.now();
    setState(() {
      _timeFilter = _TimeFilter.sevenDays;
      _start = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 6));
      _end = n;
    });
    _load();
  }

  void _setThirtyDays() {
    final n = DateTime.now();
    setState(() {
      _timeFilter = _TimeFilter.thirtyDays;
      _start = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 29));
      _end = n;
    });
    _load();
  }

  Future<void> _pick() async {
    final p = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      locale: const Locale('vi'),
      builder: (c, ch) => Theme(data: Theme.of(c).copyWith(
        colorScheme: const ColorScheme.light(primary: FinanceV2Theme.accent)), child: ch!),
    );
    if (p != null && mounted) {
      setState(() {
        _timeFilter = _TimeFilter.custom;
        _start = p.start;
        _end = p.end;
      });
      _load();
    }
  }

  void _goTx(String f) { setState(()=>_txFilter=f); _tabController.animateTo(1); }
  void _goDebt(bool r) { setState(()=>_showRec=r); _tabController.animateTo(2); }

  Future<void> _openTL(_TLEntry e) async {
    if (e.type=='REPAIR') {
      final ref=e.referenceId??'';
      Repair? r;
      if(ref.isNotEmpty) { r=await _db.getRepairByFirestoreId(ref); r??=int.tryParse(ref)!=null?await _db.getRepairById(int.parse(ref)):null; }
      if(r!=null&&mounted) Navigator.push(context, MaterialPageRoute(builder:(_)=>RepairDetailView(repair:r!)));
    } else if (e.type=='SALE') {
      final ref=e.referenceId??'';
      if(ref.isNotEmpty) { final s=await _db.getSaleByFirestoreId(ref); if(s!=null&&mounted) Navigator.push(context, MaterialPageRoute(builder:(_)=>SaleDetailView(sale:s))); }
    } else if (e.type=='EXPENSE'||e.type=='INCOME') {
      if(!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder:(_)=>ExpenseView(initialMode:e.type=='INCOME'?'THU':'CHI')));
    } else if (e.type=='DEBT_COLLECT'||e.type=='DEBT_PAY') {
      if(!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder:(_)=>const DebtView()));
    }
  }

  /// Thanh lọc dùng chung cho tất cả tab (trừ tab Báo cáo)
  Widget _sharedBar() {
    final custom = _timeFilter == _TimeFilter.custom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F7))),
      ),
      padding: EdgeInsets.fromLTRB(_hPad, 16, _hPad, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _modeChip('Hôm nay', _timeFilter == _TimeFilter.today, _setToday),
              _modeChip('7 ngày', _timeFilter == _TimeFilter.sevenDays, _setSevenDays),
              _modeChip('30 ngày', _timeFilter == _TimeFilter.thirtyDays, _setThirtyDays),
              _modeChip('Tùy chọn', _timeFilter == _TimeFilter.custom, _pick),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FinanceV2Theme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_rounded, size: 12, color: FinanceV2Theme.accent),
                  const SizedBox(width: 4),
                  Text(_sub, style: FinanceV2Theme.micro.copyWith(color: FinanceV2Theme.accent)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(
        label,
        style: FinanceV2Theme.meta.copyWith(
          color: selected ? Colors.white : FinanceV2Theme.subInk,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
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

  void _exFromTab() {
    final s = _snap;
    if (s == null) return;
    final idx = _tabController.index;
    switch (idx) {
      case 0:
        _exOverview(s);
        break;
      case 1:
        var tx = s.transactions.toList();
        if (_txFilter == 'IN') {
          tx = tx.where((t) => t.isIncome).toList();
        } else if (_txFilter == 'OUT') {
          tx = tx.where((t) => !t.isIncome).toList();
        } else if (_txFilter != 'ALL') {
          tx = tx.where((t) => t.type == _txFilter).toList();
        }
        if (_txPm.isNotEmpty) tx = tx.where((t) => (t.paymentMethod ?? '') == _txPm).toList();
        _exTx(tx);
        break;
      case 2:
        _exDebt(_showRec ? s.receivables : s.payables);
        break;
      case 3:
        _exTL(_timeline(s));
        break;
      case 4:
        _exDailyReportPhone(s);
        break;
      default:
        break;
    }
  }

  Widget _sf(TextEditingController ctrl,String hint,String q,VoidCallback clr) {
    return TextField(controller:ctrl,decoration:InputDecoration(
      hintText:hint,hintStyle:FinanceV2Theme.bodyMd.copyWith(color:FinanceV2Theme.subInk),
      prefixIcon:const Icon(Icons.search_rounded,size:18,color:FinanceV2Theme.subInk),
      suffixIcon:q.isNotEmpty?IconButton(icon:const Icon(Icons.clear_rounded,size:18),onPressed:clr):null,
      isDense:true,contentPadding:const EdgeInsets.symmetric(vertical:8),
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:Color(0xFFDDE3EF))),
      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:Color(0xFFDDE3EF))),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(10),borderSide:const BorderSide(color:FinanceV2Theme.accent))));
  }

  Widget _empty(String msg) => Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.inbox_rounded,size:48,color:Color(0xFFCDD5E0)),
    const SizedBox(height:12),
    Text(msg,style:FinanceV2Theme.titleMd.copyWith(color:FinanceV2Theme.subInk))]));

  Widget _tag(String type) {
    const m=<String,(String,Color)>{'SALE':('BH',Color(0xFF1565C0)),'REPAIR':('SC',Color(0xFF2E7D32)),'EXPENSE':('Chi',FinanceV2Theme.negative),'INCOME':('Thu',FinanceV2Theme.positive),'DEBT_COLLECT':('TN',FinanceV2Theme.warn),'DEBT_PAY':('TrN',FinanceV2Theme.negative),'REFUND':('TH',Color(0xFFE65100))};
    final e=m[type]; if(e==null) return const SizedBox.shrink();
    return Container(margin:const EdgeInsets.only(left:4),padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
      decoration:BoxDecoration(color:e.$2.withValues(alpha:0.1),borderRadius:BorderRadius.circular(4),border:Border.all(color:e.$2.withValues(alpha:0.4))),
      child:Text(e.$1,style:FinanceV2Theme.caption.copyWith(fontWeight:FontWeight.w700,color:e.$2)));
  }

  Widget _dot(Color c) => Container(width:8,height:8,decoration:BoxDecoration(color:c,shape:BoxShape.circle));

  String _cmp(int v) => MoneyUtils.formatCompactCurrency(v.abs());
  String _signedCmp(int v) => v < 0 ? '-${MoneyUtils.formatCompactCurrency(v.abs())}' : MoneyUtils.formatCompactCurrency(v.abs());
  String _full(int v) => MoneyUtils.formatCurrency(v.abs());
  int _ti(dynamic v){ if(v is int) return v; if(v is num) return v.toInt(); if(v is String) return int.tryParse(v)??0; return 0; }
  String _ft(String t) => const<String,String>{'SALE':'Bán hàng','REPAIR':'Sửa chữa','EXPENSE':'Chi phí','INCOME':'Thu phát sinh','DEBT_COLLECT':'Thu nợ','DEBT_PAY':'Trả nợ','CUSTOMER_OWES':'Phải thu','SHOP_OWES':'Phải trả','AUDIT':'Nhật ký','REFUND':'Trả hàng'}[t]??t;
  String _fa(String a) => const<String,String>{'create_repair':'Tạo đơn sửa chữa','update_repair':'Cập nhật đơn sửa','delete_repair':'Xóa đơn sửa chữa','create_sale':'Tạo đơn bán hàng','update_sale':'Cập nhật đơn bán hàng','delete_sale':'Xóa đơn bán hàng','add_expense':'Thêm chi phí','update_expense':'Cập nhật chi phí','delete_expense':'Xóa chi phí','add_debt':'Thêm công nợ','update_debt':'Cập nhật công nợ','delete_debt':'Xóa công nợ','add_debt_payment':'Thanh toán nợ','cash_closing':'Chốt ca'}[a]??a;

  int _maxPage(int total, int pageSize) {
    if (total <= 0) return 1;
    return ((total - 1) ~/ pageSize) + 1;
  }

  List<T> _slicePage<T>(List<T> source, int page, int pageSize) {
    if (source.isEmpty) return const [];
    final safePage = page.clamp(1, _maxPage(source.length, pageSize));
    final start = (safePage - 1) * pageSize;
    final end = (start + pageSize).clamp(0, source.length);
    return source.sublist(start, end);
  }

  Widget _pager({
    required int total,
    required int page,
    required int pageSize,
    required ValueChanged<int> onChanged,
    String unit = 'mục',
  }) {
    final maxPage = _maxPage(total, pageSize);
    if (total <= pageSize) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Trang $page/$maxPage • $total $unit',
              style: FinanceV2Theme.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Trang trước',
            onPressed: page > 1 ? () => onChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Trang sau',
            onPressed: page < maxPage ? () => onChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  double get _vw => MediaQuery.of(context).size.width;
  double get _hPad => FinanceV2Theme.contentHPad(_vw);
  double get _cardPad => FinanceV2Theme.cardPad(_vw);

  Future<void> _printFromTab() async {
    final s = _snap;
    if (s == null) return;

    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return;

    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;

    final lines = await _buildPrintLinesForTab(s, _tabController.index);
    final ok = await UnifiedPrinterService.printTextReceipt(
      lines,
      paper: PaperSize.mm58,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Đã gửi lệnh in' : 'Không thể in, vui lòng kiểm tra máy in'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<String> _buildPrintLinesForTab(FinanceV2Snapshot s, int idx) async {
    final shopInfo = await LabelSettingsService().getShopLabelSettings();
    final b = StringBuffer();

    if (shopInfo.shopName.isNotEmpty) {
      b.writeln('[C][B]${shopInfo.shopName}');
    }
    if (shopInfo.address.isNotEmpty) {
      b.writeln('[C]${shopInfo.address}');
    }
    if (shopInfo.hotline.isNotEmpty) {
      b.writeln('[C]SDT: ${shopInfo.hotline}');
    }
    b.writeln('[C]==============================');
    b.writeln('[C][B]TAI CHINH V2');
    b.writeln('[C]$_sub');
    b.writeln('[C]${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    b.writeln('');

    if (idx == 0 || idx == 4) {
      b.writeln('[L][B]TONG QUAN');
      b.writeln('Thu vao : ${_cmp(s.totalIn)}');
      b.writeln('Chi ra  : ${_cmp(s.totalOut)}');
      b.writeln('Rong quy: ${_signedCmp(s.netCashflow)}');
      b.writeln('Giao dich: ${s.transactionCount}');
      b.writeln('Phai thu : ${_cmp(s.receivableTotal)}');
      b.writeln('Phai tra : ${_cmp(s.payableTotal)}');
      b.writeln('');
    }

    if (idx == 1) {
      b.writeln('[L][B]GIAO DICH');
      var tx = s.transactions.toList();
      if (_txFilter == 'IN') {
        tx = tx.where((t) => t.isIncome).toList();
      } else if (_txFilter == 'OUT') {
        tx = tx.where((t) => !t.isIncome).toList();
      } else if (_txFilter != 'ALL') {
        tx = tx.where((t) => t.type == _txFilter).toList();
      }
      if (_txPm.isNotEmpty) {
        tx = tx.where((t) => (t.paymentMethod ?? '') == _txPm).toList();
      }
      for (final t in tx.take(25)) {
        final sign = t.isIncome ? '+' : '-';
        b.writeln('${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.createdAt))} ${_ft(t.type)}');
        b.writeln('  $sign${_cmp(t.amount)} | ${t.title}');
      }
      if (tx.length > 25) {
        b.writeln('... +${tx.length - 25} giao dich');
      }
      b.writeln('');
    }

    if (idx == 2) {
      b.writeln('[L][B]CONG NO');
      final items = _showRec ? s.receivables : s.payables;
      for (final d in items.take(20)) {
        b.writeln('${d.name}: ${_cmp(d.remaining)}');
      }
      if (items.length > 20) {
        b.writeln('... +${items.length - 20} khoan');
      }
      b.writeln('');
    }

    if (idx == 3) {
      b.writeln('[L][B]NHAT KY');
      final ents = _timelineCache;
      for (final e in ents.take(25)) {
        b.writeln('${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.ts))} ${_ft(e.type)}');
        if (e.amount > 0) {
          b.writeln('  ${e.isIncome ? '+' : '-'}${_cmp(e.amount)} | ${e.title}');
        } else {
          b.writeln('  ${e.title}');
        }
      }
      if (ents.length > 25) {
        b.writeln('... +${ents.length - 25} muc');
      }
      b.writeln('');
    }

    if (idx == 4) {
      b.writeln('[L][B]BAO CAO NHANH');
      b.writeln('Doanh thu BH: ${_cmp(s.incomeFromSales)}');
      b.writeln('Doanh thu SC: ${_cmp(s.incomeFromRepairs)}');
      b.writeln('Thu khac    : ${_cmp(s.incomeOther)}');
      b.writeln('Lai gop tong: ${_cmp(s.grossProfitTotal)}');
      b.writeln('');
    }

    b.writeln('[C]==============================');
    b.writeln('[C]Ket thuc');
    return b.toString();
  }

  void _onToolbarAction(_ToolbarAction action) {
    switch (action) {
      case _ToolbarAction.print:
        _printFromTab();
        break;
      case _ToolbarAction.exportExcel:
        _exFromTab();
        break;
      case _ToolbarAction.reload:
        _load();
        break;
    }
  }

  PopupMenuButton<_ToolbarAction> _buildToolbarMenu() {
    return PopupMenuButton<_ToolbarAction>(
      tooltip: 'Thao tác',
      onSelected: _onToolbarAction,
      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF1565C0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _ToolbarAction.print,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.print_rounded),
            title: Text('In'),
          ),
        ),
        PopupMenuItem(
          value: _ToolbarAction.exportExcel,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_rounded),
            title: Text('Xuất Excel'),
          ),
        ),
        PopupMenuItem(
          value: _ToolbarAction.reload,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh_rounded),
            title: Text('Tải lại'),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildFinanceHeader() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(_tabStripHeight + 1),
      child: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(_tabStripHeight + 1),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF4F8FF),
              border: Border(bottom: BorderSide(color: Color(0xFFD8E4F8))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildAdaptiveTabStrip(),
                ),
                _buildToolbarMenu(),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveTabStrip() {
    if (_financeTabs.length <= 4) {
      return SizedBox(
        height: _tabStripHeight,
        child: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: const Color(0xFF0D47A1),
          unselectedLabelColor: const Color(0xFF5F6B7A),
          labelStyle: FinanceV2Theme.meta.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: FinanceV2Theme.meta.copyWith(fontWeight: FontWeight.w600),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 2,
          indicatorColor: const Color(0xFF0D47A1),
          dividerColor: Colors.transparent,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: _financeTabs.map((label) => Tab(text: label)).toList(growable: false),
        ),
      );
    }

    return SizedBox(
      height: _tabStripHeight,
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) {
          final current = _tabController.index.clamp(0, _financeTabs.length - 1);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<Widget>.generate(_financeTabs.length, (i) {
                final selected = current == i;
                return _buildCustomTabItem(
                  label: _financeTabs[i],
                  selected: selected,
                  onTap: () => _tabController.animateTo(i),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCustomTabItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _tabStripHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFF0D47A1) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FinanceV2Theme.meta.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? const Color(0xFF0D47A1) : const Color(0xFF5F6B7A),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FinanceV2Theme.pageBg,
      appBar: _buildFinanceHeader(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: FinanceV2Theme.accent))
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: FinanceV2Theme.negative),
                  const SizedBox(height: 12),
                  Text('Lỗi tải dữ liệu tài chính', style: FinanceV2Theme.titleMd.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_loadError!, style: FinanceV2Theme.meta, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Thử lại'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
                  ),
                ])))
              : Column(
              children: [
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (_, __) => _tabController.index == 4
                      ? const SizedBox.shrink()
                      : _sharedBar(),
                ),
                Expanded(
                  child: TabBarView(controller: _tabController, children: [
                    _t0(), _t1(), _t2(), _t4(), _t5(),
                  ]),
                ),
              ],
            ),
    );
  }
  // TAB 0
  Widget _t0() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    return ResponsiveCenter(child:RefreshIndicator(onRefresh:_load,color:FinanceV2Theme.accent,
      child:ListView(padding:EdgeInsets.zero,children:[
        _hero(s),const SizedBox(height:8),
        _alerts(s),
        Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Column(children:[
          Row(children:[
            Expanded(child:_kpi('Tiền thu vào',s.totalIn,s.previousTotalIn,FinanceV2Theme.positive,Icons.arrow_downward_rounded,()=>_goTx('IN'))),
            const SizedBox(width:8),
            Expanded(child:_kpi('Tiền chi ra',s.totalOut,s.previousTotalOut,FinanceV2Theme.negative,Icons.arrow_upward_rounded,()=>_goTx('OUT'))),
          ]),
          const SizedBox(height:8),
          Row(children:[
            Expanded(child:_kpi('Nợ phải thu',s.receivableTotal,null,FinanceV2Theme.warn,Icons.people_alt_rounded,()=>_goDebt(true))),
            const SizedBox(width:8),
            Expanded(child:_kpi('Nợ phải trả',s.payableTotal,null,FinanceV2Theme.negative,Icons.store_mall_directory_rounded,()=>_goDebt(false))),
          ]),
        ])),
        const SizedBox(height:12),_compSection(s),const SizedBox(height:12),_profitSection(s),const SizedBox(height:12),_incomeSection(s),
        const SizedBox(height:12),_cfSection(s),const SizedBox(height:12),_debtSection(s),
        const SizedBox(height:12),_expCatSection(s),const SizedBox(height:12),_snapCard(s),
        const SizedBox(height:24),
      ])));
  }

  Widget _hero(FinanceV2Snapshot s) {
    return Container(
      decoration: const BoxDecoration(gradient:FinanceV2Theme.heroGradient),
      padding: const EdgeInsets.fromLTRB(20,20,20,24),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Dòng tiền ròng',style:FinanceV2Theme.bodyMd.copyWith(color:Colors.white.withValues(alpha:0.8))),
        const SizedBox(height:4),
        Text(_signedCmp(s.netCashflow),style:FinanceV2Theme.amountHero.copyWith(color:s.netCashflow>=0?Colors.white:const Color(0xFFFFB3B0))),
        const SizedBox(height:12),
        SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
          _qc(Icons.remove_circle_outline_rounded,'Ghi chi',()=>_goExp('CHI')),const SizedBox(width:8),
          _qc(Icons.add_circle_outline_rounded,'Ghi thu',()=>_goExp('THU')),const SizedBox(width:8),
          _qc(Icons.handshake_outlined,'Công nợ',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DebtView())).then((_)=>_load())),const SizedBox(width:8),
          _qc(Icons.lock_clock_rounded,'Chốt ca',()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CashClosingView()))),
        ])),
      ]));
  }

  void _goExp(String m) => Navigator.push(context,MaterialPageRoute(builder:(_)=>ExpenseView(initialMode:m,openCreateDialogOnStart:true))).then((_)=>_load());

  Widget _qc(IconData icon,String lbl,VoidCallback onTap) => GestureDetector(onTap:onTap,child:Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
    decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.2),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white.withValues(alpha:0.4))),
    child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:14,color:Colors.white),const SizedBox(width:4),Text(lbl,style:FinanceV2Theme.bodySm.copyWith(color:Colors.white))])));

  Widget _alerts(FinanceV2Snapshot s) {
    final list=<Map<String,dynamic>>[];
    final o60=s.debtAging['>60']??0;
    if(o60>3000000) list.add({'i':Icons.warning_amber_rounded,'c':FinanceV2Theme.negative,'t':'Có công nợ quá hạn trên 60 ngày. Cần xử lý ngay!'});
    if(s.netCashflow<0&&s.totalOut>0) list.add({'i':Icons.trending_down_rounded,'c':FinanceV2Theme.warn,'t':'Dòng tiền ròng âm. Chi vượt thu.'});
    if(s.transactionCount==0) list.add({'i':Icons.info_outline_rounded,'c':FinanceV2Theme.subInk,'t':'Chưa có giao dịch trong khoảng thời gian này.'});
    if(list.isEmpty) return const SizedBox.shrink();
    return Padding(padding:const EdgeInsets.fromLTRB(12,0,12,12),child:Column(children:list.map((a){
      final c=a['c'] as Color;
      return Container(margin:const EdgeInsets.only(bottom:6),padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(color:c.withValues(alpha:0.08),borderRadius:BorderRadius.circular(10),border:Border.all(color:c.withValues(alpha:0.3))),
        child:Row(children:[Icon(a['i'] as IconData,color:c,size:18),const SizedBox(width:8),Expanded(child:Text(a['t'] as String,style:FinanceV2Theme.bodySm.copyWith(color:c)))]));
    }).toList()));
  }

  Widget _kpi(String lbl,int amt,int? prev,Color c,IconData icon,VoidCallback? tap,{bool signedValue=false}) {
    final chg=prev!=null&&prev>0?((amt-prev)/prev)*100.0:null;
    return GestureDetector(onTap:tap,child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:EdgeInsets.all(_cardPad),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(icon,size:16,color:c),const SizedBox(width:4),Expanded(child:Text(lbl,style:FinanceV2Theme.micro)),if(tap!=null) const Icon(Icons.chevron_right_rounded,size:14,color:FinanceV2Theme.subInk)]),
        const SizedBox(height:4),Text(signedValue?_signedCmp(amt):_cmp(amt),style:FinanceV2Theme.amountLg.copyWith(color:c)),
        if(chg!=null)...[const SizedBox(height:2),Row(children:[Icon(chg>=0?Icons.arrow_drop_up_rounded:Icons.arrow_drop_down_rounded,size:14,color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative),Text('${chg.abs().toStringAsFixed(0)}%',style:FinanceV2Theme.caption.copyWith(color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative))])],
      ])));
  }

  Widget _compSection(FinanceV2Snapshot s) {
    final chg=s.previousNetCashflow==0?null:((s.netCashflow-s.previousNetCashflow)/s.previousNetCashflow)*100.0;
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('So sánh $_compLabel',style:FinanceV2Theme.titleMd),
        const SizedBox(height:10),
        Row(children:[Expanded(child:_cs('Thu tiền',s.totalIn,s.previousTotalIn)),Expanded(child:_cs('Chi tiền',s.totalOut,s.previousTotalOut)),Expanded(child:_cs('Ròng',s.netCashflow,s.previousNetCashflow,net:true))]),
        if(chg!=null)...[const SizedBox(height:8),Row(children:[Icon(chg>=0?Icons.trending_up_rounded:Icons.trending_down_rounded,size:14,color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative),const SizedBox(width:4),Text('${chg>=0?"+":""}${chg.toStringAsFixed(1)}% so với $_compLabel',style:FinanceV2Theme.micro.copyWith(color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative))])],
        const Divider(height:20,thickness:0.5),
        Row(children:[
          Expanded(child:_cs('Vốn BH',s.cogsFromSales,s.previousCogsFromSales)),
          Expanded(child:_cs('Vốn SC',s.cogsFromRepairs,s.previousCogsFromRepairs)),
          Expanded(child:_cs('Vốn tổng',s.cogsFromSales+s.cogsFromRepairs,s.previousCogsFromSales+s.previousCogsFromRepairs)),
        ]),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:_cs('Lãi BH',s.grossProfitFromSales,s.previousGrossProfitFromSales,net:true)),
          Expanded(child:_cs('Lãi SC',s.grossProfitFromRepairs,s.previousGrossProfitFromRepairs,net:true)),
          Expanded(child:_cs('Lãi tổng',s.grossProfitTotal,s.previousGrossProfitFromSales+s.previousGrossProfitFromRepairs,net:true)),
        ]),
      ])));
  }

  Widget _cs(String lbl,int cur,int prev,{bool net=false}) {
    final chg=prev>0?((cur-prev)/prev*100.0):null;
    final tc=net?(cur>=0?FinanceV2Theme.positive:FinanceV2Theme.negative):FinanceV2Theme.ink;
    return Column(children:[
      Text(lbl,style:FinanceV2Theme.caption),
      const SizedBox(height:2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(net?_signedCmp(cur):_cmp(cur),style:FinanceV2Theme.amountMd.copyWith(color:tc)),
      ),
      if(chg!=null)
        Text('${chg>=0?"+":""}${chg.toStringAsFixed(0)}%',style:FinanceV2Theme.caption.copyWith(color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative))
      else
        Text('-',style:FinanceV2Theme.caption)
    ]);
  }

  Widget _profitSection(FinanceV2Snapshot s) {
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Vốn & Lãi',style:FinanceV2Theme.titleMd),
        const SizedBox(height:4),
        Text('Bán hàng tính theo ngày bán (accrual)',style:FinanceV2Theme.micro),
        const SizedBox(height:10),
        Row(children:[
          Expanded(child:_kpi('Vốn BH',s.cogsFromSales,s.previousCogsFromSales>0?s.previousCogsFromSales:null,const Color(0xFF1565C0),Icons.shopping_bag_outlined,null)),
          const SizedBox(width:8),
          Expanded(child:_kpi('Vốn SC',s.cogsFromRepairs,s.previousCogsFromRepairs>0?s.previousCogsFromRepairs:null,const Color(0xFF2E7D32),Icons.build_outlined,null)),
        ]),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:_kpi('Lãi BH',s.grossProfitFromSales,s.previousGrossProfitFromSales!=0?s.previousGrossProfitFromSales:null,s.grossProfitFromSales>=0?FinanceV2Theme.positive:FinanceV2Theme.negative,Icons.trending_up_rounded,null,signedValue:true)),
          const SizedBox(width:8),
          Expanded(child:_kpi('Lãi SC',s.grossProfitFromRepairs,s.previousGrossProfitFromRepairs!=0?s.previousGrossProfitFromRepairs:null,s.grossProfitFromRepairs>=0?FinanceV2Theme.positive:FinanceV2Theme.negative,Icons.trending_up_rounded,null,signedValue:true)),
        ]),
      ])));
  }

  Widget _incomeSection(FinanceV2Snapshot s) {
    if(s.totalIn==0) return const SizedBox.shrink();
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Cơ cấu doanh thu',style:FinanceV2Theme.titleMd),const SizedBox(height:10),
        if(s.incomeFromSales>0) _ir('Bán hàng',s.incomeFromSales,s.totalIn,const Color(0xFF1565C0),()=>_goTx('SALE')),
        if(s.incomeFromRepairs>0) _ir('Sửa chữa',s.incomeFromRepairs,s.totalIn,const Color(0xFF2E7D32),()=>_goTx('REPAIR')),
        if(s.incomeOther>0) _ir('Khác',s.incomeOther,s.totalIn,const Color(0xFF6A1B9A),()=>_goTx('IN')),
      ])));
  }

  Widget _ir(String lbl,int amt,int tot,Color c,VoidCallback tap) {
    final r=tot>0?amt/tot:0.0;
    return GestureDetector(onTap:tap,child:Padding(padding:const EdgeInsets.only(bottom:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Container(width:8,height:8,decoration:BoxDecoration(color:c,shape:BoxShape.circle)),const SizedBox(width:6),Expanded(child:Text(lbl,style:FinanceV2Theme.bodySm)),Text(_cmp(amt),style:FinanceV2Theme.bodySm.copyWith(fontWeight:FontWeight.w600,color:c)),const SizedBox(width:4),Text('${(r*100).toStringAsFixed(0)}%',style:FinanceV2Theme.caption),const SizedBox(width:4),const Icon(Icons.chevron_right_rounded,size:14,color:FinanceV2Theme.subInk)]),
      const SizedBox(height:4),ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:r.clamp(0.0,1.0),minHeight:4,backgroundColor:c.withValues(alpha:0.1),valueColor:AlwaysStoppedAnimation(c))),
    ])));
  }

  Widget _cfSection(FinanceV2Snapshot s) {
    final tot=s.totalIn+s.totalOut;
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Dòng tiền',style:FinanceV2Theme.titleMd),const SizedBox(height:10),
        if(tot==0) Text('Chưa có giao dịch trong kỳ',style:FinanceV2Theme.bodySm.copyWith(color:FinanceV2Theme.subInk)) else _cfBar(s),
      ])));
  }

  Widget _cfBar(FinanceV2Snapshot s) {
    final tot=s.totalIn+s.totalOut; final inR=tot>0?s.totalIn/tot:0.5;
    final inF=(inR*100).round().clamp(1,99); final outF=(100-inF).clamp(1,99);
    return Column(children:[
      ClipRRect(borderRadius:BorderRadius.circular(8),child:Row(children:[
        Expanded(flex:inF,child:GestureDetector(onTap:()=>_goTx('IN'),child:Container(height:32,color:FinanceV2Theme.positive,alignment:Alignment.center,child:inF>15?Text(_cmp(s.totalIn),style:FinanceV2Theme.caption.copyWith(color:Colors.white,fontWeight:FontWeight.w600)):null))),
        Expanded(flex:outF,child:GestureDetector(onTap:()=>_goTx('OUT'),child:Container(height:32,color:FinanceV2Theme.negative,alignment:Alignment.center,child:outF>15?Text(_cmp(s.totalOut),style:FinanceV2Theme.caption.copyWith(color:Colors.white,fontWeight:FontWeight.w600)):null))),
      ])),
      const SizedBox(height:6),
      Row(children:[_dot(FinanceV2Theme.positive),const SizedBox(width:4),Text('Tiền vào',style:FinanceV2Theme.caption),const SizedBox(width:12),_dot(FinanceV2Theme.negative),const SizedBox(width:4),Text('Tiền ra',style:FinanceV2Theme.caption)]),
    ]);
  }

  Widget _debtSection(FinanceV2Snapshot s) {
    if(s.receivableTotal==0&&s.payableTotal==0) return const SizedBox.shrink();
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Công nợ tổng quan',style:FinanceV2Theme.titleMd),const SizedBox(height:10),
        Row(children:[
          if(s.receivableTotal>0) Expanded(child:_dTile('Phải thu',s.receivableTotal,FinanceV2Theme.warn,()=>_goDebt(true))),
          if(s.receivableTotal>0&&s.payableTotal>0) const SizedBox(width:8),
          if(s.payableTotal>0) Expanded(child:_dTile('Phải trả',s.payableTotal,FinanceV2Theme.negative,()=>_goDebt(false))),
        ]),
      ])));
  }

  Widget _dTile(String lbl,int amt,Color c,VoidCallback tap) => GestureDetector(onTap:tap,child:Container(
    padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:c.withValues(alpha:0.08),borderRadius:BorderRadius.circular(12),border:Border.all(color:c.withValues(alpha:0.3))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(lbl,style:FinanceV2Theme.micro.copyWith(color:c)),const SizedBox(height:4),Text(_cmp(amt),style:FinanceV2Theme.amountLg.copyWith(color:c)),const Row(children:[Text('Xem chi tiết',style:FinanceV2Theme.caption),Icon(Icons.chevron_right_rounded,size:12,color:FinanceV2Theme.subInk)])])));

  Widget _expCatSection(FinanceV2Snapshot s) {
    if(s.topExpenseCategories.isEmpty) return const SizedBox.shrink();
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Chi tiêu theo danh mục',style:FinanceV2Theme.titleMd),const SizedBox(height:10),
        ...s.topExpenseCategories.map((cat){
          final r=s.totalOut>0?cat.amount/s.totalOut:0.0;
          return Padding(padding:const EdgeInsets.only(bottom:8),child:Column(children:[
            Row(children:[Expanded(child:Text(cat.label,style:FinanceV2Theme.bodySm,maxLines:1,overflow:TextOverflow.ellipsis)),Text(_cmp(cat.amount),style:FinanceV2Theme.bodySm.copyWith(fontWeight:FontWeight.w600,color:FinanceV2Theme.negative)),const SizedBox(width:4),Text('${(r*100).toStringAsFixed(0)}%',style:FinanceV2Theme.caption)]),
            const SizedBox(height:4),ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:r.clamp(0.0,1.0),minHeight:4,backgroundColor:FinanceV2Theme.negative.withValues(alpha:0.1),valueColor:const AlwaysStoppedAnimation(FinanceV2Theme.negative))),
          ]));
        }),
      ])));
  }

  Widget _snapCard(FinanceV2Snapshot s) {
    final txt='Kỳ: $_sub';
    return Padding(padding:EdgeInsets.symmetric(horizontal:_hPad),child:Container(
      decoration:FinanceV2Theme.elevatedPanel(color:const Color(0xFFF8F9FA)),padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.summarize_rounded,size:16,color:FinanceV2Theme.accent),const SizedBox(width:6),Text('Tóm tắt kỳ',style:FinanceV2Theme.titleMd),const Spacer(),IconButton(icon:const Icon(Icons.copy_rounded,size:18,color:FinanceV2Theme.accent),tooltip:'Sao chép',onPressed:(){Clipboard.setData(ClipboardData(text:txt));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đã sao chép tóm tắt'),duration:Duration(seconds:2)));})]),
        const SizedBox(height:6),Text(txt,style:FinanceV2Theme.mono),
      ])));
  }
  // TAB 1
  Widget _t1() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    var tx=s.transactions.toList();
    if(_txFilter=='IN') {
      tx=tx.where((t)=>t.isIncome).toList();
    }
    else if(_txFilter=='OUT') {
      tx=tx.where((t)=>!t.isIncome).toList();
    }
    else if(_txFilter!='ALL') {
      tx=tx.where((t)=>t.type==_txFilter).toList();
    }
    if(_txPm.isNotEmpty) tx=tx.where((t)=>(t.paymentMethod??'')==_txPm).toList();
    if(_txQuery.isNotEmpty){final q=_txQuery.toLowerCase();tx=tx.where((t)=>t.title.toLowerCase().contains(q)||t.subtitle.toLowerCase().contains(q)||(t.actorName??'').toLowerCase().contains(q)).toList();}
    final txPageMax = _maxPage(tx.length, _txPageSize);
    final txPageNow = _txPage.clamp(1, txPageMax);
    final txView = _slicePage(tx, txPageNow, _txPageSize);
    return ResponsiveCenter(child:Column(children:[
      Container(color:Colors.white,padding:EdgeInsets.fromLTRB(_hPad,6,_hPad,0),child:_sf(_txCtrl,'Tìm giao dịch...',_txQuery,(){_txCtrl.clear();setState(()=>_txQuery='');})),
      Container(
        color: const Color(0xFFF8F9FA),
        padding: EdgeInsets.fromLTRB(_hPad, 6, _hPad, 6),
        child: Row(children:[
          Expanded(
            child: Text(
              '${tx.length} giao dịch • Trang $txPageNow/$txPageMax • Loại: ${_txFilter == 'ALL' ? 'Tất cả' : _ft(_txFilter)}${_txPm.isNotEmpty ? ' • TT: $_txPm' : ''}',
              style: FinanceV2Theme.meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exTx(tx)),
        ]),
      ),
      Container(height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:tx.isEmpty?_empty('Không có giao dịch phù hợp'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:txView.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_txRow(txView[i]))),
      _pager(total: tx.length, page: txPageNow, pageSize: _txPageSize, unit: 'giao dịch', onChanged: (p){setState(()=>_txPage=p);}),
    ]));
  }

  Widget _txRow(FinanceV2Txn t) {
    final dt=DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.createdAt));
    final c=t.isIncome?FinanceV2Theme.positive:FinanceV2Theme.negative;
    final detailParts = <String>[];
    if ((t.paymentMethod ?? '').isNotEmpty) {
      detailParts.add(t.paymentMethod!);
    }
    if ((t.actorName ?? '').isNotEmpty) {
      detailParts.add('NV: ${t.actorName!}');
    }
    if ((t.referenceId ?? '').isNotEmpty) {
      final ref = t.referenceId!.trim();
      detailParts.add(ref.length > 10 ? 'Mã: ${ref.substring(0, 10)}' : 'Mã: $ref');
    }
    return ListTile(
      leading:EntityAvatar(imageUrl:t.avatarUrl,name:t.title,radius:20,tappableToView:false),
      title:Text(t.title,style:FinanceV2Theme.bodyMd,maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text(t.subtitle,style:FinanceV2Theme.micro,maxLines:1,overflow:TextOverflow.ellipsis),
          if(detailParts.isNotEmpty)
            Text(
              detailParts.join(' • '),
              style:FinanceV2Theme.caption,
              maxLines:1,
              overflow:TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisAlignment:MainAxisAlignment.center,children:[Text('${t.isIncome?"+":"-"}${_cmp(t.amount)}',style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:c)),Text(dt,style:FinanceV2Theme.caption)]),
      onTap:()=>_openTL(_TLEntry(ts:t.createdAt,type:t.type,title:t.title,subtitle:t.subtitle,amount:t.amount,isIncome:t.isIncome,avatarUrl:t.avatarUrl,actorName:t.actorName,paymentMethod:t.paymentMethod,referenceId:t.referenceId)),
    );
  }

  // TAB 2
  Widget _t2() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    final items=_showRec?s.receivables:s.payables;
    final debtPageMax = _maxPage(items.length, _debtPageSize);
    final debtPageNow = _debtPage.clamp(1, debtPageMax);
    final debtView = _slicePage(items, debtPageNow, _debtPageSize);
    final total=_showRec?s.receivableTotal:s.payableTotal;
    return ResponsiveCenter(child:Column(children:[
      Container(color:Colors.white,padding:EdgeInsets.fromLTRB(_hPad,8,_hPad,8),child:Row(children:[
        Expanded(child:GestureDetector(onTap:()=>setState((){_showRec=true;_debtPage=1;}),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:9,horizontal:8),decoration:BoxDecoration(color:_showRec?FinanceV2Theme.warn:const Color(0xFFF0F3F9),borderRadius:BorderRadius.circular(10)),alignment:Alignment.center,child:Text('Phải thu  ${_cmp(s.receivableTotal)}',maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:_showRec?Colors.white:FinanceV2Theme.subInk))))),
        const SizedBox(width:8),
        Expanded(child:GestureDetector(onTap:()=>setState((){_showRec=false;_debtPage=1;}),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:9,horizontal:8),decoration:BoxDecoration(color:!_showRec?FinanceV2Theme.negative:const Color(0xFFF0F3F9),borderRadius:BorderRadius.circular(10)),alignment:Alignment.center,child:Text('Phải trả  ${_cmp(s.payableTotal)}',maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:!_showRec?Colors.white:FinanceV2Theme.subInk))))),
      ])),
      if(_showRec&&s.totalDebtAging>0) Container(color:Colors.white,padding:const EdgeInsets.fromLTRB(12,0,12,10),child:Row(children:[
        Expanded(child:_aging('0-30 ngày',s.debtAging['0-30']??0,FinanceV2Theme.positive)),const SizedBox(width:6),
        Expanded(child:_aging('31-60 ngày',s.debtAging['30-60']??0,FinanceV2Theme.warn)),const SizedBox(width:6),
        Expanded(child:_aging('>60 ngày',s.debtAging['>60']??0,FinanceV2Theme.negative)),
      ])),
      Container(color:const Color(0xFFF8F9FA),padding:EdgeInsets.fromLTRB(_hPad,6,_hPad,6),child:Row(children:[Expanded(child:Text('${items.length} khoản • Trang $debtPageNow/$debtPageMax · Tổng: ${_full(total)}',style:FinanceV2Theme.meta,maxLines:2,overflow:TextOverflow.ellipsis)),IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exDebt(items))])),
      Container(height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:items.isEmpty?_empty(_showRec?'Không có khoản phải thu':'Không có khoản phải trả'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:debtView.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_debtRow(debtView[i]))),
      _pager(total: items.length, page: debtPageNow, pageSize: _debtPageSize, unit: 'khoản', onChanged: (p){setState(()=>_debtPage=p);}),
    ]));
  }

  Widget _debtRow(FinanceV2DebtItem d) {
    final pct=d.total>0?d.paid/d.total:0.0;
    final age=DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(d.createdAt)).inDays;
    return ListTile(
      leading:EntityAvatar(imageUrl:d.avatarUrl,name:d.name,radius:20,tappableToView:false),
      title:Text(d.name,style:FinanceV2Theme.bodyMd,maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Còn lại: ${_cmp(d.remaining)} . $age ngày',style:FinanceV2Theme.micro),const SizedBox(height:3),ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:pct.clamp(0.0,1.0),minHeight:4,backgroundColor:const Color(0xFFEEF1F7),valueColor:AlwaysStoppedAnimation(_showRec?FinanceV2Theme.warn:FinanceV2Theme.negative)))]),
      trailing:Text(_cmp(d.remaining),style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w700,color:_showRec?FinanceV2Theme.warn:FinanceV2Theme.negative)),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const DebtView())),
    );
  }

  Widget _aging(String lbl,int amt,Color c) => Container(
    padding:const EdgeInsets.symmetric(vertical:8,horizontal:6),
    decoration:BoxDecoration(color:c.withValues(alpha:0.07),borderRadius:BorderRadius.circular(8),border:Border.all(color:c.withValues(alpha:0.3))),
    child:Column(children:[Text(lbl,style:FinanceV2Theme.micro.copyWith(color:c),textAlign:TextAlign.center),const SizedBox(height:2),Text(_cmp(amt),style:FinanceV2Theme.bodySm.copyWith(fontWeight:FontWeight.w700,color:c))]));

  // TAB 4
  Widget _t4() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    final all=_timelineCache;
    var ents=all;
    if(_tlSrc!='ALL'){ents=ents.where((e){if(_tlSrc=='TRANSACTION') return ['SALE','REPAIR','EXPENSE','INCOME','DEBT_COLLECT','DEBT_PAY'].contains(e.type);if(_tlSrc=='DEBT') return e.type=='DEBT_COLLECT'||e.type=='DEBT_PAY';if(_tlSrc=='AUDIT') return e.type=='AUDIT';return true;}).toList();}
    if(_tlDir=='IN') {
      ents=ents.where((e)=>e.isIncome).toList();
    }
    else if(_tlDir=='OUT') {
      ents=ents.where((e)=>!e.isIncome).toList();
    }
    if(_tlHigh) ents=ents.where((e)=>e.amount>=1000000).toList();
    if(_tlActor.isNotEmpty) ents=ents.where((e)=>e.actorName==_tlActor).toList();
    if(_tlPm.isNotEmpty) ents=ents.where((e)=>e.paymentMethod==_tlPm).toList();
    if(_tlQ.isNotEmpty){final q=_tlQ.toLowerCase();ents=ents.where((e)=>e.title.toLowerCase().contains(q)||e.subtitle.toLowerCase().contains(q)||(e.actorName??'').toLowerCase().contains(q)).toList();}
    final timelinePageMax = _maxPage(ents.length, _timelinePageSize);
    final timelinePageNow = _timelinePage.clamp(1, timelinePageMax);
    final timelineView = _slicePage(ents, timelinePageNow, _timelinePageSize);
    return ResponsiveCenter(child:Column(children:[
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(_hPad, 6, _hPad, 0),
        child: _sf(_tlCtrl,'Tìm trong nhật ký...',_tlQ,(){_tlCtrl.clear();setState(()=>_tlQ='');}),
      ),
      Container(
        color: const Color(0xFFF8F9FA),
        padding: EdgeInsets.fromLTRB(_hPad, 6, _hPad, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${ents.length} mục • Trang $timelinePageNow/$timelinePageMax • Nguồn: ${_tlSrc == 'ALL' ? 'Tất cả' : _ft(_tlSrc)} • Hướng: ${_tlDir == 'ALL' ? 'Tất cả' : (_tlDir == 'IN' ? 'Thu vào' : 'Chi ra')}',
                style: FinanceV2Theme.meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exTL(ents)),
          ],
        ),
      ),
      Container(height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:ents.isEmpty?_empty('Không có nhật ký phù hợp'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:timelineView.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_tlRow(timelineView[i]))),
      _pager(total: ents.length, page: timelinePageNow, pageSize: _timelinePageSize, unit: 'mục', onChanged: (p){setState(()=>_timelinePage=p);}),
    ]));
  }

  List<_TLEntry> _timeline(FinanceV2Snapshot s) {
    final ents=<_TLEntry>[];
    for(final t in s.transactions) {
      ents.add(_TLEntry(ts:t.createdAt,type:t.type,title:t.title,subtitle:t.subtitle,amount:t.amount,isIncome:t.isIncome,avatarUrl:t.avatarUrl,actorName:t.actorName,paymentMethod:t.paymentMethod,referenceId:t.referenceId));
    }
    for(final log in s.auditLogs){
      final ts=_ti(log['createdAt']);final ac=(log['action']??'').toString();final actor=(log['createdBy']??log['actorName']??'').toString();final ref=(log['referenceId']??log['firestoreId']??'').toString();
      final title = _fa(ac).trim();
      if (title.isEmpty) continue;
      ents.add(_TLEntry(ts:ts,type:'AUDIT',title:title,subtitle:'',amount:_ti(log['amount']),isIncome:false,actorName:actor.isNotEmpty?actor:null,referenceId:ref.isNotEmpty?ref:null));
    }
    ents.sort((a,b)=>b.ts.compareTo(a.ts)); return ents;
  }

  Widget _tlRow(_TLEntry e) {
    final dt=DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.ts));
    final isA=e.type=='AUDIT';
    return ListTile(
      leading:isA?CircleAvatar(radius:20,backgroundColor:FinanceV2Theme.accent.withValues(alpha:0.1),child:const Icon(Icons.history_rounded,size:18,color:FinanceV2Theme.accent)):EntityAvatar(imageUrl:e.avatarUrl,name:e.title,radius:20,tappableToView:false),
      title:Row(children:[Expanded(child:Text(e.title,style:FinanceV2Theme.bodyMd,maxLines:1,overflow:TextOverflow.ellipsis)),if(!isA) _tag(e.type)]),
      subtitle:(e.subtitle.trim().isEmpty && (isA || e.actorName==null))
          ? null
          : Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                if(e.subtitle.trim().isNotEmpty)
                  Text(e.subtitle,style:FinanceV2Theme.micro,maxLines:1,overflow:TextOverflow.ellipsis),
                if(e.actorName!=null&&!isA)
                  Text(e.actorName!,style:FinanceV2Theme.caption),
              ],
            ),
      trailing:Column(crossAxisAlignment:CrossAxisAlignment.end,mainAxisAlignment:MainAxisAlignment.center,children:[if(!isA&&e.amount>0)Text('${e.isIncome?"+":"-"}${_cmp(e.amount)}',style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:e.isIncome?FinanceV2Theme.positive:FinanceV2Theme.negative)),Text(dt,style:FinanceV2Theme.caption)]),
      onTap:isA?null:()=>_openTL(e),
    );
  }

  static const List<String> _auditLogHeaders = <String>[
    'timestamp',
    'action_type',
    'module',
    'reference_id',
    'product_name',
    'imei',
    'quantity',
    'price',
    'cost',
    'cash_in',
    'cash_out',
    'transfer_in',
    'transfer_out',
    'payment_method',
    'debt_customer_change',
    'debt_supplier_change',
    'inventory_change',
    'actor_name',
    'description',
  ];

  String _auditPaymentMethod(String? method) {
    final normalized = (method ?? '').trim().toUpperCase();
    if (normalized.contains('TIỀN MẶT')) return 'CASH';
    if (normalized.contains('CHUYỂN')) return 'TRANSFER';
    if (normalized.contains('CÔNG NỢ')) return 'DEBT';
    if (normalized.contains('KẾT HỢP')) return 'MIXED';
    if (normalized.contains('TRẢ GÓP')) return 'INSTALLMENT';
    return normalized;
  }

  String _auditModule(String actionType) {
    switch (actionType) {
      case 'IMPORT':
      case 'ADJUST':
        return 'kho';
      case 'SALE':
      case 'RETURN':
        return 'bán hàng';
      case 'REPAIR':
        return 'sửa chữa';
      default:
        return 'tài chính';
    }
  }

  bool _isImportExpense(Map<String, dynamic> expense) {
    final title = (expense['title'] ?? '').toString().toUpperCase();
    final category = (expense['category'] ?? '').toString().toUpperCase();
    return category.contains('NHẬP') ||
        category.contains('LINH KIỆN') ||
        title.contains('NHẬP') ||
        category.contains('PURCHASE');
  }

  bool _isSalvageExpense(Map<String, dynamic> expense) {
    final title = (expense['title'] ?? '').toString().toUpperCase();
    final category = (expense['category'] ?? '').toString().toUpperCase();
    return title.contains('MÁY XÁC') || category.contains('MÁY XÁC');
  }

  String _cleanSaleName(String input) {
    var value = input.trim();
    final qtyMatch = RegExp(r'^(.+?)\s+[xX]\d+').firstMatch(value);
    if (qtyMatch != null) {
      value = qtyMatch.group(1)!.trim();
    }
    value = value.replaceAll(RegExp(r'\s*\(TẶNG\)\s*$', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\s*\(GIẢM\s+[\d,.]+\)\s*$', caseSensitive: false), '');
    return value.trim();
  }

  Future<List<Map<String, dynamic>>> _saleAuditLines(SaleOrder sale) async {
    final names = sale.productNames.split(RegExp(r',\s*'));
    final imeis = sale.productImeis.split(RegExp(r',\s*'));
    final lines = <Map<String, dynamic>>[];
    int totalQty = 0;

    for (int i = 0; i < names.length; i++) {
      final rawName = names[i].trim();
      if (rawName.isEmpty) continue;
      final imei = i < imeis.length ? imeis[i].trim() : '';
      int qty = 1;
      final qtyMatch = RegExp(r'^(.+?)\s+[xX](\d+)').firstMatch(rawName);
      if (qtyMatch != null) {
        qty = int.tryParse(qtyMatch.group(2)!) ?? 1;
      }
      if (imei.toUpperCase().startsWith('PKX')) {
        qty = int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? qty;
      }
      final cleanName = _cleanSaleName(rawName);
      lines.add({
        'product_name': cleanName,
        'imei': imei,
        'quantity': qty,
        'reference_price': 0,
        'reference_cost': 0,
      });
      totalQty += qty;
    }

    for (final line in lines) {
      Product? product;
      final imei = (line['imei'] ?? '').toString();
      if (imei.isNotEmpty && !imei.toUpperCase().startsWith('PKX') && imei != 'NO_IMEI') {
        product = await _db.getProductByImei(imei);
      }
      product ??= await _db.getProductByName((line['product_name'] ?? '').toString());
      product ??= await _db.getProductByNameFlexible((line['product_name'] ?? '').toString());
      if (product != null) {
        line['reference_price'] = product.price;
        line['reference_cost'] = product.cost;
      }
    }

    int totalWeightPrice = 0;
    int totalWeightCost = 0;
    for (final line in lines) {
      final qty = (line['quantity'] as int?) ?? 1;
      final refPrice = ((line['reference_price'] as int?) ?? 0) > 0 ? (line['reference_price'] as int) : 1;
      final refCost = ((line['reference_cost'] as int?) ?? 0) > 0 ? (line['reference_cost'] as int) : 1;
      totalWeightPrice += refPrice * qty;
      totalWeightCost += refCost * qty;
    }

    int distributedPrice = 0;
    int distributedCost = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final qty = (line['quantity'] as int?) ?? 1;
      final refPrice = ((line['reference_price'] as int?) ?? 0) > 0 ? (line['reference_price'] as int) : 1;
      final refCost = ((line['reference_cost'] as int?) ?? 0) > 0 ? (line['reference_cost'] as int) : 1;

      int linePrice;
      int lineCost;
      if (i == lines.length - 1) {
        linePrice = sale.finalPrice - distributedPrice;
        lineCost = sale.totalCost - distributedCost;
      } else {
        linePrice = (sale.finalPrice * (refPrice * qty) / (totalWeightPrice == 0 ? totalQty : totalWeightPrice)).round();
        lineCost = (sale.totalCost * (refCost * qty) / (totalWeightCost == 0 ? totalQty : totalWeightCost)).round();
      }
      distributedPrice += linePrice;
      distributedCost += lineCost;
      line['price'] = qty > 0 ? (linePrice / qty).round() : 0;
      line['cost'] = qty > 0 ? (lineCost / qty).round() : 0;
    }

    return lines;
  }

  List<dynamic> _auditRow({
    required int timestamp,
    required String actionType,
    required String referenceId,
    String productName = '',
    String imei = '',
    int quantity = 0,
    int price = 0,
    int cost = 0,
    int cashIn = 0,
    int cashOut = 0,
    int transferIn = 0,
    int transferOut = 0,
    String paymentMethod = '',
    int debtCustomerChange = 0,
    int debtSupplierChange = 0,
    int inventoryChange = 0,
    String actorName = '',
    String description = '',
  }) {
    return <dynamic>[
      FinanceV2ExcelExport.fmtDateTime(timestamp),
      actionType,
      _auditModule(actionType),
      referenceId,
      productName,
      imei,
      quantity,
      price,
      cost,
      cashIn,
      cashOut,
      transferIn,
      transferOut,
      paymentMethod,
      debtCustomerChange,
      debtSupplierChange,
      inventoryChange,
      actorName,
      description,
    ];
  }

  Future<List<List<dynamic>>> _buildDetailedAuditLogRows() async {
    final startMs = _start.millisecondsSinceEpoch;
    final endMs = DateTime(_end.year, _end.month, _end.day, 23, 59, 59).millisecondsSinceEpoch;
    final sales = await _db.getSalesByDateRange(startMs, endMs);
    final repairs = await _db.getDeliveredRepairsByDateRange(startMs, endMs);
    final expenses = await _db.getExpensesByDateRange(startMs, endMs);
    final debtPayments = await _db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs);
    final salesReturns = await _db.getSalesReturnsByDateRange(startMs, endMs);
    final importHistory = await _db.getAllImportHistoryByDateRange(startMs, endMs);

    final rowsWithTs = <Map<String, dynamic>>[];

    for (final sale in sales) {
      final lines = await _saleAuditLines(sale);
      final method = _auditPaymentMethod(sale.paymentMethod);
      for (final line in lines) {
        final qty = (line['quantity'] as int?) ?? 0;
        final unitPrice = (line['price'] as int?) ?? 0;
        final lineAmount = unitPrice * qty;
        final lineCost = ((line['cost'] as int?) ?? 0);
        int cashIn = 0;
        int transferIn = 0;
        int debtCustomerChange = 0;
        if (method == 'CASH') {
          cashIn = lineAmount;
        } else if (method == 'TRANSFER') {
          transferIn = lineAmount;
        } else if (method == 'MIXED') {
          final total = sale.finalPrice <= 0 ? 1 : sale.finalPrice;
          cashIn = ((lineAmount * sale.cashAmount) / total).round();
          transferIn = lineAmount - cashIn;
        } else if (method == 'DEBT') {
          debtCustomerChange = lineAmount;
        }
        rowsWithTs.add({
          'ts': sale.soldAt,
          'row': _auditRow(
            timestamp: sale.soldAt,
            actionType: 'SALE',
            referenceId: sale.firestoreId ?? (sale.id?.toString() ?? ''),
            productName: (line['product_name'] ?? '').toString(),
            imei: (line['imei'] ?? '').toString(),
            quantity: qty,
            price: unitPrice,
            cost: lineCost,
            cashIn: cashIn,
            transferIn: transferIn,
            paymentMethod: method,
            debtCustomerChange: debtCustomerChange,
            inventoryChange: -qty,
            actorName: sale.sellerName,
            description: 'Bán hàng cho ${sale.customerName}',
          ),
        });
      }
    }

    for (final ret in salesReturns) {
      final salesReturnId = (ret['id'] as num?)?.toInt();
      if (salesReturnId == null) continue;
      final items = await _db.getSalesReturnItems(salesReturnId);
      final method = _auditPaymentMethod((ret['refundMethod'] ?? '').toString());
      final ts = (ret['returnDate'] as num?)?.toInt() ?? (ret['createdAt'] as num?)?.toInt() ?? 0;
      final ref = (ret['firestoreId'] ?? ret['id'] ?? '').toString();
      final customer = (ret['customerName'] ?? '').toString();
      final note = (ret['note'] ?? '').toString();
      for (final item in items) {
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final unitPrice = (item['price'] as num?)?.toInt() ?? 0;
        final unitCost = (item['cost'] as num?)?.toInt() ?? 0;
        final amount = (item['amount'] as num?)?.toInt() ?? unitPrice * qty;
        int cashOut = 0;
        int transferOut = 0;
        int debtCustomerChange = 0;
        if (method == 'CASH') {
          cashOut = amount;
        } else if (method == 'TRANSFER') {
          transferOut = amount;
        } else if (method == 'DEBT') {
          debtCustomerChange = -amount;
        }
        rowsWithTs.add({
          'ts': ts,
          'row': _auditRow(
            timestamp: ts,
            actionType: 'RETURN',
            referenceId: ref,
            productName: (item['productName'] ?? '').toString(),
            imei: (item['productImei'] ?? '').toString(),
            quantity: qty,
            price: unitPrice,
            cost: unitCost,
            cashOut: cashOut,
            transferOut: transferOut,
            paymentMethod: method,
            debtCustomerChange: debtCustomerChange,
            inventoryChange: qty,
            actorName: (ret['createdBy'] ?? '').toString(),
            description: 'Trả hàng ${note.isNotEmpty ? '- $note' : ''} | KH: $customer',
          ),
        });
      }
    }

    for (final repair in repairs) {
      final method = _auditPaymentMethod(repair.paymentMethod);
      int cashIn = 0;
      int transferIn = 0;
      int debtCustomerChange = 0;
      if (method == 'CASH') {
        cashIn = repair.price;
      } else if (method == 'TRANSFER') {
        transferIn = repair.price;
      } else if (method == 'DEBT') {
        debtCustomerChange = repair.price;
      }
      rowsWithTs.add({
        'ts': repair.deliveredAt ?? repair.createdAt,
        'row': _auditRow(
          timestamp: repair.deliveredAt ?? repair.createdAt,
          actionType: 'REPAIR',
          referenceId: repair.firestoreId ?? (repair.id?.toString() ?? ''),
          productName: repair.model,
          quantity: 1,
          price: repair.price,
          cost: repair.totalCost,
          cashIn: cashIn,
          transferIn: transferIn,
          paymentMethod: method,
          debtCustomerChange: debtCustomerChange,
          actorName: (repair.repairedBy ?? repair.createdBy ?? '').trim(),
          description: 'Sửa chữa: ${repair.issue}',
        ),
      });
    }

    for (final item in importHistory) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final costPrice = (item['costPrice'] as num?)?.toInt() ?? 0;
      final totalAmount = (item['totalAmount'] as num?)?.toInt() ?? costPrice * qty;
      final method = _auditPaymentMethod((item['paymentMethod'] ?? '').toString());
      int cashOut = 0;
      int transferOut = 0;
      int debtSupplierChange = 0;
      if (method == 'CASH') {
        cashOut = totalAmount;
      } else if (method == 'TRANSFER') {
        transferOut = totalAmount;
      } else if (method == 'DEBT') {
        debtSupplierChange = totalAmount;
      }
      rowsWithTs.add({
        'ts': (item['importDate'] as num?)?.toInt() ?? (item['createdAt'] as num?)?.toInt() ?? 0,
        'row': _auditRow(
          timestamp: (item['importDate'] as num?)?.toInt() ?? (item['createdAt'] as num?)?.toInt() ?? 0,
          actionType: 'IMPORT',
          referenceId: (item['referenceId'] ?? item['firestoreId'] ?? item['id'] ?? '').toString(),
          productName: (item['productName'] ?? '').toString(),
          imei: (item['imei'] ?? '').toString(),
          quantity: qty,
          price: 0,
          cost: costPrice,
          cashOut: cashOut,
          transferOut: transferOut,
          paymentMethod: method,
          debtSupplierChange: debtSupplierChange,
          inventoryChange: qty,
          actorName: (item['importedBy'] ?? '').toString(),
          description: 'Nhập kho từ ${item['supplierName'] ?? 'NCC'}',
        ),
      });
    }

    for (final expense in expenses) {
      final type = (expense['type'] ?? 'CHI').toString().toUpperCase();
      if (_isImportExpense(expense) && !_isSalvageExpense(expense)) {
        continue;
      }
      final method = _auditPaymentMethod((expense['paymentMethod'] ?? '').toString());
      final amount = (expense['amount'] as num?)?.toInt() ?? 0;
      int cashIn = 0;
      int cashOut = 0;
      int transferIn = 0;
      int transferOut = 0;
      if (type == 'THU') {
        if (method == 'CASH') {
          cashIn = amount;
        } else {
          transferIn = amount;
        }
      } else {
        if (method == 'CASH') {
          cashOut = amount;
        } else {
          transferOut = amount;
        }
      }
      final actionType = type == 'THU'
          ? 'PAYMENT'
          : (_isSalvageExpense(expense) ? 'IMPORT' : 'EXPENSE');
      rowsWithTs.add({
        'ts': (expense['date'] as num?)?.toInt() ?? (expense['createdAt'] as num?)?.toInt() ?? 0,
        'row': _auditRow(
          timestamp: (expense['date'] as num?)?.toInt() ?? (expense['createdAt'] as num?)?.toInt() ?? 0,
          actionType: actionType,
          referenceId: (expense['firestoreId'] ?? expense['id'] ?? '').toString(),
          productName: _isSalvageExpense(expense) ? (expense['title'] ?? '').toString() : '',
          quantity: _isSalvageExpense(expense) ? 1 : 0,
          cost: _isSalvageExpense(expense) ? amount : 0,
          cashIn: cashIn,
          cashOut: cashOut,
          transferIn: transferIn,
          transferOut: transferOut,
          paymentMethod: method,
          inventoryChange: _isSalvageExpense(expense) ? 1 : 0,
          actorName: (expense['createdBy'] ?? '').toString(),
          description: ((expense['title'] ?? '').toString().isNotEmpty ? expense['title'] : expense['category']).toString(),
        ),
      });
    }

    for (final payment in debtPayments) {
      final amount = (payment['amount'] as num?)?.toInt() ?? 0;
      final method = _auditPaymentMethod((payment['paymentMethod'] ?? '').toString());
      final debtType = (payment['resolvedDebtType'] ?? payment['debtType'] ?? '').toString().toUpperCase();
      final isSupplier = debtType == 'SHOP_OWES' || debtType == 'OTHER_SHOP_OWES' || debtType == 'OWED';
      int cashIn = 0;
      int cashOut = 0;
      int transferIn = 0;
      int transferOut = 0;
      if (method == 'CASH') {
        if (isSupplier) {
          cashOut = amount;
        } else {
          cashIn = amount;
        }
      } else {
        if (isSupplier) {
          transferOut = amount;
        } else {
          transferIn = amount;
        }
      }
      rowsWithTs.add({
        'ts': (payment['paidAt'] as num?)?.toInt() ?? 0,
        'row': _auditRow(
          timestamp: (payment['paidAt'] as num?)?.toInt() ?? 0,
          actionType: 'PAYMENT',
          referenceId: (payment['firestoreId'] ?? payment['id'] ?? '').toString(),
          cashIn: cashIn,
          cashOut: cashOut,
          transferIn: transferIn,
          transferOut: transferOut,
          paymentMethod: method,
          debtCustomerChange: isSupplier ? 0 : -amount,
          debtSupplierChange: isSupplier ? -amount : 0,
          description: isSupplier
              ? 'Trả nợ ${payment['debtPersonName'] ?? ''}'
              : 'Thu nợ ${payment['debtPersonName'] ?? ''}',
        ),
      });
    }

    rowsWithTs.sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    return rowsWithTs.map((e) => e['row'] as List<dynamic>).toList();
  }

  // EXPORT
  Future<void> _exOverview(FinanceV2Snapshot s, {bool silent = false}) async {
    if (!mounted) return;
    await FinanceV2ExcelExport.exportTable(
      context,
      sheetName: 'Tổng quan',
      filePrefix: 'tong_quan',
      headers: const ['Chỉ số', 'Giá trị'],
      rows: [
        ['Tiền vào', s.totalIn],
        ['Tiền ra', s.totalOut],
        ['Dòng tiền ròng', s.netCashflow],
        ['Số giao dịch', s.transactionCount],
        ['Doanh thu bán hàng', s.incomeFromSales],
        ['Doanh thu sửa chữa', s.incomeFromRepairs],
        ['Thu khác', s.incomeOther],
        ['Vốn bán hàng', s.cogsFromSales],
        ['Vốn sửa chữa', s.cogsFromRepairs],
        ['Lãi gộp bán hàng', s.grossProfitFromSales],
        ['Lãi gộp sửa chữa', s.grossProfitFromRepairs],
        ['Tổng lãi gộp', s.grossProfitTotal],
        ['Phải thu', s.receivableTotal],
        ['Phải trả', s.payableTotal],
      ],
      start: _start,
      end: _end,
    );
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xuất Excel tab Tổng quan')),
      );
    }
  }

  Future<void> _exTx(List<FinanceV2Txn> tx) async {
    if(!mounted) return;
    await FinanceV2ExcelExport.exportTable(context,sheetName:'Giao dịch',filePrefix:'giao_dich',headers:['Thời gian','Loại','Tiêu đề','Mô tả','NV','TT','Tiền vào','Tiền ra'],rows:tx.map((t)=>[FinanceV2ExcelExport.fmtDateTime(t.createdAt),_ft(t.type),t.title,t.subtitle,t.actorName??'',t.paymentMethod??'',t.isIncome?t.amount:0,t.isIncome?0:t.amount]).toList(),start:_start,end:_end);
  }
  Future<void> _exDebt(List<FinanceV2DebtItem> items) async {
    if(!mounted) return;
    final hasPayable = items.any((d) => d.type == 'SHOP_OWES' || d.type == 'OTHER_SHOP_OWES' || d.type == 'OWED');
    await FinanceV2ExcelExport.exportTable(context,sheetName:hasPayable?'Phải trả':'Phải thu',filePrefix:hasPayable?'phai_tra':'phai_thu',headers:['Tên','Điện thoại','Loại','Tổng nợ','Đã trả','Còn lại','Ngày tạo'],rows:items.map((d)=>[d.name,d.phone??'',_ft(d.type),d.total,d.paid,d.remaining,FinanceV2ExcelExport.fmtDate(d.createdAt)]).toList(),start:_start,end:_end);
  }
  Future<void> _exTL(List<_TLEntry> ents) async {
    if(!mounted) return;
    final rows = await _buildDetailedAuditLogRows();
    await FinanceV2ExcelExport.exportWorkbook(
      context,
      filePrefix:'nhat_ky_chi_tiet',
      sheets: <FinanceV2ExcelSheet>[
        FinanceV2ExcelSheet(
          sheetName:'activity_log',
          headers:_auditLogHeaders,
          rows:rows,
        ),
      ],
      start:_start,
      end:_end,
    );
  }

  Future<void> _exDailyReportPhone(FinanceV2Snapshot s) async {
    if (!mounted) return;

    final rows = <List<dynamic>>[
      ['BÁO CÁO KỲ', _sub],
      ['Thu vào', MoneyUtils.formatVND(s.totalIn)],
      ['Chi ra', MoneyUtils.formatVND(s.totalOut)],
      ['Ròng sổ quỹ', MoneyUtils.formatVND(s.netCashflow)],
      ['Lợi nhuận thực', MoneyUtils.formatVND(s.grossProfitTotal - s.operatingExpenseOut)],
      ['Số giao dịch', s.transactionCount.toString()],
      [''],
      ['CƠ CẤU DOANH THU', ''],
      ['Bán hàng', MoneyUtils.formatVND(s.incomeFromSales)],
      ['Sửa chữa', MoneyUtils.formatVND(s.incomeFromRepairs)],
      ['Thu khác', MoneyUtils.formatVND(s.incomeOther)],
      [''],
      ['CÔNG NỢ', ''],
      ['Phải thu', MoneyUtils.formatVND(s.receivableTotal)],
      ['Phải trả', MoneyUtils.formatVND(s.payableTotal)],
    ];

    if (s.topExpenseCategories.isNotEmpty) {
      rows.addAll([
        [''],
        ['TOP CHI PHÍ', ''],
      ]);
      for (final c in s.topExpenseCategories.take(10)) {
        rows.add([c.label, MoneyUtils.formatVND(c.amount)]);
      }
    }

    await FinanceV2ExcelExport.exportTable(
      context,
      sheetName: 'Báo cáo ngày',
      filePrefix: 'BaoCaoNgay_DienThoai',
      headers: const ['Mục', 'Giá trị'],
      rows: rows,
      start: _start,
      end: _end,
    );
  }

  // TAB 5 - Báo cáo ngày (embedded in Finance tabs)
  Widget _t5() {
    return const FinanceV2DailyReportView(embeddedInTab: true);
  }
}
