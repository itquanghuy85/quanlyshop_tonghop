import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Trang theo dõi chấm công nhân viên cho quản lý/chủ shop
/// Hiển thị tổng quan chấm công của tất cả nhân viên
class AttendanceManagementView extends StatefulWidget {
  const AttendanceManagementView({super.key});

  @override
  State<AttendanceManagementView> createState() => _AttendanceManagementViewState();
}

class _AttendanceManagementViewState extends State<AttendanceManagementView> {
  final db = DBHelper();
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime.now();
  
  List<Map<String, dynamic>> _staffList = [];
  Map<String, List<Attendance>> _staffAttendance = {};
  Map<String, Map<String, dynamic>> _monthlyStats = {};
  
  String? _currentShopId;
  
  // View mode: 'day' or 'month'
  String _viewMode = 'day';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    _currentShopId = await UserService.getCurrentShopId();
    await _loadStaffList();
    await _loadAttendanceData();
    
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
      
      // Sort by role priority
      _staffList.sort((a, b) {
        const roleOrder = {'owner': 0, 'manager': 1, 'technician': 2, 'employee': 3};
        return (roleOrder[a['role']] ?? 4).compareTo(roleOrder[b['role']] ?? 4);
      });
    } catch (e) {
      debugPrint('Error loading staff list: $e');
    }
  }

  Future<void> _loadAttendanceData() async {
    _staffAttendance.clear();
    _monthlyStats.clear();
    
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
        // TRY LOCAL DB FIRST (faster, always available)
        final local = await db.getAttendance(dateKey, userId);
        if (local != null) {
          _staffAttendance[userId] = [local];
          continue;
        }
        
        // Fallback to Firestore if local not found
        if (_currentShopId != null) {
          final doc = await FirebaseFirestore.instance
              .collection('attendance')
              .where('shopId', isEqualTo: _currentShopId)
              .where('userId', isEqualTo: userId)
              .where('dateKey', isEqualTo: dateKey)
              .limit(1)
              .get();
          
          if (doc.docs.isNotEmpty) {
            final data = doc.docs.first.data();
            _staffAttendance[userId] = [Attendance.fromMap(data)];
          } else {
            _staffAttendance[userId] = [];
          }
        } else {
          _staffAttendance[userId] = [];
        }
      } catch (e) {
        debugPrint('Error loading attendance for $userId: $e');
        // Final fallback to empty
        _staffAttendance[userId] = [];
      }
    }
  }

  Future<void> _loadMonthAttendance() async {
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startKey = DateFormat('yyyy-MM-dd').format(startOfMonth);
    final endKey = DateFormat('yyyy-MM-dd').format(endOfMonth);
    
    // TRY LOADING FROM LOCAL DB FIRST for all staff
    final allLocalRecords = await db.getAttendanceByDateRange(startKey, endKey);
    
    for (final staff in _staffList) {
      final userId = staff['id'] as String;
      try {
        // Check local DB records first
        final localRecords = allLocalRecords.where((r) => r.userId == userId).toList();
        if (localRecords.isNotEmpty) {
          _staffAttendance[userId] = localRecords;
          
          // Calculate stats
          int totalDays = localRecords.length;
          int lateDays = localRecords.where((r) => r.isLate == 1).length;
          int earlyLeaveDays = localRecords.where((r) => r.isEarlyLeave == 1).length;
          int totalHours = 0;
          for (final r in localRecords) {
            if (r.checkInAt != null && r.checkOutAt != null) {
              totalHours += ((r.checkOutAt! - r.checkInAt!) / 3600000).round();
            }
          }
          _monthlyStats[userId] = {
            'totalDays': totalDays,
            'lateDays': lateDays,
            'earlyLeaveDays': earlyLeaveDays,
            'totalHours': totalHours,
          };
          continue;
        }
        
        // Fallback to Firestore if local empty and shopId available
        if (_currentShopId != null) {
          final snapshot = await FirebaseFirestore.instance
              .collection('attendance')
              .where('shopId', isEqualTo: _currentShopId)
              .where('userId', isEqualTo: userId)
              .where('dateKey', isGreaterThanOrEqualTo: startKey)
              .where('dateKey', isLessThanOrEqualTo: endKey)
              .get();
        
          final records = snapshot.docs.map((doc) => Attendance.fromMap(doc.data())).toList();
          _staffAttendance[userId] = records;
          
          // Calculate monthly stats
          int totalDays = records.length;
          int lateDays = records.where((r) => r.isLate == 1).length;
          int earlyLeaveDays = records.where((r) => r.isEarlyLeave == 1).length;
          int totalHours = 0;
          
          for (final r in records) {
            if (r.checkInAt != null && r.checkOutAt != null) {
              totalHours += ((r.checkOutAt! - r.checkInAt!) / 3600000).round();
            }
          }
          
          _monthlyStats[userId] = {
            'totalDays': totalDays,
            'lateDays': lateDays,
            'earlyLeaveDays': earlyLeaveDays,
            'totalHours': totalHours,
          };
        } else {
          _staffAttendance[userId] = [];
          _monthlyStats[userId] = {'totalDays': 0, 'lateDays': 0, 'earlyLeaveDays': 0, 'totalHours': 0};
        }
      } catch (e) {
        debugPrint('Error loading month attendance for $userId: $e');
        _staffAttendance[userId] = [];
        _monthlyStats[userId] = {'totalDays': 0, 'lateDays': 0, 'earlyLeaveDays': 0, 'totalHours': 0};
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text('THEO DÕI CHẤM CÔNG', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Toggle view mode
          IconButton(
            icon: Icon(_viewMode == 'day' ? Icons.calendar_month : Icons.calendar_today),
            tooltip: _viewMode == 'day' ? 'Xem theo tháng' : 'Xem theo ngày',
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 'day' ? 'month' : 'day';
              });
              _loadAttendanceData().then((_) => setState(() {}));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary header
                _buildSummaryHeader(),
                // Date/Month selector
                _buildDateSelector(),
                // Staff attendance list
                Expanded(child: _buildStaffAttendanceList()),
              ],
            ),
    );
  }

  Widget _buildSummaryHeader() {
    int presentToday = 0;
    int lateToday = 0;
    int absentToday = 0;
    
    if (_viewMode == 'day') {
      for (final staff in _staffList) {
        final records = _staffAttendance[staff['id']] ?? [];
        if (records.isNotEmpty && records.first.checkInAt != null) {
          presentToday++;
          if (records.first.isLate == 1) lateToday++;
        } else {
          absentToday++;
        }
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Text(
            _viewMode == 'day' 
                ? 'CHẤM CÔNG NGÀY ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'
                : 'THÁNG ${DateFormat('MM/yyyy').format(_selectedMonth)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (_viewMode == 'day')
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryItem('Có mặt', presentToday, Colors.greenAccent),
                _summaryItem('Đi muộn', lateToday, Colors.orangeAccent),
                _summaryItem('Vắng', absentToday, Colors.redAccent),
                _summaryItem('Tổng NV', _staffList.length, Colors.white),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryItem('Tổng NV', _staffList.length, Colors.white),
                _summaryItem('Đã chấm công', _staffAttendance.values.where((v) => v.isNotEmpty).length, Colors.greenAccent),
              ],
            ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
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
              onTap: () => _pickDate(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  _viewMode == 'day'
                      ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(_selectedDate)
                      : DateFormat('MMMM yyyy', 'vi').format(_selectedMonth),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
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
          // Jump to today
          TextButton(
            onPressed: () {
              setState(() {
                _selectedDate = DateTime.now();
                _selectedMonth = DateTime.now();
              });
              _loadAttendanceData().then((_) => setState(() {}));
            },
            child: const Text('Hôm nay'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    if (_viewMode == 'day') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) {
        setState(() => _selectedDate = picked);
        _loadAttendanceData().then((_) => setState(() {}));
      }
    } else {
      // Month picker
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedMonth,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDatePickerMode: DatePickerMode.year,
      );
      if (picked != null) {
        setState(() => _selectedMonth = DateTime(picked.year, picked.month));
        _loadAttendanceData().then((_) => setState(() {}));
      }
    }
  }

  Widget _buildStaffAttendanceList() {
    if (_staffList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Chưa có nhân viên', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _staffList.length,
      itemBuilder: (context, index) {
        final staff = _staffList[index];
        return _buildStaffCard(staff);
      },
    );
  }

  Widget _buildStaffCard(Map<String, dynamic> staff) {
    final userId = staff['id'] as String;
    final records = _staffAttendance[userId] ?? [];
    final stats = _monthlyStats[userId];
    
    if (_viewMode == 'day') {
      return _buildDayCard(staff, records);
    } else {
      return _buildMonthCard(staff, records, stats);
    }
  }

  Widget _buildDayCard(Map<String, dynamic> staff, List<Attendance> records) {
    final hasCheckedIn = records.isNotEmpty && records.first.checkInAt != null;
    final hasCheckedOut = records.isNotEmpty && records.first.checkOutAt != null;
    final isLate = records.isNotEmpty && records.first.isLate == 1;
    final isEarly = records.isNotEmpty && records.first.isEarlyLeave == 1;
    
    Color statusColor = Colors.grey;
    String statusText = 'Chưa chấm công';
    IconData statusIcon = Icons.remove_circle_outline;
    
    if (hasCheckedIn && hasCheckedOut) {
      statusColor = isLate || isEarly ? Colors.orange : Colors.green;
      statusText = 'Hoàn thành';
      statusIcon = Icons.check_circle;
    } else if (hasCheckedIn) {
      statusColor = isLate ? Colors.orange : Colors.blue;
      statusText = 'Đang làm việc';
      statusIcon = Icons.work;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showStaffDetail(staff, records),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar with status
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _getRoleColor(staff['role']).withOpacity(0.2),
                    child: Text(
                      (staff['name'] as String).substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: _getRoleColor(staff['role']),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          staff['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleBadge(staff['role']),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                        if (isLate) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Đi muộn',
                              style: TextStyle(color: Colors.orange, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Time info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasCheckedIn)
                    Text(
                      'Vào: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(records.first.checkInAt!))}',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  if (hasCheckedOut)
                    Text(
                      'Ra: ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(records.first.checkOutAt!))}',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  if (!hasCheckedIn)
                    const Text('--:--', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthCard(Map<String, dynamic> staff, List<Attendance> records, Map<String, dynamic>? stats) {
    final totalDays = stats?['totalDays'] ?? 0;
    final lateDays = stats?['lateDays'] ?? 0;
    final totalHours = stats?['totalHours'] ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showMonthDetail(staff, records),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _getRoleColor(staff['role']).withOpacity(0.2),
                    child: Text(
                      (staff['name'] as String).substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: _getRoleColor(staff['role']),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(staff['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            _buildRoleBadge(staff['role']),
                          ],
                        ),
                        Text(staff['email'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _monthStatItem('Ngày công', '$totalDays', Colors.blue),
                  _monthStatItem('Đi muộn', '$lateDays', Colors.orange),
                  _monthStatItem('Giờ làm', '${totalHours}h', Colors.green),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(String? role) {
    String label;
    Color color;
    
    switch (role) {
      case 'owner':
        label = 'Chủ';
        color = Colors.purple;
        break;
      case 'manager':
        label = 'QL';
        color = Colors.blue;
        break;
      case 'technician':
        label = 'KT';
        color = Colors.teal;
        break;
      default:
        label = 'NV';
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'owner':
        return Colors.purple;
      case 'manager':
        return Colors.blue;
      case 'technician':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  void _showStaffDetail(Map<String, dynamic> staff, List<Attendance> records) {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có dữ liệu chấm công')),
      );
      return;
    }
    
    final record = records.first;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    (staff['name'] as String).substring(0, 1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(staff['email'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Attendance info
            _detailRow('Ngày', DateFormat('dd/MM/yyyy').format(_selectedDate)),
            _detailRow('Giờ vào', record.checkInAt != null 
                ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(record.checkInAt!))
                : '--'),
            _detailRow('Giờ ra', record.checkOutAt != null 
                ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(record.checkOutAt!))
                : '--'),
            _detailRow('Đi muộn', record.isLate == 1 ? 'Có' : 'Không'),
            _detailRow('Về sớm', record.isEarlyLeave == 1 ? 'Có' : 'Không'),
            if (record.location != null)
              _detailRow('Vị trí', record.location!),
            
            const SizedBox(height: 16),
            
            // Photos
            if (record.photoIn != null || record.photoOut != null) ...[
              const Text('Ảnh chấm công:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (record.photoIn != null)
                    Expanded(
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              record.photoIn!,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Vào', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  if (record.photoIn != null && record.photoOut != null)
                    const SizedBox(width: 12),
                  if (record.photoOut != null)
                    Expanded(
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              record.photoOut!,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Ra', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMonthDetail(Map<String, dynamic> staff, List<Attendance> records) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    (staff['name'] as String).substring(0, 1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Tháng ${DateFormat('MM/yyyy').format(_selectedMonth)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // List of days
            Expanded(
              child: records.isEmpty
                  ? const Center(child: Text('Chưa có dữ liệu chấm công'))
                  : ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final r = records[index];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: r.isLate == 1 ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              r.dateKey.split('-').last,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: r.isLate == 1 ? Colors.orange : Colors.green,
                              ),
                            ),
                          ),
                          title: Text(
                            DateFormat('EEEE', 'vi').format(DateTime.parse(r.dateKey)),
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            'Vào: ${r.checkInAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.checkInAt!)) : '--'} | Ra: ${r.checkOutAt != null ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.checkOutAt!)) : '--'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: r.isLate == 1
                              ? const Icon(Icons.warning, color: Colors.orange, size: 16)
                              : const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
