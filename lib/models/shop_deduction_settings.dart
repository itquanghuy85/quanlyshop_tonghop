/// Model cài đặt quy định khấu trừ và thuế của Shop
/// Bao gồm: Đi muộn, về sớm, nghỉ quá phép, thuế TNCN, BHXH, BHYT, BHTN
class ShopDeductionSettings {
  // === KHẤU TRỪ ĐI MUỘN ===
  final bool enableLateDeduction; // Bật/tắt trừ đi muộn
  final double lateDeductionPerTime; // Số tiền trừ mỗi lần đi muộn
  final int lateGraceTimes; // Số lần được phép đi muộn không bị trừ

  // === KHẤU TRỪ VỀ SỚM ===
  final bool enableEarlyLeaveDeduction; // Bật/tắt trừ về sớm
  final double earlyLeaveDeductionPerTime; // Số tiền trừ mỗi lần về sớm
  final int earlyLeaveGraceTimes; // Số lần được phép về sớm không bị trừ

  // === KHẤU TRỪ NGHỈ QUÁ PHÉP ===
  final bool enableAbsenceDeduction; // Bật/tắt trừ nghỉ quá phép
  final int allowedAbsenceDays; // Số ngày nghỉ phép được phép/tháng
  final double absenceDeductionPerDay; // Số tiền trừ mỗi ngày nghỉ quá phép

  // === THUẾ THU NHẬP CÁ NHÂN ===
  final bool enablePIT; // Bật/tắt tính thuế TNCN
  final double pitDeductionSelf; // Giảm trừ bản thân (11 triệu)
  final double
  pitDeductionDependent; // Giảm trừ người phụ thuộc (4.4 triệu/người)

  // === BẢO HIỂM ===
  final bool enableSocialInsurance; // Bật/tắt BHXH
  final double socialInsuranceRate; // % BHXH (8% người lao động)
  final bool enableHealthInsurance; // Bật/tắt BHYT
  final double healthInsuranceRate; // % BHYT (1.5% người lao động)
  final bool enableUnemploymentInsurance; // Bật/tắt BHTN
  final double unemploymentInsuranceRate; // % BHTN (1% người lao động)
  final double insuranceBaseSalary; // Mức lương đóng BH (nếu khác lương cơ bản)

  // === METADATA ===
  final String shopId;
  final DateTime updatedAt;
  final String? updatedBy;

  ShopDeductionSettings({
    this.enableLateDeduction = false,
    this.lateDeductionPerTime = 50000,
    this.lateGraceTimes = 2,
    this.enableEarlyLeaveDeduction = false,
    this.earlyLeaveDeductionPerTime = 50000,
    this.earlyLeaveGraceTimes = 2,
    this.enableAbsenceDeduction = false,
    this.allowedAbsenceDays = 2,
    this.absenceDeductionPerDay = 200000,
    this.enablePIT = false,
    this.pitDeductionSelf = 11000000,
    this.pitDeductionDependent = 4400000,
    this.enableSocialInsurance = false,
    this.socialInsuranceRate = 8.0,
    this.enableHealthInsurance = false,
    this.healthInsuranceRate = 1.5,
    this.enableUnemploymentInsurance = false,
    this.unemploymentInsuranceRate = 1.0,
    this.insuranceBaseSalary = 0,
    this.shopId = '',
    DateTime? updatedAt,
    this.updatedBy,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory ShopDeductionSettings.fromMap(Map<String, dynamic> map) {
    return ShopDeductionSettings(
      enableLateDeduction:
          map['enableLateDeduction'] == true || map['enableLateDeduction'] == 1,
      lateDeductionPerTime: (map['lateDeductionPerTime'] ?? 50000).toDouble(),
      lateGraceTimes: (map['lateGraceTimes'] ?? 2).toInt(),
      enableEarlyLeaveDeduction:
          map['enableEarlyLeaveDeduction'] == true ||
          map['enableEarlyLeaveDeduction'] == 1,
      earlyLeaveDeductionPerTime: (map['earlyLeaveDeductionPerTime'] ?? 50000)
          .toDouble(),
      earlyLeaveGraceTimes: (map['earlyLeaveGraceTimes'] ?? 2).toInt(),
      enableAbsenceDeduction:
          map['enableAbsenceDeduction'] == true ||
          map['enableAbsenceDeduction'] == 1,
      allowedAbsenceDays: (map['allowedAbsenceDays'] ?? 2).toInt(),
      absenceDeductionPerDay: (map['absenceDeductionPerDay'] ?? 200000)
          .toDouble(),
      enablePIT: map['enablePIT'] == true || map['enablePIT'] == 1,
      pitDeductionSelf: (map['pitDeductionSelf'] ?? 11000000).toDouble(),
      pitDeductionDependent: (map['pitDeductionDependent'] ?? 4400000)
          .toDouble(),
      enableSocialInsurance:
          map['enableSocialInsurance'] == true ||
          map['enableSocialInsurance'] == 1,
      socialInsuranceRate: (map['socialInsuranceRate'] ?? 8.0).toDouble(),
      enableHealthInsurance:
          map['enableHealthInsurance'] == true ||
          map['enableHealthInsurance'] == 1,
      healthInsuranceRate: (map['healthInsuranceRate'] ?? 1.5).toDouble(),
      enableUnemploymentInsurance:
          map['enableUnemploymentInsurance'] == true ||
          map['enableUnemploymentInsurance'] == 1,
      unemploymentInsuranceRate: (map['unemploymentInsuranceRate'] ?? 1.0)
          .toDouble(),
      insuranceBaseSalary: (map['insuranceBaseSalary'] ?? 0).toDouble(),
      shopId: map['shopId'] ?? '',
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is int
                ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
                : DateTime.tryParse(map['updatedAt'].toString()) ??
                      DateTime.now())
          : DateTime.now(),
      updatedBy: map['updatedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enableLateDeduction': enableLateDeduction,
      'lateDeductionPerTime': lateDeductionPerTime,
      'lateGraceTimes': lateGraceTimes,
      'enableEarlyLeaveDeduction': enableEarlyLeaveDeduction,
      'earlyLeaveDeductionPerTime': earlyLeaveDeductionPerTime,
      'earlyLeaveGraceTimes': earlyLeaveGraceTimes,
      'enableAbsenceDeduction': enableAbsenceDeduction,
      'allowedAbsenceDays': allowedAbsenceDays,
      'absenceDeductionPerDay': absenceDeductionPerDay,
      'enablePIT': enablePIT,
      'pitDeductionSelf': pitDeductionSelf,
      'pitDeductionDependent': pitDeductionDependent,
      'enableSocialInsurance': enableSocialInsurance,
      'socialInsuranceRate': socialInsuranceRate,
      'enableHealthInsurance': enableHealthInsurance,
      'healthInsuranceRate': healthInsuranceRate,
      'enableUnemploymentInsurance': enableUnemploymentInsurance,
      'unemploymentInsuranceRate': unemploymentInsuranceRate,
      'insuranceBaseSalary': insuranceBaseSalary,
      'shopId': shopId,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'updatedBy': updatedBy,
    };
  }

  ShopDeductionSettings copyWith({
    bool? enableLateDeduction,
    double? lateDeductionPerTime,
    int? lateGraceTimes,
    bool? enableEarlyLeaveDeduction,
    double? earlyLeaveDeductionPerTime,
    int? earlyLeaveGraceTimes,
    bool? enableAbsenceDeduction,
    int? allowedAbsenceDays,
    double? absenceDeductionPerDay,
    bool? enablePIT,
    double? pitDeductionSelf,
    double? pitDeductionDependent,
    bool? enableSocialInsurance,
    double? socialInsuranceRate,
    bool? enableHealthInsurance,
    double? healthInsuranceRate,
    bool? enableUnemploymentInsurance,
    double? unemploymentInsuranceRate,
    double? insuranceBaseSalary,
    String? shopId,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return ShopDeductionSettings(
      enableLateDeduction: enableLateDeduction ?? this.enableLateDeduction,
      lateDeductionPerTime: lateDeductionPerTime ?? this.lateDeductionPerTime,
      lateGraceTimes: lateGraceTimes ?? this.lateGraceTimes,
      enableEarlyLeaveDeduction:
          enableEarlyLeaveDeduction ?? this.enableEarlyLeaveDeduction,
      earlyLeaveDeductionPerTime:
          earlyLeaveDeductionPerTime ?? this.earlyLeaveDeductionPerTime,
      earlyLeaveGraceTimes: earlyLeaveGraceTimes ?? this.earlyLeaveGraceTimes,
      enableAbsenceDeduction:
          enableAbsenceDeduction ?? this.enableAbsenceDeduction,
      allowedAbsenceDays: allowedAbsenceDays ?? this.allowedAbsenceDays,
      absenceDeductionPerDay:
          absenceDeductionPerDay ?? this.absenceDeductionPerDay,
      enablePIT: enablePIT ?? this.enablePIT,
      pitDeductionSelf: pitDeductionSelf ?? this.pitDeductionSelf,
      pitDeductionDependent:
          pitDeductionDependent ?? this.pitDeductionDependent,
      enableSocialInsurance:
          enableSocialInsurance ?? this.enableSocialInsurance,
      socialInsuranceRate: socialInsuranceRate ?? this.socialInsuranceRate,
      enableHealthInsurance:
          enableHealthInsurance ?? this.enableHealthInsurance,
      healthInsuranceRate: healthInsuranceRate ?? this.healthInsuranceRate,
      enableUnemploymentInsurance:
          enableUnemploymentInsurance ?? this.enableUnemploymentInsurance,
      unemploymentInsuranceRate:
          unemploymentInsuranceRate ?? this.unemploymentInsuranceRate,
      insuranceBaseSalary: insuranceBaseSalary ?? this.insuranceBaseSalary,
      shopId: shopId ?? this.shopId,
      updatedAt: updatedAt ?? DateTime.now(),
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// Tính tổng % bảo hiểm người lao động phải đóng
  double get totalInsuranceRate {
    double rate = 0;
    if (enableSocialInsurance) rate += socialInsuranceRate;
    if (enableHealthInsurance) rate += healthInsuranceRate;
    if (enableUnemploymentInsurance) rate += unemploymentInsuranceRate;
    return rate;
  }
}

/// Model cho khoản thưởng/trừ tùy chỉnh của từng nhân viên theo tháng
class CustomSalaryAdjustment {
  final String id;
  final String staffId;
  final String staffName;
  final String shopId;
  final int month;
  final int year;
  final String type; // 'bonus' | 'deduction'
  final String name; // Tên khoản (VD: "Thưởng sinh nhật", "Tạm ứng")
  final double amount;
  final String? note;
  final DateTime createdAt;
  final String? createdBy;

  CustomSalaryAdjustment({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.shopId,
    required this.month,
    required this.year,
    required this.type,
    required this.name,
    required this.amount,
    this.note,
    DateTime? createdAt,
    this.createdBy,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CustomSalaryAdjustment.fromMap(Map<String, dynamic> map) {
    return CustomSalaryAdjustment(
      id: map['id'] ?? map['firestoreId'] ?? '',
      staffId: map['staffId'] ?? '',
      staffName: map['staffName'] ?? '',
      shopId: map['shopId'] ?? '',
      month: (map['month'] ?? DateTime.now().month).toInt(),
      year: (map['year'] ?? DateTime.now().year).toInt(),
      type: map['type'] ?? 'bonus',
      name: map['name'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      note: map['note'],
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is int
                ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
                : DateTime.tryParse(map['createdAt'].toString()) ??
                      DateTime.now())
          : DateTime.now(),
      createdBy: map['createdBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'staffName': staffName,
      'shopId': shopId,
      'month': month,
      'year': year,
      'type': type,
      'name': name,
      'amount': amount,
      'note': note,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
    };
  }

  bool get isBonus => type == 'bonus';
  bool get isDeduction => type == 'deduction';
}

/// Biểu thuế TNCN lũy tiến theo quy định Việt Nam
class PITCalculator {
  /// Tính thuế TNCN theo biểu thuế lũy tiến
  /// [taxableIncome] là thu nhập chịu thuế (sau khi đã trừ giảm trừ + BH)
  static double calculatePIT(double taxableIncome) {
    if (taxableIncome <= 0) return 0;

    // Biểu thuế lũy tiến từng phần (đơn vị: triệu đồng)
    // Bậc 1: đến 5 triệu: 5%
    // Bậc 2: 5-10 triệu: 10%
    // Bậc 3: 10-18 triệu: 15%
    // Bậc 4: 18-32 triệu: 20%
    // Bậc 5: 32-52 triệu: 25%
    // Bậc 6: 52-80 triệu: 30%
    // Bậc 7: trên 80 triệu: 35%

    double tax = 0;
    double remaining = taxableIncome;

    // Bậc 1: 0 - 5 triệu (5%)
    if (remaining > 0) {
      double bracket = remaining > 5000000 ? 5000000 : remaining;
      tax += bracket * 0.05;
      remaining -= bracket;
    }

    // Bậc 2: 5 - 10 triệu (10%)
    if (remaining > 0) {
      double bracket = remaining > 5000000 ? 5000000 : remaining;
      tax += bracket * 0.10;
      remaining -= bracket;
    }

    // Bậc 3: 10 - 18 triệu (15%)
    if (remaining > 0) {
      double bracket = remaining > 8000000 ? 8000000 : remaining;
      tax += bracket * 0.15;
      remaining -= bracket;
    }

    // Bậc 4: 18 - 32 triệu (20%)
    if (remaining > 0) {
      double bracket = remaining > 14000000 ? 14000000 : remaining;
      tax += bracket * 0.20;
      remaining -= bracket;
    }

    // Bậc 5: 32 - 52 triệu (25%)
    if (remaining > 0) {
      double bracket = remaining > 20000000 ? 20000000 : remaining;
      tax += bracket * 0.25;
      remaining -= bracket;
    }

    // Bậc 6: 52 - 80 triệu (30%)
    if (remaining > 0) {
      double bracket = remaining > 28000000 ? 28000000 : remaining;
      tax += bracket * 0.30;
      remaining -= bracket;
    }

    // Bậc 7: trên 80 triệu (35%)
    if (remaining > 0) {
      tax += remaining * 0.35;
    }

    return tax;
  }

  /// Tính thu nhập chịu thuế
  /// [grossIncome] = Tổng thu nhập trước thuế
  /// [insuranceDeduction] = Tổng BH đã đóng
  /// [selfDeduction] = Giảm trừ bản thân (11 triệu)
  /// [dependentDeduction] = Giảm trừ người phụ thuộc (4.4 triệu × số người)
  static double calculateTaxableIncome({
    required double grossIncome,
    required double insuranceDeduction,
    required double selfDeduction,
    required double dependentDeduction,
  }) {
    double taxableIncome =
        grossIncome - insuranceDeduction - selfDeduction - dependentDeduction;
    return taxableIncome > 0 ? taxableIncome : 0;
  }
}
