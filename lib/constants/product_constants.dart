/// Các hằng số dùng chung cho sản phẩm
/// Đồng bộ giữa: NHẬP KHO MỚI, HÀNG CHỜ XÁC NHẬN, QUẢN LÝ KHO,
/// THÊM MÃ NHẬP NHANH, NHẬP KHO NHANH
class ProductConstants {
  /// Danh sách màu sắc
  static const List<String> colors = [
    'ĐEN',
    'TRẮNG',
    'XANH',
    'ĐỎ',
    'VÀNG',
    'TÍM',
    'HỒNG',
    'BẠC',
    'XANH LÁ',
    'CAM',
    'XANH DƯƠNG',
    'GOLD',
    'TITAN TỰ NHIÊN',
    'TITAN ĐEN',
    'TITAN TRẮNG',
    'TITAN XÁM',
    'KHÁC',
  ];

  /// Danh sách thương hiệu điện thoại
  static const List<String> brands = [
    'IPHONE',
    'SAMSUNG',
    'OPPO',
    'XIAOMI',
    'VIVO',
    'REALME',
    'HONOR',
    'HUAWEI',
    'NOKIA',
    'KHÁC',
  ];

  /// Danh sách dung lượng
  static const List<String> capacities = [
    '32GB',
    '64GB',
    '128GB',
    '256GB',
    '512GB',
    '1TB',
  ];

  /// Danh sách tình trạng máy
  static const List<String> conditions = [
    'MỚI 100%',
    'LIKE NEW 99%',
    '98%',
    '97%',
    '95%',
    'ĐÃ QUA SD',
    'KHÁC',
  ];

  /// Danh sách tình trạng ngắn gọn (dùng cho input nhanh)
  static const List<String> conditionsShort = [
    'MỚI',
    '99',
    '98',
    '97',
    '95',
    'KHÁC',
  ];

  /// Danh sách phương thức thanh toán
  static const List<String> paymentMethods = [
    'TIỀN MẶT',
    'CHUYỂN KHOẢN',
    'CÔNG NỢ',
  ];

  /// Danh sách đơn vị (cho linh kiện/phụ kiện)
  static const List<String> units = [
    'Cái',
    'Hộp',
    'Bộ',
    'Chiếc',
    'Cuộn',
    'Túi',
    'Mét',
    'Kg',
  ];

  /// Loại sản phẩm
  static const List<String> productTypes = [
    'DIEN_THOAI',
    'PHU_KIEN',
    'LINH_KIEN',
  ];

  /// Tên hiển thị loại sản phẩm
  static const Map<String, String> productTypeNames = {
    'DIEN_THOAI': 'Điện thoại',
    'PHU_KIEN': 'Phụ kiện',
    'LINH_KIEN': 'Linh kiện',
  };

  /// Model gợi ý theo thương hiệu
  static const Map<String, List<String>> modelSuggestions = {
    'IPHONE': [
      // iPhone 17 series
      '17 PRO MAX', '17 PRO', '17 PLUS', '17',
      // iPhone 16 series
      '16 PRO MAX', '16 PRO', '16 PLUS', '16',
      // iPhone 15 series
      '15 PRO MAX', '15 PRO', '15 PLUS', '15',
      // iPhone 14 series
      '14 PRO MAX', '14 PRO', '14 PLUS', '14',
      // iPhone 13 series
      '13 PRO MAX', '13 PRO', '13 MINI', '13',
      // iPhone 12 series
      '12 PRO MAX', '12 PRO', '12 MINI', '12',
      // iPhone 11 series
      '11 PRO MAX', '11 PRO', '11',
      // Older models
      'XS MAX', 'XS', 'XR', 'X', 'SE 2024', 'SE 2022', 'SE 2020', '8 PLUS', '8',
    ],
    'SAMSUNG': [
      'S25 ULTRA', 'S25+', 'S25',
      'S24 ULTRA', 'S24+', 'S24', 'S24 FE',
      'S23 ULTRA', 'S23+', 'S23', 'S23 FE',
      'S22 ULTRA', 'S22+', 'S22',
      'S21 ULTRA', 'S21+', 'S21', 'S21 FE',
      'Z FOLD 6', 'Z FOLD 5', 'Z FOLD 4',
      'Z FLIP 6', 'Z FLIP 5', 'Z FLIP 4',
      'A55', 'A54', 'A35', 'A34', 'A25', 'A24', 'A15', 'A14', 'A05', 'A04',
      'M55', 'M54', 'M34', 'M14',
    ],
    'OPPO': [
      'FIND X7 ULTRA', 'FIND X7',
      'FIND N3', 'FIND N3 FLIP',
      'RENO 12 PRO', 'RENO 12', 'RENO 11 PRO', 'RENO 11', 'RENO 10 PRO', 'RENO 10',
      'A98', 'A79', 'A78', 'A58', 'A38', 'A18', 'A17',
      'F27 PRO', 'F25 PRO', 'F23',
    ],
    'XIAOMI': [
      '14 ULTRA', '14 PRO', '14',
      '13 ULTRA', '13 PRO', '13', '13 LITE',
      '12 PRO', '12', '12 LITE',
      'REDMI NOTE 14 PRO+', 'REDMI NOTE 14 PRO', 'REDMI NOTE 14',
      'REDMI NOTE 13 PRO+', 'REDMI NOTE 13 PRO', 'REDMI NOTE 13',
      'REDMI 14C', 'REDMI 13C', 'REDMI 13', 'REDMI 12',
      'POCO X6 PRO', 'POCO X6', 'POCO M6 PRO', 'POCO C65',
    ],
    'VIVO': [
      'X100 PRO', 'X100',
      'X90 PRO', 'X90',
      'V30 PRO', 'V30', 'V29', 'V27',
      'Y36', 'Y35', 'Y27', 'Y17',
    ],
    'REALME': [
      'GT 5 PRO', 'GT 5', 'GT NEO 6',
      '12 PRO+', '12 PRO', '12',
      'C67', 'C65', 'C55', 'C53', 'C35', 'C33',
      'NARZO 70 PRO', 'NARZO 60',
    ],
    'HONOR': [
      'MAGIC 6 PRO', 'MAGIC 6',
      '200 PRO', '200',
      '90', 'X9B', 'X8B', 'X7B',
    ],
    'HUAWEI': [
      'PURA 70 ULTRA', 'PURA 70 PRO', 'PURA 70',
      'MATE 60 PRO', 'MATE 60',
      'NOVA 12 PRO', 'NOVA 12', 'NOVA 11',
    ],
    'NOKIA': [
      'XR21', 'G42', 'G22', 'C32', 'C22', 'C12',
    ],
    'KHÁC': [],
  };

  /// Map condition từ giá trị khác nhau về giá trị chuẩn
  static String mapCondition(String condition) {
    final conditionUpper = condition.toUpperCase().trim();

    // Map các biến thể của "MỚI 100%"
    if (conditionUpper.contains('MỚI 100') ||
        conditionUpper == 'MỚI' ||
        conditionUpper == 'NEW 100' ||
        conditionUpper == '100%' ||
        conditionUpper == '100') {
      return 'MỚI 100%';
    }

    // Map các biến thể của "99%"
    if (conditionUpper.contains('99') || conditionUpper.contains('LIKE NEW')) {
      return 'LIKE NEW 99%';
    }

    // Map các biến thể khác
    if (conditionUpper.contains('98')) return '98%';
    if (conditionUpper.contains('97')) return '97%';
    if (conditionUpper.contains('95')) return '95%';
    if (conditionUpper.contains('ĐÃ QUA') || conditionUpper.contains('CŨ')) {
      return 'ĐÃ QUA SD';
    }

    return 'KHÁC';
  }

  /// Map condition ngắn từ giá trị khác nhau (cho fast_stock_in)
  static String mapConditionShort(String condition) {
    final conditionUpper = condition.toUpperCase().trim();

    if (conditionUpper.contains('MỚI 100') ||
        conditionUpper == 'MỚI' ||
        conditionUpper == '100%' ||
        conditionUpper == '100') {
      return 'MỚI';
    }
    if (conditionUpper.contains('99') || conditionUpper.contains('LIKE NEW')) {
      return '99';
    }
    if (conditionUpper.contains('98')) return '98';
    if (conditionUpper.contains('97')) return '97';
    if (conditionUpper.contains('95')) return '95';

    return 'KHÁC';
  }

  /// Map color từ giá trị khác nhau về giá trị chuẩn
  static String mapColor(String? color) {
    if (color == null || color.isEmpty) return 'KHÁC';
    final colorUpper = color.toUpperCase().trim();

    // Tìm trong danh sách chuẩn
    for (final c in colors) {
      if (c == colorUpper) return c;
    }

    // Map các biến thể
    if (colorUpper.contains('BLACK') || colorUpper.contains('ĐEN')) return 'ĐEN';
    if (colorUpper.contains('WHITE') || colorUpper.contains('TRẮNG')) return 'TRẮNG';
    if (colorUpper.contains('BLUE') || colorUpper.contains('XANH DƯƠNG')) return 'XANH DƯƠNG';
    if (colorUpper.contains('RED') || colorUpper.contains('ĐỎ')) return 'ĐỎ';
    if (colorUpper.contains('YELLOW') || colorUpper.contains('VÀNG')) return 'VÀNG';
    if (colorUpper.contains('PURPLE') || colorUpper.contains('TÍM')) return 'TÍM';
    if (colorUpper.contains('PINK') || colorUpper.contains('HỒNG')) return 'HỒNG';
    if (colorUpper.contains('SILVER') || colorUpper.contains('BẠC')) return 'BẠC';
    if (colorUpper.contains('GREEN') || colorUpper.contains('XANH LÁ')) return 'XANH LÁ';
    if (colorUpper.contains('ORANGE') || colorUpper.contains('CAM')) return 'CAM';
    if (colorUpper.contains('GOLD')) return 'GOLD';
    if (colorUpper.contains('TITAN')) {
      if (colorUpper.contains('TỰ NHIÊN') || colorUpper.contains('NATURAL')) return 'TITAN TỰ NHIÊN';
      if (colorUpper.contains('ĐEN') || colorUpper.contains('BLACK')) return 'TITAN ĐEN';
      if (colorUpper.contains('TRẮNG') || colorUpper.contains('WHITE')) return 'TITAN TRẮNG';
      if (colorUpper.contains('XÁM') || colorUpper.contains('GRAY')) return 'TITAN XÁM';
    }

    return 'KHÁC';
  }
}
