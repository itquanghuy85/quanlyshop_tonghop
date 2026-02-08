/// Model danh mục sản phẩm - thay thế hardcoded product types
/// Hỗ trợ cây danh mục (parent-child) và custom fields theo ngành
class ProductCategory {
  final String id;
  final String firestoreId;
  final String shopId;

  // === THÔNG TIN CƠ BẢN ===
  final String name;
  final String? description;
  final String? icon; // Icon emoji hoặc tên icon
  final String? color; // Màu HEX cho UI

  // === CẤU TRÚC CÂY ===
  final String? parentId; // null = root category
  final int sortOrder; // Thứ tự sắp xếp

  // === CẤU HÌNH THEO NGÀNH ===
  /// Sản phẩm trong danh mục này có HSD không
  final bool trackExpiry;

  /// Sản phẩm trong danh mục này có IMEI/Serial không
  final bool trackSerial;

  /// Sản phẩm trong danh mục này có biến thể (size/màu) không
  final bool hasVariants;

  /// Sản phẩm trong danh mục này có bảo hành không
  final bool hasWarranty;

  /// Số ngày bảo hành mặc định (nếu hasWarranty = true)
  final int defaultWarrantyDays;

  /// Các trường tùy chỉnh cho sản phẩm trong danh mục
  /// VD: {"screen_size": "Kích thước màn hình", "ram": "RAM"}
  final Map<String, String> customFields;

  // === METADATA ===
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? updatedBy;
  final bool isSynced;

  ProductCategory({
    this.id = '',
    this.firestoreId = '',
    required this.shopId,
    required this.name,
    this.description,
    this.icon,
    this.color,
    this.parentId,
    this.sortOrder = 0,
    this.trackExpiry = false,
    this.trackSerial = false,
    this.hasVariants = false,
    this.hasWarranty = false,
    this.defaultWarrantyDays = 0,
    this.customFields = const {},
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.updatedBy,
    this.isSynced = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Factory cho danh mục điện thoại mặc định
  factory ProductCategory.defaultPhoneCategory(String shopId) {
    return ProductCategory(
      shopId: shopId,
      name: 'Điện thoại',
      icon: '📱',
      trackSerial: true,
      hasWarranty: true,
      defaultWarrantyDays: 365,
      customFields: {
        'imei': 'IMEI',
        'color': 'Màu sắc',
        'storage': 'Bộ nhớ',
      },
    );
  }

  /// Factory cho danh mục phụ kiện mặc định
  factory ProductCategory.defaultAccessoryCategory(String shopId) {
    return ProductCategory(
      shopId: shopId,
      name: 'Phụ kiện',
      icon: '🎧',
      trackSerial: false,
      hasWarranty: true,
      defaultWarrantyDays: 30,
    );
  }

  /// Factory cho danh mục linh kiện mặc định
  factory ProductCategory.defaultPartCategory(String shopId) {
    return ProductCategory(
      shopId: shopId,
      name: 'Linh kiện',
      icon: '🔧',
      trackSerial: false,
      hasWarranty: false,
    );
  }

  /// Factory cho danh mục thực phẩm
  factory ProductCategory.foodCategory(String shopId, String name) {
    return ProductCategory(
      shopId: shopId,
      name: name,
      icon: '🍎',
      trackExpiry: true,
      trackSerial: false,
      hasVariants: false,
    );
  }

  /// Factory cho danh mục thời trang
  factory ProductCategory.fashionCategory(String shopId, String name) {
    return ProductCategory(
      shopId: shopId,
      name: name,
      icon: '👕',
      trackExpiry: false,
      trackSerial: false,
      hasVariants: true,
      customFields: {
        'size': 'Kích cỡ',
        'color': 'Màu sắc',
        'material': 'Chất liệu',
      },
    );
  }

  /// Tạo từ Map (Firestore hoặc SQLite)
  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    // Parse customFields
    Map<String, String> customFields = {};
    if (map['customFields'] != null) {
      if (map['customFields'] is String) {
        try {
          final decoded = map['customFields'] as String;
          // Simple JSON parsing for SQLite
          if (decoded.isNotEmpty && decoded != '{}') {
            // Parse JSON string manually to avoid import
            final withoutBraces = decoded.substring(1, decoded.length - 1);
            if (withoutBraces.isNotEmpty) {
              final pairs = withoutBraces.split(',');
              for (final pair in pairs) {
                final parts = pair.split(':');
                if (parts.length >= 2) {
                  final key = parts[0].trim().replaceAll('"', '');
                  final value = parts.sublist(1).join(':').trim().replaceAll('"', '');
                  customFields[key] = value;
                }
              }
            }
          }
        } catch (_) {}
      } else if (map['customFields'] is Map) {
        customFields = Map<String, String>.from(
          (map['customFields'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
    }

    return ProductCategory(
      id: (map['id'] ?? '').toString(),
      firestoreId: (map['firestoreId'] ?? map['id'] ?? '').toString(),
      shopId: map['shopId'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      icon: map['icon'],
      color: map['color'],
      parentId: map['parentId'],
      sortOrder: (map['sortOrder'] ?? 0).toInt(),
      trackExpiry: map['trackExpiry'] == true || map['trackExpiry'] == 1,
      trackSerial: map['trackSerial'] == true || map['trackSerial'] == 1,
      hasVariants: map['hasVariants'] == true || map['hasVariants'] == 1,
      hasWarranty: map['hasWarranty'] == true || map['hasWarranty'] == 1,
      defaultWarrantyDays: (map['defaultWarrantyDays'] ?? 0).toInt(),
      customFields: customFields,
      isActive: map['isActive'] != false && map['isActive'] != 0,
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
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
      'parentId': parentId,
      'sortOrder': sortOrder,
      'trackExpiry': trackExpiry,
      'trackSerial': trackSerial,
      'hasVariants': hasVariants,
      'hasWarranty': hasWarranty,
      'defaultWarrantyDays': defaultWarrantyDays,
      'customFields': customFields,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  /// Chuyển sang Map cho SQLite
  Map<String, dynamic> toMap() {
    // Convert customFields to JSON string for SQLite
    String customFieldsJson = '{}';
    if (customFields.isNotEmpty) {
      final pairs = customFields.entries.map((e) => '"${e.key}":"${e.value}"');
      customFieldsJson = '{${pairs.join(',')}}';
    }

    return {
      'firestoreId': firestoreId.isNotEmpty ? firestoreId : null,
      'shopId': shopId,
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
      'parentId': parentId,
      'sortOrder': sortOrder,
      'trackExpiry': trackExpiry ? 1 : 0,
      'trackSerial': trackSerial ? 1 : 0,
      'hasVariants': hasVariants ? 1 : 0,
      'hasWarranty': hasWarranty ? 1 : 0,
      'defaultWarrantyDays': defaultWarrantyDays,
      'customFields': customFieldsJson,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'updatedBy': updatedBy,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  /// Copy with để update
  ProductCategory copyWith({
    String? id,
    String? firestoreId,
    String? shopId,
    String? name,
    String? description,
    String? icon,
    String? color,
    String? parentId,
    int? sortOrder,
    bool? trackExpiry,
    bool? trackSerial,
    bool? hasVariants,
    bool? hasWarranty,
    int? defaultWarrantyDays,
    Map<String, String>? customFields,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    bool? isSynced,
  }) {
    return ProductCategory(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      parentId: parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      trackExpiry: trackExpiry ?? this.trackExpiry,
      trackSerial: trackSerial ?? this.trackSerial,
      hasVariants: hasVariants ?? this.hasVariants,
      hasWarranty: hasWarranty ?? this.hasWarranty,
      defaultWarrantyDays: defaultWarrantyDays ?? this.defaultWarrantyDays,
      customFields: customFields ?? Map.from(this.customFields),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      updatedBy: updatedBy ?? this.updatedBy,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Kiểm tra có phải danh mục gốc không
  bool get isRoot => parentId == null || parentId!.isEmpty;

  @override
  String toString() => 'ProductCategory(id: $firestoreId, name: $name)';
}
