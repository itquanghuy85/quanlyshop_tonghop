/// Model cho mẫu tem sản phẩm
/// Hỗ trợ nhiều loại tem: kiểm kho, bán hàng, khuyến mãi, bảo hành, tùy chỉnh

class LabelTemplate {
  final String id;
  final String name;
  final LabelType type;
  final LabelSize size;
  final LabelFieldSettings fields;
  final ShopInfoSettings shopInfo;
  final List<String> customLines;
  final String? cpkFormula; // 'price + 500000' hoặc 'price * 1.05'
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LabelTemplate({
    required this.id,
    required this.name,
    required this.type,
    this.size = LabelSize.medium,
    required this.fields,
    required this.shopInfo,
    this.customLines = const [],
    this.cpkFormula,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'size': size.name,
      'fields': fields.toMap(),
      'shopInfo': shopInfo.toMap(),
      'customLines': customLines,
      'cpkFormula': cpkFormula,
      'isDefault': isDefault,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory LabelTemplate.fromMap(Map<String, dynamic> map) {
    return LabelTemplate(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: LabelType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => LabelType.sales,
      ),
      size: LabelSize.values.firstWhere(
        (e) => e.name == map['size'],
        orElse: () => LabelSize.medium,
      ),
      fields: LabelFieldSettings.fromMap(map['fields'] ?? {}),
      shopInfo: ShopInfoSettings.fromMap(map['shopInfo'] ?? {}),
      customLines: List<String>.from(map['customLines'] ?? []),
      cpkFormula: map['cpkFormula'],
      isDefault: map['isDefault'] ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
    );
  }

  LabelTemplate copyWith({
    String? id,
    String? name,
    LabelType? type,
    LabelSize? size,
    LabelFieldSettings? fields,
    ShopInfoSettings? shopInfo,
    List<String>? customLines,
    String? cpkFormula,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LabelTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      fields: fields ?? this.fields,
      shopInfo: shopInfo ?? this.shopInfo,
      customLines: customLines ?? this.customLines,
      cpkFormula: cpkFormula ?? this.cpkFormula,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Các mẫu tem mặc định
  static List<LabelTemplate> getDefaultTemplates() {
    return [
      // Mẫu Kiểm kho - Tối giản
      LabelTemplate(
        id: 'inventory',
        name: 'Kiểm kho',
        type: LabelType.inventory,
        size: LabelSize.small,
        fields: LabelFieldSettings(
          showProductName: true,
          showProductCode: true,
          showQrCode: true,
          showPriceKPK: false,
          showPriceCPK: false,
          showCondition: false,
          showWarranty: false,
          showImei: false,
          showStorage: false,
          showColor: false,
          showSupplier: false,
          showImportDate: false,
        ),
        shopInfo: ShopInfoSettings(
          showShopName: false,
          showHotline: false,
          showLogo: false,
          showSlogan: false,
        ),
        isDefault: true,
      ),

      // Mẫu Bán hàng - Đầy đủ thông tin giá
      LabelTemplate(
        id: 'sales',
        name: 'Bán hàng',
        type: LabelType.sales,
        size: LabelSize.medium,
        fields: LabelFieldSettings(
          showProductName: true,
          showProductCode: true,
          showQrCode: true,
          showPriceKPK: true,
          showPriceCPK: true,
          showCondition: true,
          showWarranty: true,
          showImei: false,
          showStorage: true,
          showColor: true,
          showSupplier: false,
          showImportDate: false,
        ),
        shopInfo: ShopInfoSettings(
          showShopName: true,
          showHotline: true,
          showLogo: false,
          showSlogan: true,
        ),
        cpkFormula: 'price + 500000',
        isDefault: true,
      ),

      // Mẫu Khuyến mãi - Highlight giảm giá
      LabelTemplate(
        id: 'promotion',
        name: 'Khuyến mãi',
        type: LabelType.promotion,
        size: LabelSize.large,
        fields: LabelFieldSettings(
          showProductName: true,
          showProductCode: true,
          showQrCode: true,
          showPriceKPK: true,
          showPriceCPK: true,
          showOriginalPrice: true,
          showDiscountPercent: true,
          showCondition: true,
          showWarranty: true,
          showImei: false,
          showStorage: true,
          showColor: true,
          showSupplier: false,
          showImportDate: false,
        ),
        shopInfo: ShopInfoSettings(
          showShopName: true,
          showHotline: true,
          showLogo: false,
          showSlogan: true,
        ),
        isDefault: true,
      ),

      // Mẫu Bảo hành - Dán sau khi bán
      LabelTemplate(
        id: 'warranty',
        name: 'Bảo hành',
        type: LabelType.warranty,
        size: LabelSize.small,
        fields: LabelFieldSettings(
          showProductName: true,
          showProductCode: true,
          showQrCode: true,
          showPriceKPK: false,
          showPriceCPK: false,
          showCondition: false,
          showWarranty: true,
          showWarrantyEndDate: true,
          showSaleDate: true,
          showImei: true,
          showStorage: false,
          showColor: false,
          showSupplier: false,
          showImportDate: false,
        ),
        shopInfo: ShopInfoSettings(
          showShopName: true,
          showHotline: true,
          showLogo: false,
          showSlogan: false,
        ),
        isDefault: true,
      ),
    ];
  }
}

/// Loại tem
enum LabelType {
  inventory, // Kiểm kho
  sales, // Bán hàng
  promotion, // Khuyến mãi
  warranty, // Bảo hành
  custom, // Tùy chỉnh
}

extension LabelTypeExtension on LabelType {
  String get displayName {
    switch (this) {
      case LabelType.inventory:
        return 'Kiểm kho';
      case LabelType.sales:
        return 'Bán hàng';
      case LabelType.promotion:
        return 'Khuyến mãi';
      case LabelType.warranty:
        return 'Bảo hành';
      case LabelType.custom:
        return 'Tùy chỉnh';
    }
  }

  String get icon {
    switch (this) {
      case LabelType.inventory:
        return '📦';
      case LabelType.sales:
        return '🏷️';
      case LabelType.promotion:
        return '🔥';
      case LabelType.warranty:
        return '🛡️';
      case LabelType.custom:
        return '✏️';
    }
  }
}

/// Kích thước tem
enum LabelSize {
  small, // 40x30mm - Tem nhỏ kiểm kho
  medium, // 50x40mm - Tem tiêu chuẩn
  large, // 60x50mm - Tem lớn có nhiều thông tin
  custom, // Tùy chỉnh
}

extension LabelSizeExtension on LabelSize {
  String get displayName {
    switch (this) {
      case LabelSize.small:
        return 'Nhỏ (40x30mm)';
      case LabelSize.medium:
        return 'Vừa (50x40mm)';
      case LabelSize.large:
        return 'Lớn (60x50mm)';
      case LabelSize.custom:
        return 'Tùy chỉnh';
    }
  }

  int get widthMm {
    switch (this) {
      case LabelSize.small:
        return 40;
      case LabelSize.medium:
        return 50;
      case LabelSize.large:
        return 60;
      case LabelSize.custom:
        return 50;
    }
  }

  int get heightMm {
    switch (this) {
      case LabelSize.small:
        return 30;
      case LabelSize.medium:
        return 40;
      case LabelSize.large:
        return 50;
      case LabelSize.custom:
        return 40;
    }
  }
}

/// Cài đặt các trường thông tin sản phẩm hiển thị
class LabelFieldSettings {
  final bool showProductName;
  final bool showProductCode;
  final bool showQrCode;
  final bool showPriceKPK;
  final bool showPriceCPK;
  final bool showOriginalPrice; // Giá gốc (gạch ngang)
  final bool showDiscountPercent; // % giảm giá
  final bool showCondition; // Tình trạng (mới/cũ/like new)
  final bool showWarranty; // Thời gian bảo hành
  final bool showWarrantyEndDate; // Ngày hết hạn BH
  final bool showSaleDate; // Ngày bán (cho tem BH)
  final bool showImei; // IMEI/Serial
  final bool showStorage; // Dung lượng
  final bool showColor; // Màu sắc
  final bool showSupplier; // Nhà cung cấp
  final bool showImportDate; // Ngày nhập

  const LabelFieldSettings({
    this.showProductName = true,
    this.showProductCode = true,
    this.showQrCode = true,
    this.showPriceKPK = true,
    this.showPriceCPK = true,
    this.showOriginalPrice = false,
    this.showDiscountPercent = false,
    this.showCondition = true,
    this.showWarranty = true,
    this.showWarrantyEndDate = false,
    this.showSaleDate = false,
    this.showImei = false,
    this.showStorage = true,
    this.showColor = true,
    this.showSupplier = false,
    this.showImportDate = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'showProductName': showProductName,
      'showProductCode': showProductCode,
      'showQrCode': showQrCode,
      'showPriceKPK': showPriceKPK,
      'showPriceCPK': showPriceCPK,
      'showOriginalPrice': showOriginalPrice,
      'showDiscountPercent': showDiscountPercent,
      'showCondition': showCondition,
      'showWarranty': showWarranty,
      'showWarrantyEndDate': showWarrantyEndDate,
      'showSaleDate': showSaleDate,
      'showImei': showImei,
      'showStorage': showStorage,
      'showColor': showColor,
      'showSupplier': showSupplier,
      'showImportDate': showImportDate,
    };
  }

  factory LabelFieldSettings.fromMap(Map<String, dynamic> map) {
    return LabelFieldSettings(
      showProductName: map['showProductName'] ?? true,
      showProductCode: map['showProductCode'] ?? true,
      showQrCode: map['showQrCode'] ?? true,
      showPriceKPK: map['showPriceKPK'] ?? true,
      showPriceCPK: map['showPriceCPK'] ?? true,
      showOriginalPrice: map['showOriginalPrice'] ?? false,
      showDiscountPercent: map['showDiscountPercent'] ?? false,
      showCondition: map['showCondition'] ?? true,
      showWarranty: map['showWarranty'] ?? true,
      showWarrantyEndDate: map['showWarrantyEndDate'] ?? false,
      showSaleDate: map['showSaleDate'] ?? false,
      showImei: map['showImei'] ?? false,
      showStorage: map['showStorage'] ?? true,
      showColor: map['showColor'] ?? true,
      showSupplier: map['showSupplier'] ?? false,
      showImportDate: map['showImportDate'] ?? false,
    );
  }

  LabelFieldSettings copyWith({
    bool? showProductName,
    bool? showProductCode,
    bool? showQrCode,
    bool? showPriceKPK,
    bool? showPriceCPK,
    bool? showOriginalPrice,
    bool? showDiscountPercent,
    bool? showCondition,
    bool? showWarranty,
    bool? showWarrantyEndDate,
    bool? showSaleDate,
    bool? showImei,
    bool? showStorage,
    bool? showColor,
    bool? showSupplier,
    bool? showImportDate,
  }) {
    return LabelFieldSettings(
      showProductName: showProductName ?? this.showProductName,
      showProductCode: showProductCode ?? this.showProductCode,
      showQrCode: showQrCode ?? this.showQrCode,
      showPriceKPK: showPriceKPK ?? this.showPriceKPK,
      showPriceCPK: showPriceCPK ?? this.showPriceCPK,
      showOriginalPrice: showOriginalPrice ?? this.showOriginalPrice,
      showDiscountPercent: showDiscountPercent ?? this.showDiscountPercent,
      showCondition: showCondition ?? this.showCondition,
      showWarranty: showWarranty ?? this.showWarranty,
      showWarrantyEndDate: showWarrantyEndDate ?? this.showWarrantyEndDate,
      showSaleDate: showSaleDate ?? this.showSaleDate,
      showImei: showImei ?? this.showImei,
      showStorage: showStorage ?? this.showStorage,
      showColor: showColor ?? this.showColor,
      showSupplier: showSupplier ?? this.showSupplier,
      showImportDate: showImportDate ?? this.showImportDate,
    );
  }
}

/// Cài đặt thông tin shop hiển thị
class ShopInfoSettings {
  final bool showShopName;
  final bool showHotline;
  final bool showLogo;
  final bool showSlogan;
  final bool showAddress;
  final String? customShopName;
  final String? customHotline;
  final String? customSlogan;
  final String? customAddress;

  const ShopInfoSettings({
    this.showShopName = true,
    this.showHotline = true,
    this.showLogo = false,
    this.showSlogan = false,
    this.showAddress = false,
    this.customShopName,
    this.customHotline,
    this.customSlogan,
    this.customAddress,
  });

  Map<String, dynamic> toMap() {
    return {
      'showShopName': showShopName,
      'showHotline': showHotline,
      'showLogo': showLogo,
      'showSlogan': showSlogan,
      'showAddress': showAddress,
      'customShopName': customShopName,
      'customHotline': customHotline,
      'customSlogan': customSlogan,
      'customAddress': customAddress,
    };
  }

  factory ShopInfoSettings.fromMap(Map<String, dynamic> map) {
    return ShopInfoSettings(
      showShopName: map['showShopName'] ?? true,
      showHotline: map['showHotline'] ?? true,
      showLogo: map['showLogo'] ?? false,
      showSlogan: map['showSlogan'] ?? false,
      showAddress: map['showAddress'] ?? false,
      customShopName: map['customShopName'],
      customHotline: map['customHotline'],
      customSlogan: map['customSlogan'],
      customAddress: map['customAddress'],
    );
  }

  ShopInfoSettings copyWith({
    bool? showShopName,
    bool? showHotline,
    bool? showLogo,
    bool? showSlogan,
    bool? showAddress,
    String? customShopName,
    String? customHotline,
    String? customSlogan,
    String? customAddress,
  }) {
    return ShopInfoSettings(
      showShopName: showShopName ?? this.showShopName,
      showHotline: showHotline ?? this.showHotline,
      showLogo: showLogo ?? this.showLogo,
      showSlogan: showSlogan ?? this.showSlogan,
      showAddress: showAddress ?? this.showAddress,
      customShopName: customShopName ?? this.customShopName,
      customHotline: customHotline ?? this.customHotline,
      customSlogan: customSlogan ?? this.customSlogan,
      customAddress: customAddress ?? this.customAddress,
    );
  }
}

/// Dữ liệu để in tem (kết hợp template + product data)
class LabelPrintData {
  final LabelTemplate template;
  final Map<String, dynamic> product;
  final int quantity;
  final List<String> additionalLines;
  final int? customPriceKPK;
  final int? customPriceCPK;
  final int? originalPrice; // Giá gốc trước KM
  final int? discountPercent;
  final DateTime? saleDate;
  final DateTime? warrantyEndDate;

  LabelPrintData({
    required this.template,
    required this.product,
    this.quantity = 1,
    this.additionalLines = const [],
    this.customPriceKPK,
    this.customPriceCPK,
    this.originalPrice,
    this.discountPercent,
    this.saleDate,
    this.warrantyEndDate,
  });

  /// Tính giá CPK dựa trên công thức
  int get calculatedCPK {
    if (customPriceCPK != null) return customPriceCPK!;

    final price = product['price'] as int? ?? 0;
    final formula = template.cpkFormula ?? 'price + 500000';

    if (formula.contains('*')) {
      // Công thức nhân: price * 1.05
      final multiplier =
          double.tryParse(formula.replaceAll('price', '').replaceAll('*', '').trim()) ?? 1.05;
      return (price * multiplier).round();
    } else {
      // Công thức cộng: price + 500000
      final addition =
          int.tryParse(formula.replaceAll('price', '').replaceAll('+', '').trim()) ?? 500000;
      return price + addition;
    }
  }

  /// Lấy giá KPK
  int get priceKPK => customPriceKPK ?? (product['price'] as int? ?? 0);
}
