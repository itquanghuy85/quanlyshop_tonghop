/// Script tạo dữ liệu test cho Multi-Industry Expansion Phase 1
/// Chạy file này để tạo dữ liệu mẫu cho 4 loại ngành: Điện tử, Thực phẩm, Thời trang, Tổng hợp
///
/// Cách sử dụng: Import file này và gọi hàm generateAllTestData(shopId)

import 'package:quanlyshop/models/shop_settings_model.dart';
import 'package:quanlyshop/models/product_category_model.dart';
import 'package:quanlyshop/models/product_variant_model.dart';
import 'package:quanlyshop/models/product_model.dart';

/// Class chứa tất cả dữ liệu test
class MultiIndustryTestData {
  /// Tạo ShopSettings mẫu cho tất cả loại ngành
  static Map<String, ShopSettings> generateShopSettings() {
    return {
      'electronics': ShopSettings.electronics('test_shop_electronics'),
      'food': ShopSettings.food('test_shop_food'),
      'fashion': ShopSettings.fashion('test_shop_fashion'),
      'general': ShopSettings.general('test_shop_general'),
    };
  }

  /// Tạo danh mục sản phẩm mẫu cho ngành Điện tử
  static List<ProductCategory> generateElectronicsCategories(String shopId) {
    return [
      ProductCategory(
        firestoreId: 'cat_electronics_phone',
        shopId: shopId,
        name: 'Điện thoại',
        icon: '📱',
        sortOrder: 1,
        trackSerial: true,
        hasWarranty: true,
        defaultWarrantyDays: 365,
        customFields: {'imei': 'IMEI', 'color': 'Màu sắc', 'storage': 'Bộ nhớ'},
      ),
      ProductCategory(
        firestoreId: 'cat_electronics_tablet',
        shopId: shopId,
        name: 'Máy tính bảng',
        icon: '📲',
        sortOrder: 2,
        trackSerial: true,
        hasWarranty: true,
        defaultWarrantyDays: 365,
        customFields: {'imei': 'IMEI', 'screen_size': 'Kích thước màn hình'},
      ),
      ProductCategory(
        firestoreId: 'cat_electronics_accessory',
        shopId: shopId,
        name: 'Phụ kiện',
        icon: '🎧',
        sortOrder: 3,
        trackSerial: false,
        hasWarranty: true,
        defaultWarrantyDays: 30,
      ),
      ProductCategory(
        firestoreId: 'cat_electronics_part',
        shopId: shopId,
        name: 'Linh kiện',
        icon: '🔧',
        sortOrder: 4,
        trackSerial: false,
        hasWarranty: false,
      ),
      ProductCategory(
        firestoreId: 'cat_electronics_laptop',
        shopId: shopId,
        name: 'Laptop',
        icon: '💻',
        sortOrder: 5,
        trackSerial: true,
        hasWarranty: true,
        defaultWarrantyDays: 730,
        customFields: {'serial': 'Serial Number', 'cpu': 'CPU', 'ram': 'RAM', 'ssd': 'SSD'},
      ),
    ];
  }

  /// Tạo sản phẩm mẫu cho ngành Điện tử
  static List<Product> generateElectronicsProducts(String shopId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      Product(
        firestoreId: 'prod_elec_001',
        shopId: shopId,
        name: 'iPhone 15 Pro Max 256GB',
        brand: 'Apple',
        model: 'iPhone 15 Pro Max',
        imei: '353456789012345',
        cost: 28000000,
        price: 32000000,
        condition: 'Mới 100%',
        status: 1,
        quantity: 5,
        color: 'Titan Đen',
        capacity: '256GB',
        categoryId: 'cat_electronics_phone',
        unit: 'cái',
        createdAt: now,
        customData: '{"screen_size":"6.7 inch","ram":"8GB","chip":"A17 Pro"}',
      ),
      Product(
        firestoreId: 'prod_elec_002',
        shopId: shopId,
        name: 'Samsung Galaxy S24 Ultra 512GB',
        brand: 'Samsung',
        model: 'Galaxy S24 Ultra',
        imei: '352109876543210',
        cost: 25000000,
        price: 29000000,
        condition: 'Mới 100%',
        status: 1,
        quantity: 8,
        color: 'Titan Gray',
        capacity: '512GB',
        categoryId: 'cat_electronics_phone',
        unit: 'cái',
        createdAt: now,
        customData: '{"screen_size":"6.8 inch","ram":"12GB","chip":"Snapdragon 8 Gen 3"}',
      ),
      Product(
        firestoreId: 'prod_elec_003',
        shopId: shopId,
        name: 'Tai nghe AirPods Pro 2',
        brand: 'Apple',
        cost: 4500000,
        price: 5500000,
        condition: 'Mới 100%',
        status: 1,
        quantity: 15,
        categoryId: 'cat_electronics_accessory',
        unit: 'cái',
        createdAt: now,
      ),
      Product(
        firestoreId: 'prod_elec_004',
        shopId: shopId,
        name: 'Màn hình iPhone 14 Pro',
        brand: 'Foxconn',
        cost: 2500000,
        price: 3200000,
        condition: 'Mới',
        status: 1,
        quantity: 20,
        categoryId: 'cat_electronics_part',
        unit: 'cái',
        createdAt: now,
      ),
      Product(
        firestoreId: 'prod_elec_005',
        shopId: shopId,
        name: 'iPad Pro M2 12.9 inch 256GB',
        brand: 'Apple',
        model: 'iPad Pro M2',
        imei: '354321098765432',
        cost: 22000000,
        price: 26000000,
        condition: 'Mới 100%',
        status: 1,
        quantity: 3,
        color: 'Space Gray',
        capacity: '256GB',
        categoryId: 'cat_electronics_tablet',
        unit: 'cái',
        createdAt: now,
      ),
    ];
  }

  /// Tạo danh mục sản phẩm mẫu cho ngành Thực phẩm
  static List<ProductCategory> generateFoodCategories(String shopId) {
    return [
      ProductCategory(
        firestoreId: 'cat_food_dairy',
        shopId: shopId,
        name: 'Sữa & Sản phẩm từ sữa',
        icon: '🥛',
        sortOrder: 1,
        trackExpiry: true,
        trackSerial: false,
        hasVariants: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_meat',
        shopId: shopId,
        name: 'Thịt & Hải sản',
        icon: '🥩',
        sortOrder: 2,
        trackExpiry: true,
        trackSerial: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_vegetable',
        shopId: shopId,
        name: 'Rau củ quả',
        icon: '🥬',
        sortOrder: 3,
        trackExpiry: true,
        trackSerial: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_fruit',
        shopId: shopId,
        name: 'Trái cây tươi',
        icon: '🍎',
        sortOrder: 4,
        trackExpiry: true,
        trackSerial: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_dry',
        shopId: shopId,
        name: 'Đồ khô & Gia vị',
        icon: '🌾',
        sortOrder: 5,
        trackExpiry: true,
        trackSerial: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_beverage',
        shopId: shopId,
        name: 'Đồ uống',
        icon: '🍹',
        sortOrder: 6,
        trackExpiry: true,
        trackSerial: false,
      ),
      ProductCategory(
        firestoreId: 'cat_food_frozen',
        shopId: shopId,
        name: 'Thực phẩm đông lạnh',
        icon: '🧊',
        sortOrder: 7,
        trackExpiry: true,
        trackSerial: false,
      ),
    ];
  }

  /// Tạo sản phẩm mẫu cho ngành Thực phẩm
  static List<Product> generateFoodProducts(String shopId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final threeDays = DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch;
    final oneWeek = DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
    final twoWeeks = DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch;
    final oneMonth = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
    final sixMonths = DateTime.now().add(const Duration(days: 180)).millisecondsSinceEpoch;
    final expired = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;

    return [
      // Sản phẩm đã hết hạn - để test cảnh báo
      Product(
        firestoreId: 'prod_food_001',
        shopId: shopId,
        name: 'Sữa TH True Milk 1L',
        brand: 'TH True Milk',
        cost: 28000,
        price: 35000,
        quantity: 10,
        categoryId: 'cat_food_dairy',
        unit: 'hộp',
        expiryDate: expired,
        batchNumber: 'LOT-2026-01-001',
        createdAt: now,
      ),
      // Sản phẩm sắp hết hạn (3 ngày)
      Product(
        firestoreId: 'prod_food_002',
        shopId: shopId,
        name: 'Sữa chua Vinamilk 100g',
        brand: 'Vinamilk',
        cost: 5000,
        price: 7000,
        quantity: 50,
        categoryId: 'cat_food_dairy',
        unit: 'hộp',
        expiryDate: threeDays,
        batchNumber: 'LOT-2026-02-005',
        createdAt: now,
      ),
      // Sản phẩm sắp hết hạn (1 tuần)
      Product(
        firestoreId: 'prod_food_003',
        shopId: shopId,
        name: 'Thịt bò Úc',
        brand: 'Australian Beef',
        cost: 280000,
        price: 350000,
        quantity: 5,
        categoryId: 'cat_food_meat',
        unit: 'kg',
        expiryDate: oneWeek,
        batchNumber: 'LOT-2026-02-010',
        createdAt: now,
      ),
      // Sản phẩm còn hạn 2 tuần
      Product(
        firestoreId: 'prod_food_004',
        shopId: shopId,
        name: 'Cá hồi Na Uy',
        brand: 'Norway Salmon',
        cost: 350000,
        price: 450000,
        quantity: 8,
        categoryId: 'cat_food_meat',
        unit: 'kg',
        expiryDate: twoWeeks,
        batchNumber: 'LOT-2026-02-015',
        createdAt: now,
      ),
      // Rau củ tươi
      Product(
        firestoreId: 'prod_food_005',
        shopId: shopId,
        name: 'Rau cải ngọt',
        brand: 'Organic Garden',
        cost: 15000,
        price: 25000,
        quantity: 30,
        categoryId: 'cat_food_vegetable',
        unit: 'bó',
        expiryDate: threeDays,
        batchNumber: 'LOT-2026-02-008',
        createdAt: now,
      ),
      // Trái cây
      Product(
        firestoreId: 'prod_food_006',
        shopId: shopId,
        name: 'Táo Mỹ',
        brand: 'Washington Apple',
        cost: 60000,
        price: 80000,
        quantity: 25,
        categoryId: 'cat_food_fruit',
        unit: 'kg',
        expiryDate: twoWeeks,
        batchNumber: 'LOT-2026-02-012',
        createdAt: now,
      ),
      // Đồ khô - hạn dài
      Product(
        firestoreId: 'prod_food_007',
        shopId: shopId,
        name: 'Gạo ST25',
        brand: 'ST25',
        cost: 25000,
        price: 35000,
        quantity: 100,
        categoryId: 'cat_food_dry',
        unit: 'kg',
        expiryDate: sixMonths,
        batchNumber: 'LOT-2026-01-100',
        createdAt: now,
      ),
      // Đồ uống
      Product(
        firestoreId: 'prod_food_008',
        shopId: shopId,
        name: 'Nước cam Teppy 1L',
        brand: 'Teppy',
        cost: 18000,
        price: 25000,
        quantity: 40,
        categoryId: 'cat_food_beverage',
        unit: 'chai',
        expiryDate: oneMonth,
        batchNumber: 'LOT-2026-02-020',
        createdAt: now,
      ),
      // Thực phẩm đông lạnh
      Product(
        firestoreId: 'prod_food_009',
        shopId: shopId,
        name: 'Há cảo đông lạnh 500g',
        brand: 'CP',
        cost: 45000,
        price: 65000,
        quantity: 20,
        categoryId: 'cat_food_frozen',
        unit: 'gói',
        expiryDate: sixMonths,
        batchNumber: 'LOT-2026-02-001',
        createdAt: now,
      ),
    ];
  }

  /// Tạo danh mục sản phẩm mẫu cho ngành Thời trang
  static List<ProductCategory> generateFashionCategories(String shopId) {
    return [
      ProductCategory(
        firestoreId: 'cat_fashion_shirt',
        shopId: shopId,
        name: 'Áo',
        icon: '👕',
        sortOrder: 1,
        hasVariants: true,
        trackSerial: false,
        trackExpiry: false,
        customFields: {'size': 'Kích cỡ', 'color': 'Màu sắc', 'material': 'Chất liệu'},
      ),
      ProductCategory(
        firestoreId: 'cat_fashion_pants',
        shopId: shopId,
        name: 'Quần',
        icon: '👖',
        sortOrder: 2,
        hasVariants: true,
        customFields: {'size': 'Kích cỡ', 'color': 'Màu sắc', 'material': 'Chất liệu'},
      ),
      ProductCategory(
        firestoreId: 'cat_fashion_dress',
        shopId: shopId,
        name: 'Váy & Đầm',
        icon: '👗',
        sortOrder: 3,
        hasVariants: true,
        customFields: {'size': 'Kích cỡ', 'color': 'Màu sắc', 'style': 'Kiểu dáng'},
      ),
      ProductCategory(
        firestoreId: 'cat_fashion_shoes',
        shopId: shopId,
        name: 'Giày dép',
        icon: '👟',
        sortOrder: 4,
        hasVariants: true,
        customFields: {'size': 'Size', 'color': 'Màu sắc'},
      ),
      ProductCategory(
        firestoreId: 'cat_fashion_bag',
        shopId: shopId,
        name: 'Túi xách',
        icon: '👜',
        sortOrder: 5,
        hasVariants: true,
        customFields: {'color': 'Màu sắc', 'material': 'Chất liệu'},
      ),
      ProductCategory(
        firestoreId: 'cat_fashion_accessory',
        shopId: shopId,
        name: 'Phụ kiện thời trang',
        icon: '🎀',
        sortOrder: 6,
        hasVariants: false,
      ),
    ];
  }

  /// Tạo sản phẩm mẫu cho ngành Thời trang (sản phẩm cha)
  static List<Product> generateFashionProducts(String shopId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      Product(
        firestoreId: 'prod_fashion_001',
        shopId: shopId,
        name: 'Áo sơ mi nam Oxford',
        brand: 'Việt Tiến',
        cost: 250000,
        price: 450000,
        quantity: 0, // Tổng qty nằm trong variants
        categoryId: 'cat_fashion_shirt',
        unit: 'cái',
        createdAt: now,
        customData: '{"material":"Cotton 100%","style":"Regular fit"}',
      ),
      Product(
        firestoreId: 'prod_fashion_002',
        shopId: shopId,
        name: 'Áo thun nữ basic',
        brand: 'Canifa',
        cost: 120000,
        price: 199000,
        quantity: 0,
        categoryId: 'cat_fashion_shirt',
        unit: 'cái',
        createdAt: now,
        customData: '{"material":"Cotton blend","style":"Slim fit"}',
      ),
      Product(
        firestoreId: 'prod_fashion_003',
        shopId: shopId,
        name: 'Quần jean nam slim fit',
        brand: 'Aristino',
        cost: 350000,
        price: 590000,
        quantity: 0,
        categoryId: 'cat_fashion_pants',
        unit: 'cái',
        createdAt: now,
        customData: '{"material":"Denim stretch","style":"Slim fit"}',
      ),
      Product(
        firestoreId: 'prod_fashion_004',
        shopId: shopId,
        name: 'Váy công sở A-line',
        brand: 'Eva de Eva',
        cost: 400000,
        price: 750000,
        quantity: 0,
        categoryId: 'cat_fashion_dress',
        unit: 'cái',
        createdAt: now,
        customData: '{"material":"Polyester blend","style":"A-line"}',
      ),
      Product(
        firestoreId: 'prod_fashion_005',
        shopId: shopId,
        name: 'Giày sneaker nam',
        brand: 'Biti\'s Hunter',
        cost: 450000,
        price: 750000,
        quantity: 0,
        categoryId: 'cat_fashion_shoes',
        unit: 'đôi',
        createdAt: now,
      ),
    ];
  }

  /// Tạo biến thể sản phẩm mẫu cho ngành Thời trang
  static List<ProductVariant> generateFashionVariants(String shopId) {
    final now = DateTime.now();
    return [
      // Variants cho Áo sơ mi nam Oxford (prod_fashion_001)
      ProductVariant(
        firestoreId: 'var_001_s_white',
        shopId: shopId,
        productId: 'prod_fashion_001',
        sku: 'OXFORD-S-WHITE',
        size: 'S',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 250000,
        salePrice: 450000,
        quantity: 5,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_001_m_white',
        shopId: shopId,
        productId: 'prod_fashion_001',
        sku: 'OXFORD-M-WHITE',
        size: 'M',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 250000,
        salePrice: 450000,
        quantity: 10,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_001_l_white',
        shopId: shopId,
        productId: 'prod_fashion_001',
        sku: 'OXFORD-L-WHITE',
        size: 'L',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 250000,
        salePrice: 450000,
        quantity: 8,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_001_m_blue',
        shopId: shopId,
        productId: 'prod_fashion_001',
        sku: 'OXFORD-M-BLUE',
        size: 'M',
        color: 'Xanh navy',
        colorCode: '#000080',
        costPrice: 250000,
        salePrice: 450000,
        quantity: 6,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_001_l_blue',
        shopId: shopId,
        productId: 'prod_fashion_001',
        sku: 'OXFORD-L-BLUE',
        size: 'L',
        color: 'Xanh navy',
        colorCode: '#000080',
        costPrice: 250000,
        salePrice: 450000,
        quantity: 4,
        minQuantity: 2,
        createdAt: now,
      ),

      // Variants cho Áo thun nữ basic (prod_fashion_002)
      ProductVariant(
        firestoreId: 'var_002_s_white',
        shopId: shopId,
        productId: 'prod_fashion_002',
        sku: 'TSHIRT-S-WHITE',
        size: 'S',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 120000,
        salePrice: 199000,
        quantity: 15,
        minQuantity: 5,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_002_m_white',
        shopId: shopId,
        productId: 'prod_fashion_002',
        sku: 'TSHIRT-M-WHITE',
        size: 'M',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 120000,
        salePrice: 199000,
        quantity: 20,
        minQuantity: 5,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_002_s_black',
        shopId: shopId,
        productId: 'prod_fashion_002',
        sku: 'TSHIRT-S-BLACK',
        size: 'S',
        color: 'Đen',
        colorCode: '#000000',
        costPrice: 120000,
        salePrice: 199000,
        quantity: 12,
        minQuantity: 5,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_002_m_pink',
        shopId: shopId,
        productId: 'prod_fashion_002',
        sku: 'TSHIRT-M-PINK',
        size: 'M',
        color: 'Hồng',
        colorCode: '#FFC0CB',
        costPrice: 120000,
        salePrice: 199000,
        quantity: 8,
        minQuantity: 5,
        createdAt: now,
      ),

      // Variants cho Quần jean nam (prod_fashion_003)
      ProductVariant(
        firestoreId: 'var_003_29_blue',
        shopId: shopId,
        productId: 'prod_fashion_003',
        sku: 'JEAN-29-BLUE',
        size: '29',
        color: 'Xanh đậm',
        colorCode: '#00008B',
        costPrice: 350000,
        salePrice: 590000,
        quantity: 7,
        minQuantity: 3,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_003_30_blue',
        shopId: shopId,
        productId: 'prod_fashion_003',
        sku: 'JEAN-30-BLUE',
        size: '30',
        color: 'Xanh đậm',
        colorCode: '#00008B',
        costPrice: 350000,
        salePrice: 590000,
        quantity: 12,
        minQuantity: 3,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_003_31_blue',
        shopId: shopId,
        productId: 'prod_fashion_003',
        sku: 'JEAN-31-BLUE',
        size: '31',
        color: 'Xanh đậm',
        colorCode: '#00008B',
        costPrice: 350000,
        salePrice: 590000,
        quantity: 10,
        minQuantity: 3,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_003_32_black',
        shopId: shopId,
        productId: 'prod_fashion_003',
        sku: 'JEAN-32-BLACK',
        size: '32',
        color: 'Đen',
        colorCode: '#000000',
        costPrice: 350000,
        salePrice: 590000,
        quantity: 5,
        minQuantity: 3,
        createdAt: now,
      ),

      // Variants cho Giày sneaker (prod_fashion_005)
      ProductVariant(
        firestoreId: 'var_005_39_white',
        shopId: shopId,
        productId: 'prod_fashion_005',
        sku: 'SNEAKER-39-WHITE',
        size: '39',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 450000,
        salePrice: 750000,
        quantity: 3,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_005_40_white',
        shopId: shopId,
        productId: 'prod_fashion_005',
        sku: 'SNEAKER-40-WHITE',
        size: '40',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 450000,
        salePrice: 750000,
        quantity: 6,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_005_41_white',
        shopId: shopId,
        productId: 'prod_fashion_005',
        sku: 'SNEAKER-41-WHITE',
        size: '41',
        color: 'Trắng',
        colorCode: '#FFFFFF',
        costPrice: 450000,
        salePrice: 750000,
        quantity: 8,
        minQuantity: 2,
        createdAt: now,
      ),
      ProductVariant(
        firestoreId: 'var_005_42_black',
        shopId: shopId,
        productId: 'prod_fashion_005',
        sku: 'SNEAKER-42-BLACK',
        size: '42',
        color: 'Đen',
        colorCode: '#000000',
        costPrice: 450000,
        salePrice: 750000,
        quantity: 4,
        minQuantity: 2,
        createdAt: now,
      ),
    ];
  }

  /// Tạo báo cáo kiểm tra dữ liệu
  static String generateDataReport(String shopId, String businessType) {
    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('   BÁO CÁO DỮ LIỆU TEST - MULTI-INDUSTRY PHASE 1');
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('Shop ID: $shopId');
    buffer.writeln('Business Type: $businessType');
    buffer.writeln('Thời gian: ${DateTime.now()}');
    buffer.writeln('');

    switch (businessType) {
      case 'electronics':
        final settings = ShopSettings.electronics(shopId);
        final categories = generateElectronicsCategories(shopId);
        final products = generateElectronicsProducts(shopId);
        
        buffer.writeln('📱 NGÀNH ĐIỆN TỬ');
        buffer.writeln('───────────────────────────────────────────────────────');
        buffer.writeln('CÀI ĐẶT SHOP:');
        buffer.writeln('  • Sửa chữa: ${settings.enableRepair ? "✅" : "❌"}');
        buffer.writeln('  • Serial/IMEI: ${settings.enableSerial ? "✅" : "❌"}');
        buffer.writeln('  • Bảo hành: ${settings.enableWarranty ? "✅" : "❌"}');
        buffer.writeln('  • Hạn sử dụng: ${settings.enableExpiry ? "✅" : "❌"}');
        buffer.writeln('  • Biến thể: ${settings.enableVariants ? "✅" : "❌"}');
        buffer.writeln('');
        buffer.writeln('DANH MỤC (${categories.length}):');
        for (final cat in categories) {
          buffer.writeln('  ${cat.icon} ${cat.name}');
          buffer.writeln('     - Serial: ${cat.trackSerial ? "✅" : "❌"}');
          buffer.writeln('     - Warranty: ${cat.hasWarranty ? "${cat.defaultWarrantyDays} ngày" : "❌"}');
        }
        buffer.writeln('');
        buffer.writeln('SẢN PHẨM (${products.length}):');
        for (final prod in products) {
          buffer.writeln('  • ${prod.name}');
          buffer.writeln('    Giá vốn: ${_formatPrice(prod.cost)} | Giá bán: ${_formatPrice(prod.price)}');
          buffer.writeln('    Tồn kho: ${prod.quantity} ${prod.unit ?? "cái"}');
          if (prod.imei != null) buffer.writeln('    IMEI: ${prod.imei}');
        }
        break;

      case 'food':
        final settings = ShopSettings.food(shopId);
        final categories = generateFoodCategories(shopId);
        final products = generateFoodProducts(shopId);
        
        buffer.writeln('🍎 NGÀNH THỰC PHẨM');
        buffer.writeln('───────────────────────────────────────────────────────');
        buffer.writeln('CÀI ĐẶT SHOP:');
        buffer.writeln('  • Sửa chữa: ${settings.enableRepair ? "✅" : "❌"}');
        buffer.writeln('  • Hạn sử dụng: ${settings.enableExpiry ? "✅" : "❌"}');
        buffer.writeln('  • Số lô: ${settings.enableBatch ? "✅" : "❌"}');
        buffer.writeln('  • Đơn vị mặc định: ${settings.defaultUnit}');
        buffer.writeln('  • Cảnh báo HSD: ${settings.expiryWarningDays} ngày');
        buffer.writeln('');
        buffer.writeln('DANH MỤC (${categories.length}):');
        for (final cat in categories) {
          buffer.writeln('  ${cat.icon} ${cat.name} - Theo dõi HSD: ${cat.trackExpiry ? "✅" : "❌"}');
        }
        buffer.writeln('');
        buffer.writeln('SẢN PHẨM (${products.length}):');
        final now = DateTime.now();
        for (final prod in products) {
          buffer.writeln('  • ${prod.name}');
          buffer.writeln('    Giá vốn: ${_formatPrice(prod.cost)} | Giá bán: ${_formatPrice(prod.price)}');
          buffer.writeln('    Tồn kho: ${prod.quantity} ${prod.unit ?? "cái"}');
          if (prod.expiryDate != null) {
            final expiry = DateTime.fromMillisecondsSinceEpoch(prod.expiryDate!);
            final diff = expiry.difference(now).inDays;
            String status;
            if (diff < 0) {
              status = '⛔ ĐÃ HẾT HẠN ${-diff} ngày';
            } else if (diff <= 7) {
              status = '⚠️ Còn $diff ngày';
            } else {
              status = '✅ Còn $diff ngày';
            }
            buffer.writeln('    HSD: ${_formatDate(expiry)} $status');
          }
          if (prod.batchNumber != null) buffer.writeln('    Số lô: ${prod.batchNumber}');
        }
        break;

      case 'fashion':
        final settings = ShopSettings.fashion(shopId);
        final categories = generateFashionCategories(shopId);
        final products = generateFashionProducts(shopId);
        final variants = generateFashionVariants(shopId);
        
        buffer.writeln('👕 NGÀNH THỜI TRANG');
        buffer.writeln('───────────────────────────────────────────────────────');
        buffer.writeln('CÀI ĐẶT SHOP:');
        buffer.writeln('  • Biến thể (size/màu): ${settings.enableVariants ? "✅" : "❌"}');
        buffer.writeln('  • Sửa chữa: ${settings.enableRepair ? "✅" : "❌"}');
        buffer.writeln('  • Serial: ${settings.enableSerial ? "✅" : "❌"}');
        buffer.writeln('');
        buffer.writeln('DANH MỤC (${categories.length}):');
        for (final cat in categories) {
          buffer.writeln('  ${cat.icon} ${cat.name} - Biến thể: ${cat.hasVariants ? "✅" : "❌"}');
        }
        buffer.writeln('');
        buffer.writeln('SẢN PHẨM & BIẾN THỂ:');
        for (final prod in products) {
          final prodVariants = variants.where((v) => v.productId == prod.firestoreId).toList();
          final summary = VariantSummary.fromVariants(prod.firestoreId ?? '', prodVariants);
          
          buffer.writeln('  📦 ${prod.name}');
          buffer.writeln('     Giá gốc: ${_formatPrice(prod.cost)} - ${_formatPrice(prod.price)}');
          buffer.writeln('     Số biến thể: ${summary.totalVariants}');
          buffer.writeln('     Tổng tồn kho: ${summary.totalStock}');
          buffer.writeln('     Size: ${summary.availableSizes.join(", ")}');
          buffer.writeln('     Màu: ${summary.availableColors.join(", ")}');
          buffer.writeln('     Range giá: ${summary.priceRange}');
          buffer.writeln('');
          for (final v in prodVariants) {
            buffer.writeln('       └ ${v.displayName}');
            buffer.writeln('         SKU: ${v.sku} | Qty: ${v.quantity} | Giá: ${_formatPrice(v.salePrice)}');
          }
        }
        break;
    }

    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════════════════════');
    buffer.writeln('                   KẾT THÚC BÁO CÁO');
    buffer.writeln('═══════════════════════════════════════════════════════');
    
    return buffer.toString();
  }

  static String _formatPrice(int price) {
    if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}M';
    } else if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(0)}K';
    }
    return '$price';
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Entry point để chạy test data generation
void main() {
  // Tạo báo cáo cho từng ngành
  print(MultiIndustryTestData.generateDataReport('shop_elec_001', 'electronics'));
  print('');
  print(MultiIndustryTestData.generateDataReport('shop_food_001', 'food'));
  print('');
  print(MultiIndustryTestData.generateDataReport('shop_fashion_001', 'fashion'));
}
