// ignore_for_file: prefer_const_constructors, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../utils/money_utils.dart';
import '../views/cash_closing_view.dart';
import '../views/debt_view.dart';
import '../views/expense_view.dart';
import '../views/repair_detail_view.dart';
import '../views/sale_detail_view.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/responsive_wrapper.dart';
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

enum _FilterMode { today, month, year, custom }

class FinanceV2View extends StatefulWidget {
  const FinanceV2View({super.key});
  @override
  State<FinanceV2View> createState() => _FinanceV2ViewState();
}

class _FinanceV2ViewState extends State<FinanceV2View>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FinanceV2DataService _service = FinanceV2DataService();
  final DBHelper _db = DBHelper();
  final _txCtrl = TextEditingController();
  final _tlCtrl = TextEditingController();
  bool _loading = true;
  FinanceV2Snapshot? _snap;
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _end = DateTime.now();
  // Chế độ lọc tường minh - không suy diễn từ ngày
  _FilterMode _mode = _FilterMode.today;
  String _txFilter = 'ALL';
  String _txQuery = '';
  String _txPm = '';
  bool _showRec = true;
  FinanceV2Aggregation _agg = FinanceV2Aggregation.day;
  String _tlSrc = 'ALL';
  String _tlDir = 'ALL';
  String _tlQ = '';
  bool _tlHigh = false;
  String _tlActor = '';
  String _tlPm = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _txCtrl.addListener(() { if (mounted) setState(() => _txQuery = _txCtrl.text); });
    _tlCtrl.addListener(() { if (mounted) setState(() => _tlQ = _tlCtrl.text); });
    _load();
  }

  @override
  void dispose() {
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
      setState(() { _snap = d; _loading = false; });
    } catch (e, st) {
      debugPrint('FinanceV2 _load error: $e\n$st');
      if (!mounted) return;
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  /// Tính khoảng kỳ trước tuỳ theo chế độ lọc:
  /// - Ngày → hôm qua
  /// - Tháng → tháng trước
  /// - Năm → năm trước
  /// - Khoảng tùy chọn → cùng độ dài, liền trước kỳ hiện tại
  (DateTime?, DateTime?) _previousPeriod() {
    if (_mode == _FilterMode.today) {
      final y = _start.subtract(const Duration(days: 1));
      return (DateTime(y.year, y.month, y.day), DateTime(y.year, y.month, y.day));
    }
    if (_mode == _FilterMode.month) {
      final prevMonth = _start.month == 1
          ? DateTime(_start.year - 1, 12, 1)
          : DateTime(_start.year, _start.month - 1, 1);
      final lastDayPrev = DateTime(prevMonth.year, prevMonth.month + 1, 0);
      return (prevMonth, lastDayPrev);
    }
    if (_mode == _FilterMode.year) {
      return (DateTime(_start.year - 1, 1, 1), DateTime(_start.year - 1, 12, 31));
    }
    return (null, null); // custom → data service xử lý theo độ dài
  }

  /// Nhãn hiển thị kỳ trước trong mục So sánh
  String get _compLabel {
    if (_mode == _FilterMode.today) return 'hôm qua';
    if (_mode == _FilterMode.month) {
      final prev = _start.month == 1
          ? DateTime(_start.year - 1, 12)
          : DateTime(_start.year, _start.month - 1);
      return 'tháng ${prev.month}/${prev.year}';
    }
    if (_mode == _FilterMode.year) return 'năm ${_start.year - 1}';
    return 'kỳ trước';
  }

  bool get _isSingle => _mode == _FilterMode.custom &&
      _start.year == _end.year && _start.month == _end.month && _start.day == _end.day;

  String get _sub {
    switch (_mode) {
      case _FilterMode.today:  return 'Hôm nay';
      case _FilterMode.month:  return 'Tháng ${DateFormat('MM/yyyy').format(_start)}';
      case _FilterMode.year:   return 'Năm ${DateFormat('yyyy').format(_start)}';
      case _FilterMode.custom:
        if (_isSingle) return DateFormat('dd/MM/yyyy').format(_start);
        return '${DateFormat('dd/MM').format(_start)} - ${DateFormat('dd/MM/yyyy').format(_end)}';
    }
  }

  void _setToday() { final n=DateTime.now(); setState((){_mode=_FilterMode.today;_start=DateTime(n.year,n.month,n.day);_end=n;}); _load(); }
  void _setMonth() { final n=DateTime.now(); setState((){_mode=_FilterMode.month;_start=DateTime(n.year,n.month,1);_end=n;}); _load(); }
  void _setYear()  { final n=DateTime.now(); setState((){_mode=_FilterMode.year;_start=DateTime(n.year,1,1);_end=n;}); _load(); }

  Future<void> _pick() async {
    final p = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      locale: const Locale('vi'),
      builder: (c, ch) => Theme(data: Theme.of(c).copyWith(
        colorScheme: const ColorScheme.light(primary: FinanceV2Theme.accent)), child: ch!),
    );
    if (p != null && mounted) { setState((){_mode=_FilterMode.custom;_start=p.start;_end=p.end;}); _load(); }
  }

  void _goTx(String f) { setState(()=>_txFilter=f); _tabController.animateTo(1); }
  void _goDebt(bool r) { setState(()=>_showRec=r); _tabController.animateTo(2); }

  void _goBucket(String key) {
    final parts = key.split('-');
    DateTime s, e;
    if (parts.length == 3) { final d=DateTime(int.parse(parts[0]),int.parse(parts[1]),int.parse(parts[2])); s=d; e=d; }
    else if (parts.length == 2) {
      final y=int.parse(parts[0]), m=int.parse(parts[1]);
      s=DateTime(y,m,1); e=(m==12?DateTime(y+1,1,1):DateTime(y,m+1,1)).subtract(const Duration(days:1));
    } else { final y=int.parse(parts[0]); s=DateTime(y,1,1); e=DateTime(y,12,31); }
    setState((){_mode=_FilterMode.custom;_start=s;_end=e;_txFilter='ALL';});
    _load().then((_){ if(mounted) _tabController.animateTo(1); });
  }
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
    final custom = _mode == _FilterMode.custom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F7))),
      ),
      padding: EdgeInsets.fromLTRB(_hPad, 4, _hPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Chọn bộ lọc thời gian',
                        onSelected: (value) {
                          switch (value) {
                            case 'today':
                              _setToday();
                              break;
                            case 'month':
                              _setMonth();
                              break;
                            case 'year':
                              _setYear();
                              break;
                            case 'custom':
                              _pick();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'today',
                            child: Row(
                              children: [
                                const Expanded(child: Text('Hôm nay')),
                                if (_mode == _FilterMode.today)
                                  const Icon(Icons.check_rounded, size: 16),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'month',
                            child: Row(
                              children: [
                                const Expanded(child: Text('Tháng này')),
                                if (_mode == _FilterMode.month)
                                  const Icon(Icons.check_rounded, size: 16),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'year',
                            child: Row(
                              children: [
                                const Expanded(child: Text('Năm nay')),
                                if (_mode == _FilterMode.year)
                                  const Icon(Icons.check_rounded, size: 16),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'custom',
                            child: Row(
                              children: [
                                const Expanded(child: Text('Tùy chọn')),
                                if (_mode == _FilterMode.custom)
                                  const Icon(Icons.check_rounded, size: 16),
                              ],
                            ),
                          ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded, size: 18, color: FinanceV2Theme.accent),
                            const SizedBox(width: 4),
                            Text(_sub, style: FinanceV2Theme.meta.copyWith(color: FinanceV2Theme.accent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _barActionButton(Icons.print_rounded, 'In', _printFromTab),
              const SizedBox(width: 2),
              _barActionButton(Icons.download_rounded, 'Xuất Excel', _exFromTab),
              const SizedBox(width: 2),
              _barActionButton(Icons.refresh_rounded, 'Làm mới', _load),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: 2),
            GestureDetector(
              onTap: _pick,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_today_rounded, size: 11, color: FinanceV2Theme.accent),
                const SizedBox(width: 4),
                Text(_sub, style: FinanceV2Theme.micro.copyWith(color: FinanceV2Theme.accent)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barActionButton(IconData icon, String label, VoidCallback? onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: FinanceV2Theme.meta),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: FinanceV2Theme.accent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 32),
      ),
    );
  }

  void _exFromTab() {
    final s = _snap;
    if (s == null) return;
    final idx = _tabController.index;
    switch (idx) {
      case 1:
        var tx = s.transactions.toList();
        if (_txFilter == 'IN') tx = tx.where((t) => t.isIncome).toList();
        else if (_txFilter == 'OUT') tx = tx.where((t) => !t.isIncome).toList();
        else if (_txFilter != 'ALL') tx = tx.where((t) => t.type == _txFilter).toList();
        if (_txPm.isNotEmpty) tx = tx.where((t) => (t.paymentMethod ?? '') == _txPm).toList();
        _exTx(tx);
        break;
      case 2:
        _exDebt(_showRec ? s.receivables : s.payables);
        break;
      case 3:
        _exRep(s.buckets(_agg));
        break;
      case 4:
        _exTL(_timeline(s));
        break;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chuyển sang tab Giao dịch hoặc Nhật ký để xuất Excel')),
          );
        }
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
    const m=<String,(String,Color)>{'SALE':('BH',Color(0xFF1565C0)),'REPAIR':('SC',Color(0xFF2E7D32)),'EXPENSE':('Chi',FinanceV2Theme.negative),'INCOME':('Thu',FinanceV2Theme.positive),'DEBT_COLLECT':('TN',FinanceV2Theme.warn),'DEBT_PAY':('TrN',FinanceV2Theme.negative)};
    final e=m[type]; if(e==null) return const SizedBox.shrink();
    return Container(margin:const EdgeInsets.only(left:4),padding:const EdgeInsets.symmetric(horizontal:5,vertical:1),
      decoration:BoxDecoration(color:e.$2.withValues(alpha:0.1),borderRadius:BorderRadius.circular(4),border:Border.all(color:e.$2.withValues(alpha:0.4))),
      child:Text(e.$1,style:FinanceV2Theme.caption.copyWith(fontWeight:FontWeight.w700,color:e.$2)));
  }

  Widget _dot(Color c) => Container(width:8,height:8,decoration:BoxDecoration(color:c,shape:BoxShape.circle));

  Widget _mini(String lbl,String val,Color c) => Column(children:[
    Text(lbl,style:FinanceV2Theme.micro),
    const SizedBox(height:2),
    Text(val,style:FinanceV2Theme.amountLg.copyWith(color:c))]);

  String _cmp(int v) => MoneyUtils.formatCompactCurrency(v.abs());
  String _signedCmp(int v) => v < 0 ? '-${MoneyUtils.formatCompactCurrency(v.abs())}' : MoneyUtils.formatCompactCurrency(v.abs());
  String _full(int v) => MoneyUtils.formatCurrency(v.abs());
  int _ti(dynamic v){ if(v is int) return v; if(v is num) return v.toInt(); if(v is String) return int.tryParse(v)??0; return 0; }
  String _ft(String t) => const<String,String>{'SALE':'Bán hàng','REPAIR':'Sửa chữa','EXPENSE':'Chi phí','INCOME':'Thu phát sinh','DEBT_COLLECT':'Thu nợ','DEBT_PAY':'Trả nợ','CUSTOMER_OWES':'Phải thu','SHOP_OWES':'Phải trả','AUDIT':'Nhật ký'}[t]??t;
  String _fa(String a) => const<String,String>{'create_repair':'Tạo đơn sửa chữa','update_repair':'Cập nhật đơn sửa','delete_repair':'Xóa đơn sửa chữa','create_sale':'Tạo đơn bán hàng','update_sale':'Cập nhật đơn bán hàng','delete_sale':'Xóa đơn bán hàng','add_expense':'Thêm chi phí','update_expense':'Cập nhật chi phí','delete_expense':'Xóa chi phí','add_debt':'Thêm công nợ','update_debt':'Cập nhật công nợ','delete_debt':'Xóa công nợ','add_debt_payment':'Thanh toán nợ','cash_closing':'Chốt ca'}[a]??a;

  double get _vw => MediaQuery.of(context).size.width;
  double get _hPad => FinanceV2Theme.contentHPad(_vw);
  double get _cardPad => FinanceV2Theme.cardPad(_vw);

  void _printFromTab() {
    _exFromTab();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xuất dữ liệu, bạn có thể in từ file vừa tạo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FinanceV2Theme.pageBg,
      appBar: CustomAppBar.buildWithTabs(
        title: '', tabController: _tabController,
        tabs: [
          _tab2('Tổng quan'), _tab2('Giao dịch'), _tab2('Công nợ'),
          _tab2('Phân tích'), _tab2('Nhật ký'), _tab2('Báo cáo'),
        ],
        isScrollable: true,
        accentColor: AppBarAccents.finance, showBackButton: false,
      ),
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
                  builder: (_, __) => _tabController.index == 5
                      ? const SizedBox.shrink()
                      : _sharedBar(),
                ),
                Expanded(
                  child: TabBarView(controller: _tabController, children: [
                    _t0(), _t1(), _t2(), _t3(), _t4(), _t5(),
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

  Tab _tab2(String text) => Tab(height: 38, child: Text(text, maxLines: 1, textAlign: TextAlign.center, style: FinanceV2Theme.meta.copyWith(fontWeight: FontWeight.w600, color: FinanceV2Theme.ink)));

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
    return Column(children:[Text(lbl,style:FinanceV2Theme.caption),const SizedBox(height:2),Text(net?_signedCmp(cur):_cmp(cur),style:FinanceV2Theme.amountMd.copyWith(color:tc)),if(chg!=null) Text('${chg>=0?"+":""}${chg.toStringAsFixed(0)}%',style:FinanceV2Theme.caption.copyWith(color:chg>=0?FinanceV2Theme.positive:FinanceV2Theme.negative)) else Text('-',style:FinanceV2Theme.caption)]);
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
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(lbl,style:FinanceV2Theme.micro.copyWith(color:c)),const SizedBox(height:4),Text(_cmp(amt),style:FinanceV2Theme.amountLg.copyWith(color:c)),Row(children:[Text('Xem chi tiết',style:FinanceV2Theme.caption),const Icon(Icons.chevron_right_rounded,size:12,color:FinanceV2Theme.subInk)])])));

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
    return ResponsiveCenter(child:Column(children:[
      Container(color:Colors.white,padding:EdgeInsets.fromLTRB(_hPad,6,_hPad,0),child:_sf(_txCtrl,'Tìm giao dịch...',_txQuery,(){_txCtrl.clear();setState(()=>_txQuery='');})),
      Container(
        color: const Color(0xFFF8F9FA),
        padding: EdgeInsets.fromLTRB(_hPad, 6, _hPad, 6),
        child: Row(children:[
          Expanded(
            child: Text(
              '${tx.length} giao dịch • Loại: ${_txFilter == 'ALL' ? 'Tất cả' : _ft(_txFilter)}${_txPm.isNotEmpty ? ' • TT: $_txPm' : ''}',
              style: FinanceV2Theme.meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exTx(tx)),
        ]),
      ),
      Container(height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:tx.isEmpty?_empty('Không có giao dịch phù hợp'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:tx.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_txRow(tx[i]))),
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
    final total=_showRec?s.receivableTotal:s.payableTotal;
    return ResponsiveCenter(child:Column(children:[
      Container(color:Colors.white,padding:EdgeInsets.fromLTRB(_hPad,8,_hPad,8),child:Row(children:[
        Expanded(child:GestureDetector(onTap:()=>setState(()=>_showRec=true),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:_showRec?FinanceV2Theme.warn:const Color(0xFFF0F3F9),borderRadius:BorderRadius.circular(10)),alignment:Alignment.center,child:Text('Phải thu  ${_cmp(s.receivableTotal)}',style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:_showRec?Colors.white:FinanceV2Theme.subInk))))),
        const SizedBox(width:8),
        Expanded(child:GestureDetector(onTap:()=>setState(()=>_showRec=false),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:!_showRec?FinanceV2Theme.negative:const Color(0xFFF0F3F9),borderRadius:BorderRadius.circular(10)),alignment:Alignment.center,child:Text('Phải trả  ${_cmp(s.payableTotal)}',style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600,color:!_showRec?Colors.white:FinanceV2Theme.subInk))))),
      ])),
      if(_showRec&&s.totalDebtAging>0) Container(color:Colors.white,padding:const EdgeInsets.fromLTRB(12,0,12,10),child:Row(children:[
        Expanded(child:_aging('0-30 ngày',s.debtAging['0-30']??0,FinanceV2Theme.positive)),const SizedBox(width:6),
        Expanded(child:_aging('31-60 ngày',s.debtAging['30-60']??0,FinanceV2Theme.warn)),const SizedBox(width:6),
        Expanded(child:_aging('>60 ngày',s.debtAging['>60']??0,FinanceV2Theme.negative)),
      ])),
      Container(color:const Color(0xFFF8F9FA),padding:EdgeInsets.fromLTRB(_hPad,6,_hPad,6),child:Row(children:[Text('${items.length} khoản · Tổng: ',style:FinanceV2Theme.meta),Text(_full(total),style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w700,color:_showRec?FinanceV2Theme.warn:FinanceV2Theme.negative)),const Spacer(),IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exDebt(items))])),
      Container(height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:items.isEmpty?_empty(_showRec?'Không có khoản phải thu':'Không có khoản phải trả'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:items.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_debtRow(items[i]))),
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

  // TAB 3
  Widget _t3() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    final bkts=s.buckets(_agg);
    return ResponsiveCenter(child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(12,10,12,0),child:Container(decoration:FinanceV2Theme.elevatedPanel(),padding:const EdgeInsets.all(14),child:Row(children:[Expanded(child:_mini('Tiền vào',_cmp(s.totalIn),FinanceV2Theme.positive)),Expanded(child:_mini('Tiền ra',_cmp(s.totalOut),FinanceV2Theme.negative)),Expanded(child:_mini('Dòng tiền ròng',_signedCmp(s.netCashflow),s.netCashflow>=0?FinanceV2Theme.positive:FinanceV2Theme.negative))]))),
      Padding(padding:EdgeInsets.fromLTRB(_hPad,8,_hPad,0),child:Text('* Dựa trên tiền mặt thực nhận / thực chi trong kỳ.',style:FinanceV2Theme.micro.copyWith(fontStyle:FontStyle.italic))),
      Padding(padding:EdgeInsets.fromLTRB(_hPad,8,_hPad,0),child:Row(children:[
        _aChip('Ngày',FinanceV2Aggregation.day),const SizedBox(width:6),_aChip('Tháng',FinanceV2Aggregation.month),const SizedBox(width:6),_aChip('Năm',FinanceV2Aggregation.year),
        const Spacer(),IconButton(icon:const Icon(Icons.download_rounded,color:FinanceV2Theme.accent,size:20),tooltip:'Xuất Excel',onPressed:()=>_exRep(bkts)),
      ])),
      if(bkts.isNotEmpty) Padding(padding:EdgeInsets.fromLTRB(_hPad,4,_hPad,0),child:Row(children:[Text('${bkts.length} kỳ',style:FinanceV2Theme.micro),const SizedBox(width:12),Text('TB vào: ${_cmp(bkts.isEmpty?0:s.totalIn~/bkts.length)}',style:FinanceV2Theme.micro)])),
      Container(margin:const EdgeInsets.only(top:6),height:1,color:const Color(0xFFEEF1F7)),
      Expanded(child:bkts.isEmpty?_empty('Chưa có dữ liệu theo kỳ'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:bkts.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:16),itemBuilder:(_,i)=>GestureDetector(onTap:()=>_goBucket(bkts[i].key),child:_rptRow(bkts[i])))),
    ]));
  }

  Widget _rptRow(FinanceV2PeriodBucket b) {
    final mx=b.totalIn>b.totalOut?b.totalIn:b.totalOut;
    return Padding(padding:const EdgeInsets.fromLTRB(14,10,14,10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Text(b.label,style:FinanceV2Theme.bodyMd.copyWith(fontWeight:FontWeight.w600)),const Spacer(),Text('${b.txCount} GD',style:FinanceV2Theme.micro),const SizedBox(width:8),Text(_signedCmp(b.net),style:FinanceV2Theme.amountMd.copyWith(color:b.net>=0?FinanceV2Theme.positive:FinanceV2Theme.negative)),const SizedBox(width:4),const Icon(Icons.chevron_right_rounded,size:16,color:FinanceV2Theme.subInk)]),
      const SizedBox(height:6),
      if(mx>0)...[_bRow('Vào',b.totalIn,mx,FinanceV2Theme.positive),const SizedBox(height:4),_bRow('Ra',b.totalOut,mx,FinanceV2Theme.negative)],
    ]));
  }

  Widget _bRow(String lbl,int val,int mx,Color c) {
    final r=mx>0?val/mx:0.0;
    return Row(children:[SizedBox(width:28,child:Text(lbl,style:FinanceV2Theme.caption)),Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(3),child:LinearProgressIndicator(value:r.clamp(0.0,1.0),minHeight:6,backgroundColor:c.withValues(alpha:0.1),valueColor:AlwaysStoppedAnimation(c)))),const SizedBox(width:8),Text(_cmp(val),style:FinanceV2Theme.micro.copyWith(color:c))]);
  }

  Widget _aChip(String lbl,FinanceV2Aggregation val) {
    final a=_agg==val;
    return GestureDetector(onTap:()=>setState(()=>_agg=val),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:a?FinanceV2Theme.accent:const Color(0xFFF0F3F9),borderRadius:BorderRadius.circular(20)),child:Text(lbl,style:FinanceV2Theme.bodySm.copyWith(color:a?Colors.white:FinanceV2Theme.subInk))));
  }
  // TAB 4
  Widget _t4() {
    final s=_snap; if(s==null) return _empty('Không có dữ liệu');
    final all=_timeline(s);
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
                '${ents.length} mục • Nguồn: ${_tlSrc == 'ALL' ? 'Tất cả' : _ft(_tlSrc)} • Hướng: ${_tlDir == 'ALL' ? 'Tất cả' : (_tlDir == 'IN' ? 'Thu vào' : 'Chi ra')}',
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
      Expanded(child:ents.isEmpty?_empty('Không có nhật ký phù hợp'):ListView.separated(padding:const EdgeInsets.symmetric(vertical:4),itemCount:ents.length,separatorBuilder:(_,__)=>const Divider(height:1,indent:60),itemBuilder:(_,i)=>_tlRow(ents[i]))),
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

  // EXPORT
  Future<void> _exTx(List<FinanceV2Txn> tx) async {
    if(!mounted) return;
    await FinanceV2ExcelExport.exportTable(context,sheetName:'Giao dịch',filePrefix:'giao_dich',headers:['Thời gian','Loại','Tiêu đề','Mô tả','NV','TT','Tiền vào','Tiền ra'],rows:tx.map((t)=>[FinanceV2ExcelExport.fmtDateTime(t.createdAt),_ft(t.type),t.title,t.subtitle,t.actorName??'',t.paymentMethod??'',t.isIncome?t.amount:0,t.isIncome?0:t.amount]).toList(),start:_start,end:_end);
  }
  Future<void> _exDebt(List<FinanceV2DebtItem> items) async {
    if(!mounted) return;
    await FinanceV2ExcelExport.exportTable(context,sheetName:'Công nợ',filePrefix:'cong_no',headers:['Ten','Điện thoại','Loại','Tổng nợ','Đã trả','Còn lại','Ngày tao'],rows:items.map((d)=>[d.name,d.phone??'',_ft(d.type),d.total,d.paid,d.remaining,FinanceV2ExcelExport.fmtDate(d.createdAt)]).toList(),start:_start,end:_end);
  }
  Future<void> _exRep(List<FinanceV2PeriodBucket> bkts) async {
    if(!mounted) return;
    await FinanceV2ExcelExport.exportTable(context,sheetName:'Báo cáo',filePrefix:'bao_cao',headers:['Ky','Tiền vào','Tiền ra','Ròng','Số GD'],rows:bkts.map((b)=>[b.label,b.totalIn,b.totalOut,b.net,b.txCount]).toList(),start:_start,end:_end);
  }
  Future<void> _exTL(List<_TLEntry> ents) async {
    if(!mounted) return;
    await FinanceV2ExcelExport.exportTable(context,sheetName:'Nhật ký',filePrefix:'nhat_ky',headers:['Thời gian','Loại','Tiêu đề','Mô tả','NV','TT','Tiền vào','Tiền ra'],rows:ents.map((e)=>[FinanceV2ExcelExport.fmtDateTime(e.ts),_ft(e.type),e.title,e.subtitle,e.actorName??'',e.paymentMethod??'',e.isIncome?e.amount:0,e.isIncome?0:e.amount]).toList(),start:_start,end:_end);
  }

  // TAB 5 - Báo cáo ngày (embedded in Finance tabs)
  Widget _t5() {
    return const FinanceV2DailyReportView(embeddedInTab: true);
  }
}
