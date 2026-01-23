import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/employee_salary_model.dart';
import '../models/shop_deduction_settings.dart';
import '../models/salary_breakdown_model.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// TEST VIEW: Kịch bản chấm công & tính lương chi tiết
/// - 5+ nhân viên với các kịch bản đa dạng
/// - Đi muộn, về sớm, nghỉ nhiều, nghỉ ít, không chấm công
/// - Trừ bảo hiểm (BHXH, BHYT, BHTN)
/// - Trừ thuế thu nhập cá nhân (TNCN)
/// - Lương khác nhau: monthly, daily, hourly
class AttendanceSalaryTestView extends StatefulWidget {
  const AttendanceSalaryTestView({super.key});

  @override
  State<AttendanceSalaryTestView> createState() =>
      _AttendanceSalaryTestViewState();
}

class _AttendanceSalaryTestViewState extends State<AttendanceSalaryTestView> {
  final _db = DBHelper();
  final _fmt = NumberFormat('#,###', 'vi_VN');
  bool _loading = false;
  bool _dataGenerated = false;
  String _log = '';
  List<_TestEmployee> _employees = [];
  List<_SalaryResult> _salaryResults = [];
  Map<String, List<Attendance>> _generatedAttendance = {};
  ShopDeductionSettings? _deductionSettings;

  // Tháng test = tháng trước
  late int _testMonth;
  late int _testYear;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Test cho tháng trước để có đủ dữ liệu
    if (now.month == 1) {
      _testMonth = 12;
      _testYear = now.year - 1;
    } else {
      _testMonth = now.month - 1;
      _testYear = now.year;
    }
    _initEmployees();
  }

  void _initEmployees() {
    // Định nghĩa 6 nhân viên với các kịch bản khác nhau
    _employees = [
      _TestEmployee(
        id: 'test_emp_001',
        name: 'NGUYỄN VĂN A',
        email: 'nva@test.com',
        baseSalary: 15000000, // 15 triệu/tháng
        salaryType: 'monthly',
        scenario: _AttendanceScenario.perfect, // Đi đầy đủ, không trễ
        description: 'Đi đầy đủ 22 ngày, không trễ, không về sớm',
        numDependents: 2, // 2 người phụ thuộc
      ),
      _TestEmployee(
        id: 'test_emp_002',
        name: 'TRẦN THỊ B',
        email: 'ttb@test.com',
        baseSalary: 20000000, // 20 triệu/tháng - lương cao để đóng thuế
        salaryType: 'monthly',
        scenario: _AttendanceScenario.frequent_late, // Hay đi muộn
        description: 'Đi 20 ngày, 8 lần đi muộn, 3 lần về sớm - Thu nhập cao, đóng thuế',
        numDependents: 1,
      ),
      _TestEmployee(
        id: 'test_emp_003',
        name: 'LÊ VĂN C',
        email: 'lvc@test.com',
        baseSalary: 400000, // 400k/ngày
        salaryType: 'daily',
        scenario: _AttendanceScenario.many_absences, // Nghỉ nhiều
        description: 'Lương ngày 400k, nghỉ 10 ngày (chỉ đi 12 ngày), 2 lần trễ',
        numDependents: 0,
      ),
      _TestEmployee(
        id: 'test_emp_004',
        name: 'PHẠM THỊ D',
        email: 'ptd@test.com',
        baseSalary: 60000, // 60k/giờ
        salaryType: 'hourly',
        scenario: _AttendanceScenario.overtime, // Làm OT nhiều
        description: 'Lương giờ 60k, đi đủ 22 ngày, OT 20 giờ, 1 lần trễ',
        numDependents: 0,
      ),
      _TestEmployee(
        id: 'test_emp_005',
        name: 'HOÀNG VĂN E',
        email: 'hve@test.com',
        baseSalary: 25000000, // 25 triệu - lương rất cao để đóng thuế lũy tiến
        salaryType: 'monthly',
        scenario: _AttendanceScenario.early_leave, // Hay về sớm
        description: 'Lương cao 25tr, đi 18 ngày, 10 lần về sớm - Thuế lũy tiến bậc cao',
        numDependents: 3,
      ),
      _TestEmployee(
        id: 'test_emp_006',
        name: 'ĐẶNG THỊ F',
        email: 'dtf@test.com',
        baseSalary: 12000000, // 12 triệu
        salaryType: 'monthly',
        scenario: _AttendanceScenario.no_attendance, // Không chấm công
        description: 'KHÔNG CÓ CHẤM CÔNG trong tháng (nghỉ thai sản/ốm dài hạn)',
        numDependents: 1,
      ),
    ];
  }

  /// Tạo dữ liệu test
  Future<void> _generateTestData() async {
    setState(() {
      _loading = true;
      _log = '🚀 Bắt đầu tạo dữ liệu test...\n';
    });

    try {
      final shopId = await UserService.getCurrentShopId() ?? 'test_shop';
      
      // 1. Tạo cài đặt khấu trừ/thuế của shop
      _deductionSettings = ShopDeductionSettings(
        shopId: shopId,
        // Bật trừ đi muộn
        enableLateDeduction: true,
        lateDeductionPerTime: 50000, // 50k/lần
        lateGraceTimes: 2, // Được phép trễ 2 lần
        // Bật trừ về sớm
        enableEarlyLeaveDeduction: true,
        earlyLeaveDeductionPerTime: 30000, // 30k/lần
        earlyLeaveGraceTimes: 2, // Được phép về sớm 2 lần
        // Bật trừ nghỉ quá phép
        enableAbsenceDeduction: true,
        allowedAbsenceDays: 2, // Được nghỉ 2 ngày/tháng
        absenceDeductionPerDay: 200000, // 200k/ngày quá phép
        // Bật bảo hiểm
        enableSocialInsurance: true,
        socialInsuranceRate: 8.0, // BHXH 8%
        enableHealthInsurance: true,
        healthInsuranceRate: 1.5, // BHYT 1.5%
        enableUnemploymentInsurance: true,
        unemploymentInsuranceRate: 1.0, // BHTN 1%
        insuranceBaseSalary: 0, // Dùng lương cơ bản
        // Bật thuế TNCN
        enablePIT: true,
        pitDeductionSelf: 11000000, // Giảm trừ bản thân 11 triệu
        pitDeductionDependent: 4400000, // Giảm trừ người phụ thuộc 4.4 triệu/người
      );

      _addLog('✅ Đã tạo cài đặt khấu trừ/thuế shop');
      _addLog('   - Trừ đi muộn: 50,000đ/lần (miễn 2 lần)');
      _addLog('   - Trừ về sớm: 30,000đ/lần (miễn 2 lần)');
      _addLog('   - Nghỉ quá phép: 200,000đ/ngày (phép 2 ngày)');
      _addLog('   - BHXH: 8%, BHYT: 1.5%, BHTN: 1%');
      _addLog('   - Thuế TNCN: Bật (giảm trừ 11tr + 4.4tr/người PT)\n');

      // 2. Xóa dữ liệu test cũ
      await _clearOldTestData();
      _addLog('🗑️ Đã xóa dữ liệu test cũ\n');

      // 3. Tạo cài đặt lương cho từng nhân viên
      for (var emp in _employees) {
        await _createSalarySettings(emp, shopId);
      }
      _addLog('✅ Đã tạo cài đặt lương cho ${_employees.length} nhân viên\n');

      // 4. Tạo chấm công cho từng nhân viên
      _generatedAttendance.clear();
      for (var emp in _employees) {
        final attendanceList = await _createAttendanceData(emp, shopId);
        _generatedAttendance[emp.id] = attendanceList;
      }
      _addLog('✅ Đã tạo dữ liệu chấm công\n');

      // 5. Tính lương
      await _calculateSalaries();

      setState(() {
        _dataGenerated = true;
        _loading = false;
      });
    } catch (e, stack) {
      _addLog('❌ LỖI: $e\n$stack');
      setState(() => _loading = false);
    }
  }

  void _addLog(String msg) {
    setState(() => _log += '$msg\n');
  }

  Future<void> _clearOldTestData() async {
    // Xóa attendance test
    final db = await _db.database;
    await db.delete(
      'attendance',
      where: "userId LIKE 'test_emp_%'",
    );
    // Xóa salary settings test
    await db.delete(
      'employee_salary_settings',
      where: "staffId LIKE 'test_emp_%'",
    );
  }

  Future<void> _createSalarySettings(_TestEmployee emp, String shopId) async {
    final settings = EmployeeSalarySettings(
      id: 'settings_${emp.id}',
      staffId: emp.id,
      staffName: emp.name,
      shopId: shopId,
      baseSalary: emp.baseSalary,
      dailyRate: emp.salaryType == 'daily' ? emp.baseSalary : 0,
      salaryType: emp.salaryType,
      // Hoa hồng bán hàng
      saleCommType: 'percent',
      saleCommValue: 1.0, // 1% doanh số
      // Hoa hồng sửa chữa
      repairCommType: 'fixed_per_order',
      repairCommValue: 50000, // 50k/đơn
      // Phụ cấp
      transportAllowance: 500000, // 500k xăng xe
      mealAllowance: 700000, // 700k ăn trưa
      phoneAllowance: 200000, // 200k điện thoại
      otherAllowance: 0,
      // OT
      standardHoursPerDay: 8,
      overtimeRate: 150, // 1.5x
      // Target
      monthlyTarget: 50000000, // 50 triệu
      targetBonusPercent: 2, // 2% nếu đạt target
    );

    await _db.upsertEmployeeSalarySettings(settings.toMap());
    _addLog('   📝 ${emp.name}: ${_fmt.format(emp.baseSalary)}đ/${_getSalaryTypeLabel(emp.salaryType)}');
  }

  String _getSalaryTypeLabel(String type) {
    switch (type) {
      case 'daily': return 'ngày';
      case 'hourly': return 'giờ';
      default: return 'tháng';
    }
  }

  Future<List<Attendance>> _createAttendanceData(_TestEmployee emp, String shopId) async {
    final attendanceList = <Attendance>[];
    
    // Số ngày làm việc trong tháng (trừ CN)
    final daysInMonth = DateTime(_testYear, _testMonth + 1, 0).day;
    final workingDays = <DateTime>[];
    
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_testYear, _testMonth, d);
      if (date.weekday != DateTime.sunday) {
        workingDays.add(date);
      }
    }
    
    _addLog('   👤 ${emp.name} (${emp.scenario.name}):');
    
    switch (emp.scenario) {
      case _AttendanceScenario.perfect:
        // Đi đầy đủ, không trễ
        for (var date in workingDays) {
          final att = _createAttendance(
            emp, shopId, date,
            checkInHour: 8, checkInMin: 0, // Đúng giờ
            checkOutHour: 17, checkOutMin: 0, // Đúng giờ
            isLate: false, isEarlyLeave: false,
          );
          attendanceList.add(att);
          await _db.insertAttendance(att);
        }
        _addLog('      - Đi đủ ${workingDays.length} ngày, vào 8:00, ra 17:00');
        break;

      case _AttendanceScenario.frequent_late:
        // Hay đi muộn
        int lateDays = 0;
        int earlyDays = 0;
        for (int i = 0; i < workingDays.length; i++) {
          final date = workingDays[i];
          // Bỏ qua 2 ngày cuối (nghỉ)
          if (i >= workingDays.length - 2) continue;
          
          // 8 ngày đi muộn (30 phút)
          final isLate = i % 3 == 0 && lateDays < 8;
          if (isLate) lateDays++;
          
          // 3 ngày về sớm (1 tiếng)
          final isEarly = i % 7 == 0 && earlyDays < 3;
          if (isEarly) earlyDays++;
          
          final att = _createAttendance(
            emp, shopId, date,
            checkInHour: isLate ? 8 : 8,
            checkInMin: isLate ? 30 : 0,
            checkOutHour: isEarly ? 16 : 17,
            checkOutMin: 0,
            isLate: isLate,
            isEarlyLeave: isEarly,
          );
          attendanceList.add(att);
          await _db.insertAttendance(att);
        }
        _addLog('      - Đi ${attendanceList.length} ngày, trễ $lateDays lần, về sớm $earlyDays lần');
        break;

      case _AttendanceScenario.many_absences:
        // Nghỉ nhiều (chỉ đi 12 ngày)
        int lateDays = 0;
        for (int i = 0; i < 12 && i < workingDays.length; i++) {
          final date = workingDays[i];
          final isLate = i < 2;
          if (isLate) lateDays++;
          
          final att = _createAttendance(
            emp, shopId, date,
            checkInHour: isLate ? 8 : 8,
            checkInMin: isLate ? 15 : 0,
            checkOutHour: 17, checkOutMin: 0,
            isLate: isLate, isEarlyLeave: false,
          );
          attendanceList.add(att);
          await _db.insertAttendance(att);
        }
        final absentDays = workingDays.length - 12;
        _addLog('      - Chỉ đi 12 ngày, nghỉ $absentDays ngày, trễ $lateDays lần');
        break;

      case _AttendanceScenario.overtime:
        // Làm OT nhiều
        int otHours = 0;
        int lateDays = 0;
        for (int i = 0; i < workingDays.length; i++) {
          final date = workingDays[i];
          // 1 lần trễ
          final isLate = i == 5;
          if (isLate) lateDays++;
          
          // 10 ngày làm thêm 2 giờ
          final hasOT = i < 10;
          if (hasOT) otHours += 2;
          
          final att = _createAttendance(
            emp, shopId, date,
            checkInHour: isLate ? 8 : 8,
            checkInMin: isLate ? 20 : 0,
            checkOutHour: hasOT ? 19 : 17, // Ra 19h nếu OT
            checkOutMin: 0,
            isLate: isLate, isEarlyLeave: false,
            overtimeOn: hasOT ? 1 : 0,
          );
          attendanceList.add(att);
          await _db.insertAttendance(att);
        }
        _addLog('      - Đi đủ ${workingDays.length} ngày, OT $otHours giờ, trễ $lateDays lần');
        break;

      case _AttendanceScenario.early_leave:
        // Hay về sớm
        int earlyDays = 0;
        for (int i = 0; i < workingDays.length; i++) {
          final date = workingDays[i];
          // Bỏ 4 ngày cuối (nghỉ)
          if (i >= workingDays.length - 4) continue;
          
          // 10 ngày về sớm
          final isEarly = i % 2 == 0 && earlyDays < 10;
          if (isEarly) earlyDays++;
          
          final att = _createAttendance(
            emp, shopId, date,
            checkInHour: 8, checkInMin: 0,
            checkOutHour: isEarly ? 16 : 17,
            checkOutMin: isEarly ? 0 : 0,
            isLate: false,
            isEarlyLeave: isEarly,
          );
          attendanceList.add(att);
          await _db.insertAttendance(att);
        }
        _addLog('      - Đi ${attendanceList.length} ngày, về sớm $earlyDays lần');
        break;

      case _AttendanceScenario.no_attendance:
        // Không có chấm công
        _addLog('      - KHÔNG CÓ CHẤM CÔNG (0 ngày)');
        break;
    }
    
    return attendanceList;
  }

  Attendance _createAttendance(
    _TestEmployee emp,
    String shopId,
    DateTime date, {
    required int checkInHour,
    required int checkInMin,
    required int checkOutHour,
    required int checkOutMin,
    required bool isLate,
    required bool isEarlyLeave,
    int overtimeOn = 0,
  }) {
    final checkIn = DateTime(date.year, date.month, date.day, checkInHour, checkInMin);
    final checkOut = DateTime(date.year, date.month, date.day, checkOutHour, checkOutMin);
    
    return Attendance(
      firestoreId: 'test_att_${emp.id}_${DateFormat('yyyyMMdd').format(date)}',
      userId: emp.id,
      email: emp.email,
      name: emp.name,
      dateKey: DateFormat('yyyy-MM-dd').format(date),
      checkInAt: checkIn.millisecondsSinceEpoch,
      checkOutAt: checkOut.millisecondsSinceEpoch,
      overtimeOn: overtimeOn,
      status: 'approved',
      isLate: isLate ? 1 : 0,
      isEarlyLeave: isEarlyLeave ? 1 : 0,
      workSchedule: '08:00-17:00',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSynced: true,
    );
  }

  Future<void> _calculateSalaries() async {
    _addLog('📊 TÍNH LƯƠNG THÁNG $_testMonth/$_testYear\n');
    _salaryResults.clear();

    for (var emp in _employees) {
      final result = await _calculateEmployeeSalary(emp);
      _salaryResults.add(result);
    }
    
    _addLog('\n✅ Hoàn tất tính lương cho ${_employees.length} nhân viên');
  }

  Future<_SalaryResult> _calculateEmployeeSalary(_TestEmployee emp) async {
    // Lấy settings
    final settingsMap = await _db.getEmployeeSalarySettingByStaffId(emp.id);
    final settings = settingsMap != null 
        ? EmployeeSalarySettings.fromMap(settingsMap)
        : EmployeeSalarySettings(
            id: '', staffId: emp.id, staffName: emp.name, shopId: '',
          );

    // Lấy chấm công
    final attendanceList = _generatedAttendance[emp.id] ?? [];
    
    // Tính các chỉ số chấm công
    int workDays = attendanceList.length;
    double totalWorkHours = 0;
    double overtimeHours = 0;
    int lateDays = 0;
    int earlyLeaveDays = 0;
    
    for (var att in attendanceList) {
      if (att.checkInAt != null && att.checkOutAt != null) {
        final hours = (att.checkOutAt! - att.checkInAt!) / 3600000.0;
        totalWorkHours += hours;
        
        // Tính OT
        if (hours > settings.standardHoursPerDay && att.overtimeOn == 1) {
          overtimeHours += hours - settings.standardHoursPerDay;
        }
      }
      if (att.isLate == 1) lateDays++;
      if (att.isEarlyLeave == 1) earlyLeaveDays++;
    }
    
    // Số ngày làm việc tiêu chuẩn trong tháng
    final workingDaysInMonth = _getWorkingDaysInMonth(_testYear, _testMonth);
    final absentDays = workingDaysInMonth - workDays;

    // ===== TÍNH LƯƠNG =====
    
    // 1. Lương cơ bản
    double calculatedBaseSalary = 0;
    switch (settings.salaryType) {
      case 'monthly':
        calculatedBaseSalary = settings.baseSalary;
        break;
      case 'daily':
        calculatedBaseSalary = settings.dailyRate * workDays;
        break;
      case 'hourly':
        calculatedBaseSalary = settings.baseSalary * totalWorkHours;
        break;
    }

    // 2. Tính OT
    double calculatedOT = 0;
    if (overtimeHours > 0) {
      double hourlyRate;
      if (settings.salaryType == 'hourly') {
        hourlyRate = settings.baseSalary;
      } else if (settings.salaryType == 'daily') {
        hourlyRate = settings.dailyRate / settings.standardHoursPerDay;
      } else {
        hourlyRate = settings.baseSalary / 26 / settings.standardHoursPerDay;
      }
      calculatedOT = overtimeHours * hourlyRate * (settings.overtimeRate / 100);
    }

    // 3. Phụ cấp
    double calculatedAllowance = settings.transportAllowance + 
        settings.mealAllowance + 
        settings.phoneAllowance + 
        settings.otherAllowance;

    // 4. GROSS
    double grossIncome = calculatedBaseSalary + calculatedOT + calculatedAllowance;

    // ===== KHẤU TRỪ =====
    final ds = _deductionSettings!;
    
    // 5. Trừ đi muộn
    double lateDeduction = 0;
    if (ds.enableLateDeduction && lateDays > ds.lateGraceTimes) {
      lateDeduction = (lateDays - ds.lateGraceTimes) * ds.lateDeductionPerTime;
    }

    // 6. Trừ về sớm
    double earlyLeaveDeduction = 0;
    if (ds.enableEarlyLeaveDeduction && earlyLeaveDays > ds.earlyLeaveGraceTimes) {
      earlyLeaveDeduction = (earlyLeaveDays - ds.earlyLeaveGraceTimes) * ds.earlyLeaveDeductionPerTime;
    }

    // 7. Trừ nghỉ quá phép
    double absenceDeduction = 0;
    if (ds.enableAbsenceDeduction && absentDays > ds.allowedAbsenceDays) {
      absenceDeduction = (absentDays - ds.allowedAbsenceDays) * ds.absenceDeductionPerDay;
    }

    // 8. Bảo hiểm
    double insuranceBase = ds.insuranceBaseSalary > 0 
        ? ds.insuranceBaseSalary 
        : settings.baseSalary;
    
    double socialInsurance = ds.enableSocialInsurance 
        ? insuranceBase * (ds.socialInsuranceRate / 100) 
        : 0;
    double healthInsurance = ds.enableHealthInsurance 
        ? insuranceBase * (ds.healthInsuranceRate / 100) 
        : 0;
    double unemploymentInsurance = ds.enableUnemploymentInsurance 
        ? insuranceBase * (ds.unemploymentInsuranceRate / 100) 
        : 0;
    double totalInsurance = socialInsurance + healthInsurance + unemploymentInsurance;

    // 9. Thuế TNCN
    double selfDeduction = ds.enablePIT ? ds.pitDeductionSelf : 0;
    double dependentDeduction = ds.enablePIT 
        ? emp.numDependents * ds.pitDeductionDependent 
        : 0;
    
    double taxableIncome = 0;
    double personalIncomeTax = 0;
    
    if (ds.enablePIT) {
      taxableIncome = grossIncome - totalInsurance - selfDeduction - dependentDeduction;
      if (taxableIncome < 0) taxableIncome = 0;
      personalIncomeTax = _calculatePIT(taxableIncome);
    }

    // 10. Tổng khấu trừ
    double totalDeductions = lateDeduction + 
        earlyLeaveDeduction + 
        absenceDeduction + 
        totalInsurance + 
        personalIncomeTax;

    // 11. LƯƠNG THỰC NHẬN
    double netSalary = grossIncome - totalDeductions;

    return _SalaryResult(
      employee: emp,
      workDays: workDays,
      totalWorkHours: totalWorkHours,
      overtimeHours: overtimeHours,
      lateDays: lateDays,
      earlyLeaveDays: earlyLeaveDays,
      absentDays: absentDays,
      calculatedBaseSalary: calculatedBaseSalary,
      calculatedOT: calculatedOT,
      calculatedAllowance: calculatedAllowance,
      grossIncome: grossIncome,
      lateDeduction: lateDeduction,
      earlyLeaveDeduction: earlyLeaveDeduction,
      absenceDeduction: absenceDeduction,
      socialInsurance: socialInsurance,
      healthInsurance: healthInsurance,
      unemploymentInsurance: unemploymentInsurance,
      totalInsurance: totalInsurance,
      selfDeduction: selfDeduction,
      dependentDeduction: dependentDeduction,
      taxableIncome: taxableIncome,
      personalIncomeTax: personalIncomeTax,
      totalDeductions: totalDeductions,
      netSalary: netSalary,
    );
  }

  /// Tính thuế TNCN theo biểu lũy tiến từng phần
  double _calculatePIT(double taxableIncome) {
    if (taxableIncome <= 0) return 0;
    
    // Biểu thuế lũy tiến từng phần (đơn vị: triệu đồng)
    final brackets = [
      (limit: 5000000.0, rate: 0.05),     // Bậc 1: ≤5tr: 5%
      (limit: 10000000.0, rate: 0.10),    // Bậc 2: 5-10tr: 10%
      (limit: 18000000.0, rate: 0.15),    // Bậc 3: 10-18tr: 15%
      (limit: 32000000.0, rate: 0.20),    // Bậc 4: 18-32tr: 20%
      (limit: 52000000.0, rate: 0.25),    // Bậc 5: 32-52tr: 25%
      (limit: 80000000.0, rate: 0.30),    // Bậc 6: 52-80tr: 30%
      (limit: double.infinity, rate: 0.35), // Bậc 7: >80tr: 35%
    ];
    
    double tax = 0;
    double remainingIncome = taxableIncome;
    double previousLimit = 0;
    
    for (var bracket in brackets) {
      if (remainingIncome <= 0) break;
      
      final taxableAtBracket = (bracket.limit - previousLimit).clamp(0.0, remainingIncome);
      tax += taxableAtBracket * bracket.rate;
      remainingIncome -= taxableAtBracket;
      previousLimit = bracket.limit;
    }
    
    return tax;
  }

  int _getWorkingDaysInMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    int count = 0;
    for (int d = 1; d <= lastDay; d++) {
      final date = DateTime(year, month, d);
      if (date.weekday != DateTime.sunday) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEST: Chấm công & Tính lương'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header với nút tạo data
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              border: Border(bottom: BorderSide(color: Colors.purple.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🧪 KỊCH BẢN TEST CHẤM CÔNG & TÍNH LƯƠNG',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tháng test: $_testMonth/$_testYear (${_getWorkingDaysInMonth(_testYear, _testMonth)} ngày làm việc)',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _generateTestData,
                        icon: _loading 
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_loading ? 'Đang tạo...' : 'TẠO DATA TEST'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_dataGenerated) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _dataGenerated = false;
                          _log = '';
                          _salaryResults.clear();
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('RESET'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Nội dung
          Expanded(
            child: _dataGenerated 
                ? _buildResultsView()
                : _buildEmployeeListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeListView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Thông tin cài đặt
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚙️ CÀI ĐẶT KHẤU TRỪ/THUẾ SẼ ÁP DỤNG:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _buildSettingRow('Trừ đi muộn', '50,000đ/lần (miễn 2 lần)'),
                _buildSettingRow('Trừ về sớm', '30,000đ/lần (miễn 2 lần)'),
                _buildSettingRow('Nghỉ quá phép', '200,000đ/ngày (phép 2 ngày)'),
                _buildSettingRow('BHXH', '8% lương cơ bản'),
                _buildSettingRow('BHYT', '1.5% lương cơ bản'),
                _buildSettingRow('BHTN', '1% lương cơ bản'),
                _buildSettingRow('Thuế TNCN', 'Biểu lũy tiến 5%-35%'),
                _buildSettingRow('Giảm trừ bản thân', '11,000,000đ'),
                _buildSettingRow('Giảm trừ người PT', '4,400,000đ/người'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Danh sách nhân viên
        const Text(
          '👥 DANH SÁCH NHÂN VIÊN TEST:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        
        ..._employees.map((emp) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getScenarioColor(emp.scenario),
              child: Text(
                emp.name.substring(emp.name.lastIndexOf(' ') + 1, emp.name.lastIndexOf(' ') + 2),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lương: ${_fmt.format(emp.baseSalary)}đ/${_getSalaryTypeLabel(emp.salaryType)}',
                  style: TextStyle(color: Colors.green.shade700),
                ),
                Text(
                  emp.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (emp.numDependents > 0)
                  Text(
                    '👨‍👩‍👧‍👦 ${emp.numDependents} người phụ thuộc',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
              ],
            ),
            isThreeLine: true,
          ),
        )),
        
        // Log
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('📋 LOG:', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _log,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultsView() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.purple.shade100,
            child: TabBar(
              labelColor: Colors.purple.shade800,
              unselectedLabelColor: Colors.grey.shade600,
              tabs: const [
                Tab(text: '📊 KẾT QUẢ TÍNH LƯƠNG'),
                Tab(text: '📋 CHI TIẾT LOG'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSalaryResultsTab(),
                _buildLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryResultsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _salaryResults.length,
      itemBuilder: (context, index) {
        final result = _salaryResults[index];
        return _buildSalaryResultCard(result);
      },
    );
  }

  Widget _buildSalaryResultCard(_SalaryResult result) {
    final emp = result.employee;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getScenarioColor(emp.scenario),
          child: Text(
            emp.name.substring(emp.name.lastIndexOf(' ') + 1, emp.name.lastIndexOf(' ') + 2),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(emp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emp.description, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildMiniChip('GROSS', result.grossIncome, Colors.blue),
                const SizedBox(width: 8),
                _buildMiniChip('NET', result.netSalary, Colors.green),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chấm công
                _buildSection('📅 CHẤM CÔNG', [
                  _buildDetailRow('Ngày làm việc', '${result.workDays} ngày'),
                  _buildDetailRow('Tổng giờ làm', '${result.totalWorkHours.toStringAsFixed(1)} giờ'),
                  _buildDetailRow('Giờ OT', '${result.overtimeHours.toStringAsFixed(1)} giờ'),
                  _buildDetailRow('Đi muộn', '${result.lateDays} lần', 
                      isWarning: result.lateDays > 2),
                  _buildDetailRow('Về sớm', '${result.earlyLeaveDays} lần',
                      isWarning: result.earlyLeaveDays > 2),
                  _buildDetailRow('Nghỉ', '${result.absentDays} ngày',
                      isWarning: result.absentDays > 2),
                ]),
                
                const Divider(),
                
                // Thu nhập
                _buildSection('💰 THU NHẬP (GROSS)', [
                  _buildDetailRow('Lương cơ bản', _fmt.format(result.calculatedBaseSalary)),
                  if (result.calculatedOT > 0)
                    _buildDetailRow('Tiền OT', _fmt.format(result.calculatedOT)),
                  _buildDetailRow('Phụ cấp', _fmt.format(result.calculatedAllowance)),
                  _buildDetailRow('TỔNG GROSS', _fmt.format(result.grossIncome), 
                      isBold: true, color: Colors.blue),
                ]),
                
                const Divider(),
                
                // Khấu trừ
                _buildSection('➖ KHẤU TRỪ', [
                  if (result.lateDeduction > 0)
                    _buildDetailRow('Trừ đi muộn', '-${_fmt.format(result.lateDeduction)}', 
                        color: Colors.red),
                  if (result.earlyLeaveDeduction > 0)
                    _buildDetailRow('Trừ về sớm', '-${_fmt.format(result.earlyLeaveDeduction)}',
                        color: Colors.red),
                  if (result.absenceDeduction > 0)
                    _buildDetailRow('Trừ nghỉ quá phép', '-${_fmt.format(result.absenceDeduction)}',
                        color: Colors.red),
                  _buildDetailRow('BHXH (8%)', '-${_fmt.format(result.socialInsurance)}'),
                  _buildDetailRow('BHYT (1.5%)', '-${_fmt.format(result.healthInsurance)}'),
                  _buildDetailRow('BHTN (1%)', '-${_fmt.format(result.unemploymentInsurance)}'),
                ]),
                
                // Thuế TNCN
                if (result.personalIncomeTax > 0) ...[
                  const Divider(),
                  _buildSection('🏛️ THUẾ TNCN', [
                    _buildDetailRow('Giảm trừ bản thân', '-${_fmt.format(result.selfDeduction)}'),
                    if (result.dependentDeduction > 0)
                      _buildDetailRow('Giảm trừ người PT (${emp.numDependents})', 
                          '-${_fmt.format(result.dependentDeduction)}'),
                    _buildDetailRow('Thu nhập chịu thuế', _fmt.format(result.taxableIncome)),
                    _buildDetailRow('Thuế TNCN', '-${_fmt.format(result.personalIncomeTax)}',
                        color: Colors.red, isBold: true),
                  ]),
                ],
                
                const Divider(thickness: 2),
                
                // Tổng kết
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TỔNG KHẤU TRỪ:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '-${_fmt.format(result.totalDeductions)}đ',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '💵 LƯƠNG THỰC NHẬN (NET):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${_fmt.format(result.netSalary)}đ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {
    bool isBold = false,
    Color? color,
    bool isWarning = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: 13,
            color: isWarning ? Colors.orange.shade700 : Colors.grey.shade700,
          )),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? (isWarning ? Colors.orange.shade700 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '$label: ${_fmt.format(value)}đ',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('• $label: ', style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildLogTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          _log,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    );
  }

  Color _getScenarioColor(_AttendanceScenario scenario) {
    switch (scenario) {
      case _AttendanceScenario.perfect:
        return Colors.green;
      case _AttendanceScenario.frequent_late:
        return Colors.orange;
      case _AttendanceScenario.many_absences:
        return Colors.red;
      case _AttendanceScenario.overtime:
        return Colors.blue;
      case _AttendanceScenario.early_leave:
        return Colors.purple;
      case _AttendanceScenario.no_attendance:
        return Colors.grey;
    }
  }
}

/// Enum các kịch bản chấm công
enum _AttendanceScenario {
  perfect,        // Đi đầy đủ, không trễ
  frequent_late,  // Hay đi muộn
  many_absences,  // Nghỉ nhiều
  overtime,       // Làm OT nhiều
  early_leave,    // Hay về sớm
  no_attendance,  // Không chấm công
}

/// Model nhân viên test
class _TestEmployee {
  final String id;
  final String name;
  final String email;
  final double baseSalary;
  final String salaryType;
  final _AttendanceScenario scenario;
  final String description;
  final int numDependents;

  _TestEmployee({
    required this.id,
    required this.name,
    required this.email,
    required this.baseSalary,
    required this.salaryType,
    required this.scenario,
    required this.description,
    this.numDependents = 0,
  });
}

/// Model kết quả tính lương
class _SalaryResult {
  final _TestEmployee employee;
  final int workDays;
  final double totalWorkHours;
  final double overtimeHours;
  final int lateDays;
  final int earlyLeaveDays;
  final int absentDays;
  final double calculatedBaseSalary;
  final double calculatedOT;
  final double calculatedAllowance;
  final double grossIncome;
  final double lateDeduction;
  final double earlyLeaveDeduction;
  final double absenceDeduction;
  final double socialInsurance;
  final double healthInsurance;
  final double unemploymentInsurance;
  final double totalInsurance;
  final double selfDeduction;
  final double dependentDeduction;
  final double taxableIncome;
  final double personalIncomeTax;
  final double totalDeductions;
  final double netSalary;

  _SalaryResult({
    required this.employee,
    required this.workDays,
    required this.totalWorkHours,
    required this.overtimeHours,
    required this.lateDays,
    required this.earlyLeaveDays,
    required this.absentDays,
    required this.calculatedBaseSalary,
    required this.calculatedOT,
    required this.calculatedAllowance,
    required this.grossIncome,
    required this.lateDeduction,
    required this.earlyLeaveDeduction,
    required this.absenceDeduction,
    required this.socialInsurance,
    required this.healthInsurance,
    required this.unemploymentInsurance,
    required this.totalInsurance,
    required this.selfDeduction,
    required this.dependentDeduction,
    required this.taxableIncome,
    required this.personalIncomeTax,
    required this.totalDeductions,
    required this.netSalary,
  });
}
