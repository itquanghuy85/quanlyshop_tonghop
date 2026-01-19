import 'shop_deduction_settings.dart';

/// Model chi tiết bảng lương nhân viên
/// Hiển thị từng khoản rõ ràng để dễ kiểm tra
class SalaryBreakdown {
  final String staffId;
  final String staffName;
  final int month;
  final int year;

  // === THÔNG TIN CHẤM CÔNG ===
  final int workDays; // Số ngày đi làm
  final double totalWorkHours; // Tổng giờ làm việc
  final double overtimeHours; // Giờ OT
  final int lateDays; // Số lần đi muộn
  final int earlyLeaveDays; // Số lần về sớm
  final int absentDays; // Số ngày nghỉ (không phép)

  // === THÔNG TIN DOANH SỐ ===
  final int saleOrderCount; // Số đơn bán
  final double saleRevenue; // Doanh số bán hàng
  final double saleProfit; // Lợi nhuận bán hàng

  final int repairOrderCount; // Số đơn sửa chữa (đã giao)
  final double repairRevenue; // Doanh thu sửa chữa
  final double repairProfit; // Lợi nhuận sửa chữa

  // === CÀI ĐẶT LƯƠNG (từ settings) ===
  final String salaryType; // monthly/daily/hourly
  final double baseSalary; // Lương cơ bản/tháng hoặc /ngày hoặc /giờ
  final String saleCommType; // percent/fixed_per_order
  final double saleCommValue; // Giá trị cài đặt
  final String repairCommType; // percent/fixed_per_order
  final double repairCommValue; // Giá trị cài đặt
  final double overtimeRate; // Hệ số OT (150 = 1.5x)
  final double monthlyTarget; // Mục tiêu doanh số
  final double targetBonusPercent; // % thưởng khi đạt target
  final double standardHoursPerDay; // Giờ chuẩn/ngày

  // === PHỤ CẤP ===
  final double transportAllowance;
  final double mealAllowance;
  final double phoneAllowance;
  final double otherAllowance;

  // === TÍNH TOÁN TỪNG KHOẢN (THU NHẬP) ===
  final double calculatedBaseSalary; // Lương cơ bản thực nhận
  final double calculatedSaleComm; // Hoa hồng bán hàng
  final double calculatedRepairComm; // Hoa hồng sửa chữa
  final double calculatedOT; // Tiền OT
  final double calculatedBonus; // Thưởng doanh số
  final double calculatedAllowance; // Tổng phụ cấp

  // === KHOẢN THƯỞNG/TRỪ TÙY CHỈNH ===
  final List<CustomSalaryAdjustment> customBonuses; // Thưởng tùy chỉnh
  final List<CustomSalaryAdjustment> customDeductions; // Trừ tùy chỉnh

  // === KHẤU TRỪ THEO QUY ĐỊNH SHOP ===
  final double lateDeduction; // Trừ đi muộn
  final double earlyLeaveDeduction; // Trừ về sớm
  final double absenceDeduction; // Trừ nghỉ quá phép

  // === BẢO HIỂM ===
  final double socialInsurance; // BHXH (8%)
  final double healthInsurance; // BHYT (1.5%)
  final double unemploymentInsurance; // BHTN (1%)

  // === THUẾ TNCN ===
  final double grossIncomeBeforeTax; // Tổng thu nhập trước thuế
  final double insuranceDeduction; // Tổng BH đã trừ
  final double selfDeduction; // Giảm trừ bản thân
  final double dependentDeduction; // Giảm trừ người phụ thuộc
  final double taxableIncome; // Thu nhập chịu thuế
  final double personalIncomeTax; // Thuế TNCN phải đóng

  // === TỔNG KHẤU TRỪ ===
  final double totalDeductions; // Tổng tất cả khấu trừ

  // === TỔNG CỘNG ===
  final double totalSalary; // Tổng lương thực nhận (GROSS - tất cả khấu trừ)

  // === GHI CHÚ TÍNH TOÁN ===
  final List<String> calculationNotes; // Giải thích cách tính

  SalaryBreakdown({
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.year,
    this.workDays = 0,
    this.totalWorkHours = 0,
    this.overtimeHours = 0,
    this.lateDays = 0,
    this.earlyLeaveDays = 0,
    this.absentDays = 0,
    this.saleOrderCount = 0,
    this.saleRevenue = 0,
    this.saleProfit = 0,
    this.repairOrderCount = 0,
    this.repairRevenue = 0,
    this.repairProfit = 0,
    this.salaryType = 'monthly',
    this.baseSalary = 0,
    this.saleCommType = 'percent',
    this.saleCommValue = 0,
    this.repairCommType = 'percent',
    this.repairCommValue = 0,
    this.overtimeRate = 150,
    this.monthlyTarget = 0,
    this.targetBonusPercent = 0,
    this.standardHoursPerDay = 8,
    this.transportAllowance = 0,
    this.mealAllowance = 0,
    this.phoneAllowance = 0,
    this.otherAllowance = 0,
    this.calculatedBaseSalary = 0,
    this.calculatedSaleComm = 0,
    this.calculatedRepairComm = 0,
    this.calculatedOT = 0,
    this.calculatedBonus = 0,
    this.calculatedAllowance = 0,
    this.customBonuses = const [],
    this.customDeductions = const [],
    this.lateDeduction = 0,
    this.earlyLeaveDeduction = 0,
    this.absenceDeduction = 0,
    this.socialInsurance = 0,
    this.healthInsurance = 0,
    this.unemploymentInsurance = 0,
    this.grossIncomeBeforeTax = 0,
    this.insuranceDeduction = 0,
    this.selfDeduction = 0,
    this.dependentDeduction = 0,
    this.taxableIncome = 0,
    this.personalIncomeTax = 0,
    this.totalDeductions = 0,
    this.totalSalary = 0,
    this.calculationNotes = const [],
  });

  /// Tổng doanh số (bán + sửa)
  double get totalRevenue => saleRevenue + repairRevenue;

  /// Tổng lợi nhuận mang về
  double get totalProfit => saleProfit + repairProfit;

  /// Tổng số đơn
  int get totalOrders => saleOrderCount + repairOrderCount;

  /// Tổng thu nhập GROSS (trước khấu trừ)
  double get grossIncome =>
      calculatedBaseSalary +
      calculatedSaleComm +
      calculatedRepairComm +
      calculatedOT +
      calculatedBonus +
      calculatedAllowance +
      totalCustomBonuses;

  /// Tổng thưởng tùy chỉnh
  double get totalCustomBonuses =>
      customBonuses.fold(0.0, (sum, b) => sum + b.amount);

  /// Tổng trừ tùy chỉnh
  double get totalCustomDeductions =>
      customDeductions.fold(0.0, (sum, d) => sum + d.amount);

  /// Tổng bảo hiểm
  double get totalInsurance =>
      socialInsurance + healthInsurance + unemploymentInsurance;

  /// Copy with để update
  SalaryBreakdown copyWith({
    String? staffId,
    String? staffName,
    int? month,
    int? year,
    int? workDays,
    double? totalWorkHours,
    double? overtimeHours,
    int? lateDays,
    int? earlyLeaveDays,
    int? absentDays,
    int? saleOrderCount,
    double? saleRevenue,
    double? saleProfit,
    int? repairOrderCount,
    double? repairRevenue,
    double? repairProfit,
    String? salaryType,
    double? baseSalary,
    String? saleCommType,
    double? saleCommValue,
    String? repairCommType,
    double? repairCommValue,
    double? overtimeRate,
    double? monthlyTarget,
    double? targetBonusPercent,
    double? standardHoursPerDay,
    double? transportAllowance,
    double? mealAllowance,
    double? phoneAllowance,
    double? otherAllowance,
    double? calculatedBaseSalary,
    double? calculatedSaleComm,
    double? calculatedRepairComm,
    double? calculatedOT,
    double? calculatedBonus,
    double? calculatedAllowance,
    List<CustomSalaryAdjustment>? customBonuses,
    List<CustomSalaryAdjustment>? customDeductions,
    double? lateDeduction,
    double? earlyLeaveDeduction,
    double? absenceDeduction,
    double? socialInsurance,
    double? healthInsurance,
    double? unemploymentInsurance,
    double? grossIncomeBeforeTax,
    double? insuranceDeduction,
    double? selfDeduction,
    double? dependentDeduction,
    double? taxableIncome,
    double? personalIncomeTax,
    double? totalDeductions,
    double? totalSalary,
    List<String>? calculationNotes,
  }) {
    return SalaryBreakdown(
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
      month: month ?? this.month,
      year: year ?? this.year,
      workDays: workDays ?? this.workDays,
      totalWorkHours: totalWorkHours ?? this.totalWorkHours,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      lateDays: lateDays ?? this.lateDays,
      earlyLeaveDays: earlyLeaveDays ?? this.earlyLeaveDays,
      absentDays: absentDays ?? this.absentDays,
      saleOrderCount: saleOrderCount ?? this.saleOrderCount,
      saleRevenue: saleRevenue ?? this.saleRevenue,
      saleProfit: saleProfit ?? this.saleProfit,
      repairOrderCount: repairOrderCount ?? this.repairOrderCount,
      repairRevenue: repairRevenue ?? this.repairRevenue,
      repairProfit: repairProfit ?? this.repairProfit,
      salaryType: salaryType ?? this.salaryType,
      baseSalary: baseSalary ?? this.baseSalary,
      saleCommType: saleCommType ?? this.saleCommType,
      saleCommValue: saleCommValue ?? this.saleCommValue,
      repairCommType: repairCommType ?? this.repairCommType,
      repairCommValue: repairCommValue ?? this.repairCommValue,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      monthlyTarget: monthlyTarget ?? this.monthlyTarget,
      targetBonusPercent: targetBonusPercent ?? this.targetBonusPercent,
      standardHoursPerDay: standardHoursPerDay ?? this.standardHoursPerDay,
      transportAllowance: transportAllowance ?? this.transportAllowance,
      mealAllowance: mealAllowance ?? this.mealAllowance,
      phoneAllowance: phoneAllowance ?? this.phoneAllowance,
      otherAllowance: otherAllowance ?? this.otherAllowance,
      calculatedBaseSalary: calculatedBaseSalary ?? this.calculatedBaseSalary,
      calculatedSaleComm: calculatedSaleComm ?? this.calculatedSaleComm,
      calculatedRepairComm: calculatedRepairComm ?? this.calculatedRepairComm,
      calculatedOT: calculatedOT ?? this.calculatedOT,
      calculatedBonus: calculatedBonus ?? this.calculatedBonus,
      calculatedAllowance: calculatedAllowance ?? this.calculatedAllowance,
      customBonuses: customBonuses ?? this.customBonuses,
      customDeductions: customDeductions ?? this.customDeductions,
      lateDeduction: lateDeduction ?? this.lateDeduction,
      earlyLeaveDeduction: earlyLeaveDeduction ?? this.earlyLeaveDeduction,
      absenceDeduction: absenceDeduction ?? this.absenceDeduction,
      socialInsurance: socialInsurance ?? this.socialInsurance,
      healthInsurance: healthInsurance ?? this.healthInsurance,
      unemploymentInsurance:
          unemploymentInsurance ?? this.unemploymentInsurance,
      grossIncomeBeforeTax: grossIncomeBeforeTax ?? this.grossIncomeBeforeTax,
      insuranceDeduction: insuranceDeduction ?? this.insuranceDeduction,
      selfDeduction: selfDeduction ?? this.selfDeduction,
      dependentDeduction: dependentDeduction ?? this.dependentDeduction,
      taxableIncome: taxableIncome ?? this.taxableIncome,
      personalIncomeTax: personalIncomeTax ?? this.personalIncomeTax,
      totalDeductions: totalDeductions ?? this.totalDeductions,
      totalSalary: totalSalary ?? this.totalSalary,
      calculationNotes: calculationNotes ?? this.calculationNotes,
    );
  }

  @override
  String toString() =>
      'SalaryBreakdown($staffName, T$month/$year, net: $totalSalary)';
}
