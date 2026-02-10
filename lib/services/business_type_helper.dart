import 'package:flutter/foundation.dart';
import '../models/shop_settings_model.dart';
import 'category_service.dart';

/// Helper service để lọc UI theo loại kinh doanh
/// Cung cấp các method nhanh để check feature flags
class BusinessTypeHelper {
  static final BusinessTypeHelper _instance = BusinessTypeHelper._internal();
  static BusinessTypeHelper get instance => _instance;
  factory BusinessTypeHelper() => _instance;
  BusinessTypeHelper._internal();

  ShopSettings? _cachedSettings;
  DateTime? _lastFetchTime;
  static const _cacheExpiry = Duration(minutes: 5);

  /// Lấy settings đã cache hoặc fetch mới
  Future<ShopSettings> getSettings() async {
    // Check cache validity
    if (_cachedSettings != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheExpiry) {
        return _cachedSettings!;
      }
    }

    // Fetch fresh
    final settings = await CategoryService().getShopSettings();
    if (settings != null) {
      _cachedSettings = settings;
      _lastFetchTime = DateTime.now();
      return settings;
    }

    // Return default
    return ShopSettings.electronics('');
  }

  /// Clear cache (call when shop changes or settings update)
  void clearCache() {
    _cachedSettings = null;
    _lastFetchTime = null;
    debugPrint('BusinessTypeHelper: Cache cleared');
  }

  /// Lấy settings đồng bộ (chỉ dùng khi đã fetch trước đó)
  ShopSettings? get cachedSettings => _cachedSettings;

  // === QUICK ACCESS METHODS ===

  /// Lấy loại kinh doanh
  Future<String> getBusinessType() async {
    final settings = await getSettings();
    return settings.businessType;
  }

  /// Có phải electronics không (sửa chữa điện thoại)
  Future<bool> isElectronics() async {
    final settings = await getSettings();
    return settings.businessType == 'electronics';
  }

  /// Có phải food không (thực phẩm)
  Future<bool> isFood() async {
    final settings = await getSettings();
    return settings.businessType == 'food';
  }

  /// Có phải fashion không (thời trang)
  Future<bool> isFashion() async {
    final settings = await getSettings();
    return settings.businessType == 'fashion';
  }

  // === FEATURE FLAGS ===

  /// Bật module sửa chữa?
  Future<bool> isRepairEnabled() async {
    final settings = await getSettings();
    return settings.enableRepair;
  }

  /// Bật theo dõi HSD?
  Future<bool> isExpiryEnabled() async {
    final settings = await getSettings();
    return settings.enableExpiry;
  }

  /// Bật biến thể size/màu?
  Future<bool> isVariantsEnabled() async {
    final settings = await getSettings();
    return settings.enableVariants;
  }

  /// Bật theo dõi IMEI/Serial?
  Future<bool> isSerialEnabled() async {
    final settings = await getSettings();
    return settings.enableSerial;
  }

  /// Bật bảo hành?
  Future<bool> isWarrantyEnabled() async {
    final settings = await getSettings();
    return settings.enableWarranty;
  }

  /// Bật quản lý lô hàng?
  Future<bool> isBatchEnabled() async {
    final settings = await getSettings();
    return settings.enableBatch;
  }

  /// Lấy đơn vị mặc định
  Future<String> getDefaultUnit() async {
    final settings = await getSettings();
    return settings.defaultUnit;
  }

  /// Lấy tên loại kinh doanh hiển thị
  Future<String> getBusinessTypeName() async {
    final settings = await getSettings();
    return settings.businessTypeName;
  }

  // === VISIBILITY HELPERS ===

  /// Hiển thị tab/menu sửa chữa?
  Future<bool> shouldShowRepair() async {
    return await isRepairEnabled();
  }

  /// Hiển thị tab bảo hành?
  Future<bool> shouldShowWarranty() async {
    return await isWarrantyEnabled();
  }

  /// Hiển thị quản lý HSD?
  Future<bool> shouldShowExpiry() async {
    return await isExpiryEnabled();
  }

  /// Hiển thị biến thể?
  Future<bool> shouldShowVariants() async {
    return await isVariantsEnabled();
  }

  /// Hiển thị trường IMEI trong form?
  Future<bool> shouldShowSerialField() async {
    return await isSerialEnabled();
  }

  /// Hiển thị trường warranty trong form?
  Future<bool> shouldShowWarrantyField() async {
    return await isWarrantyEnabled();
  }

  /// Hiển thị trường HSD trong form?
  Future<bool> shouldShowExpiryField() async {
    return await isExpiryEnabled();
  }

  /// Hiển thị chọn size/màu trong form?
  Future<bool> shouldShowVariantFields() async {
    return await isVariantsEnabled();
  }

  /// Hiển thị đối tác sửa chữa?
  Future<bool> shouldShowRepairPartners() async {
    return await isRepairEnabled();
  }

  // === TERMINOLOGY - Labels động theo ngành ===

  /// Class chứa tất cả labels cho một ngành
  BusinessTerminology getTerminology([ShopSettings? settings]) {
    final type = settings?.businessType ?? _cachedSettings?.businessType ?? 'electronics';
    return BusinessTerminology.forType(type);
  }

  /// Lấy terminology async (fetch settings nếu chưa có)
  Future<BusinessTerminology> getTerminologyAsync() async {
    final settings = await getSettings();
    return BusinessTerminology.forType(settings.businessType);
  }
}

/// Class chứa terminology cho từng ngành kinh doanh
/// Giúp app hiển thị như được thiết kế riêng cho ngành đó
class BusinessTerminology {
  // === PRODUCT ===
  final String productLabel; // "Sản phẩm" / "Điện thoại" / "Món ăn" / "Quần áo"
  final String productPlural; // "Sản phẩm" / "Điện thoại" / "Món" / "Sản phẩm"
  final String productIcon; // Emoji icon
  final String addProduct; // "Thêm sản phẩm" / "Thêm điện thoại"
  final String productCode; // "Mã SP" / "IMEI" / "Mã món"
  final String productCodeHint; // "Nhập mã sản phẩm" / "Nhập IMEI"

  // === INVENTORY ===
  final String inventoryLabel; // "Kho hàng" / "Kho điện thoại"
  final String stockIn; // "Nhập kho" / "Nhập máy"
  final String stockOut; // "Xuất kho"
  final String lowStock; // "Sắp hết" / "Còn ít"
  final String outOfStock; // "Hết hàng" / "Hết máy"

  // === SALE ===
  final String saleLabel; // "Bán hàng" / "Bán máy"
  final String saleOrder; // "Đơn bán" / "Đơn bán máy"
  final String customer; // "Khách hàng"
  final String sellAction; // "Bán" / "Bán máy"
  final String priceLabel; // "Giá bán"
  final String costLabel; // "Giá nhập" / "Giá vốn"

  // === CATEGORY ===
  final String category1; // "Điện thoại" / "Thực phẩm" / "Áo"
  final String category2; // "Phụ kiện" / "Đồ uống" / "Quần"
  final String category3; // "Linh kiện" / "Nguyên liệu" / "Phụ kiện"

  // === QUICK ACCESS ===
  final String quickSale; // "Bán nhanh" / "Bán ngay"
  final String quickStock; // "Nhập nhanh"

  // === DASHBOARD ===
  final String todaySales; // "Doanh số hôm nay"
  final String todayOrders; // "Đơn hôm nay" / "Máy bán hôm nay"
  final String pendingOrders; // "Đang chờ" / "Máy chờ giao"

  // === REPAIR (chỉ electronics) ===
  final String repairLabel; // "Sửa chữa"
  final String repairOrder; // "Đơn sửa"
  final String repairPartner; // "Đối tác sửa"

  // === SPECIAL FIELDS ===
  final String specialField1Label; // "IMEI" / "HSD" / "Size"
  final String specialField1Hint; // "Nhập IMEI" / "Chọn HSD" / "Chọn size"
  final String specialField2Label; // "Bảo hành" / "Số lô" / "Màu"
  final String specialField2Hint;

  // === UNITS ===
  final String defaultUnit; // "cái" / "kg" / "cái"
  final List<String> suggestedUnits; // ["cái", "chiếc"] / ["kg", "g", "hộp"]

  // === APP BRANDING ===
  final String appSubtitle; // "Quản lý cửa hàng điện thoại"
  final String welcomeMessage; // "Chào mừng đến cửa hàng điện thoại"

  const BusinessTerminology({
    required this.productLabel,
    required this.productPlural,
    required this.productIcon,
    required this.addProduct,
    required this.productCode,
    required this.productCodeHint,
    required this.inventoryLabel,
    required this.stockIn,
    required this.stockOut,
    required this.lowStock,
    required this.outOfStock,
    required this.saleLabel,
    required this.saleOrder,
    required this.customer,
    required this.sellAction,
    required this.priceLabel,
    required this.costLabel,
    required this.category1,
    required this.category2,
    required this.category3,
    required this.quickSale,
    required this.quickStock,
    required this.todaySales,
    required this.todayOrders,
    required this.pendingOrders,
    required this.repairLabel,
    required this.repairOrder,
    required this.repairPartner,
    required this.specialField1Label,
    required this.specialField1Hint,
    required this.specialField2Label,
    required this.specialField2Hint,
    required this.defaultUnit,
    required this.suggestedUnits,
    required this.appSubtitle,
    required this.welcomeMessage,
  });

  /// Factory để tạo terminology theo loại ngành
  factory BusinessTerminology.forType(String businessType) {
    switch (businessType) {
      case 'electronics':
        return const BusinessTerminology(
          productLabel: 'Điện thoại',
          productPlural: 'Điện thoại',
          productIcon: '📱',
          addProduct: 'Thêm điện thoại',
          productCode: 'IMEI',
          productCodeHint: 'Nhập số IMEI 15 chữ số',
          inventoryLabel: 'Kho máy',
          stockIn: 'Nhập máy',
          stockOut: 'Xuất máy',
          lowStock: 'Sắp hết',
          outOfStock: 'Hết máy',
          saleLabel: 'Bán máy',
          saleOrder: 'Đơn bán máy',
          customer: 'Khách hàng',
          sellAction: 'Bán máy',
          priceLabel: 'Giá bán',
          costLabel: 'Giá nhập',
          category1: 'Điện thoại',
          category2: 'Phụ kiện',
          category3: 'Linh kiện',
          quickSale: 'Bán nhanh',
          quickStock: 'Nhập nhanh',
          todaySales: 'Doanh số hôm nay',
          todayOrders: 'Máy bán hôm nay',
          pendingOrders: 'Đơn chờ xử lý',
          repairLabel: 'Sửa chữa',
          repairOrder: 'Đơn sửa',
          repairPartner: 'Đối tác sửa chữa',
          specialField1Label: 'IMEI/Serial',
          specialField1Hint: 'Nhập IMEI hoặc Serial Number',
          specialField2Label: 'Bảo hành',
          specialField2Hint: 'Chọn thời hạn bảo hành',
          defaultUnit: 'cái',
          suggestedUnits: ['cái', 'chiếc', 'bộ'],
          appSubtitle: 'Quản lý cửa hàng điện thoại',
          welcomeMessage: 'Chào mừng đến cửa hàng điện thoại của bạn',
        );

      case 'food':
        return const BusinessTerminology(
          productLabel: 'Món hàng',
          productPlural: 'Món hàng',
          productIcon: '🍜',
          addProduct: 'Thêm món',
          productCode: 'Mã món',
          productCodeHint: 'Nhập mã món hoặc barcode',
          inventoryLabel: 'Kho hàng',
          stockIn: 'Nhập hàng',
          stockOut: 'Xuất hàng',
          lowStock: 'Sắp hết',
          outOfStock: 'Hết hàng',
          saleLabel: 'Bán hàng',
          saleOrder: 'Đơn bán',
          customer: 'Khách hàng',
          sellAction: 'Bán',
          priceLabel: 'Giá bán',
          costLabel: 'Giá vốn',
          category1: 'Thực phẩm',
          category2: 'Đồ uống',
          category3: 'Nguyên liệu',
          quickSale: 'Bán nhanh',
          quickStock: 'Nhập nhanh',
          todaySales: 'Doanh số hôm nay',
          todayOrders: 'Đơn bán hôm nay',
          pendingOrders: 'Đơn chờ xử lý',
          repairLabel: 'Chế biến',
          repairOrder: 'Đơn chế biến',
          repairPartner: 'Nhà cung cấp',
          specialField1Label: 'Hạn sử dụng',
          specialField1Hint: 'Chọn ngày hết hạn',
          specialField2Label: 'Số lô',
          specialField2Hint: 'Nhập số lô sản xuất',
          defaultUnit: 'kg',
          suggestedUnits: ['kg', 'g', 'lít', 'ml', 'hộp', 'chai', 'gói', 'túi'],
          appSubtitle: 'Quản lý cửa hàng thực phẩm',
          welcomeMessage: 'Chào mừng đến cửa hàng thực phẩm của bạn',
        );

      case 'fashion':
        return const BusinessTerminology(
          productLabel: 'Sản phẩm',
          productPlural: 'Sản phẩm',
          productIcon: '👕',
          addProduct: 'Thêm sản phẩm',
          productCode: 'Mã SP',
          productCodeHint: 'Nhập mã sản phẩm hoặc barcode',
          inventoryLabel: 'Kho hàng',
          stockIn: 'Nhập hàng',
          stockOut: 'Xuất hàng',
          lowStock: 'Sắp hết size',
          outOfStock: 'Hết hàng',
          saleLabel: 'Bán hàng',
          saleOrder: 'Đơn bán',
          customer: 'Khách hàng',
          sellAction: 'Bán',
          priceLabel: 'Giá bán',
          costLabel: 'Giá vốn',
          category1: 'Áo',
          category2: 'Quần',
          category3: 'Phụ kiện',
          quickSale: 'Bán nhanh',
          quickStock: 'Nhập nhanh',
          todaySales: 'Doanh số hôm nay',
          todayOrders: 'Đơn bán hôm nay',
          pendingOrders: 'Đơn chờ giao',
          repairLabel: 'Sửa đổ',
          repairOrder: 'Đơn sửa',
          repairPartner: 'Thợ may',
          specialField1Label: 'Size',
          specialField1Hint: 'Chọn size (S, M, L, XL...)',
          specialField2Label: 'Màu sắc',
          specialField2Hint: 'Chọn màu sản phẩm',
          defaultUnit: 'cái',
          suggestedUnits: ['cái', 'bộ', 'đôi', 'chiếc'],
          appSubtitle: 'Quản lý cửa hàng thời trang',
          welcomeMessage: 'Chào mừng đến cửa hàng thời trang của bạn',
        );

      case 'general':
      default:
        return const BusinessTerminology(
          productLabel: 'Sản phẩm',
          productPlural: 'Sản phẩm',
          productIcon: '📦',
          addProduct: 'Thêm sản phẩm',
          productCode: 'Mã SP',
          productCodeHint: 'Nhập mã sản phẩm',
          inventoryLabel: 'Kho hàng',
          stockIn: 'Nhập kho',
          stockOut: 'Xuất kho',
          lowStock: 'Sắp hết',
          outOfStock: 'Hết hàng',
          saleLabel: 'Bán hàng',
          saleOrder: 'Đơn bán',
          customer: 'Khách hàng',
          sellAction: 'Bán',
          priceLabel: 'Giá bán',
          costLabel: 'Giá vốn',
          category1: 'Sản phẩm A',
          category2: 'Sản phẩm B',
          category3: 'Dịch vụ',
          quickSale: 'Bán nhanh',
          quickStock: 'Nhập nhanh',
          todaySales: 'Doanh số hôm nay',
          todayOrders: 'Đơn bán hôm nay',
          pendingOrders: 'Đơn chờ xử lý',
          repairLabel: 'Dịch vụ',
          repairOrder: 'Đơn dịch vụ',
          repairPartner: 'Đối tác',
          specialField1Label: 'Mã vạch',
          specialField1Hint: 'Quét hoặc nhập mã vạch',
          specialField2Label: 'Ghi chú',
          specialField2Hint: 'Nhập ghi chú sản phẩm',
          defaultUnit: 'cái',
          suggestedUnits: ['cái', 'hộp', 'thùng', 'kg', 'lít'],
          appSubtitle: 'Quản lý cửa hàng',
          welcomeMessage: 'Chào mừng đến cửa hàng của bạn',
        );
    }
  }
}
