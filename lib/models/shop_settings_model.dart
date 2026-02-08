/// Model cài đặt cửa hàng theo ngành kinh doanh
/// Định nghĩa businessType và các module được bật cho shop
class ShopSettings {
  final String id;
  final String firestoreId;
  final String shopId;

  // === NGÀNH KINH DOANH ===
  /// 'electronics' | 'food' | 'fashion' | 'general'
  final String businessType;
  final String businessTypeName; // Tên hiển thị (VD: "Điện thoại", "Thực phẩm")

  // === MODULES ĐƯỢC BẬT ===
  final bool enableRepair; // Module sửa chữa (electronics)
  final bool enableExpiry; // Quản lý hạn sử dụng (food)
  final bool enableVariants; // Biến thể size/màu (fashion)
  final bool enableSerial; // Quản lý IMEI/Serial (electronics)
  final bool enableWarranty; // Quản lý bảo hành (electronics)
  final bool enableBatch; // Quản lý số lô (food)

  // === CÀI ĐẶT MẶC ĐỊNH ===
  final String defaultUnit; // Đơn vị mặc định: 'cái', 'kg', 'lít'...
  final int expiryWarningDays; // Số ngày cảnh báo HSD (mặc định 7)
  final int lowStockWarning; // Cảnh báo tồn kho thấp

  // === METADATA ===
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedBy;
  final bool isSynced;

  ShopSettings({
    this.id = '',
    this.firestoreId = '',
    required this.shopId,
    this.businessType = 'electronics',
    this.businessTypeName = 'Điện thoại & Điện tử',
    this.enableRepair = true,
    this.enableExpiry = false,
    this.enableVariants = false,
    this.enableSerial = true,
    this.enableWarranty = true,
    this.enableBatch = false,
    this.defaultUnit = 'cái',
    this.expiryWarningDays = 7,
    this.lowStockWarning = 5,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.updatedBy,
    this.isSynced = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Factory constructor cho từng loại ngành
  factory ShopSettings.electronics(String shopId) {
    return ShopSettings(
      shopId: shopId,
      businessType: 'electronics',
      businessTypeName: 'Điện thoại & Điện tử',
      enableRepair: true,
      enableExpiry: false,
      enableVariants: false,
      enableSerial: true,
      enableWarranty: true,
      enableBatch: false,
      defaultUnit: 'cái',
    );
  }

  factory ShopSettings.food(String shopId) {
    return ShopSettings(
      shopId: shopId,
      businessType: 'food',
      businessTypeName: 'Thực phẩm & Đồ tươi sống',
      enableRepair: false,
      enableExpiry: true,
      enableVariants: false,
      enableSerial: false,
      enableWarranty: false,
      enableBatch: true,
      defaultUnit: 'kg',
      expiryWarningDays: 7,
    );
  }

  factory ShopSettings.fashion(String shopId) {
    return ShopSettings(
      shopId: shopId,
      businessType: 'fashion',
      businessTypeName: 'Thời trang & May mặc',
      enableRepair: false,
      enableExpiry: false,
      enableVariants: true,
      enableSerial: false,
      enableWarranty: false,
      enableBatch: false,
      defaultUnit: 'cái',
    );
  }

  factory ShopSettings.general(String shopId) {
    return ShopSettings(
      shopId: shopId,
      businessType: 'general',
      businessTypeName: 'Tổng hợp',
      enableRepair: false,
      enableExpiry: false,
      enableVariants: false,
      enableSerial: false,
      enableWarranty: false,
      enableBatch: false,
      defaultUnit: 'cái',
    );
  }

  /// Tạo từ Map (Firestore hoặc SQLite)
  factory ShopSettings.fromMap(Map<String, dynamic> map) {
    return ShopSettings(
      id: (map['id'] ?? '').toString(),
      firestoreId: (map['firestoreId'] ?? map['id'] ?? '').toString(),
      shopId: map['shopId'] ?? '',
      businessType: map['businessType'] ?? 'electronics',
      businessTypeName: map['businessTypeName'] ?? 'Điện thoại & Điện tử',
      enableRepair: map['enableRepair'] == true || map['enableRepair'] == 1,
      enableExpiry: map['enableExpiry'] == true || map['enableExpiry'] == 1,
      enableVariants: map['enableVariants'] == true || map['enableVariants'] == 1,
      enableSerial: map['enableSerial'] == true || map['enableSerial'] == 1,
      enableWarranty: map['enableWarranty'] == true || map['enableWarranty'] == 1,
      enableBatch: map['enableBatch'] == true || map['enableBatch'] == 1,
      defaultUnit: map['defaultUnit'] ?? 'cái',
      expiryWarningDays: (map['expiryWarningDays'] ?? 7).toInt(),
      lowStockWarning: (map['lowStockWarning'] ?? 5).toInt(),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      updatedBy: map['updatedBy'],
      isSynced: map['isSynced'] == true || map['isSynced'] == 1,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Chuyển sang Map cho Firestore
  Map<String, dynamic> toFirestoreMap() {
    return {
      'shopId': shopId,
      'businessType': businessType,
      'businessTypeName': businessTypeName,
      'enableRepair': enableRepair,
      'enableExpiry': enableExpiry,
      'enableVariants': enableVariants,
      'enableSerial': enableSerial,
      'enableWarranty': enableWarranty,
      'enableBatch': enableBatch,
      'defaultUnit': defaultUnit,
      'expiryWarningDays': expiryWarningDays,
      'lowStockWarning': lowStockWarning,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  /// Chuyển sang Map cho SQLite
  Map<String, dynamic> toMap() {
    return {
      'firestoreId': firestoreId.isNotEmpty ? firestoreId : 'settings_$shopId',
      'shopId': shopId,
      'businessType': businessType,
      'businessTypeName': businessTypeName,
      'enableRepair': enableRepair ? 1 : 0,
      'enableExpiry': enableExpiry ? 1 : 0,
      'enableVariants': enableVariants ? 1 : 0,
      'enableSerial': enableSerial ? 1 : 0,
      'enableWarranty': enableWarranty ? 1 : 0,
      'enableBatch': enableBatch ? 1 : 0,
      'defaultUnit': defaultUnit,
      'expiryWarningDays': expiryWarningDays,
      'lowStockWarning': lowStockWarning,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'updatedBy': updatedBy,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  /// Copy with để update
  ShopSettings copyWith({
    String? id,
    String? firestoreId,
    String? shopId,
    String? businessType,
    String? businessTypeName,
    bool? enableRepair,
    bool? enableExpiry,
    bool? enableVariants,
    bool? enableSerial,
    bool? enableWarranty,
    bool? enableBatch,
    String? defaultUnit,
    int? expiryWarningDays,
    int? lowStockWarning,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    bool? isSynced,
  }) {
    return ShopSettings(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      businessType: businessType ?? this.businessType,
      businessTypeName: businessTypeName ?? this.businessTypeName,
      enableRepair: enableRepair ?? this.enableRepair,
      enableExpiry: enableExpiry ?? this.enableExpiry,
      enableVariants: enableVariants ?? this.enableVariants,
      enableSerial: enableSerial ?? this.enableSerial,
      enableWarranty: enableWarranty ?? this.enableWarranty,
      enableBatch: enableBatch ?? this.enableBatch,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      expiryWarningDays: expiryWarningDays ?? this.expiryWarningDays,
      lowStockWarning: lowStockWarning ?? this.lowStockWarning,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      updatedBy: updatedBy ?? this.updatedBy,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Kiểm tra có phải ngành điện tử không
  bool get isElectronics => businessType == 'electronics';

  /// Kiểm tra có phải ngành thực phẩm không
  bool get isFood => businessType == 'food';

  /// Kiểm tra có phải ngành thời trang không
  bool get isFashion => businessType == 'fashion';

  /// Kiểm tra có phải ngành tổng hợp không
  bool get isGeneral => businessType == 'general';

  @override
  String toString() =>
      'ShopSettings(shopId: $shopId, businessType: $businessType)';
}

/// Enum các loại ngành kinh doanh
enum BusinessType {
  electronics('electronics', 'Điện thoại & Điện tử', '📱'),
  food('food', 'Thực phẩm & Đồ tươi sống', '🍎'),
  fashion('fashion', 'Thời trang & May mặc', '👕'),
  general('general', 'Tổng hợp', '📦');

  final String code;
  final String displayName;
  final String icon;

  const BusinessType(this.code, this.displayName, this.icon);

  static BusinessType fromCode(String code) {
    return BusinessType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => BusinessType.electronics,
    );
  }
}
