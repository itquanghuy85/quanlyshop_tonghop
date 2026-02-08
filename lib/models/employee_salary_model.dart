/// Model cho cài đặt lương và hoa hồng của từng nhân viên
/// Hỗ trợ sync với Firestore và lưu local SQLite
class EmployeeSalarySettings {
  final String id;
  final String staffId; // userId của nhân viên
  final String staffName;
  final String shopId;

  // === LƯƠNG CƠ BẢN ===
  final double baseSalary; // Lương cơ bản/tháng
  final double dailyRate; // Lương theo ngày (nếu tính theo ngày)
  final String salaryType; // 'monthly' | 'daily' | 'hourly'

  // === HOA HỒNG BÁN HÀNG ===
  final String saleCommType; // 'percent' | 'fixed_per_order' | 'tiered'
  final double saleCommValue; // % hoặc số tiền cố định/đơn
  
  // === HOA HỒNG THEO BẬC (TIERED) ===
  // Tier 1: Đơn hàng dưới tier1Max
  final double saleCommTier1Max;    // e.g., 10,000,000 (10 triệu)
  final double saleCommTier1Value;  // e.g., 20,000 (20k)
  // Tier 2: Đơn hàng từ tier1Max đến tier2Max
  final double saleCommTier2Max;    // e.g., 50,000,000 (50 triệu)
  final double saleCommTier2Value;  // e.g., 50,000 (50k)
  // Tier 3: Đơn hàng trên tier2Max
  final double saleCommTier3Value;  // e.g., 100,000 (100k)

  // === HOA HỒNG SỬA CHỮA ===
  final String repairCommType; // 'percent' | 'fixed_per_order'
  final double repairCommValue; // % lợi nhuận hoặc số tiền cố định/đơn

  // === PHỤ CẤP ===
  final double transportAllowance; // Phụ cấp xăng xe
  final double mealAllowance; // Phụ cấp ăn trưa
  final double phoneAllowance; // Phụ cấp điện thoại
  final double otherAllowance; // Phụ cấp khác
  final String otherAllowanceNote; // Ghi chú phụ cấp khác

  // === THƯỞNG DOANH SỐ ===
  final double monthlyTarget; // Mục tiêu doanh số tháng
  final double targetBonusPercent; // % thưởng khi đạt mục tiêu

  // === GIỜ LÀM VIỆC & OT ===
  final double standardHoursPerDay; // Giờ chuẩn/ngày
  final double overtimeRate; // Hệ số OT (e.g., 150 = 1.5x)

  // === METADATA ===
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedBy;
  final bool isActive;

  EmployeeSalarySettings({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.shopId,
    this.baseSalary = 0,
    this.dailyRate = 0,
    this.salaryType = 'monthly',
    this.saleCommType = 'percent',
    this.saleCommValue = 1.0,
    this.saleCommTier1Max = 10000000,  // 10 triệu
    this.saleCommTier1Value = 20000,   // 20k
    this.saleCommTier2Max = 50000000,  // 50 triệu
    this.saleCommTier2Value = 50000,   // 50k
    this.saleCommTier3Value = 100000,  // 100k
    this.repairCommType = 'percent',
    this.repairCommValue = 10.0,
    this.transportAllowance = 0,
    this.mealAllowance = 0,
    this.phoneAllowance = 0,
    this.otherAllowance = 0,
    this.otherAllowanceNote = '',
    this.monthlyTarget = 0,
    this.targetBonusPercent = 0,
    this.standardHoursPerDay = 8.0,
    this.overtimeRate = 150,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.updatedBy,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Tạo từ Map (Firestore hoặc SQLite)
  factory EmployeeSalarySettings.fromMap(Map<String, dynamic> map) {
    // Parse dates - có thể là int (milliseconds), String (ISO), hoặc DateTime
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        // Try parse as int first (milliseconds as string)
        final asInt = int.tryParse(value);
        if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
        // Try parse as ISO string
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return EmployeeSalarySettings(
      id: (map['id'] ?? map['firestoreId'] ?? '').toString(),
      staffId: map['staffId'] ?? '',
      staffName: map['staffName'] ?? '',
      shopId: map['shopId'] ?? '',
      baseSalary: (map['baseSalary'] ?? 0).toDouble(),
      dailyRate: (map['dailyRate'] ?? 0).toDouble(),
      salaryType: map['salaryType'] ?? 'monthly',
      saleCommType: map['saleCommType'] ?? 'percent',
      saleCommValue: (map['saleCommValue'] ?? 1.0).toDouble(),
      saleCommTier1Max: (map['saleCommTier1Max'] ?? 10000000).toDouble(),
      saleCommTier1Value: (map['saleCommTier1Value'] ?? 20000).toDouble(),
      saleCommTier2Max: (map['saleCommTier2Max'] ?? 50000000).toDouble(),
      saleCommTier2Value: (map['saleCommTier2Value'] ?? 50000).toDouble(),
      saleCommTier3Value: (map['saleCommTier3Value'] ?? 100000).toDouble(),
      repairCommType: map['repairCommType'] ?? 'percent',
      repairCommValue: (map['repairCommValue'] ?? 10.0).toDouble(),
      transportAllowance: (map['transportAllowance'] ?? 0).toDouble(),
      mealAllowance: (map['mealAllowance'] ?? 0).toDouble(),
      phoneAllowance: (map['phoneAllowance'] ?? 0).toDouble(),
      otherAllowance: (map['otherAllowance'] ?? 0).toDouble(),
      otherAllowanceNote: map['otherAllowanceNote'] ?? '',
      monthlyTarget: (map['monthlyTarget'] ?? 0).toDouble(),
      targetBonusPercent: (map['targetBonusPercent'] ?? 0).toDouble(),
      standardHoursPerDay: (map['standardHoursPerDay'] ?? 8.0).toDouble(),
      overtimeRate: (map['overtimeRate'] ?? 150).toDouble(),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      updatedBy: map['updatedBy'],
      isActive: map['isActive'] == 1 || map['isActive'] == true,
    );
  }

  /// Chuyển sang Map cho Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'staffId': staffId,
      'staffName': staffName,
      'shopId': shopId,
      'baseSalary': baseSalary,
      'dailyRate': dailyRate,
      'salaryType': salaryType,
      'saleCommType': saleCommType,
      'saleCommValue': saleCommValue,
      'saleCommTier1Max': saleCommTier1Max,
      'saleCommTier1Value': saleCommTier1Value,
      'saleCommTier2Max': saleCommTier2Max,
      'saleCommTier2Value': saleCommTier2Value,
      'saleCommTier3Value': saleCommTier3Value,
      'repairCommType': repairCommType,
      'repairCommValue': repairCommValue,
      'transportAllowance': transportAllowance,
      'mealAllowance': mealAllowance,
      'phoneAllowance': phoneAllowance,
      'otherAllowance': otherAllowance,
      'otherAllowanceNote': otherAllowanceNote,
      'monthlyTarget': monthlyTarget,
      'targetBonusPercent': targetBonusPercent,
      'standardHoursPerDay': standardHoursPerDay,
      'overtimeRate': overtimeRate,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
      'isActive': isActive,
    };
  }

  /// Chuyển sang Map cho SQLite
  Map<String, dynamic> toMap() {
    return {
      // 'id' không bao gồm vì là AUTO INCREMENT trong SQLite
      'staffId': staffId,
      'staffName': staffName,
      'shopId': shopId,
      'baseSalary': baseSalary,
      'dailyRate': dailyRate,
      'salaryType': salaryType,
      'saleCommType': saleCommType,
      'saleCommValue': saleCommValue,
      'saleCommTier1Max': saleCommTier1Max,
      'saleCommTier1Value': saleCommTier1Value,
      'saleCommTier2Max': saleCommTier2Max,
      'saleCommTier2Value': saleCommTier2Value,
      'saleCommTier3Value': saleCommTier3Value,
      'repairCommType': repairCommType,
      'repairCommValue': repairCommValue,
      'transportAllowance': transportAllowance,
      'mealAllowance': mealAllowance,
      'phoneAllowance': phoneAllowance,
      'otherAllowance': otherAllowance,
      'otherAllowanceNote': otherAllowanceNote,
      'monthlyTarget': monthlyTarget,
      'targetBonusPercent': targetBonusPercent,
      'standardHoursPerDay': standardHoursPerDay,
      'overtimeRate': overtimeRate,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'updatedBy': updatedBy,
      'isActive': isActive ? 1 : 0,
      'isSynced': 0,
    };
  }

  /// Copy with để update
  EmployeeSalarySettings copyWith({
    String? id,
    String? staffId,
    String? staffName,
    String? shopId,
    double? baseSalary,
    double? dailyRate,
    String? salaryType,
    String? saleCommType,
    double? saleCommValue,
    double? saleCommTier1Max,
    double? saleCommTier1Value,
    double? saleCommTier2Max,
    double? saleCommTier2Value,
    double? saleCommTier3Value,
    String? repairCommType,
    double? repairCommValue,
    double? transportAllowance,
    double? mealAllowance,
    double? phoneAllowance,
    double? otherAllowance,
    String? otherAllowanceNote,
    double? monthlyTarget,
    double? targetBonusPercent,
    double? standardHoursPerDay,
    double? overtimeRate,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    bool? isActive,
  }) {
    return EmployeeSalarySettings(
      id: id ?? this.id,
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
      shopId: shopId ?? this.shopId,
      baseSalary: baseSalary ?? this.baseSalary,
      dailyRate: dailyRate ?? this.dailyRate,
      salaryType: salaryType ?? this.salaryType,
      saleCommType: saleCommType ?? this.saleCommType,
      saleCommValue: saleCommValue ?? this.saleCommValue,
      saleCommTier1Max: saleCommTier1Max ?? this.saleCommTier1Max,
      saleCommTier1Value: saleCommTier1Value ?? this.saleCommTier1Value,
      saleCommTier2Max: saleCommTier2Max ?? this.saleCommTier2Max,
      saleCommTier2Value: saleCommTier2Value ?? this.saleCommTier2Value,
      saleCommTier3Value: saleCommTier3Value ?? this.saleCommTier3Value,
      repairCommType: repairCommType ?? this.repairCommType,
      repairCommValue: repairCommValue ?? this.repairCommValue,
      transportAllowance: transportAllowance ?? this.transportAllowance,
      mealAllowance: mealAllowance ?? this.mealAllowance,
      phoneAllowance: phoneAllowance ?? this.phoneAllowance,
      otherAllowance: otherAllowance ?? this.otherAllowance,
      otherAllowanceNote: otherAllowanceNote ?? this.otherAllowanceNote,
      monthlyTarget: monthlyTarget ?? this.monthlyTarget,
      targetBonusPercent: targetBonusPercent ?? this.targetBonusPercent,
      standardHoursPerDay: standardHoursPerDay ?? this.standardHoursPerDay,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      updatedBy: updatedBy ?? this.updatedBy,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Tính tổng phụ cấp
  double get totalAllowance =>
      transportAllowance + mealAllowance + phoneAllowance + otherAllowance;

  /// Tính hoa hồng bán hàng dự kiến theo doanh số (giá trị đơn hàng)
  /// [orderValue]: Giá trị đơn hàng
  /// Returns: Hoa hồng cho đơn hàng đó
  double calculateSaleCommission(double orderValue) {
    if (saleCommType == 'percent') {
      return orderValue * (saleCommValue / 100);
    } else if (saleCommType == 'tiered') {
      // Hoa hồng theo bậc dựa vào giá trị đơn hàng
      // Tier 1: Dưới tier1Max -> tier1Value
      // Tier 2: Từ tier1Max đến tier2Max -> tier2Value
      // Tier 3: Trên tier2Max -> tier3Value
      if (orderValue < saleCommTier1Max) {
        return saleCommTier1Value;
      } else if (orderValue <= saleCommTier2Max) {
        return saleCommTier2Value;
      } else {
        return saleCommTier3Value;
      }
    } else {
      // fixed_per_order - số tiền cố định
      return saleCommValue;
    }
  }

  /// Tính tổng hoa hồng cho nhiều đơn hàng (dùng cho tiered)
  /// [orderValues]: List giá trị các đơn hàng
  double calculateTotalSaleCommission(List<double> orderValues) {
    return orderValues.fold(0.0, (sum, orderValue) => sum + calculateSaleCommission(orderValue));
  }

  /// Tính hoa hồng sửa chữa dự kiến theo lợi nhuận
  double calculateRepairCommission(double profit) {
    if (repairCommType == 'percent') {
      return profit * (repairCommValue / 100);
    } else {
      return repairCommValue;
    }
  }

  /// Tính thưởng doanh số
  double calculateTargetBonus(double actualRevenue) {
    if (monthlyTarget <= 0 || actualRevenue < monthlyTarget) return 0;
    return actualRevenue * (targetBonusPercent / 100);
  }

  @override
  String toString() =>
      'EmployeeSalarySettings(staffId: $staffId, staffName: $staffName, baseSalary: $baseSalary)';
}
