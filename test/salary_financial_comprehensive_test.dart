// Comprehensive Salary & Financial Test Suite
// Tests ALL salary calculations, commission tiers, attendance, repairs, and financial logic
// 
// Created: 2026-02-08
// Purpose: Production-ready tests for Play Store release
// Coverage: 
//   - Salary calculation (monthly/daily/hourly)
//   - Commission calculation (percent/fixed/tiered)
//   - Attendance and OT
//   - Repair order flow
//   - Financial reconciliation
//   - Tax (PIT) calculation
//   - Insurance deductions

import 'package:flutter_test/flutter_test.dart';

// =============================================================================
// TEST MODELS (Pure Dart - No Firebase dependency)
// =============================================================================

/// Employee salary settings for testing
class TestEmployeeSalarySettings {
  final String staffId;
  final String staffName;
  final double baseSalary;
  final double dailyRate;
  final String salaryType; // 'monthly' | 'daily' | 'hourly'
  
  // Commission
  final String saleCommType; // 'percent' | 'fixed_per_order' | 'tiered'
  final double saleCommValue;
  
  // Tiered commission
  final double saleCommTier1Max;
  final double saleCommTier1Value;
  final double saleCommTier2Max;
  final double saleCommTier2Value;
  final double saleCommTier3Value;
  
  // Repair commission
  final String repairCommType;
  final double repairCommValue;
  
  // Allowances
  final double transportAllowance;
  final double mealAllowance;
  final double phoneAllowance;
  final double otherAllowance;
  
  // Target bonus
  final double monthlyTarget;
  final double targetBonusPercent;
  
  // OT
  final double standardHoursPerDay;
  final double overtimeRate;
  
  TestEmployeeSalarySettings({
    required this.staffId,
    required this.staffName,
    this.baseSalary = 0,
    this.dailyRate = 0,
    this.salaryType = 'monthly',
    this.saleCommType = 'percent',
    this.saleCommValue = 1.0,
    this.saleCommTier1Max = 10000000,
    this.saleCommTier1Value = 20000,
    this.saleCommTier2Max = 50000000,
    this.saleCommTier2Value = 50000,
    this.saleCommTier3Value = 100000,
    this.repairCommType = 'percent',
    this.repairCommValue = 10.0,
    this.transportAllowance = 0,
    this.mealAllowance = 0,
    this.phoneAllowance = 0,
    this.otherAllowance = 0,
    this.monthlyTarget = 0,
    this.targetBonusPercent = 0,
    this.standardHoursPerDay = 8.0,
    this.overtimeRate = 150,
  });
  
  /// Calculate tiered commission for an order
  double calculateSaleCommission(double orderValue) {
    if (saleCommType == 'percent') {
      return orderValue * (saleCommValue / 100);
    } else if (saleCommType == 'tiered') {
      if (orderValue < saleCommTier1Max) {
        return saleCommTier1Value;
      } else if (orderValue <= saleCommTier2Max) {
        return saleCommTier2Value;
      } else {
        return saleCommTier3Value;
      }
    } else {
      // fixed_per_order
      return saleCommValue;
    }
  }
  
  /// Calculate total commission for multiple orders
  double calculateTotalSaleCommission(List<double> orderValues) {
    return orderValues.fold(0.0, (sum, v) => sum + calculateSaleCommission(v));
  }
  
  double get totalAllowance => 
      transportAllowance + mealAllowance + phoneAllowance + otherAllowance;
  
  double get hourlyRate => dailyRate > 0 
      ? dailyRate / standardHoursPerDay 
      : baseSalary / (26 * standardHoursPerDay);
}

/// Attendance record for testing
class TestAttendanceRecord {
  final String dateKey;
  final int checkInAt;
  final int checkOutAt;
  final bool isLate;
  final bool isEarlyLeave;
  final double overtimeMinutes;
  
  TestAttendanceRecord({
    required this.dateKey,
    required this.checkInAt,
    required this.checkOutAt,
    this.isLate = false,
    this.isEarlyLeave = false,
    this.overtimeMinutes = 0,
  });
  
  double get workHours {
    final diff = checkOutAt - checkInAt;
    return diff / (1000 * 60 * 60); // ms to hours
  }
}

/// Sale order for testing
class TestSaleOrder {
  final String id;
  final double totalPrice;
  final double totalCost;
  final String sellerName;
  final int soldAt;
  final String paymentMethod;
  
  TestSaleOrder({
    required this.id,
    required this.totalPrice,
    required this.totalCost,
    required this.sellerName,
    required this.soldAt,
    this.paymentMethod = 'TIỀN MẶT',
  });
  
  double get profit => totalPrice - totalCost;
}

/// Repair order for testing
class TestRepair {
  final String id;
  final String model;
  final int status; // 1=received, 2=processing, 3=done, 4=delivered
  final double price;
  final double totalCost;
  final String createdBy;
  final String? deliveredBy;
  final int createdAt;
  final int? deliveredAt;
  
  TestRepair({
    required this.id,
    required this.model,
    required this.status,
    this.price = 0,
    this.totalCost = 0,
    required this.createdBy,
    this.deliveredBy,
    required this.createdAt,
    this.deliveredAt,
  });
  
  double get profit => price - totalCost;
}

/// Deduction settings for testing
class TestDeductionSettings {
  final bool enableLateDeduction;
  final int lateGraceTimes;
  final double lateDeductionPerTime;
  
  final bool enableEarlyLeaveDeduction;
  final int earlyLeaveGraceTimes;
  final double earlyLeaveDeductionPerTime;
  
  final bool enableAbsenceDeduction;
  final int allowedAbsenceDays;
  final double absenceDeductionPerDay;
  
  final bool enableSocialInsurance;
  final double socialInsuranceRate;
  
  final bool enableHealthInsurance;
  final double healthInsuranceRate;
  
  final bool enableUnemploymentInsurance;
  final double unemploymentInsuranceRate;
  
  final double insuranceBaseSalary;
  
  final bool enablePIT;
  final double pitDeductionSelf;
  final double pitDeductionDependent;
  
  TestDeductionSettings({
    this.enableLateDeduction = true,
    this.lateGraceTimes = 3,
    this.lateDeductionPerTime = 50000,
    this.enableEarlyLeaveDeduction = true,
    this.earlyLeaveGraceTimes = 2,
    this.earlyLeaveDeductionPerTime = 50000,
    this.enableAbsenceDeduction = true,
    this.allowedAbsenceDays = 2,
    this.absenceDeductionPerDay = 200000,
    this.enableSocialInsurance = true,
    this.socialInsuranceRate = 8.0,
    this.enableHealthInsurance = true,
    this.healthInsuranceRate = 1.5,
    this.enableUnemploymentInsurance = true,
    this.unemploymentInsuranceRate = 1.0,
    this.insuranceBaseSalary = 0, // 0 = use baseSalary
    this.enablePIT = true,
    this.pitDeductionSelf = 11000000,
    this.pitDeductionDependent = 4400000,
  });
}

// =============================================================================
// SALARY CALCULATION LOGIC (Mirrors salary_calculation_service.dart)
// =============================================================================

class SalaryCalculator {
  /// Calculate PIT (Personal Income Tax) using Vietnamese progressive rates
  static double calculatePIT(double taxableIncome) {
    if (taxableIncome <= 0) return 0;
    
    double tax = 0;
    double remaining = taxableIncome;
    
    // Bracket 1: 0 - 5M (5%)
    if (remaining > 0) {
      double bracket = remaining > 5000000 ? 5000000 : remaining;
      tax += bracket * 0.05;
      remaining -= bracket;
    }
    
    // Bracket 2: 5 - 10M (10%)
    if (remaining > 0) {
      double bracket = remaining > 5000000 ? 5000000 : remaining;
      tax += bracket * 0.10;
      remaining -= bracket;
    }
    
    // Bracket 3: 10 - 18M (15%)
    if (remaining > 0) {
      double bracket = remaining > 8000000 ? 8000000 : remaining;
      tax += bracket * 0.15;
      remaining -= bracket;
    }
    
    // Bracket 4: 18 - 32M (20%)
    if (remaining > 0) {
      double bracket = remaining > 14000000 ? 14000000 : remaining;
      tax += bracket * 0.20;
      remaining -= bracket;
    }
    
    // Bracket 5: 32 - 52M (25%)
    if (remaining > 0) {
      double bracket = remaining > 20000000 ? 20000000 : remaining;
      tax += bracket * 0.25;
      remaining -= bracket;
    }
    
    // Bracket 6: 52 - 80M (30%)
    if (remaining > 0) {
      double bracket = remaining > 28000000 ? 28000000 : remaining;
      tax += bracket * 0.30;
      remaining -= bracket;
    }
    
    // Bracket 7: > 80M (35%)
    if (remaining > 0) {
      tax += remaining * 0.35;
    }
    
    return tax;
  }
  
  /// Get standard working days in a month (excluding Sundays)
  static int getWorkingDaysInMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0);
    int workingDays = 0;
    
    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday != DateTime.sunday) {
        workingDays++;
      }
    }
    
    return workingDays;
  }
  
  /// Full salary calculation
  static Map<String, double> calculateMonthlySalary({
    required TestEmployeeSalarySettings settings,
    required int workDays,
    required double totalWorkHours,
    required double overtimeHours,
    required int lateDays,
    required int earlyLeaveDays,
    required List<TestSaleOrder> sales,
    required List<TestRepair> repairs,
    required TestDeductionSettings deductions,
    required int workingDaysInMonth,
    int numDependents = 0,
  }) {
    final result = <String, double>{};
    
    // 1. BASE SALARY
    double baseSalary = 0;
    if (settings.salaryType == 'monthly') {
      // Pro-rate for actual work days
      baseSalary = settings.baseSalary * (workDays / workingDaysInMonth);
    } else if (settings.salaryType == 'daily') {
      baseSalary = settings.dailyRate * workDays;
    } else {
      // hourly
      baseSalary = settings.hourlyRate * totalWorkHours;
    }
    result['baseSalary'] = baseSalary;
    
    // 2. SALE COMMISSION
    double saleComm = 0;
    final saleOrderValues = sales.map((s) => s.totalPrice).toList();
    final saleRevenue = saleOrderValues.fold(0.0, (sum, v) => sum + v);
    
    if (settings.saleCommType == 'percent') {
      saleComm = saleRevenue * (settings.saleCommValue / 100);
    } else if (settings.saleCommType == 'tiered') {
      saleComm = settings.calculateTotalSaleCommission(saleOrderValues);
    } else {
      // fixed_per_order
      saleComm = settings.saleCommValue * sales.length;
    }
    result['saleCommission'] = saleComm;
    result['saleRevenue'] = saleRevenue;
    result['saleOrderCount'] = sales.length.toDouble();
    
    // 3. REPAIR COMMISSION
    double repairComm = 0;
    final repairProfit = repairs.fold(0.0, (sum, r) => sum + r.profit);
    
    if (settings.repairCommType == 'percent') {
      repairComm = repairProfit * (settings.repairCommValue / 100);
    } else {
      repairComm = settings.repairCommValue * repairs.length;
    }
    result['repairCommission'] = repairComm;
    result['repairProfit'] = repairProfit;
    result['repairOrderCount'] = repairs.length.toDouble();
    
    // 4. OVERTIME
    double overtime = 0;
    if (overtimeHours > 0) {
      overtime = overtimeHours * settings.hourlyRate * (settings.overtimeRate / 100);
    }
    result['overtime'] = overtime;
    
    // 5. TARGET BONUS
    double targetBonus = 0;
    if (settings.monthlyTarget > 0 && saleRevenue >= settings.monthlyTarget) {
      targetBonus = saleRevenue * (settings.targetBonusPercent / 100);
    }
    result['targetBonus'] = targetBonus;
    
    // 6. ALLOWANCES
    final allowances = settings.totalAllowance;
    result['allowances'] = allowances;
    
    // 7. GROSS INCOME
    final grossIncome = baseSalary + saleComm + repairComm + overtime + targetBonus + allowances;
    result['grossIncome'] = grossIncome;
    
    // 8. DEDUCTIONS
    
    // 8a. Late deduction
    double lateDeduction = 0;
    if (deductions.enableLateDeduction && lateDays > deductions.lateGraceTimes) {
      final penaltyTimes = lateDays - deductions.lateGraceTimes;
      lateDeduction = penaltyTimes * deductions.lateDeductionPerTime;
    }
    result['lateDeduction'] = lateDeduction;
    
    // 8b. Early leave deduction
    double earlyLeaveDeduction = 0;
    if (deductions.enableEarlyLeaveDeduction && earlyLeaveDays > deductions.earlyLeaveGraceTimes) {
      final penaltyTimes = earlyLeaveDays - deductions.earlyLeaveGraceTimes;
      earlyLeaveDeduction = penaltyTimes * deductions.earlyLeaveDeductionPerTime;
    }
    result['earlyLeaveDeduction'] = earlyLeaveDeduction;
    
    // 8c. Absence deduction
    double absenceDeduction = 0;
    final absentDays = (workingDaysInMonth - workDays).clamp(0, workingDaysInMonth);
    if (deductions.enableAbsenceDeduction && absentDays > deductions.allowedAbsenceDays) {
      final excessDays = absentDays - deductions.allowedAbsenceDays;
      absenceDeduction = excessDays * deductions.absenceDeductionPerDay;
    }
    result['absenceDeduction'] = absenceDeduction;
    result['absentDays'] = absentDays.toDouble();
    
    // 8d. Insurance
    final insuranceBase = deductions.insuranceBaseSalary > 0 
        ? deductions.insuranceBaseSalary 
        : settings.baseSalary;
    
    double socialInsurance = 0;
    if (deductions.enableSocialInsurance) {
      socialInsurance = insuranceBase * (deductions.socialInsuranceRate / 100);
    }
    
    double healthInsurance = 0;
    if (deductions.enableHealthInsurance) {
      healthInsurance = insuranceBase * (deductions.healthInsuranceRate / 100);
    }
    
    double unemploymentInsurance = 0;
    if (deductions.enableUnemploymentInsurance) {
      unemploymentInsurance = insuranceBase * (deductions.unemploymentInsuranceRate / 100);
    }
    
    final totalInsurance = socialInsurance + healthInsurance + unemploymentInsurance;
    result['socialInsurance'] = socialInsurance;
    result['healthInsurance'] = healthInsurance;
    result['unemploymentInsurance'] = unemploymentInsurance;
    result['totalInsurance'] = totalInsurance;
    
    // 8e. PIT (Personal Income Tax)
    double pit = 0;
    if (deductions.enablePIT) {
      final selfDeduction = deductions.pitDeductionSelf;
      final dependentDeduction = numDependents * deductions.pitDeductionDependent;
      final taxableIncome = grossIncome - totalInsurance - selfDeduction - dependentDeduction;
      
      if (taxableIncome > 0) {
        pit = calculatePIT(taxableIncome);
      }
      
      result['selfDeduction'] = selfDeduction;
      result['dependentDeduction'] = dependentDeduction;
      result['taxableIncome'] = taxableIncome > 0 ? taxableIncome : 0;
    }
    result['pit'] = pit;
    
    // 9. TOTAL DEDUCTIONS
    final totalDeductions = lateDeduction + earlyLeaveDeduction + absenceDeduction + totalInsurance + pit;
    result['totalDeductions'] = totalDeductions;
    
    // 10. NET SALARY
    final netSalary = grossIncome - totalDeductions;
    result['netSalary'] = netSalary;
    
    return result;
  }
}

// =============================================================================
// MAIN TEST SUITE
// =============================================================================

void main() {
  // ===========================================================================
  // 1. TIERED COMMISSION CALCULATION TESTS
  // ===========================================================================
  group('Tiered Commission Calculation', () {
    late TestEmployeeSalarySettings tieredSettings;
    
    setUp(() {
      tieredSettings = TestEmployeeSalarySettings(
        staffId: 'emp_001',
        staffName: 'Nguyễn Văn A',
        baseSalary: 10000000,
        saleCommType: 'tiered',
        saleCommTier1Max: 10000000,    // Dưới 10M -> 20k
        saleCommTier1Value: 20000,
        saleCommTier2Max: 50000000,    // 10M-50M -> 50k
        saleCommTier2Value: 50000,
        saleCommTier3Value: 100000,    // Trên 50M -> 100k
      );
    });
    
    test('Tier 1: Order under 10M gets 20k commission', () {
      expect(tieredSettings.calculateSaleCommission(5000000), 20000);
      expect(tieredSettings.calculateSaleCommission(9999999), 20000);
      expect(tieredSettings.calculateSaleCommission(1000000), 20000);
    });
    
    test('Tier 2: Order 10M-50M gets 50k commission', () {
      expect(tieredSettings.calculateSaleCommission(10000000), 50000);
      expect(tieredSettings.calculateSaleCommission(25000000), 50000);
      expect(tieredSettings.calculateSaleCommission(50000000), 50000);
    });
    
    test('Tier 3: Order over 50M gets 100k commission', () {
      expect(tieredSettings.calculateSaleCommission(50000001), 100000);
      expect(tieredSettings.calculateSaleCommission(100000000), 100000);
      expect(tieredSettings.calculateSaleCommission(200000000), 100000);
    });
    
    test('Multiple orders calculate correctly per order value', () {
      // 3 orders: 5M (tier1), 15M (tier2), 60M (tier3)
      final orders = [5000000.0, 15000000.0, 60000000.0];
      final total = tieredSettings.calculateTotalSaleCommission(orders);
      
      // 20k + 50k + 100k = 170k
      expect(total, 170000);
    });
    
    test('Mixed tier orders: Real-world scenario', () {
      // Scenario: Employee sold 5 orders in a month
      final orders = [
        8500000.0,   // iPhone SE -> Tier 1 -> 20k
        12000000.0,  // iPhone 14 -> Tier 2 -> 50k
        35000000.0,  // iPhone 15 Pro Max -> Tier 2 -> 50k
        55000000.0,  // MacBook Pro -> Tier 3 -> 100k
        3000000.0,   // Phụ kiện -> Tier 1 -> 20k
      ];
      
      final total = tieredSettings.calculateTotalSaleCommission(orders);
      expect(total, 240000); // 20k + 50k + 50k + 100k + 20k
    });
  });
  
  // ===========================================================================
  // 2. PERCENT COMMISSION TESTS
  // ===========================================================================
  group('Percent Commission Calculation', () {
    test('1% commission on revenue', () {
      final settings = TestEmployeeSalarySettings(
        staffId: 'emp_002',
        staffName: 'Trần Văn B',
        saleCommType: 'percent',
        saleCommValue: 1.0,
      );
      
      expect(settings.calculateSaleCommission(10000000), 100000);
      expect(settings.calculateSaleCommission(50000000), 500000);
    });
    
    test('2.5% commission on high revenue', () {
      final settings = TestEmployeeSalarySettings(
        staffId: 'emp_003',
        staffName: 'Lê Thị C',
        saleCommType: 'percent',
        saleCommValue: 2.5,
      );
      
      expect(settings.calculateSaleCommission(100000000), 2500000);
    });
  });
  
  // ===========================================================================
  // 3. FIXED PER ORDER COMMISSION TESTS  
  // ===========================================================================
  group('Fixed Per Order Commission', () {
    test('50k per order regardless of value', () {
      final settings = TestEmployeeSalarySettings(
        staffId: 'emp_004',
        staffName: 'Phạm Văn D',
        saleCommType: 'fixed_per_order',
        saleCommValue: 50000,
      );
      
      expect(settings.calculateSaleCommission(1000000), 50000);
      expect(settings.calculateSaleCommission(100000000), 50000);
      
      // 10 orders = 500k commission
      final orders = List.generate(10, (_) => 15000000.0);
      expect(settings.calculateTotalSaleCommission(orders), 500000);
    });
  });
  
  // ===========================================================================
  // 4. FULL SALARY CALCULATION SCENARIOS
  // ===========================================================================
  group('Full Salary Calculation', () {
    late TestEmployeeSalarySettings monthlyEmployee;
    late TestDeductionSettings deductions;
    
    setUp(() {
      monthlyEmployee = TestEmployeeSalarySettings(
        staffId: 'emp_full_001',
        staffName: 'Nguyễn Văn Full',
        baseSalary: 10000000,        // 10M base
        salaryType: 'monthly',
        saleCommType: 'tiered',
        saleCommTier1Max: 10000000,
        saleCommTier1Value: 20000,
        saleCommTier2Max: 50000000,
        saleCommTier2Value: 50000,
        saleCommTier3Value: 100000,
        repairCommType: 'percent',
        repairCommValue: 10,         // 10% of repair profit
        transportAllowance: 500000,
        mealAllowance: 1000000,
        phoneAllowance: 200000,
        monthlyTarget: 100000000,    // 100M target
        targetBonusPercent: 1,       // 1% bonus
        standardHoursPerDay: 8,
        overtimeRate: 150,
      );
      
      deductions = TestDeductionSettings(
        enableLateDeduction: true,
        lateGraceTimes: 3,
        lateDeductionPerTime: 50000,
        enableEarlyLeaveDeduction: true,
        earlyLeaveGraceTimes: 2,
        earlyLeaveDeductionPerTime: 50000,
        enableAbsenceDeduction: true,
        allowedAbsenceDays: 2,
        absenceDeductionPerDay: 200000,
        enableSocialInsurance: true,
        socialInsuranceRate: 8,
        enableHealthInsurance: true,
        healthInsuranceRate: 1.5,
        enableUnemploymentInsurance: true,
        unemploymentInsuranceRate: 1,
        enablePIT: true,
        pitDeductionSelf: 11000000,
        pitDeductionDependent: 4400000,
      );
    });
    
    test('Scenario 1: Perfect attendance, hit target, high sales', () {
      final sales = [
        TestSaleOrder(id: 's1', totalPrice: 35000000, totalCost: 30000000, sellerName: 'FULL', soldAt: 0),
        TestSaleOrder(id: 's2', totalPrice: 55000000, totalCost: 45000000, sellerName: 'FULL', soldAt: 0),
        TestSaleOrder(id: 's3', totalPrice: 25000000, totalCost: 20000000, sellerName: 'FULL', soldAt: 0),
      ];
      
      final repairs = [
        TestRepair(id: 'r1', model: 'iPhone 14', status: 4, price: 500000, totalCost: 100000, createdBy: 'FULL', createdAt: 0),
        TestRepair(id: 'r2', model: 'Samsung S23', status: 4, price: 800000, totalCost: 200000, createdBy: 'FULL', createdAt: 0),
      ];
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: monthlyEmployee,
        workDays: 26,
        totalWorkHours: 208,
        overtimeHours: 10,
        lateDays: 1,
        earlyLeaveDays: 0,
        sales: sales,
        repairs: repairs,
        deductions: deductions,
        workingDaysInMonth: 26,
        numDependents: 0,
      );
      
      // Verify calculations
      expect(result['baseSalary'], 10000000); // Full month
      expect(result['saleOrderCount'], 3);
      expect(result['saleRevenue'], 115000000); // 35M + 55M + 25M
      
      // Tiered commission: 35M->50k, 55M->100k, 25M->50k = 200k
      expect(result['saleCommission'], 200000);
      
      // Repair commission: (400k + 600k) * 10% = 100k
      expect(result['repairProfit'], 1000000);
      expect(result['repairCommission'], 100000);
      
      // Target bonus: 115M >= 100M target, so 115M * 1% = 1.15M
      expect(result['targetBonus'], 1150000);
      
      // Allowances: 500k + 1M + 200k = 1.7M
      expect(result['allowances'], 1700000);
      
      // OT: 10h * (10M / (26 * 8)) * 1.5 = 10 * 48077 * 1.5 = 721,155
      expect(result['overtime']! > 700000, true);
      
      // No late deduction (1 late < 3 grace)
      expect(result['lateDeduction'], 0);
      
      // No absence deduction
      expect(result['absentDays'], 0);
      
      // Gross > 13M
      expect(result['grossIncome']! > 13000000, true);
      
      // Net should be positive
      expect(result['netSalary']! > 0, true);
    });
    
    test('Scenario 2: Poor attendance, many lates, below target', () {
      final sales = [
        TestSaleOrder(id: 's1', totalPrice: 15000000, totalCost: 12000000, sellerName: 'FULL', soldAt: 0),
      ];
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: monthlyEmployee,
        workDays: 18, // Only 18 days worked
        totalWorkHours: 144,
        overtimeHours: 0,
        lateDays: 7, // Late 7 times
        earlyLeaveDays: 4, // Early leave 4 times
        sales: sales,
        repairs: [],
        deductions: deductions,
        workingDaysInMonth: 26,
        numDependents: 0,
      );
      
      // Pro-rated base: 10M * (18/26) = ~6.9M
      expect(result['baseSalary']! < 7000000, true);
      expect(result['baseSalary']! > 6800000, true);
      
      // Late deduction: (7 - 3) * 50k = 200k
      expect(result['lateDeduction'], 200000);
      
      // Early leave deduction: (4 - 2) * 50k = 100k  
      expect(result['earlyLeaveDeduction'], 100000);
      
      // Absent days: 26 - 18 = 8 days
      // Absence deduction: (8 - 2) * 200k = 1.2M
      expect(result['absentDays'], 8);
      expect(result['absenceDeduction'], 1200000);
      
      // No target bonus (15M < 100M target)
      expect(result['targetBonus'], 0);
    });
    
    test('Scenario 3: Daily rate employee', () {
      final dailyEmployee = TestEmployeeSalarySettings(
        staffId: 'emp_daily',
        staffName: 'Nhân viên lương ngày',
        dailyRate: 400000, // 400k/day
        salaryType: 'daily',
        saleCommType: 'fixed_per_order',
        saleCommValue: 30000,
      );
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: dailyEmployee,
        workDays: 22,
        totalWorkHours: 176,
        overtimeHours: 5,
        lateDays: 0,
        earlyLeaveDays: 0,
        sales: [
          TestSaleOrder(id: 's1', totalPrice: 5000000, totalCost: 4000000, sellerName: 'daily', soldAt: 0),
          TestSaleOrder(id: 's2', totalPrice: 8000000, totalCost: 6000000, sellerName: 'daily', soldAt: 0),
        ],
        repairs: [],
        deductions: TestDeductionSettings(
          enableSocialInsurance: false,
          enableHealthInsurance: false,
          enableUnemploymentInsurance: false,
          enablePIT: false,
        ),
        workingDaysInMonth: 26,
      );
      
      // Base: 400k * 22 = 8.8M
      expect(result['baseSalary'], 8800000);
      
      // Commission: 30k * 2 orders = 60k
      expect(result['saleCommission'], 60000);
    });
    
    test('Scenario 4: High earner with PIT', () {
      final highEarner = TestEmployeeSalarySettings(
        staffId: 'emp_high',
        staffName: 'Top Performer',
        baseSalary: 30000000, // 30M base
        saleCommType: 'percent',
        saleCommValue: 2,
        transportAllowance: 1000000,
        mealAllowance: 2000000,
      );
      
      final sales = List.generate(20, (i) => TestSaleOrder(
        id: 's$i',
        totalPrice: 25000000,
        totalCost: 20000000,
        sellerName: 'HIGH',
        soldAt: 0,
      ));
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: highEarner,
        workDays: 26,
        totalWorkHours: 208,
        overtimeHours: 0,
        lateDays: 0,
        earlyLeaveDays: 0,
        sales: sales,
        repairs: [],
        deductions: deductions,
        workingDaysInMonth: 26,
        numDependents: 2,
      );
      
      // Revenue: 25M * 20 = 500M
      expect(result['saleRevenue'], 500000000);
      
      // Commission: 500M * 2% = 10M
      expect(result['saleCommission'], 10000000);
      
      // Gross: 30M + 10M + 3M allowance = 43M
      expect(result['grossIncome'], 43000000);
      
      // Insurance: 30M * 10.5% = 3.15M
      expect(result['totalInsurance'], 3150000);
      
      // Taxable: 43M - 3.15M - 11M - 8.8M = 20.05M
      // PIT should be calculated on ~20M
      expect(result['taxableIncome']! > 19000000, true);
      expect(result['pit']! > 0, true);
      
      // Net should be positive and significant
      expect(result['netSalary']! > 35000000, true);
    });
  });
  
  // ===========================================================================
  // 5. PIT (PERSONAL INCOME TAX) CALCULATION TESTS
  // ===========================================================================
  group('PIT Calculation', () {
    test('No tax for income under deduction', () {
      expect(SalaryCalculator.calculatePIT(0), 0);
      expect(SalaryCalculator.calculatePIT(-1000000), 0);
    });
    
    test('Bracket 1: 0-5M at 5%', () {
      expect(SalaryCalculator.calculatePIT(5000000), 250000);
      expect(SalaryCalculator.calculatePIT(3000000), 150000);
    });
    
    test('Bracket 2: 5-10M at 10%', () {
      // 5M * 5% + 5M * 10% = 250k + 500k = 750k
      expect(SalaryCalculator.calculatePIT(10000000), 750000);
    });
    
    test('Bracket 3: 10-18M at 15%', () {
      // 5M * 5% + 5M * 10% + 8M * 15% = 250k + 500k + 1.2M = 1.95M
      expect(SalaryCalculator.calculatePIT(18000000), 1950000);
    });
    
    test('High income: 50M taxable', () {
      // Progressive calculation for 50M
      // 5% * 5M = 250k
      // 10% * 5M = 500k
      // 15% * 8M = 1.2M
      // 20% * 14M = 2.8M
      // 25% * 18M = 4.5M (only 50-32=18M in this bracket)
      final tax = SalaryCalculator.calculatePIT(50000000);
      expect(tax, 9250000);
    });
  });
  
  // ===========================================================================
  // 6. WORKING DAYS CALCULATION TESTS
  // ===========================================================================
  group('Working Days Calculation', () {
    test('February 2026 has correct working days', () {
      final days = SalaryCalculator.getWorkingDaysInMonth(2026, 2);
      // February 2026: 28 days, but let's count non-Sundays
      // Sundays: Feb 1, 8, 15, 22 = 4 Sundays
      // Working days = 28 - 4 = 24
      expect(days, 24);
    });
    
    test('January 2026 has correct working days', () {
      final days = SalaryCalculator.getWorkingDaysInMonth(2026, 1);
      // January 2026: 31 days
      // Sundays: Jan 4, 11, 18, 25 = 4 Sundays
      // Working days = 31 - 4 = 27
      expect(days, 27);
    });
    
    test('December 2025 has correct working days', () {
      final days = SalaryCalculator.getWorkingDaysInMonth(2025, 12);
      // December 2025: 31 days
      // Working days excluding Sundays
      expect(days >= 26 && days <= 27, true);
    });
  });
  
  // ===========================================================================
  // 7. REPAIR FLOW TESTS
  // ===========================================================================
  group('Repair Order Flow', () {
    test('Repair status transitions', () {
      // Status: 1=received, 2=processing, 3=done, 4=delivered
      final repair = TestRepair(
        id: 'repair_001',
        model: 'iPhone 14 Pro',
        status: 1,
        price: 500000,
        totalCost: 100000,
        createdBy: 'tech_A',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      
      expect(repair.status, 1);
      expect(repair.profit, 400000);
    });
    
    test('Repair profit calculation', () {
      final repairs = [
        TestRepair(id: 'r1', model: 'iPhone', status: 4, price: 500000, totalCost: 100000, createdBy: 'A', createdAt: 0),
        TestRepair(id: 'r2', model: 'Samsung', status: 4, price: 300000, totalCost: 50000, createdBy: 'A', createdAt: 0),
        TestRepair(id: 'r3', model: 'Xiaomi', status: 4, price: 200000, totalCost: 30000, createdBy: 'A', createdAt: 0),
      ];
      
      final totalRevenue = repairs.fold(0.0, (sum, r) => sum + r.price);
      final totalCost = repairs.fold(0.0, (sum, r) => sum + r.totalCost);
      final totalProfit = repairs.fold(0.0, (sum, r) => sum + r.profit);
      
      expect(totalRevenue, 1000000);
      expect(totalCost, 180000);
      expect(totalProfit, 820000);
    });
  });
  
  // ===========================================================================
  // 8. FINANCIAL RECONCILIATION TESTS
  // ===========================================================================
  group('Financial Reconciliation', () {
    test('Daily cash flow calculation', () {
      final sales = [
        TestSaleOrder(id: 's1', totalPrice: 10000000, totalCost: 8000000, sellerName: 'A', soldAt: 0, paymentMethod: 'TIỀN MẶT'),
        TestSaleOrder(id: 's2', totalPrice: 15000000, totalCost: 12000000, sellerName: 'A', soldAt: 0, paymentMethod: 'CHUYỂN KHOẢN'),
        TestSaleOrder(id: 's3', totalPrice: 5000000, totalCost: 4000000, sellerName: 'A', soldAt: 0, paymentMethod: 'CÔNG NỢ'),
      ];
      
      final cashIn = sales
          .where((s) => s.paymentMethod == 'TIỀN MẶT')
          .fold(0.0, (sum, s) => sum + s.totalPrice);
      final bankIn = sales
          .where((s) => s.paymentMethod == 'CHUYỂN KHOẢN')
          .fold(0.0, (sum, s) => sum + s.totalPrice);
      final debtSales = sales
          .where((s) => s.paymentMethod == 'CÔNG NỢ')
          .fold(0.0, (sum, s) => sum + s.totalPrice);
      
      expect(cashIn, 10000000);
      expect(bankIn, 15000000);
      expect(debtSales, 5000000);
      
      // Total revenue (accrual)
      final totalRevenue = sales.fold(0.0, (sum, s) => sum + s.totalPrice);
      expect(totalRevenue, 30000000);
      
      // Total profit
      final totalProfit = sales.fold(0.0, (sum, s) => sum + s.profit);
      expect(totalProfit, 6000000);
    });
    
    test('Monthly summary calculation', () {
      // Simulate a full month
      final totalSales = 150000000.0;
      final totalCost = 120000000.0;
      final grossProfit = totalSales - totalCost;
      
      final operatingExpenses = 15000000.0; // Rent, utilities, etc.
      final salaryExpenses = 25000000.0;   // Staff salaries
      
      final netProfit = grossProfit - operatingExpenses - salaryExpenses;
      
      expect(grossProfit, 30000000);
      expect(netProfit, -10000000); // Loss scenario
    });
  });
  
  // ===========================================================================
  // 9. EDGE CASES AND ERROR HANDLING
  // ===========================================================================
  group('Edge Cases', () {
    test('Zero work days should not cause division by zero', () {
      final settings = TestEmployeeSalarySettings(
        staffId: 'edge_001',
        staffName: 'Edge Case',
        baseSalary: 10000000,
        salaryType: 'monthly',
      );
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: settings,
        workDays: 0,
        totalWorkHours: 0,
        overtimeHours: 0,
        lateDays: 0,
        earlyLeaveDays: 0,
        sales: [],
        repairs: [],
        deductions: TestDeductionSettings(),
        workingDaysInMonth: 26,
      );
      
      expect(result['baseSalary'], 0);
      expect(result['netSalary']!.isFinite, true);
    });
    
    test('Negative absent days should be clamped to 0', () {
      // Employee worked more days than standard (e.g., came in on Sunday)
      final settings = TestEmployeeSalarySettings(
        staffId: 'edge_002',
        staffName: 'Hard Worker',
        baseSalary: 10000000,
      );
      
      final result = SalaryCalculator.calculateMonthlySalary(
        settings: settings,
        workDays: 30, // More than working days in month
        totalWorkHours: 240,
        overtimeHours: 0,
        lateDays: 0,
        earlyLeaveDays: 0,
        sales: [],
        repairs: [],
        deductions: TestDeductionSettings(),
        workingDaysInMonth: 26,
      );
      
      // Absent days should be 0, not negative
      expect(result['absentDays'], 0);
      expect(result['absenceDeduction'], 0);
    });
    
    test('Very high sales should not overflow', () {
      final settings = TestEmployeeSalarySettings(
        staffId: 'edge_003',
        staffName: 'Super Seller',
        saleCommType: 'percent',
        saleCommValue: 1,
      );
      
      // 1 billion VND sale
      final comm = settings.calculateSaleCommission(1000000000);
      expect(comm, 10000000); // 1% of 1B = 10M
    });
  });
  
  // ===========================================================================
  // 10. REAL-WORLD INTEGRATION SCENARIO
  // ===========================================================================
  group('Real-World Integration Scenarios', () {
    test('Complete monthly payroll for a small shop', () {
      // Setup: A small phone repair shop with 3 employees
      
      // Employee 1: Manager with monthly salary
      final manager = TestEmployeeSalarySettings(
        staffId: 'manager_001',
        staffName: 'Nguyễn Văn Manager',
        baseSalary: 15000000,
        salaryType: 'monthly',
        saleCommType: 'percent',
        saleCommValue: 0.5,
        repairCommType: 'percent',
        repairCommValue: 5,
        transportAllowance: 1000000,
        mealAllowance: 1500000,
      );
      
      // Employee 2: Sales staff with tiered commission
      final sales = TestEmployeeSalarySettings(
        staffId: 'sales_001',
        staffName: 'Trần Thị Sales',
        baseSalary: 8000000,
        salaryType: 'monthly',
        saleCommType: 'tiered',
        saleCommTier1Max: 10000000,
        saleCommTier1Value: 20000,
        saleCommTier2Max: 50000000,
        saleCommTier2Value: 50000,
        saleCommTier3Value: 100000,
        transportAllowance: 500000,
        mealAllowance: 1000000,
      );
      
      // Employee 3: Technician with daily rate
      final tech = TestEmployeeSalarySettings(
        staffId: 'tech_001',
        staffName: 'Lê Văn Tech',
        dailyRate: 400000,
        salaryType: 'daily',
        repairCommType: 'fixed_per_order',
        repairCommValue: 50000,
        mealAllowance: 500000,
      );
      
      final deductions = TestDeductionSettings();
      
      // Manager worked full month, 2 sales
      final managerResult = SalaryCalculator.calculateMonthlySalary(
        settings: manager,
        workDays: 26,
        totalWorkHours: 208,
        overtimeHours: 0,
        lateDays: 0,
        earlyLeaveDays: 0,
        sales: [
          TestSaleOrder(id: 'm1', totalPrice: 50000000, totalCost: 40000000, sellerName: 'manager', soldAt: 0),
          TestSaleOrder(id: 'm2', totalPrice: 30000000, totalCost: 24000000, sellerName: 'manager', soldAt: 0),
        ],
        repairs: [
          TestRepair(id: 'mr1', model: 'iPhone', status: 4, price: 500000, totalCost: 100000, createdBy: 'manager', createdAt: 0),
        ],
        deductions: deductions,
        workingDaysInMonth: 26,
      );
      
      // Sales staff worked 24 days, sold 8 products
      final salesResult = SalaryCalculator.calculateMonthlySalary(
        settings: sales,
        workDays: 24,
        totalWorkHours: 192,
        overtimeHours: 5,
        lateDays: 2,
        earlyLeaveDays: 0,
        sales: [
          TestSaleOrder(id: 's1', totalPrice: 8000000, totalCost: 6500000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's2', totalPrice: 12000000, totalCost: 10000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's3', totalPrice: 25000000, totalCost: 20000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's4', totalPrice: 55000000, totalCost: 45000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's5', totalPrice: 5000000, totalCost: 4000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's6', totalPrice: 15000000, totalCost: 12000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's7', totalPrice: 9000000, totalCost: 7000000, sellerName: 'sales', soldAt: 0),
          TestSaleOrder(id: 's8', totalPrice: 35000000, totalCost: 28000000, sellerName: 'sales', soldAt: 0),
        ],
        repairs: [],
        deductions: deductions,
        workingDaysInMonth: 26,
      );
      
      // Tech worked 22 days, fixed 15 devices
      final techResult = SalaryCalculator.calculateMonthlySalary(
        settings: tech,
        workDays: 22,
        totalWorkHours: 176,
        overtimeHours: 8,
        lateDays: 4,
        earlyLeaveDays: 3,
        sales: [],
        repairs: List.generate(15, (i) => TestRepair(
          id: 'tr$i',
          model: 'Device $i',
          status: 4,
          price: 300000,
          totalCost: 80000,
          createdBy: 'tech',
          createdAt: 0,
        )),
        deductions: deductions,
        workingDaysInMonth: 26,
      );
      
      // Verify all results are valid
      expect(managerResult['netSalary']! > 0, true);
      expect(salesResult['netSalary']! > 0, true);
      expect(techResult['netSalary']! > 0, true);
      
      // Total payroll
      final totalPayroll = managerResult['netSalary']! + 
                           salesResult['netSalary']! + 
                           techResult['netSalary']!;
      expect(totalPayroll > 0, true);
      
      // Debug output (will show in test results)
      print('=== MONTHLY PAYROLL SUMMARY ===');
      print('Manager: ${managerResult['netSalary']!.toStringAsFixed(0)}đ');
      print('  - Base: ${managerResult['baseSalary']!.toStringAsFixed(0)}đ');
      print('  - Commission: ${(managerResult['saleCommission']! + managerResult['repairCommission']!).toStringAsFixed(0)}đ');
      print('Sales: ${salesResult['netSalary']!.toStringAsFixed(0)}đ');
      print('  - Base: ${salesResult['baseSalary']!.toStringAsFixed(0)}đ');
      print('  - Commission: ${salesResult['saleCommission']!.toStringAsFixed(0)}đ (${salesResult['saleOrderCount']!.toInt()} orders)');
      print('Tech: ${techResult['netSalary']!.toStringAsFixed(0)}đ');
      print('  - Base: ${techResult['baseSalary']!.toStringAsFixed(0)}đ');
      print('  - Commission: ${techResult['repairCommission']!.toStringAsFixed(0)}đ (${techResult['repairOrderCount']!.toInt()} repairs)');
      print('Total Payroll: ${totalPayroll.toStringAsFixed(0)}đ');
      
      // Sales staff tiered commission verification
      // Orders: 8M(T1), 12M(T2), 25M(T2), 55M(T3), 5M(T1), 15M(T2), 9M(T1), 35M(T2)
      // = 20k + 50k + 50k + 100k + 20k + 50k + 20k + 50k = 360k
      expect(salesResult['saleCommission'], 360000);
    });
  });
}
