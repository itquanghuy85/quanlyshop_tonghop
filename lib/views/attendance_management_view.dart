import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/custom_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/attendance_monthly_summary_model.dart';
import '../models/leave_request_model.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../services/osm_map_service.dart';
import '../services/attendance_approval_service.dart';
import '../services/attendance_summary_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/app_cached_image.dart';

/// Trang theo dõi chấm công nhân viên cho quản lý/chủ shop
/// 3 Tab: Tổng quan | Duyệt chấm công | Xin nghỉ
class AttendanceManagementView extends StatefulWidget {
  const AttendanceManagementView({super.key});

  @override
  State<AttendanceManagementView> createState() => _AttendanceManagementViewState();
}

class _AttendanceManagementViewState extends State<AttendanceManagementView>
    with TickerProviderStateMixin {
  final _db = DBHelper();
  late TabController _tabCtrl;
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime.now();

  List<Map<String, dynamic>> _staffList = [];
  final Map<String, List<Attendance>> _staffAttendance = {};
  List<AttendanceMonthlySummary> _monthlySummaries = [];
  List<Attendance> _pendingRequests = [];
  List<LeaveRequest> _leaveRequests = [];

  String? _currentShopId;
  String _viewMode = 'day'; // 'day' or 'month'

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    _currentShopId = await UserService.getCurrentShopId();
    await _loadStaffList();
    await Future.wait([_loadAttendanceData(), _loadPendingRequests(), _loadLeaveRequests()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStaffList() async {
    try {
      if (_currentShopId == null) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: _currentShopId)
          .get();
      _staffList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? data['email']?.toString().split('@').first.toUpperCase() ?? 'NV',
          'email': data['email'] ?? '',
          'role': data['role'] ?? 'employee',
        };
      }).toList();
      _staffList.sort((a, b) {
        const order = {'owner': 0, 'manager': 1, 'technician': 2, 'employee': 3};
        return (order[a['role']] ?? 4).compareTo(order[b['role']] ?? 4);
      });
    } catch (e) {
      debugPrint('Error loading staff list: $e');
    }
  }

  Future<void> _loadAttendanceData() async {
    _staffAttendance.clear();
    _monthlySummaries = [];
    if (_viewMode == 'day') {
      await _loadDayAttendance();
    } else {
      await _loadMonthAttendance();
    }
  }

  Future<void> _loadDayAttendance() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    for (final staff in _staffList) {
      final userId = staff['id'] as String;
      try {
        final local = await _db.getAttendance(dateKey, userId);
        if (local != null) {
          _staffAttendance[userId] = [local];
          continue;
        }
        if (_currentShopId != null) {
          final doc = await FirebaseFirestore.instance
              .collection('attendance')
              .where('shopId', isEqualTo: _currentShopId)
              .where('userId', isEqualTo: userId)
              .where('dateKey', isEqualTo: dateKey)
              .limit(1)
              .get();
          _staffAttendance[userId] = doc.docs.isNotEmpty
              ? [Attendance.fromMap(doc.docs.first.data())]
              : [];
        } else {
          _staffAttendance[userId] = [];
        }
      } catch (e) {
        _staffAttendance[userId] = [];
      }
    }
  }

  Future<void> _loadMonthAttendance() async {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(end);
    final allLocal = await _db.getAttendanceByDateRange(startKey, endKey);

    for (final staff in _staffList) {
      final userId = staff['id'] as String;
      try {
        final records = allLocal.where((r) => r.userId == userId).toList();
        if (records.isNotEmpty) {
          _staffAttendance[userId] = records;
          continue;
        }
        if (_currentShopId != null) {
          final snap = await FirebaseFirestore.instance
              .collection('attendance')
              .where('shopId', isEqualTo: _currentShopId)
              .where('userId', isEqualTo: userId)
              .where('dateKey', isGreaterThanOrEqualTo: startKey)
              .where('dateKey', isLessThanOrEqualTo: endKey)
              .get();
          final recs = snap.docs.map((d) => Attendance.fromMap(d.data())).toList();
          _staffAttendance[userId] = recs;
        } else {
          _staffAttendance[userId] = [];
        }
      } catch (e) {
        _staffAttendance[userId] = [];
      }
    }
    _monthlySummaries = AttendanceSummaryService.buildMonthlySummaries(
      staffList: _staffList,
      staffAttendance: _staffAttendance,
    );
  }

  Future<void> _loadPendingRequests() async {
    try {
      _pendingRequests = await _db.getPendingAttendanceRequests();
    } catch (e) {
      _pendingRequests = [];
    }
  }

  Future<void> _loadLeaveRequests() async {
    try {
      final start = DateFormat('yyyy-MM-dd').format(DateTime(_selectedMonth.year, _selectedMonth.month, 1));
      final end = DateFormat('yyyy-MM-dd').format(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0));
      _leaveRequests = await AttendanceApprovalService.getLeaveRequestsByDateRange(start, end);
      debugPrint('📋 Loaded ${_leaveRequests.length} leave requests for $start → $end');
    } catch (e) {
      debugPrint('❌ _loadLeaveRequests error: $e');
      _leaveRequests = [];
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final pendingCount = _pendingRequests.length;
    final leaveCount = _leaveRequests.where((l) => l.status == 'pending').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: loc.attendanceTracking,
        accentColor: AppBarAccents.staff,
        actions: [
          IconButton(
            icon: Icon(_viewMode == 'day' ? Icons.calendar_month : Icons.calendar_today, color: Colors.white, size: 20),
            tooltip: _viewMode == 'day' ? loc.viewByMonth : loc.viewByDay,
            onPressed: () {
              setState(() => _viewMode = _viewMode == 'day' ? 'month' : 'day');
              _loadAttendanceData().then((_) => setState(() {}));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: [
            const Tab(text: 'TỔNG QUAN'),
            Tab(child: _tabWithBadge('DUYỆT', pendingCount)),
            Tab(child: _tabWithBadge('XIN NGHỈ', leaveCount)),
          ],
        ),
      ),
      body: ResponsiveCenter(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _tabCtrl.index,
                children: [
                  _buildOverviewTab(),
                  _buildApprovalTab(),
                  _buildLeaveTab(),
                ],
              ),
      ),
    );
  }

  Widget _tabWithBadge(String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  // ==================== TAB 1: OVERVIEW ====================

  Widget _buildOverviewTab() {
    return CustomScrollView(
      primary: false,
      slivers: [
        SliverToBoxAdapter(child: _buildSummaryHeader()),
        SliverToBoxAdapter(child: _buildDateSelector()),
        if (_viewMode == 'month')
          SliverToBoxAdapter(child: _buildMonthlySummaryTable()),
        _buildStaffSliver(),
      ],
    );
  }

  Widget _buildMonthlySummaryTable() {
    if (_monthlySummaries.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalWorkMinutes = _monthlySummaries.fold<int>(
      0,
      (sum, item) => sum + item.totalWorkMinutes,
    );
    final totalOtMinutes = _monthlySummaries.fold<int>(
      0,
      (sum, item) => sum + item.overtimeMinutes,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bảng tổng hợp tháng ${DateFormat('MM/yyyy').format(_selectedMonth)}',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline5.fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Giờ công ${AttendanceMonthlySummary.formatMinutes(totalWorkMinutes)} • OT ${AttendanceMonthlySummary.formatMinutes(totalOtMinutes)}',
                      style: TextStyle(
                        fontSize: AppTextStyles.caption.fontSize,
                        color: AppColors.inactive,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _exportMonthlySummary,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Xuất Excel'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('Nhân viên')),
                DataColumn(label: Text('Công')),
                DataColumn(label: Text('Duyệt')),
                DataColumn(label: Text('Chờ')),
                DataColumn(label: Text('Muộn')),
                DataColumn(label: Text('Sớm')),
                DataColumn(label: Text('Thiếu ra')),
                DataColumn(label: Text('Giờ công')),
                DataColumn(label: Text('OT')),
              ],
              rows: _monthlySummaries.map((summary) {
                return DataRow(
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 150),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              summary.email,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.inactive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text('${summary.workDays}')),
                    DataCell(Text('${summary.approvedDays}')),
                    DataCell(Text('${summary.pendingDays}')),
                    DataCell(Text('${summary.lateDays}')),
                    DataCell(Text('${summary.earlyLeaveDays}')),
                    DataCell(Text('${summary.incompleteDays}')),
                    DataCell(Text(summary.totalWorkLabel)),
                    DataCell(Text(summary.overtimeLabel)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final loc = AppLocalizations.of(context)!;
    int present = 0, late = 0, absent = 0;
    if (_viewMode == 'day') {
      for (final s in _staffList) {
        final recs = _staffAttendance[s['id']] ?? [];
        if (recs.isNotEmpty && recs.first.checkInAt != null) {
          present++;
          if (recs.first.isLate == 1) late++;
        } else {
          absent++;
        }
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
      ),
      child: Column(
        children: [
          Text(
            _viewMode == 'day'
                ? loc.attendanceForDate(DateFormat('dd/MM/yyyy').format(_selectedDate))
                : loc.monthLabel(DateFormat('MM/yyyy').format(_selectedMonth)),
            style: TextStyle(color: Colors.white70, fontSize: AppTextStyles.caption.fontSize),
          ),
          const SizedBox(height: 6),
          if (_viewMode == 'day')
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryItem(loc.present, present, Colors.greenAccent),
                _summaryItem(loc.lateArrival, late, Colors.orangeAccent),
                _summaryItem(loc.absent, absent, Colors.redAccent),
                _summaryItem(loc.totalStaff, _staffList.length, Colors.white),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryItem(loc.totalStaff, _staffList.length, Colors.white),
                _summaryItem(loc.checkedInStatus, _staffAttendance.values.where((v) => v.isNotEmpty).length, Colors.greenAccent),
              ],
            ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value', style: TextStyle(color: color, fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: AppTextStyles.caption.fontSize)),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20), visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                if (_viewMode == 'day') {
                  _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                } else {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                }
              });
              _loadAttendanceData().then((_) => setState(() {}));
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                child: Text(
                  _viewMode == 'day'
                      ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(_selectedDate)
                      : DateFormat('MMMM yyyy', 'vi').format(_selectedMonth),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTextStyles.headline5.fontSize),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20), visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                if (_viewMode == 'day') {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                } else {
                  _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                }
              });
              _loadAttendanceData().then((_) => setState(() {}));
            },
          ),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () {
              setState(() { _selectedDate = DateTime.now(); _selectedMonth = DateTime.now(); });
              _loadAttendanceData().then((_) => setState(() {}));
            },
            child: Text(AppLocalizations.of(context)!.todayLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    if (_viewMode == 'day') {
      final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
      if (picked != null) { setState(() => _selectedDate = picked); _loadAttendanceData().then((_) => setState(() {})); }
    } else {
      final picked = await showDatePicker(context: context, initialDate: _selectedMonth, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)), initialDatePickerMode: DatePickerMode.year);
      if (picked != null) { setState(() => _selectedMonth = DateTime(picked.year, picked.month)); _loadAttendanceData().then((_) => setState(() {})); }
    }
  }

  Widget _buildStaffSliver() {
    if (_staffList.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 48, color: AppColors.inactive),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.noStaffYet, style: TextStyle(color: AppColors.inactive)),
            ],
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final staff = _staffList[i];
            final userId = staff['id'] as String;
            final records = _staffAttendance[userId] ?? [];
            final summary = _summaryByUserId(userId);
            return _viewMode == 'day'
                ? _buildDayCard(staff, records)
                : _buildMonthCard(staff, records, summary);
          },
          childCount: _staffList.length,
        ),
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> staff, List<Attendance> records) {
    final loc = AppLocalizations.of(context)!;
    final hasIn = records.isNotEmpty && records.first.checkInAt != null;
    final hasOut = records.isNotEmpty && records.first.checkOutAt != null;
    final isLate = records.isNotEmpty && records.first.isLate == 1;
    final status = records.isNotEmpty ? records.first.status : null;

    Color statusColor = AppColors.inactive;
    String statusText = loc.notCheckedIn;
    IconData statusIcon = Icons.remove_circle_outline;
    if (hasIn && hasOut) {
      statusColor = isLate ? AppColors.warning : AppColors.success;
      statusText = loc.completedStatus;
      statusIcon = Icons.check_circle;
    } else if (hasIn) {
      statusColor = isLate ? AppColors.warning : AppColors.primary;
      statusText = loc.workingStatus;
      statusIcon = Icons.work;
    }

    // Approval badge color
    Color? approvalColor;
    String? approvalText;
    if (status == 'approved') { approvalColor = AppColors.success; approvalText = loc.approvedStatus; }
    else if (status == 'rejected') { approvalColor = AppColors.error; approvalText = loc.rejectedStatus; }
    else if (status == 'pending' && hasIn) { approvalColor = AppColors.warning; approvalText = loc.pendingStatus; }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showStaffDetail(staff, records),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _roleColor(staff['role']).withOpacity(0.2),
                    child: Text((staff['name'] as String).substring(0, 1).toUpperCase(),
                      style: TextStyle(color: _roleColor(staff['role']), fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline4.fontSize)),
                  ),
                  Positioned(right: 0, bottom: 0, child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  )),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(staff['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      _roleBadge(staff['role']),
                      if (approvalColor != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: approvalColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(approvalText!, style: TextStyle(fontSize: 9, color: approvalColor, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 3),
                      Text(statusText, style: TextStyle(color: statusColor, fontSize: AppTextStyles.caption.fontSize)),
                      if (isLate) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(loc.lateArrival, style: TextStyle(color: AppColors.warning, fontSize: 10)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasIn) Text('Vào: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(records.first.checkInAt!))}',
                    style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.success)),
                  if (hasOut) Text('Ra: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(records.first.checkOutAt!))}',
                    style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.error)),
                  if (!hasIn) Text('--:--', style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.inactive)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthCard(
    Map<String, dynamic> staff,
    List<Attendance> records,
    AttendanceMonthlySummary? summary,
  ) {
    final loc = AppLocalizations.of(context)!;
    final totalDays = summary?.workDays ?? 0;
    final approved = summary?.approvedDays ?? 0;
    final lateDays = summary?.lateDays ?? 0;
    final earlyLeaveDays = summary?.earlyLeaveDays ?? 0;
    final pendingDays = summary?.pendingDays ?? 0;
    final incompleteDays = summary?.incompleteDays ?? 0;
    final totalHours = summary?.totalWorkLabel ?? '0h';
    final ot = summary?.overtimeLabel ?? '0h';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showMonthDetail(staff, records),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _roleColor(staff['role']).withOpacity(0.2),
                  child: Text((staff['name'] as String).substring(0, 1).toUpperCase(),
                    style: TextStyle(color: _roleColor(staff['role']), fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline6.fontSize)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(staff['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6), _roleBadge(staff['role']),
                    ]),
                    Text(staff['email'], style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.inactive)),
                  ],
                )),
              ]),
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _monthStatItem(loc.workDaysCount, '$totalDays', AppColors.primary),
                  _monthStatItem(loc.approvedStatus, '$approved', AppColors.success),
                  _monthStatItem(loc.lateArrival, '$lateDays', AppColors.warning),
                  _monthStatItem(loc.workHoursCount, totalHours, AppColors.primary),
                  _monthStatItem('OT', ot, Colors.deepOrange),
                ],
              ),
              if (pendingDays > 0 || earlyLeaveDays > 0 || incompleteDays > 0) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (pendingDays > 0)
                      _monthFlag('Chờ duyệt $pendingDays', AppColors.warning),
                    if (earlyLeaveDays > 0)
                      _monthFlag('Về sớm $earlyLeaveDays', Colors.orange),
                    if (incompleteDays > 0)
                      _monthFlag('Thiếu giờ ra $incompleteDays', AppColors.error),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthFlag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _monthStatItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: AppTextStyles.headline4.fontSize, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(fontSize: 10, color: AppColors.inactive)),
    ]);
  }

  // ==================== TAB 2: APPROVAL ====================

  Widget _buildApprovalTab() {
    try {
      final loc = AppLocalizations.of(context)!;
      // Collect ALL attendance that needs approval (pending with checkIn)
      List<Attendance> pending = [];
      for (final staff in _staffList) {
        final records = _staffAttendance[staff['id']] ?? [];
        for (final r in records) {
          if (r.status == 'pending' && r.checkInAt != null) pending.add(r);
        }
      }
      // Also include forgot check-in requests from _pendingRequests
      for (final r in _pendingRequests) {
        if (!pending.any((p) => p.firestoreId == r.firestoreId)) pending.add(r);
      }

      // Build children list imperatively (no collection-if/for/spread in list literal)
      final children = <Widget>[];

      // Bulk approve bar
      if (pending.isNotEmpty) {
        children.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.warning.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.pending_actions, size: 18, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text('${pending.length} yêu cầu chờ duyệt',
                  style: TextStyle(fontSize: AppTextStyles.caption.fontSize, fontWeight: FontWeight.w500))),
                TextButton.icon(
                  onPressed: () => _bulkApprove(pending),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: Text(loc.bulkApprove, style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.success),
                ),
              ],
            ),
          ),
        );
      }

      // Action buttons (always visible)
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showForgotCheckinDialog,
                  icon: const Icon(Icons.add_alarm, size: 16),
                  label: Text(loc.forgotCheckin, style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showEditOvertimeDialog,
                  icon: const Icon(Icons.more_time, size: 16),
                  label: Text(loc.editOvertime, style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),
      );

      // Empty state or cards
      if (pending.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline, size: 48, color: AppColors.success.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text(loc.noPendingRequests, style: TextStyle(color: AppColors.inactive)),
            ])),
          ),
        );
      } else {
        for (final record in pending) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildApprovalCard(record),
            ),
          );
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    } catch (e, s) {
      debugPrint('❌ _buildApprovalTab error: $e\n$s');
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Lỗi tab duyệt: $e', style: const TextStyle(color: Colors.red)),
      ));
    }
  }

  Widget _buildApprovalCard(Attendance record) {
    final staffName = _staffNameById(record.userId);
    final isForget = record.requestType == 'forgot_checkin' || record.requestType == 'forgot_checkout';
    final isOTEdit = record.requestType == 'overtime_edit';
    final typeLabel = isForget ? 'Quên chấm công' : isOTEdit ? 'Sửa tăng ca' : 'Chấm công';
    final typeColor = isForget ? AppColors.warning : isOTEdit ? Colors.deepOrange : AppColors.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(typeLabel, style: TextStyle(fontSize: 10, color: typeColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(staffName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline6.fontSize), overflow: TextOverflow.ellipsis)),
              Text(record.dateKey, style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.inactive)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              if (record.checkInAt != null) Text('Vào: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!))} ', style: TextStyle(fontSize: 12, color: AppColors.success)),
              if (record.checkOutAt != null) Text('Ra: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!))} ', style: TextStyle(fontSize: 12, color: AppColors.error)),
              if (record.overtimeOn > 0) Text('OT: ${record.overtimeOn}p ', style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
            ]),
            if (record.note != null && record.note!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ghi chú: ${record.note}', style: TextStyle(fontSize: 11, color: AppColors.inactive))),
            const Divider(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(
                child: TextButton(
                  onPressed: () => _rejectAttendance(record),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error, visualDensity: VisualDensity.compact),
                  child: Text(AppLocalizations.of(context)!.rejectAttendance, style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: ElevatedButton(
                  onPressed: () => _approveAttendance(record),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  child: Text(AppLocalizations.of(context)!.approveAttendance, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _approveAttendance(Attendance record) async {
    final ok = await AttendanceApprovalService.approveAttendance(record);
    if (ok) {
      NotificationService.showSnackBar('Đã duyệt chấm công', color: AppColors.success);
      await _loadData();
    } else {
      NotificationService.showSnackBar('Lỗi duyệt chấm công', color: Colors.red);
    }
  }

  Future<void> _rejectAttendance(Attendance record) async {
    final reason = await _showReasonDialog('Lý do từ chối');
    if (reason == null) return;
    final ok = await AttendanceApprovalService.rejectAttendance(record, reason);
    if (ok) {
      NotificationService.showSnackBar('Đã từ chối chấm công', color: AppColors.warning);
      await _loadData();
    }
  }

  Future<void> _bulkApprove(List<Attendance> records) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Duyệt tất cả'),
      content: Text('Xác nhận duyệt ${records.length} bản ghi chấm công?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.success), child: const Text('Duyệt tất cả')),
      ],
    ));
    if (confirmed != true) return;
    int count = 0;
    for (final r in records) {
      final ok = await AttendanceApprovalService.approveAttendance(r);
      if (ok) count++;
    }
    NotificationService.showSnackBar('Đã duyệt $count/${records.length} bản ghi', color: AppColors.success);
    await _loadData();
  }

  void _showForgotCheckinDialog() {
    String? selectedUserId;
    DateTime selectedDate = _selectedDate;
    TimeOfDay? checkInTime;
    TimeOfDay? checkOutTime;
    String note = '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.add_alarm, size: 20),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.forgotCheckinRequest, style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Staff picker
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Nhân viên', border: OutlineInputBorder(), isDense: true),
              items: _staffList.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setDlg(() => selectedUserId = v),
            ),
            const SizedBox(height: 10),
            // Date picker
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate)}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setDlg(() => selectedDate = d);
              },
            ),
            // Check-in time
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('Giờ vào: ${checkInTime?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.access_time, size: 18),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 8, minute: 0));
                if (t != null) setDlg(() => checkInTime = t);
              },
            ),
            // Check-out time
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('Giờ ra: ${checkOutTime?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.access_time, size: 18),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 17, minute: 0));
                if (t != null) setDlg(() => checkOutTime = t);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => note = v,
              style: const TextStyle(fontSize: 13),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (selectedUserId == null || checkInTime == null) {
                NotificationService.showSnackBar('Chọn nhân viên và giờ vào', color: Colors.red);
                return;
              }
              final staff = _staffList.firstWhere((s) => s['id'] == selectedUserId);
              final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
              final inMs = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, checkInTime!.hour, checkInTime!.minute).millisecondsSinceEpoch;
              final outMs = checkOutTime != null
                  ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day, checkOutTime!.hour, checkOutTime!.minute).millisecondsSinceEpoch
                  : null;
              Navigator.pop(ctx);
              final ok = await AttendanceApprovalService.createForgotCheckinRequest(
                userId: selectedUserId!, email: staff['email'], name: staff['name'],
                dateKey: dateKey, checkInAt: inMs, checkOutAt: outMs, note: note.isNotEmpty ? note : null,
              );
              if (ok) {
                NotificationService.showSnackBar('Đã tạo yêu cầu bổ sung chấm công', color: AppColors.success);
                await _loadData();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Tạo yêu cầu'),
          ),
        ],
      );
    }));
  }

  void _showEditOvertimeDialog() {
    String? selectedUserId;
    DateTime selectedDate = _selectedDate;
    TimeOfDay? otStart;
    TimeOfDay? otEnd;
    String note = '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
      final otMinutes = (otStart != null && otEnd != null)
          ? ((otEnd!.hour * 60 + otEnd!.minute) - (otStart!.hour * 60 + otStart!.minute)).clamp(0, 480)
          : 0;
      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.more_time, size: 20),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.editOvertime, style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Nhân viên', border: OutlineInputBorder(), isDense: true),
              items: _staffList.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setDlg(() => selectedUserId = v),
            ),
            const SizedBox(height: 10),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate)}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setDlg(() => selectedDate = d);
              },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${AppLocalizations.of(context)!.overtimeFrom}: ${otStart?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.access_time, size: 18),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 17, minute: 0));
                if (t != null) setDlg(() => otStart = t);
              },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${AppLocalizations.of(context)!.overtimeTo}: ${otEnd?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.access_time, size: 18),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 20, minute: 0));
                if (t != null) setDlg(() => otEnd = t);
              },
            ),
            if (otMinutes > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('${AppLocalizations.of(context)!.overtimeMinutes}: $otMinutes phút (${(otMinutes / 60).toStringAsFixed(1)} giờ)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.deepOrange)),
              ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => note = v,
              style: const TextStyle(fontSize: 13),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (selectedUserId == null || otStart == null || otEnd == null) {
                NotificationService.showSnackBar('Chọn nhân viên và giờ tăng ca', color: Colors.red);
                return;
              }
              final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
              final existing = await _db.getAttendance(dateKey, selectedUserId!);
              if (existing == null) {
                NotificationService.showSnackBar('Không tìm thấy bản ghi chấm công ngày này', color: Colors.red);
                return;
              }
              Navigator.pop(ctx);
              final startMs = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, otStart!.hour, otStart!.minute).millisecondsSinceEpoch;
              final endMs = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, otEnd!.hour, otEnd!.minute).millisecondsSinceEpoch;
              final ok = await AttendanceApprovalService.editOvertime(
                record: existing, overtimeMinutes: otMinutes,
                overtimeStartAt: startMs, overtimeEndAt: endMs,
                note: note.isNotEmpty ? 'Tăng ca: $note' : null,
              );
              if (ok) {
                NotificationService.showSnackBar('Đã ghi nhận tăng ca $otMinutes phút', color: AppColors.success);
                await _loadData();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('Ghi nhận OT'),
          ),
        ],
      );
    }));
  }

  // ==================== TAB 3: LEAVE REQUESTS ====================

  Widget _buildLeaveTab() {
    try {
      final loc = AppLocalizations.of(context)!;
      final pending = _leaveRequests.where((l) => l.status == 'pending').toList();
      final processed = _leaveRequests.where((l) => l.status != 'pending').toList();

      // Build children list imperatively (no collection-if/for/spread in list literal)
      final children = <Widget>[];

      // Create button (always visible)
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showCreateLeaveDialog,
              icon: const Icon(Icons.add, size: 16),
              label: Text(loc.createLeaveRequest, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ),
      );

      // Empty state
      if (_leaveRequests.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.event_available, size: 48, color: AppColors.inactive.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text(loc.noLeaveRequests, style: TextStyle(color: AppColors.inactive)),
            ])),
          ),
        );
      }

      // Pending section
      if (pending.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 6),
            child: Text('Chờ duyệt (${pending.length})', style: TextStyle(fontSize: AppTextStyles.caption.fontSize, fontWeight: FontWeight.bold, color: AppColors.warning)),
          ),
        );
        for (final lr in pending) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildLeaveCard(lr),
            ),
          );
        }
      }

      // Processed section
      if (processed.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
            child: Text('Đã xử lý (${processed.length})', style: TextStyle(fontSize: AppTextStyles.caption.fontSize, fontWeight: FontWeight.bold, color: AppColors.inactive)),
          ),
        );
        for (final lr in processed) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildLeaveCard(lr),
            ),
          );
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    } catch (e, s) {
      debugPrint('❌ _buildLeaveTab error: $e\n$s');
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Lỗi tab nghỉ: $e', style: const TextStyle(color: Colors.red)),
      ));
    }
  }

  Widget _buildLeaveCard(LeaveRequest lr) {
    final loc = AppLocalizations.of(context)!;
    Color statusColor;
    String statusLabel;
    switch (lr.status) {
      case 'approved': statusColor = AppColors.success; statusLabel = loc.approvedStatus; break;
      case 'rejected': statusColor = AppColors.error; statusLabel = loc.rejectedStatus; break;
      default: statusColor = AppColors.warning; statusLabel = loc.pendingStatus;
    }
    final leaveLabel = LeaveRequest.leaveTypeDisplayVi(lr.leaveType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(leaveLabel, style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Text('${lr.totalDays} ngày', style: TextStyle(fontSize: AppTextStyles.caption.fontSize, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            Text(lr.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline6.fontSize)),
            const SizedBox(height: 2),
            Text('${lr.startDate} → ${lr.endDate}', style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: AppColors.inactive)),
            if (lr.reason != null && lr.reason!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('Lý do: ${lr.reason}', style: TextStyle(fontSize: 11, color: AppColors.onSurface.withOpacity(0.7)))),
            if (lr.rejectReason != null && lr.rejectReason!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('Từ chối: ${lr.rejectReason}', style: TextStyle(fontSize: 11, color: AppColors.error))),
            if (lr.status?.toLowerCase() == 'pending') ...[  
              const Divider(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Flexible(
                  child: TextButton(
                    onPressed: () => _rejectLeave(lr),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error, visualDensity: VisualDensity.compact),
                    child: Text(loc.rejectLeave, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: ElevatedButton(
                    onPressed: () => _approveLeave(lr),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                    child: Text(loc.approveLeave, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  void _showCreateLeaveDialog() {
    String? selectedUserId;
    String leaveType = 'annual';
    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    DateTime endDate = DateTime.now().add(const Duration(days: 1));
    String reason = '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
      final days = endDate.difference(startDate).inDays + 1;
      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.event_busy, size: 20),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.createLeaveRequest, style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Nhân viên', border: OutlineInputBorder(), isDense: true),
              items: _staffList.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setDlg(() => selectedUserId = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: leaveType,
              decoration: InputDecoration(labelText: AppLocalizations.of(context)!.leaveType, border: const OutlineInputBorder(), isDense: true),
              items: ['annual', 'sick', 'unpaid', 'personal', 'maternity'].map((t) =>
                DropdownMenuItem(value: t, child: Text(LeaveRequest.leaveTypeDisplayVi(t), style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setDlg(() => leaveType = v ?? 'annual'),
            ),
            const SizedBox(height: 10),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${AppLocalizations.of(context)!.startDate}: ${DateFormat('dd/MM/yyyy').format(startDate)}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: startDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setDlg(() { startDate = d; if (endDate.isBefore(startDate)) endDate = startDate; });
              },
            ),
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${AppLocalizations.of(context)!.endDate}: ${DateFormat('dd/MM/yyyy').format(endDate)}', style: const TextStyle(fontSize: 13)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: endDate, firstDate: startDate, lastDate: startDate.add(const Duration(days: 90)));
                if (d != null) setDlg(() => endDate = d);
              },
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text('${AppLocalizations.of(context)!.totalDays}: $days ngày', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(labelText: AppLocalizations.of(context)!.leaveReason, border: const OutlineInputBorder(), isDense: true),
              onChanged: (v) => reason = v,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (selectedUserId == null) {
                NotificationService.showSnackBar('Chọn nhân viên', color: Colors.red);
                return;
              }
              final staff = _staffList.firstWhere((s) => s['id'] == selectedUserId);
              final lr = LeaveRequest(
                userId: selectedUserId!,
                email: staff['email'],
                name: staff['name'],
                leaveType: leaveType,
                startDate: DateFormat('yyyy-MM-dd').format(startDate),
                endDate: DateFormat('yyyy-MM-dd').format(endDate),
                totalDays: days.toDouble(),
                reason: reason.isNotEmpty ? reason : null,
                status: 'pending',
                createdAt: DateTime.now().millisecondsSinceEpoch,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
                isSynced: false,
              );
              Navigator.pop(ctx);
              final ok = await AttendanceApprovalService.createLeaveRequest(lr);
              if (ok) {
                NotificationService.showSnackBar('Đã tạo đơn xin nghỉ', color: AppColors.success);
                await _loadData();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(AppLocalizations.of(context)!.createLeaveRequest),
          ),
        ],
      );
    }));
  }

  Future<void> _approveLeave(LeaveRequest lr) async {
    final ok = await AttendanceApprovalService.approveLeaveRequest(lr);
    if (ok) {
      NotificationService.showSnackBar('Đã duyệt đơn xin nghỉ', color: AppColors.success);
      await _loadData();
    }
  }

  Future<void> _rejectLeave(LeaveRequest lr) async {
    final reason = await _showReasonDialog(AppLocalizations.of(context)!.rejectReasonHint);
    if (reason == null) return;
    final ok = await AttendanceApprovalService.rejectLeaveRequest(lr, reason);
    if (ok) {
      NotificationService.showSnackBar('Đã từ chối đơn xin nghỉ', color: AppColors.warning);
      await _loadData();
    }
  }

  // ==================== DETAIL SHEETS ====================

  void _showStaffDetail(Map<String, dynamic> staff, List<Attendance> records) {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noAttendanceData)),
      );
      return;
    }
    final record = records.first;
    final loc = AppLocalizations.of(context)!;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text((staff['name'] as String).substring(0, 1), style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(staff['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize)),
                Text(staff['email'], style: TextStyle(color: AppColors.inactive, fontSize: AppTextStyles.caption.fontSize)),
              ])),
              // Edit times button
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
                tooltip: loc.editCheckTime,
                onPressed: () { Navigator.pop(ctx); _showEditTimesDialog(record, staff); },
              ),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
            ]),
            const Divider(height: 16),
            _detailRow(loc.dateLabel, DateFormat('dd/MM/yyyy').format(_selectedDate)),
            _detailRow(loc.checkInTimeShort, record.checkInAt != null ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!)) : '--'),
            _detailRow(loc.checkOutTimeShort, record.checkOutAt != null ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!)) : '--'),
            _detailRow(loc.lateArrival, record.isLate == 1 ? loc.yes : loc.no),
            _detailRow(loc.earlyLeave, record.isEarlyLeave == 1 ? loc.yes : loc.no),
            _detailRow('Trạng thái', _statusDisplayVi(record.status)),
            if (record.overtimeOn > 0) _detailRow('Tăng ca', '${record.overtimeOn} phút'),
            if (record.overtimeStartAt != null && record.overtimeEndAt != null)
              _detailRow('Giờ TC', '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.overtimeStartAt!))} - ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(record.overtimeEndAt!))}'),
            if (record.note != null && record.note!.isNotEmpty) _detailRow('Ghi chú', record.note!),
            if (record.location != null) _detailRow(loc.locationLabel, record.location!),
            if (record.location != null && OsmMapService.parseLatLng(record.location) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final p = OsmMapService.parseLatLng(record.location);
                    if (p != null) await OsmMapService.openPoint(p[0], p[1]);
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('Xem vị trí', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            // Approve/Reject from detail
            if (record.status == 'pending' && record.checkInAt != null) ...[
              const Divider(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () { Navigator.pop(ctx); _rejectAttendance(record); },
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: Text(loc.rejectAttendance, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); _approveAttendance(record); },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                  child: Text(loc.approveAttendance, style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            // Photos
            if (record.photoIn != null || record.photoOut != null) ...[
              Text(loc.attendancePhotos, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline6.fontSize)),
              const SizedBox(height: 6),
              Row(children: [
                if (record.photoIn != null)
                  Expanded(child: Column(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: _buildAttendanceImage(record.photoIn!)),
                    const SizedBox(height: 4),
                    Text(loc.checkInPhoto, style: TextStyle(fontSize: AppTextStyles.caption.fontSize)),
                  ])),
                if (record.photoIn != null && record.photoOut != null) const SizedBox(width: 8),
                if (record.photoOut != null)
                  Expanded(child: Column(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: _buildAttendanceImage(record.photoOut!)),
                    const SizedBox(height: 4),
                    Text(loc.checkOutPhoto, style: TextStyle(fontSize: AppTextStyles.caption.fontSize)),
                  ])),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  void _showEditTimesDialog(Attendance record, Map<String, dynamic> staff) {
    TimeOfDay? newIn = record.checkInAt != null ? TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!)) : null;
    TimeOfDay? newOut = record.checkOutAt != null ? TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!)) : null;
    String note = '';

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.edit_calendar, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text('${AppLocalizations.of(context)!.editCheckTime} - ${staff['name']}', style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ngày: ${record.dateKey}', style: TextStyle(fontSize: 13, color: AppColors.inactive)),
          const SizedBox(height: 10),
          ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: Text('Giờ vào: ${newIn?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.access_time, size: 18),
            onTap: () async {
              final t = await showTimePicker(context: ctx, initialTime: newIn ?? const TimeOfDay(hour: 8, minute: 0));
              if (t != null) setDlg(() => newIn = t);
            },
          ),
          ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: Text('Giờ ra: ${newOut?.format(ctx) ?? '--:--'}', style: const TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.access_time, size: 18),
            onTap: () async {
              final t = await showTimePicker(context: ctx, initialTime: newOut ?? const TimeOfDay(hour: 17, minute: 0));
              if (t != null) setDlg(() => newOut = t);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => note = v,
            style: const TextStyle(fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final date = DateTime.parse(record.dateKey);
              final inMs = newIn != null ? DateTime(date.year, date.month, date.day, newIn!.hour, newIn!.minute).millisecondsSinceEpoch : null;
              final outMs = newOut != null ? DateTime(date.year, date.month, date.day, newOut!.hour, newOut!.minute).millisecondsSinceEpoch : null;
              Navigator.pop(ctx);
              final ok = await AttendanceApprovalService.editAttendanceTimes(
                record: record, checkInAt: inMs, checkOutAt: outMs, note: note.isNotEmpty ? note : null,
              );
              if (ok) {
                NotificationService.showSnackBar('Đã sửa giờ chấm công', color: AppColors.success);
                await _loadData();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Lưu'),
          ),
        ],
      );
    }));
  }

  void _showMonthDetail(Map<String, dynamic> staff, List<Attendance> records) {
    final loc = AppLocalizations.of(context)!;
    final summary = _summaryByUserId(staff['id'] as String);
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text((staff['name'] as String).substring(0, 1), style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(staff['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize)),
                Text(loc.monthYearFormat(DateFormat('MM/yyyy').format(_selectedMonth)), style: TextStyle(color: AppColors.inactive, fontSize: AppTextStyles.caption.fontSize)),
              ])),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
            ]),
            if (summary != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _monthFlag('Ngày công ${summary.workDays}', AppColors.primary),
                  _monthFlag('Đã duyệt ${summary.approvedDays}', AppColors.success),
                  _monthFlag('Chờ ${summary.pendingDays}', AppColors.warning),
                  _monthFlag('Giờ công ${summary.totalWorkLabel}', AppColors.primaryDark),
                  if (summary.overtimeMinutes > 0)
                    _monthFlag('OT ${summary.overtimeLabel}', Colors.deepOrange),
                ],
              ),
            ],
            const Divider(height: 16),
            Expanded(
              child: records.isEmpty
                  ? Center(child: Text(loc.noAttendanceData, style: TextStyle(color: AppColors.inactive)))
                  : ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (_, i) {
                        final r = records[i];
                        final statusColor = r.status == 'approved' ? AppColors.success : r.status == 'rejected' ? AppColors.error : AppColors.warning;
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: r.isLate == 1 ? AppColors.warning.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6)),
                            alignment: Alignment.center,
                            child: Text(r.dateKey.split('-').last, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: r.isLate == 1 ? AppColors.warning : AppColors.success)),
                          ),
                          title: Text(DateFormat('EEEE', 'vi').format(DateTime.parse(r.dateKey)), style: TextStyle(fontSize: AppTextStyles.caption.fontSize)),
                          subtitle: Text(
                            'Vào: ${r.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.checkInAt!)) : '--'} | Ra: ${r.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.checkOutAt!)) : '--'}${r.overtimeOn > 0 ? ' | OT: ${r.overtimeOn}p' : ''}',
                            style: TextStyle(fontSize: 11)),
                          trailing: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================

  Widget _buildAttendanceImage(String imagePath) {
    return FutureBuilder<String?>(
      future: StorageService.resolveDisplayUrl(imagePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(height: 100, color: Colors.grey[100], child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final url = snapshot.data;
        if (url == null || url.isEmpty) {
          return Container(height: 100, color: Colors.grey[200], child: const Icon(Icons.broken_image));
        }
        return AppCachedImage(imageUrl: url, height: 100, fit: BoxFit.cover, memCacheHeight: 200);
      },
    );
  }

  String _staffNameById(String userId) {
    final s = _staffList.cast<Map<String, dynamic>?>().firstWhere((s) => s?['id'] == userId, orElse: () => null);
    return (s?['name'] as String?) ?? (userId.length > 8 ? userId.substring(0, 8) : userId.isNotEmpty ? userId : 'N/A');
  }

  AttendanceMonthlySummary? _summaryByUserId(String userId) {
    for (final summary in _monthlySummaries) {
      if (summary.userId == userId) {
        return summary;
      }
    }
    return null;
  }

  Future<void> _exportMonthlySummary() async {
    if (_monthlySummaries.isEmpty) {
      NotificationService.showSnackBar(
        'Không có dữ liệu chấm công tháng để xuất',
        color: AppColors.warning,
      );
      return;
    }

    await ExcelExportHelper.exportAttendanceMonthlySummary(
      context,
      month: _selectedMonth,
      summaries: _monthlySummaries,
      staffAttendance: _staffAttendance,
    );
  }

  String _statusDisplayVi(String status) {
    switch (status) {
      case 'approved': return 'Đã duyệt ✓';
      case 'rejected': return 'Từ chối ✗';
      default: return 'Chờ duyệt';
    }
  }

  Widget _roleBadge(String? role) {
    final loc = AppLocalizations.of(context)!;
    String label;
    Color color;
    switch (role) {
      case 'owner': label = loc.roleOwnerShort; color = AppColors.primary; break;
      case 'manager': label = loc.roleManagerShort; color = AppColors.primary; break;
      case 'technician': label = loc.roleTechnicianShort; color = AppColors.success; break;
      default: label = loc.roleEmployeeShort; color = AppColors.inactive;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'owner': case 'manager': return AppColors.primary;
      case 'technician': return AppColors.success;
      default: return AppColors.inactive;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.inactive, fontSize: AppTextStyles.caption.fontSize)),
          Flexible(child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, fontSize: AppTextStyles.caption.fontSize), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Future<String?> _showReasonDialog(String hint) async {
    String reason = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lý do', style: TextStyle(fontSize: 16)),
        content: TextField(
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder(), isDense: true),
          onChanged: (v) => reason = v,
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              if (reason.trim().isEmpty) { NotificationService.showSnackBar('Nhập lý do', color: Colors.red); return; }
              Navigator.pop(ctx, reason.trim());
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }
}
