import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/salary_breakdown_model.dart';
import '../services/encryption_service.dart';
import '../models/employee_salary_model.dart';
import '../models/shop_deduction_settings.dart';
import 'firestore_service.dart';
import 'user_service.dart';

/// Service tính lương nhân viên tự động
/// Kết hợp: Cài đặt lương + Chấm công + Doanh số + Thuế + Bảo hiểm + Khấu trừ
class SalaryCalculationService {
  static final DBHelper _db = DBHelper();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// So sánh linh hoạt giữa giá trị trên đơn (sellerName/repairedBy/createdBy)
  /// với thông tin nhân viên (email prefix + displayName).
  /// sellerName/repairedBy thường lưu dạng email prefix uppercase (VD: "HUY")
  /// còn staffName từ Firestore users có thể là displayName (VD: "Nguyen Van Huy")
  static bool _matchesStaff(String? value, String emailPrefix, String displayName) {
    if (value == null || value.isEmpty) return false;
    final v = value.toUpperCase();
    return v == emailPrefix || v == displayName || v.contains(emailPrefix);
  }

  /// Tính lương chi tiết cho một nhân viên trong tháng
  static Future<SalaryBreakdown> calculateMonthlySalary({
    required String staffId,
    required String staffName,
    required int month,
    required int year,
    String? staffEmail, // Email để trích xuất prefix so khớp với sellerName/repairedBy
    ShopDeductionSettings? deductionSettings,
    List<CustomSalaryAdjustment>? customAdjustments,
    int numDependents = 0, // Số người phụ thuộc (để tính giảm trừ thuế)
  }) async {
    final notes = <String>[];

    // Chuẩn bị email prefix và displayName cho matching
    final emailPrefix = (staffEmail ?? '').split('@').first.toUpperCase();
    final displayName = staffName.toUpperCase();

    debugPrint('📊 [SalaryCalc] $staffName: matching with emailPrefix=$emailPrefix, displayName=$displayName');

    // ===== 1. LẤY CÀI ĐẶT LƯƠNG =====
    EmployeeSalarySettings? settings;

    // Thử lấy từ local DB trước
    final localSettings = await _db.getEmployeeSalarySettingByStaffId(staffId);
    if (localSettings != null) {
      settings = EmployeeSalarySettings.fromMap(localSettings);
      notes.add('📋 Dùng cài đặt riêng của nhân viên');
    } else {
      // Dùng shop defaults
      final defaults = await FirestoreService.getShopDefaultSalarySettings();
      if (defaults != null) {
        settings = EmployeeSalarySettings(
          id: '',
          staffId: staffId,
          staffName: staffName,
          shopId: defaults['shopId'] ?? '',
          baseSalary: (defaults['baseSalary'] ?? 0).toDouble(),
          dailyRate: (defaults['dailyRate'] ?? 0).toDouble(),
          salaryType: defaults['salaryType'] ?? 'monthly',
          saleCommType: defaults['saleCommType'] ?? 'percent',
          saleCommValue: (defaults['saleCommValue'] ?? 1.0).toDouble(),
          saleCommTier1Max: (defaults['saleCommTier1Max'] ?? 10000000).toDouble(),
          saleCommTier1Value: (defaults['saleCommTier1Value'] ?? 20000).toDouble(),
          saleCommTier2Max: (defaults['saleCommTier2Max'] ?? 50000000).toDouble(),
          saleCommTier2Value: (defaults['saleCommTier2Value'] ?? 50000).toDouble(),
          saleCommTier3Value: (defaults['saleCommTier3Value'] ?? 100000).toDouble(),
          repairCommType: defaults['repairCommType'] ?? 'percent',
          repairCommValue: (defaults['repairCommValue'] ?? 10.0).toDouble(),
          transportAllowance: (defaults['transportAllowance'] ?? 0).toDouble(),
          mealAllowance: (defaults['mealAllowance'] ?? 0).toDouble(),
          phoneAllowance: (defaults['phoneAllowance'] ?? 0).toDouble(),
          otherAllowance: (defaults['otherAllowance'] ?? 0).toDouble(),
          standardHoursPerDay: (defaults['standardHoursPerDay'] ?? 8.0)
              .toDouble(),
          overtimeRate: (defaults['overtimeRate'] ?? 150).toDouble(),
          monthlyTarget: (defaults['monthlyTarget'] ?? 0).toDouble(),
          targetBonusPercent: (defaults['targetBonusPercent'] ?? 0).toDouble(),
        );
        notes.add('📋 Dùng cài đặt mặc định của shop');
      }
    }

    // Nếu không có settings, tạo mặc định
    settings ??= EmployeeSalarySettings(
      id: '',
      staffId: staffId,
      staffName: staffName,
      shopId: '',
    );

    // ===== 2. LẤY CÀI ĐẶT KHẤU TRỪ/THUẾ CỦA SHOP =====
    deductionSettings ??= await getShopDeductionSettings();

    // ===== 2.5 LẤY LỊCH LÀM VIỆC CỦA NHÂN VIÊN =====
    List<int> configuredWorkDays = [1, 2, 3, 4, 5, 6]; // Default Mon-Sat (Dart weekday)
    try {
      // Ưu tiên lịch riêng của nhân viên, fallback sang shop_general
      var schedule = await _db.getWorkSchedule(staffId);
      if (schedule == null || schedule['workDays'] == null) {
        schedule = await _db.getWorkSchedule('shop_general');
      }
      if (schedule != null && schedule['workDays'] != null) {
        final wd = schedule['workDays'];
        configuredWorkDays = _parseWorkDays(wd);
        debugPrint('📊 [SalaryCalc] $staffName: workDays config (Dart weekday) = $configuredWorkDays');
      }
    } catch (e) {
      debugPrint('📊 [SalaryCalc] Error loading work schedule: $e');
    }

    // ===== 3. LẤY DỮ LIỆU CHẤM CÔNG TỪ FIRESTORE =====
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0); // Ngày cuối tháng
    final startKey = DateFormat('yyyy-MM-dd').format(startDate);
    final endKey = DateFormat('yyyy-MM-dd').format(endDate);

    debugPrint('📊 [SalaryCalc] $staffName: Lọc chấm công từ $startKey đến $endKey');

    // Tính toán chấm công
    int workDays = 0;
    double totalWorkHours = 0;
    double overtimeHours = 0;
    int lateDays = 0;
    int earlyLeaveDays = 0;

    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null) {
        // Lấy chấm công từ Firestore theo dateKey range
        final attendanceSnapshot = await _firestore
            .collection('attendance')
            .where('shopId', isEqualTo: shopId)
            .where('userId', isEqualTo: staffId)
            .where('dateKey', isGreaterThanOrEqualTo: startKey)
            .where('dateKey', isLessThanOrEqualTo: endKey)
            .get();
        
        debugPrint('📊 [SalaryCalc] $staffName: Firestore tìm thấy ${attendanceSnapshot.docs.length} bản ghi chấm công');
        
        for (final doc in attendanceSnapshot.docs) {
          var data = doc.data();
          data = EncryptionService.decryptMap(data);
          
          final deleted = data['deleted'] == true;
          final checkInAt = data['checkInAt'] as int?;
          final checkOutAt = data['checkOutAt'] as int?;
          
          if (!deleted && checkInAt != null) {
            workDays++;

            // Tính giờ làm
            if (checkOutAt != null) {
              final hours = (checkOutAt - checkInAt) / 3600000.0;
              totalWorkHours += hours;

              // Tính OT: Giờ vượt quá giờ chuẩn
              if (hours > settings.standardHoursPerDay) {
                overtimeHours += hours - settings.standardHoursPerDay;
              }
            }

            // Đếm đi muộn/về sớm
            if (data['isLate'] == 1) lateDays++;
            if (data['isEarlyLeave'] == 1) earlyLeaveDays++;

            // Thêm OT đã được ghi nhận
            final overtimeOn = (data['overtimeOn'] ?? 0).toDouble();
            if (overtimeOn > 0) {
              overtimeHours += overtimeOn / 60.0;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching attendance from Firestore: $e');
      // Fallback to local DB
      final attendanceRecords = await _db.getAttendanceByDateRange(startKey, endKey);
      final staffAttendance = attendanceRecords.where((r) => r.userId == staffId).toList();
      
      for (final record in staffAttendance) {
        if (record.checkInAt != null) {
          workDays++;
          if (record.checkOutAt != null) {
            final hours = (record.checkOutAt! - record.checkInAt!) / 3600000.0;
            totalWorkHours += hours;
            if (hours > settings.standardHoursPerDay) {
              overtimeHours += hours - settings.standardHoursPerDay;
            }
          }
          if (record.isLate == 1) lateDays++;
          if (record.isEarlyLeave == 1) earlyLeaveDays++;
          if (record.overtimeOn > 0) {
            overtimeHours += record.overtimeOn / 60.0;
          }
        }
      }
    }

    debugPrint('📊 [SalaryCalc] $staffName: Tìm thấy $workDays ngày chấm công trong tháng $month/$year');

    // Tính số ngày nghỉ (dựa trên số ngày làm việc tiêu chuẩn trong tháng)
    final workingDaysInMonth = _getWorkingDaysInMonth(year, month, configuredWorkDays);
    // Đảm bảo absentDays không âm (nếu NV làm thêm ngày)
    final absentDays = (workingDaysInMonth - workDays).clamp(0, workingDaysInMonth);

    notes.add(
      '📅 Chấm công: $workDays/$workingDaysInMonth ngày, ${totalWorkHours.toStringAsFixed(1)}h làm việc',
    );
    if (overtimeHours > 0) {
      notes.add('⏰ OT: ${overtimeHours.toStringAsFixed(1)} giờ');
    }
    if (lateDays > 0) {
      notes.add('⚠️ Đi muộn: $lateDays lần');
    }
    if (earlyLeaveDays > 0) {
      notes.add('⚠️ Về sớm: $earlyLeaveDays lần');
    }
    if (absentDays > 0) {
      notes.add('❌ Nghỉ: $absentDays ngày');
    }

    // ===== 4. LẤY DOANH SỐ BÁN HÀNG TỪ FIRESTORE =====
    final startMs = startDate.millisecondsSinceEpoch;
    final endMs = DateTime(
      year,
      month + 1,
      0,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;

    // Lấy từ Firestore để đảm bảo đồng nhất giữa các thiết bị
    int saleOrderCount = 0;
    double saleRevenue = 0;
    double saleProfit = 0;
    List<double> saleOrderValues = []; // Lưu giá trị từng đơn cho tính tiered
    
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null) {
        final salesSnapshot = await _firestore
            .collection('sales')
            .where('shopId', isEqualTo: shopId)
            .where('soldAt', isGreaterThanOrEqualTo: startMs)
            .where('soldAt', isLessThanOrEqualTo: endMs)
            .get();
        
        for (final doc in salesSnapshot.docs) {
          var data = doc.data();
          // Decrypt if needed
          data = EncryptionService.decryptMap(data);
          
          final sellerName = (data['sellerName'] ?? '').toString();
          final deleted = data['deleted'] == true;
          
          if (!deleted && _matchesStaff(sellerName, emailPrefix, displayName)) {
            saleOrderCount++;
            final totalPrice = (data['totalPrice'] ?? 0).toDouble();
            final discountVal = (data['discount'] ?? 0).toDouble();
            final finalPrice = totalPrice - discountVal > 0 ? totalPrice - discountVal : 0.0;
            final totalCost = (data['totalCost'] ?? 0).toDouble();
            saleRevenue += finalPrice;
            saleProfit += (finalPrice - totalCost);
            saleOrderValues.add(finalPrice); // Lưu giá trị đơn (sau giảm giá)
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching sales from Firestore: $e');
      // Fallback to local DB if Firestore fails
      final allSales = await _db.getAllSales();
      final staffSales = allSales
          .where((s) =>
              _matchesStaff(s.sellerName, emailPrefix, displayName) &&
              s.soldAt >= startMs &&
              s.soldAt <= endMs)
          .toList();
      saleOrderCount = staffSales.length;
      saleRevenue = staffSales.fold(0.0, (sum, s) => sum + s.finalPrice);
      saleProfit = staffSales.fold(0.0, (sum, s) => sum + (s.finalPrice - s.totalCost));
      saleOrderValues = staffSales.map((s) => s.finalPrice.toDouble()).toList();
    }

    if (saleOrderCount > 0) {
      notes.add(
        '🛒 Bán hàng: $saleOrderCount đơn, doanh số ${_formatCurrency(saleRevenue)}',
      );
    }

    // ===== 5. LẤY DOANH SỐ SỬA CHỮA TỪ FIRESTORE =====
    int repairOrderCount = 0;
    double repairRevenue = 0;
    double repairProfit = 0;
    
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null) {
        // Lấy repairs đã giao trong tháng (status = 4)
        final repairsSnapshot = await _firestore
            .collection('repairs')
            .where('shopId', isEqualTo: shopId)
            .where('status', isEqualTo: 4)
            .get();
        
        for (final doc in repairsSnapshot.docs) {
          var data = doc.data();
          // Decrypt if needed
          data = EncryptionService.decryptMap(data);
          
          // Doanh số sửa chữa chỉ tính cho người sửa xong (repairedBy), không tính cho người nhận/giao
          final repairedBy = (data['repairedBy'] ?? '').toString();
          final createdBy = (data['createdBy'] ?? '').toString();
          final deleted = data['deleted'] == true;
          final deliveredAt = data['deliveredAt'] as int?;
          
          // Match by repairedBy, or fallback to createdBy for old repairs
          final matchesByRepaired = _matchesStaff(repairedBy, emailPrefix, displayName);
          final matchesByCreated = repairedBy.isEmpty && _matchesStaff(createdBy, emailPrefix, displayName);
          
          if (!deleted && 
              (matchesByRepaired || matchesByCreated) &&
              deliveredAt != null &&
              deliveredAt >= startMs &&
              deliveredAt <= endMs) {
            repairOrderCount++;
            final price = (data['price'] ?? 0).toDouble();
            final totalCost = (data['totalCost'] ?? 0).toDouble();
            repairRevenue += price;
            repairProfit += (price - totalCost);
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching repairs from Firestore: $e');
      // Fallback to local DB if Firestore fails
      final allRepairs = await _db.getAllRepairs();
      final staffRepairs = allRepairs
          .where((r) {
              final matchRepaired = _matchesStaff(r.repairedBy, emailPrefix, displayName);
              final matchCreated = (r.repairedBy == null || r.repairedBy!.isEmpty) &&
                  _matchesStaff(r.createdBy, emailPrefix, displayName);
              return (matchRepaired || matchCreated) &&
                  r.status == 4 &&
                  r.deliveredAt != null &&
                  r.deliveredAt! >= startMs &&
                  r.deliveredAt! <= endMs;
          })
          .toList();
      repairOrderCount = staffRepairs.length;
      repairRevenue = staffRepairs.fold(0.0, (sum, r) => sum + r.price);
      repairProfit = staffRepairs.fold(0.0, (sum, r) => sum + (r.price - r.totalCost));
    }

    if (repairOrderCount > 0) {
      notes.add(
        '🔧 Sửa chữa: $repairOrderCount đơn, lợi nhuận ${_formatCurrency(repairProfit)}',
      );
    }

    // ===== 6. TÍNH TOÁN TỪNG KHOẢN THU NHẬP =====
    notes.add('');
    notes.add('═══ THU NHẬP ═══');

    // (1) LƯƠNG CƠ BẢN
    double calculatedBaseSalary = 0;
    switch (settings.salaryType) {
      case 'monthly':
        calculatedBaseSalary = settings.baseSalary;
        notes.add('💰 Lương tháng: ${_formatCurrency(calculatedBaseSalary)}');
        break;
      case 'daily':
        calculatedBaseSalary = settings.dailyRate * workDays;
        notes.add(
          '💰 Lương ngày: ${_formatCurrency(settings.dailyRate)} × $workDays ngày = ${_formatCurrency(calculatedBaseSalary)}',
        );
        break;
      case 'hourly':
        final hourlyRate =
            settings.baseSalary; // baseSalary là lương/giờ khi type = hourly
        calculatedBaseSalary = hourlyRate * totalWorkHours;
        notes.add(
          '💰 Lương giờ: ${_formatCurrency(hourlyRate)} × ${totalWorkHours.toStringAsFixed(1)}h = ${_formatCurrency(calculatedBaseSalary)}',
        );
        break;
    }

    // (2) HOA HỒNG BÁN HÀNG
    double calculatedSaleComm = 0;
    if (settings.saleCommType == 'percent') {
      calculatedSaleComm = saleRevenue * (settings.saleCommValue / 100);
      if (saleRevenue > 0) {
        notes.add(
          '🛒 HH bán: ${_formatCurrency(saleRevenue)} × ${settings.saleCommValue}% = ${_formatCurrency(calculatedSaleComm)}',
        );
      }
    } else if (settings.saleCommType == 'tiered') {
      // Tính hoa hồng theo bậc - dùng giá trị thực từng đơn
      if (saleOrderValues.isNotEmpty) {
        // Đếm số đơn theo từng bậc
        int tier1Count = 0;
        int tier2Count = 0;
        int tier3Count = 0;
        for (final orderValue in saleOrderValues) {
          final comm = settings.calculateSaleCommission(orderValue);
          calculatedSaleComm += comm;
          // Đếm bậc
          if (orderValue < settings.saleCommTier1Max) {
            tier1Count++;
          } else if (orderValue <= settings.saleCommTier2Max) {
            tier2Count++;
          } else {
            tier3Count++;
          }
        }
        // Ghi chú chi tiết từng bậc
        List<String> tierDetails = [];
        if (tier1Count > 0) {
          tierDetails.add('$tier1Count đơn bậc 1 (${_formatCurrency(settings.saleCommTier1Value)})');
        }
        if (tier2Count > 0) {
          tierDetails.add('$tier2Count đơn bậc 2 (${_formatCurrency(settings.saleCommTier2Value)})');
        }
        if (tier3Count > 0) {
          tierDetails.add('$tier3Count đơn bậc 3 (${_formatCurrency(settings.saleCommTier3Value)})');
        }
        notes.add(
          '🛒 HH bậc: ${tierDetails.join(', ')} = ${_formatCurrency(calculatedSaleComm)}',
        );
      }
    } else {
      // fixed_per_order
      calculatedSaleComm = settings.saleCommValue * saleOrderCount;
      if (saleOrderCount > 0) {
        notes.add(
          '🛒 HH bán: ${_formatCurrency(settings.saleCommValue)} × $saleOrderCount đơn = ${_formatCurrency(calculatedSaleComm)}',
        );
      }
    }

    // (3) HOA HỒNG SỬA CHỮA
    double calculatedRepairComm = 0;
    if (settings.repairCommType == 'percent') {
      // Guard: negative profit should not generate negative commission
      final effectiveRepairProfit = repairProfit > 0 ? repairProfit : 0.0;
      calculatedRepairComm = effectiveRepairProfit * (settings.repairCommValue / 100);
      if (repairProfit > 0) {
        notes.add(
          '🔧 HH sửa: ${_formatCurrency(repairProfit)} × ${settings.repairCommValue}% = ${_formatCurrency(calculatedRepairComm)}',
        );
      } else if (repairProfit < 0) {
        notes.add(
          '🔧 HH sửa: Lợi nhuận âm ${_formatCurrency(repairProfit)} → HH = 0',
        );
      }
    } else {
      calculatedRepairComm = settings.repairCommValue * repairOrderCount;
      if (repairOrderCount > 0) {
        notes.add(
          '🔧 HH sửa: ${_formatCurrency(settings.repairCommValue)} × $repairOrderCount đơn = ${_formatCurrency(calculatedRepairComm)}',
        );
      }
    }

    // (4) TIỀN OT
    double calculatedOT = 0;
    if (overtimeHours > 0) {
      // Tính lương giờ chuẩn
      double hourlyRate;
      if (settings.salaryType == 'hourly') {
        hourlyRate = settings.baseSalary;
      } else if (settings.salaryType == 'daily') {
        hourlyRate = settings.dailyRate / settings.standardHoursPerDay;
      } else {
        // monthly: chia cho 26 ngày, rồi chia cho giờ chuẩn
        hourlyRate = settings.baseSalary / 26 / settings.standardHoursPerDay;
      }

      // Tiền OT = Giờ OT × Lương giờ × Hệ số OT
      calculatedOT = overtimeHours * hourlyRate * (settings.overtimeRate / 100);
      notes.add(
        '⏰ OT: ${overtimeHours.toStringAsFixed(1)}h × ${_formatCurrency(hourlyRate)} × ${(settings.overtimeRate / 100).toStringAsFixed(1)} = ${_formatCurrency(calculatedOT)}',
      );
    }

    // (5) THƯỞNG DOANH SỐ
    double calculatedBonus = 0;
    final totalRevenue = saleRevenue + repairRevenue;
    if (settings.monthlyTarget > 0 && totalRevenue >= settings.monthlyTarget) {
      calculatedBonus = totalRevenue * (settings.targetBonusPercent / 100);
      notes.add(
        '🎯 Thưởng: Đạt target ${_formatCurrency(settings.monthlyTarget)} → ${settings.targetBonusPercent}% = ${_formatCurrency(calculatedBonus)}',
      );
    } else if (settings.monthlyTarget > 0) {
      final progress = (totalRevenue / settings.monthlyTarget * 100)
          .toStringAsFixed(0);
      notes.add(
        '🎯 Target: ${_formatCurrency(totalRevenue)} / ${_formatCurrency(settings.monthlyTarget)} ($progress%)',
      );
    }

    // (6) PHỤ CẤP
    double calculatedAllowance =
        settings.transportAllowance +
        settings.mealAllowance +
        settings.phoneAllowance +
        settings.otherAllowance;
    if (calculatedAllowance > 0) {
      notes.add('🎁 Phụ cấp: ${_formatCurrency(calculatedAllowance)}');
    }

    // ===== 7. KHOẢN THƯỞNG/TRỪ TÙY CHỈNH =====
    final customBonuses = <CustomSalaryAdjustment>[];
    final customDeductions = <CustomSalaryAdjustment>[];

    if (customAdjustments != null) {
      for (final adj in customAdjustments) {
        if (adj.staffId == staffId && adj.month == month && adj.year == year) {
          if (adj.isBonus) {
            customBonuses.add(adj);
          } else {
            customDeductions.add(adj);
          }
        }
      }
    }

    double totalCustomBonuses = customBonuses.fold(
      0.0,
      (sum, b) => sum + b.amount,
    );
    double totalCustomDeductions = customDeductions.fold(
      0.0,
      (sum, d) => sum + d.amount,
    );

    if (customBonuses.isNotEmpty) {
      notes.add('');
      notes.add('═══ THƯỞNG TÙY CHỈNH ═══');
      for (final b in customBonuses) {
        notes.add('🎉 ${b.name}: +${_formatCurrency(b.amount)}');
      }
    }

    // ===== 8. TÍNH TỔNG THU NHẬP GROSS =====
    double grossIncome =
        calculatedBaseSalary +
        calculatedSaleComm +
        calculatedRepairComm +
        calculatedOT +
        calculatedBonus +
        calculatedAllowance +
        totalCustomBonuses;

    notes.add('');
    notes.add('═══ KHẤU TRỪ ═══');

    // ===== 9. KHẤU TRỪ ĐI MUỘN/VỀ SỚM/NGHỈ QUÁ PHÉP =====
    double lateDeduction = 0;
    double earlyLeaveDeduction = 0;
    double absenceDeduction = 0;

    // (a) Trừ đi muộn
    if (deductionSettings.enableLateDeduction &&
        lateDays > deductionSettings.lateGraceTimes) {
      final penaltyTimes = lateDays - deductionSettings.lateGraceTimes;
      lateDeduction = penaltyTimes * deductionSettings.lateDeductionPerTime;
      notes.add(
        '⚠️ Đi muộn: $lateDays lần (miễn ${deductionSettings.lateGraceTimes}) → $penaltyTimes × ${_formatCurrency(deductionSettings.lateDeductionPerTime)} = -${_formatCurrency(lateDeduction)}',
      );
    }

    // (b) Trừ về sớm
    if (deductionSettings.enableEarlyLeaveDeduction &&
        earlyLeaveDays > deductionSettings.earlyLeaveGraceTimes) {
      final penaltyTimes =
          earlyLeaveDays - deductionSettings.earlyLeaveGraceTimes;
      earlyLeaveDeduction =
          penaltyTimes * deductionSettings.earlyLeaveDeductionPerTime;
      notes.add(
        '⚠️ Về sớm: $earlyLeaveDays lần (miễn ${deductionSettings.earlyLeaveGraceTimes}) → $penaltyTimes × ${_formatCurrency(deductionSettings.earlyLeaveDeductionPerTime)} = -${_formatCurrency(earlyLeaveDeduction)}',
      );
    }

    // (c) Trừ nghỉ quá phép
    if (deductionSettings.enableAbsenceDeduction &&
        absentDays > deductionSettings.allowedAbsenceDays) {
      final excessDays = absentDays - deductionSettings.allowedAbsenceDays;
      absenceDeduction = excessDays * deductionSettings.absenceDeductionPerDay;
      notes.add(
        '❌ Nghỉ quá phép: $absentDays ngày (phép ${deductionSettings.allowedAbsenceDays}) → $excessDays × ${_formatCurrency(deductionSettings.absenceDeductionPerDay)} = -${_formatCurrency(absenceDeduction)}',
      );
    }

    // Khoản trừ tùy chỉnh
    if (customDeductions.isNotEmpty) {
      for (final d in customDeductions) {
        notes.add('📌 ${d.name}: -${_formatCurrency(d.amount)}');
      }
    }

    // ===== 10. TÍNH BẢO HIỂM =====
    double socialInsurance = 0;
    double healthInsurance = 0;
    double unemploymentInsurance = 0;

    // Mức lương đóng BH (dùng insuranceBaseSalary nếu có, không thì dùng baseSalary)
    double insuranceBase = deductionSettings.insuranceBaseSalary > 0
        ? deductionSettings.insuranceBaseSalary
        : settings.baseSalary;

    if (deductionSettings.enableSocialInsurance) {
      socialInsurance =
          insuranceBase * (deductionSettings.socialInsuranceRate / 100);
      notes.add(
        '🏥 BHXH (${deductionSettings.socialInsuranceRate}%): ${_formatCurrency(insuranceBase)} × ${deductionSettings.socialInsuranceRate}% = -${_formatCurrency(socialInsurance)}',
      );
    }

    if (deductionSettings.enableHealthInsurance) {
      healthInsurance =
          insuranceBase * (deductionSettings.healthInsuranceRate / 100);
      notes.add(
        '💊 BHYT (${deductionSettings.healthInsuranceRate}%): ${_formatCurrency(insuranceBase)} × ${deductionSettings.healthInsuranceRate}% = -${_formatCurrency(healthInsurance)}',
      );
    }

    if (deductionSettings.enableUnemploymentInsurance) {
      unemploymentInsurance =
          insuranceBase * (deductionSettings.unemploymentInsuranceRate / 100);
      notes.add(
        '📋 BHTN (${deductionSettings.unemploymentInsuranceRate}%): ${_formatCurrency(insuranceBase)} × ${deductionSettings.unemploymentInsuranceRate}% = -${_formatCurrency(unemploymentInsurance)}',
      );
    }

    double totalInsurance =
        socialInsurance + healthInsurance + unemploymentInsurance;

    // ===== 11. TÍNH THUẾ TNCN =====
    double selfDeduction = 0;
    double dependentDeduction = 0;
    double taxableIncome = 0;
    double personalIncomeTax = 0;

    if (deductionSettings.enablePIT) {
      // Giảm trừ bản thân
      selfDeduction = deductionSettings.pitDeductionSelf;
      // Giảm trừ người phụ thuộc
      dependentDeduction =
          numDependents * deductionSettings.pitDeductionDependent;

      // Thu nhập chịu thuế = GROSS - BH - Giảm trừ
      taxableIncome = PITCalculator.calculateTaxableIncome(
        grossIncome: grossIncome,
        insuranceDeduction: totalInsurance,
        selfDeduction: selfDeduction,
        dependentDeduction: dependentDeduction,
      );

      // Tính thuế theo biểu lũy tiến
      personalIncomeTax = PITCalculator.calculatePIT(taxableIncome);

      notes.add('');
      notes.add('═══ THUẾ TNCN ═══');
      notes.add('📊 Thu nhập GROSS: ${_formatCurrency(grossIncome)}');
      notes.add('📊 Trừ BH: -${_formatCurrency(totalInsurance)}');
      notes.add('📊 Giảm trừ bản thân: -${_formatCurrency(selfDeduction)}');
      if (numDependents > 0) {
        notes.add(
          '📊 Giảm trừ $numDependents người phụ thuộc: -${_formatCurrency(dependentDeduction)}',
        );
      }
      notes.add('📊 Thu nhập chịu thuế: ${_formatCurrency(taxableIncome)}');
      notes.add('💸 Thuế TNCN: -${_formatCurrency(personalIncomeTax)}');
    }

    // ===== 12. TỔNG KHẤU TRỪ =====
    double totalDeductions =
        lateDeduction +
        earlyLeaveDeduction +
        absenceDeduction +
        totalCustomDeductions +
        totalInsurance +
        personalIncomeTax;

    // ===== 13. TỔNG LƯƠNG THỰC NHẬN (NET) =====
    double totalSalary = grossIncome - totalDeductions;

    notes.add('');
    notes.add('═══════════════════════════');
    notes.add('💰 GROSS: ${_formatCurrency(grossIncome)}');
    notes.add('➖ Tổng khấu trừ: ${_formatCurrency(totalDeductions)}');
    notes.add('💵 NET (Thực nhận): ${_formatCurrency(totalSalary)}');

    return SalaryBreakdown(
      staffId: staffId,
      staffName: staffName,
      month: month,
      year: year,
      // Chấm công
      workDays: workDays,
      totalWorkHours: totalWorkHours,
      overtimeHours: overtimeHours,
      lateDays: lateDays,
      earlyLeaveDays: earlyLeaveDays,
      absentDays: absentDays,
      // Doanh số
      saleOrderCount: saleOrderCount,
      saleRevenue: saleRevenue,
      saleProfit: saleProfit,
      repairOrderCount: repairOrderCount,
      repairRevenue: repairRevenue,
      repairProfit: repairProfit,
      // Cài đặt
      salaryType: settings.salaryType,
      baseSalary: settings.baseSalary,
      saleCommType: settings.saleCommType,
      saleCommValue: settings.saleCommValue,
      repairCommType: settings.repairCommType,
      repairCommValue: settings.repairCommValue,
      overtimeRate: settings.overtimeRate,
      monthlyTarget: settings.monthlyTarget,
      targetBonusPercent: settings.targetBonusPercent,
      standardHoursPerDay: settings.standardHoursPerDay,
      transportAllowance: settings.transportAllowance,
      mealAllowance: settings.mealAllowance,
      phoneAllowance: settings.phoneAllowance,
      otherAllowance: settings.otherAllowance,
      // Thu nhập
      calculatedBaseSalary: calculatedBaseSalary,
      calculatedSaleComm: calculatedSaleComm,
      calculatedRepairComm: calculatedRepairComm,
      calculatedOT: calculatedOT,
      calculatedBonus: calculatedBonus,
      calculatedAllowance: calculatedAllowance,
      // Thưởng/trừ tùy chỉnh
      customBonuses: customBonuses,
      customDeductions: customDeductions,
      // Khấu trừ quy định
      lateDeduction: lateDeduction,
      earlyLeaveDeduction: earlyLeaveDeduction,
      absenceDeduction: absenceDeduction,
      // Bảo hiểm
      socialInsurance: socialInsurance,
      healthInsurance: healthInsurance,
      unemploymentInsurance: unemploymentInsurance,
      // Thuế
      grossIncomeBeforeTax: grossIncome,
      insuranceDeduction: totalInsurance,
      selfDeduction: selfDeduction,
      dependentDeduction: dependentDeduction,
      taxableIncome: taxableIncome,
      personalIncomeTax: personalIncomeTax,
      // Tổng
      totalDeductions: totalDeductions,
      totalSalary: totalSalary,
      calculationNotes: notes,
    );
  }

  /// Lấy cài đặt khấu trừ/thuế của shop
  static Future<ShopDeductionSettings> getShopDeductionSettings() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return ShopDeductionSettings();

      final settings = await FirestoreService.getShopDeductionSettings(shopId);
      if (settings != null) {
        return ShopDeductionSettings.fromMap(settings);
      }
    } catch (e) {
      debugPrint('Error getting shop deduction settings: $e');
    }
    return ShopDeductionSettings();
  }

  /// Lưu cài đặt khấu trừ/thuế của shop
  static Future<bool> saveShopDeductionSettings(
    ShopDeductionSettings settings,
  ) async {
    var shopId = await UserService.getCurrentShopId();
    if (shopId == null || shopId.isEmpty) {
      try {
        shopId = await UserService.ensureShopId(maxRetries: 3);
      } catch (e) {
        debugPrint('Error ensuring shopId for saving deduction settings: $e');
        rethrow;
      }
    }

    final data = settings.copyWith(shopId: shopId).toMap();
    return await FirestoreService.saveShopDeductionSettings(shopId, data);
  }

  /// Lấy danh sách khoản thưởng/trừ tùy chỉnh của nhân viên trong tháng
  static Future<List<CustomSalaryAdjustment>> getCustomAdjustments({
    required String staffId,
    required int month,
    required int year,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final data = await FirestoreService.getCustomSalaryAdjustments(
        shopId: shopId,
        staffId: staffId,
        month: month,
        year: year,
      );

      return data.map((e) => CustomSalaryAdjustment.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Error getting custom adjustments: $e');
      return [];
    }
  }

  /// Thêm khoản thưởng/trừ tùy chỉnh
  static Future<bool> addCustomAdjustment(
    CustomSalaryAdjustment adjustment,
  ) async {
    try {
      var shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        try {
          shopId = await UserService.ensureShopId(maxRetries: 3);
        } catch (e) {
          debugPrint('Error ensuring shopId for saving deduction settings: $e');
          return false;
        }
      }

      final data = adjustment.toMap();
      data['shopId'] = shopId;

      return await FirestoreService.addCustomSalaryAdjustment(shopId, data);
    } catch (e) {
      debugPrint('Error adding custom adjustment: $e');
      return false;
    }
  }

  /// Xóa khoản thưởng/trừ tùy chỉnh
  static Future<bool> deleteCustomAdjustment(String adjustmentId) async {
    try {
      var shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        try {
          shopId = await UserService.ensureShopId(maxRetries: 3);
        } catch (e) {
          debugPrint('Error ensuring shopId for saving deduction settings: $e');
          return false;
        }
      }

      return await FirestoreService.deleteCustomSalaryAdjustment(
        shopId,
        adjustmentId,
      );
    } catch (e) {
      debugPrint('Error deleting custom adjustment: $e');
      return false;
    }
  }

  /// Lấy tất cả khoản thưởng/trừ của shop trong tháng (all staff)
  static Future<List<CustomSalaryAdjustment>> getAllShopAdjustments({
    required String shopId,
    required int month,
    required int year,
  }) async {
    try {
      final data = await FirestoreService.getAllCustomSalaryAdjustments(
        shopId: shopId,
        month: month,
        year: year,
      );
      return data.map((e) => CustomSalaryAdjustment.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Error getting all shop adjustments: $e');
      return [];
    }
  }

  /// Tính số ngày làm việc trong tháng theo config workDays
  /// workDays: [1,2,3,4,5,6] = Mon-Sat, [1,2,3,4,5,6,7] = Mon-Sun
  static int _getWorkingDaysInMonth(int year, int month, [List<int> workDays = const [1, 2, 3, 4, 5, 6]]) {
    final lastDay = DateTime(year, month + 1, 0);
    int workingDays = 0;

    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(year, month, day);
      // Chỉ tính những ngày trong workDays config
      if (workDays.contains(date.weekday)) {
        workingDays++;
      }
    }

    return workingDays;
  }

  /// Helper để parse JSON string thành List
  static List<dynamic> _parseJsonList(String jsonStr) {
    try {
      // Simple parser for [1,2,3,4,5,6,7] format
      final stripped = jsonStr.replaceAll('[', '').replaceAll(']', '');
      return stripped.split(',').map((s) => int.parse(s.trim())).toList();
    } catch (_) {
      return [1, 2, 3, 4, 5, 6];
    }
  }

  /// Convert workDays from any stored format to Dart weekday list [1..7]
  /// Handles:
  /// - Shop general format: "1,1,1,1,1,1,1" (7 booleans, index 0=CN, 1=T2, ..., 6=T7)
  /// - Staff individual format: "0,1,2,3,4,5,6" (UI indices where 0=CN, 1=T2, ..., 6=T7)  
  /// - List<int> format: [0,1,2,3,4,5,6] (same UI indices)
  /// - JSON string: "[1,2,3,4,5,6]" (Dart weekday format - legacy)
  /// Returns List<int> with Dart weekday values (1=Mon, 2=Tue, ..., 7=Sun)
  static List<int> _parseWorkDays(dynamic wd) {
    // UI index to Dart weekday mapping:
    // UI: 0=CN(Sun) 1=T2(Mon) 2=T3(Tue) 3=T4(Wed) 4=T5(Thu) 5=T6(Fri) 6=T7(Sat)
    // Dart: 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat 7=Sun
    const uiToDartWeekday = [7, 1, 2, 3, 4, 5, 6]; // index=UI, value=Dart

    if (wd is List) {
      // List format - convert UI indices to Dart weekday
      final result = <int>[];
      for (final v in wd) {
        final idx = (v is int) ? v : int.tryParse(v.toString()) ?? -1;
        if (idx >= 0 && idx < 7) {
          result.add(uiToDartWeekday[idx]);
        }
      }
      return result.isNotEmpty ? result : [1, 2, 3, 4, 5, 6];
    }

    if (wd is String) {
      final stripped = wd.replaceAll('[', '').replaceAll(']', '').trim();
      if (stripped.isEmpty) return [1, 2, 3, 4, 5, 6];

      final parts = stripped.split(',').map((s) => s.trim()).toList();

      // Detect format: shop general has exactly 7 items all "0" or "1"
      if (parts.length == 7 && parts.every((p) => p == '0' || p == '1')) {
        // Boolean format: "0,1,1,1,1,1,0" or "1,1,1,1,1,1,1"
        final result = <int>[];
        for (int i = 0; i < 7; i++) {
          if (parts[i] == '1') {
            result.add(uiToDartWeekday[i]);
          }
        }
        return result.isNotEmpty ? result : [1, 2, 3, 4, 5, 6];
      }

      // Index format: "0,1,2,3,4,5,6" (UI indices)
      final result = <int>[];
      for (final p in parts) {
        final idx = int.tryParse(p) ?? -1;
        if (idx >= 0 && idx < 7) {
          result.add(uiToDartWeekday[idx]);
        }
      }
      return result.isNotEmpty ? result : [1, 2, 3, 4, 5, 6];
    }

    return [1, 2, 3, 4, 5, 6]; // Default Mon-Sat
  }

  /// Tính lương cho tất cả nhân viên trong tháng
  static Future<List<SalaryBreakdown>> calculateAllStaffSalaries({
    required int month,
    required int year,
  }) async {
    final results = <SalaryBreakdown>[];

    debugPrint('📊 [SalaryCalc] Đang tính lương tháng $month/$year...');

    try {
      // Lấy danh sách nhân viên từ Firestore
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return results;

      final staffList = await FirestoreService.getShopStaffList(shopId);
      debugPrint('📊 [SalaryCalc] Tìm thấy ${staffList.length} nhân viên');

      // Lấy cài đặt khấu trừ của shop 1 lần
      final deductionSettings = await getShopDeductionSettings();

      // Lấy tất cả custom adjustments của shop trong tháng
      final allAdjustments =
          await FirestoreService.getAllCustomSalaryAdjustments(
            shopId: shopId,
            month: month,
            year: year,
          );
      final customAdjustments = allAdjustments
          .map((e) => CustomSalaryAdjustment.fromMap(e))
          .toList();

      final futures = <Future<SalaryBreakdown>>[];
      for (final staff in staffList) {
        final staffId = staff['uid'] ?? staff['id'] ?? '';
        final staffName = staff['name'] ?? staff['displayName'] ?? 'NV';
        final staffEmail = staff['email'] as String? ?? '';
        final numDependents = (staff['numDependents'] ?? 0) as int;

        if (staffId.isEmpty) continue;

        futures.add(calculateMonthlySalary(
          staffId: staffId,
          staffName: staffName,
          staffEmail: staffEmail,
          month: month,
          year: year,
          deductionSettings: deductionSettings,
          customAdjustments: customAdjustments,
          numDependents: numDependents,
        ));
      }

      final computed = await Future.wait(futures);
      results.addAll(computed);

      // Sắp xếp theo tổng lương giảm dần
      results.sort((a, b) => b.totalSalary.compareTo(a.totalSalary));
    } catch (e) {
      debugPrint('Error calculating all staff salaries: $e');
    }

    return results;
  }

  /// Format tiền tệ
  static String _formatCurrency(double amount) {
    final fmt = NumberFormat('#,###', 'vi_VN');
    return '${fmt.format(amount)}đ';
  }

  /// Format tiền tệ (public)
  static String formatCurrency(double amount) => _formatCurrency(amount);
}

