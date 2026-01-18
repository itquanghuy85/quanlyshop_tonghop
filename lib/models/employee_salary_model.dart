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
  final String saleCommType; // 'percent' | 'fixed_per_order'
  final double saleCommValue; // % hoặc số tiền cố định/đơn

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
    return EmployeeSalarySettings(
      id: map['id'] ?? '',
      staffId: map['staffId'] ?? '',
      staffName: map['staffName'] ?? '',
      shopId: map['shopId'] ?? '',
      baseSalary: (map['baseSalary'] ?? 0).toDouble(),
      dailyRate: (map['dailyRate'] ?? 0).toDouble(),
      salaryType: map['salaryType'] ?? 'monthly',
      saleCommType: map['saleCommType'] ?? 'percent',
      saleCommValue: (map['saleCommValue'] ?? 1.0).toDouble(),
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
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt']
          : DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedAt: map['updatedAt'] is DateTime
          ? map['updatedAt']
          : DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedBy: map['updatedBy'],
      isActive: map['isActive'] ?? true,
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
      'id': id,
      'staffId': staffId,
      'staffName': staffName,
      'shopId': shopId,
      'baseSalary': baseSalary,
      'dailyRate': dailyRate,
      'salaryType': salaryType,
      'saleCommType': saleCommType,
      'saleCommValue': saleCommValue,
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
      'updatedAt': updatedAt.toIso8601String(),
      'updatedBy': updatedBy,
      'isActive': isActive ? 1 : 0,
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

  /// Tính hoa hồng bán hàng dự kiến theo doanh số
  double calculateSaleCommission(double revenue) {
    if (saleCommType == 'percent') {
      return revenue * (saleCommValue / 100);
    } else {
      // fixed_per_order - cần biết số đơn
      return saleCommValue; // Trả về giá trị/đơn
    }
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
