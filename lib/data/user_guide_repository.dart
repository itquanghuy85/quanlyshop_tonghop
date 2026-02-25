import 'package:flutter/material.dart';

/// Complete User Guide Repository - Comprehensive documentation for Shopmanager app
/// Contains all user guides organized by module with step-by-step instructions

// ============================================================================
// DATA MODELS
// ============================================================================

class GuideModule {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int order;
  final List<String> targetRoles;

  const GuideModule({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.order,
    this.targetRoles = const ['all'],
  });
}

class GuideSection {
  final String id;
  final String moduleId;
  final String title;
  final String description;
  final List<GuideStep> steps;
  final List<String> tips;
  final List<String> warnings;
  final List<String> relatedSections;
  final String difficulty; // 'Dễ', 'Trung bình', 'Nâng cao'
  final String estimatedTime;
  final List<String> targetRoles;
  final bool isNew;
  final bool isPopular;

  const GuideSection({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.description,
    required this.steps,
    this.tips = const [],
    this.warnings = const [],
    this.relatedSections = const [],
    this.difficulty = 'Dễ',
    this.estimatedTime = '5 phút',
    this.targetRoles = const ['all'],
    this.isNew = false,
    this.isPopular = false,
  });
}

class GuideStep {
  final int order;
  final String title;
  final String description;
  final String? imagePath;
  final String? note;

  const GuideStep({
    required this.order,
    required this.title,
    required this.description,
    this.imagePath,
    this.note,
  });
}

// ============================================================================
// REPOSITORY
// ============================================================================

class UserGuideRepository {
  // ---------------------------------------------------------------------------
  // MODULES (Main categories)
  // ---------------------------------------------------------------------------
  static final List<GuideModule> modules = [
    const GuideModule(
      id: 'getting-started',
      title: 'Bắt đầu sử dụng',
      description: 'Hướng dẫn cài đặt, đăng nhập và làm quen với giao diện ứng dụng',
      icon: Icons.rocket_launch,
      color: Color(0xFF4CAF50),
      order: 1,
    ),
    const GuideModule(
      id: 'inventory',
      title: 'Quản lý kho hàng',
      description: 'Nhập hàng, kiểm kho, in tem và quản lý sản phẩm',
      icon: Icons.inventory_2,
      color: Color(0xFF2196F3),
      order: 2,
    ),
    const GuideModule(
      id: 'sales',
      title: 'Bán hàng',
      description: 'Tạo hóa đơn, quét mã, thanh toán và in hóa đơn',
      icon: Icons.point_of_sale,
      color: Color(0xFFFF9800),
      order: 3,
      targetRoles: ['owner', 'manager', 'cashier'],
    ),
    const GuideModule(
      id: 'repairs',
      title: 'Sửa chữa',
      description: 'Tiếp nhận máy, theo dõi tiến độ và bàn giao cho khách',
      icon: Icons.build_circle,
      color: Color(0xFF0068FF),
      order: 4,
      targetRoles: ['owner', 'manager', 'technician'],
    ),
    const GuideModule(
      id: 'customers',
      title: 'Quản lý khách hàng',
      description: 'Thêm khách hàng, theo dõi công nợ và lịch sử giao dịch',
      icon: Icons.people,
      color: Color(0xFF00BCD4),
      order: 5,
    ),
    const GuideModule(
      id: 'finance',
      title: 'Tài chính & Báo cáo',
      description: 'Quỹ tiền mặt, thu chi, báo cáo doanh thu và lợi nhuận',
      icon: Icons.analytics,
      color: Color(0xFFE91E63),
      order: 6,
      targetRoles: ['owner', 'manager'],
    ),
    const GuideModule(
      id: 'staff',
      title: 'Quản lý nhân viên',
      description: 'Thêm nhân viên, phân quyền và chấm công',
      icon: Icons.badge,
      color: Color(0xFF795548),
      order: 7,
      targetRoles: ['owner', 'manager'],
    ),
    const GuideModule(
      id: 'printing',
      title: 'In ấn & Tem nhãn',
      description: 'Kết nối máy in, thiết kế tem và in hóa đơn',
      icon: Icons.print,
      color: Color(0xFF607D8B),
      order: 8,
    ),
    const GuideModule(
      id: 'settings',
      title: 'Cài đặt hệ thống',
      description: 'Đồng bộ dữ liệu, sao lưu và cấu hình ứng dụng',
      icon: Icons.settings,
      color: Color(0xFF9E9E9E),
      order: 9,
      targetRoles: ['owner', 'admin'],
    ),
    const GuideModule(
      id: 'suppliers',
      title: 'Quản lý nhà cung cấp',
      description: 'Thêm NCC, theo dõi công nợ và lịch sử nhập hàng',
      icon: Icons.local_shipping,
      color: Color(0xFF0068FF),
      order: 10,
      targetRoles: ['owner', 'manager'],
    ),
  ];

  // ---------------------------------------------------------------------------
  // SECTIONS (Detailed guides)
  // ---------------------------------------------------------------------------
  static final List<GuideSection> sections = [
    // =========================================================================
    // MODULE: GETTING STARTED
    // =========================================================================
    const GuideSection(
      id: 'gs-login',
      moduleId: 'getting-started',
      title: 'Đăng nhập lần đầu',
      description: 'Hướng dẫn đăng nhập và thiết lập tài khoản ban đầu',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở ứng dụng Shopmanager',
          description: 'Nhấn vào biểu tượng Shopmanager trên màn hình điện thoại để khởi động ứng dụng.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhập thông tin đăng nhập',
          description: 'Điền email và mật khẩu được cấp bởi quản lý shop. Nếu chưa có tài khoản, liên hệ chủ shop để được cấp.',
        ),
        GuideStep(
          order: 3,
          title: 'Xác thực hai bước (nếu có)',
          description: 'Nếu shop bật bảo mật 2 lớp, nhập mã OTP được gửi về số điện thoại đã đăng ký.',
        ),
        GuideStep(
          order: 4,
          title: 'Chọn shop làm việc',
          description: 'Nếu tài khoản được gắn nhiều shop, chọn shop cần làm việc từ danh sách.',
        ),
        GuideStep(
          order: 5,
          title: 'Hoàn tất',
          description: 'Sau khi đăng nhập thành công, bạn sẽ thấy màn hình chính với các tab chức năng.',
        ),
      ],
      tips: [
        'Tích chọn "Ghi nhớ đăng nhập" để không phải nhập lại mỗi lần mở app.',
        'Nếu quên mật khẩu, nhấn "Quên mật khẩu" và làm theo hướng dẫn qua email.',
      ],
      warnings: [
        'Không chia sẻ thông tin đăng nhập cho người khác.',
        'Đăng xuất khi sử dụng thiết bị công cộng.',
      ],
    ),

    const GuideSection(
      id: 'gs-interface',
      moduleId: 'getting-started',
      title: 'Làm quen giao diện',
      description: 'Tổng quan các màn hình và chức năng chính của ứng dụng',
      difficulty: 'Dễ',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Thanh điều hướng dưới cùng',
          description: 'Gồm các tab: Trang chủ, Kho, Bán hàng, Sửa chữa và Cài đặt. Nhấn để chuyển giữa các chức năng.',
        ),
        GuideStep(
          order: 2,
          title: 'Trang chủ (Dashboard)',
          description: 'Hiển thị tổng quan: doanh thu hôm nay, đơn sửa chữa đang xử lý, cảnh báo hết hàng và thông báo mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Nút hành động nhanh',
          description: 'Nút tròn (+) ở góc phải dưới giúp tạo nhanh: hóa đơn bán, đơn sửa, nhập kho mà không cần vào từng tab.',
        ),
        GuideStep(
          order: 4,
          title: 'Thanh tìm kiếm',
          description: 'Ở đầu mỗi màn hình danh sách, dùng để tìm nhanh sản phẩm, khách hàng hoặc đơn hàng theo tên, mã, IMEI.',
        ),
        GuideStep(
          order: 5,
          title: 'Menu ngữ cảnh',
          description: 'Nhấn giữ vào một mục (sản phẩm, đơn hàng...) để hiện menu thao tác nhanh: sửa, xóa, in tem...',
        ),
      ],
      tips: [
        'Vuốt xuống ở đầu danh sách để làm mới dữ liệu.',
        'Nhấn đúp vào tab đang chọn để cuộn lên đầu trang.',
      ],
    ),

    const GuideSection(
      id: 'gs-notifications',
      moduleId: 'getting-started',
      title: 'Cài đặt thông báo',
      description: 'Bật/tắt và tùy chỉnh các loại thông báo nhận được',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Cài đặt > Thông báo',
          description: 'Từ tab Cài đặt, cuộn xuống và nhấn vào mục "Thông báo".',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn loại thông báo',
          description: 'Bật/tắt từng loại: đơn sửa mới, đơn hoàn thành, cảnh báo hết hàng, nhắc công nợ...',
        ),
        GuideStep(
          order: 3,
          title: 'Cài đặt âm thanh',
          description: 'Chọn âm thanh thông báo hoặc tắt âm nếu không cần.',
        ),
      ],
      tips: [
        'Bật thông báo "Đơn sửa hoàn thành" để kịp thời liên hệ khách đến lấy máy.',
      ],
    ),

    // =========================================================================
    // MODULE: INVENTORY
    // =========================================================================
    const GuideSection(
      id: 'inv-add-product',
      moduleId: 'inventory',
      title: 'Thêm sản phẩm mới',
      description: 'Hướng dẫn nhập thông tin sản phẩm vào kho',
      difficulty: 'Dễ',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào tab Kho',
          description: 'Nhấn vào tab "Kho" ở thanh điều hướng dưới cùng.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn nút Thêm (+)',
          description: 'Nhấn nút tròn có dấu + ở góc phải dưới màn hình.',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn danh mục sản phẩm',
          description: 'Chọn loại: Điện thoại, Laptop, Phụ kiện, Linh kiện... để hiển thị form phù hợp.',
        ),
        GuideStep(
          order: 4,
          title: 'Nhập thông tin cơ bản',
          description: 'Điền tên sản phẩm, IMEI/Serial (nếu có), dung lượng, màu sắc, tình trạng máy.',
        ),
        GuideStep(
          order: 5,
          title: 'Nhập giá',
          description: 'Nhập giá nhập (giá vốn), giá bán KPK (không phụ kiện), giá bán CPK (có phụ kiện).',
          note: 'KPK = Không Phụ Kiện, CPK = Có Phụ Kiện (sạc, cáp, ốp...)',
        ),
        GuideStep(
          order: 6,
          title: 'Thêm hình ảnh (tùy chọn)',
          description: 'Nhấn "Thêm ảnh" để chụp hoặc chọn từ thư viện. Có thể thêm nhiều ảnh.',
        ),
        GuideStep(
          order: 7,
          title: 'Lưu sản phẩm',
          description: 'Nhấn "Lưu" để hoàn tất. Sản phẩm sẽ xuất hiện trong danh sách kho.',
        ),
      ],
      tips: [
        'Quét mã vạch/QR để tự động điền IMEI nhanh hơn.',
        'Dùng tính năng "Sao chép sản phẩm" khi nhập nhiều máy cùng model.',
        'Giá CPK thường cao hơn KPK khoảng 300-500k tùy loại phụ kiện kèm theo.',
      ],
      warnings: [
        'Kiểm tra kỹ IMEI trước khi lưu vì không thể sửa sau này.',
      ],
      relatedSections: ['inv-scan-qr', 'inv-print-label'],
    ),

    const GuideSection(
      id: 'inv-scan-qr',
      moduleId: 'inventory',
      title: 'Quét mã QR/Barcode',
      description: 'Sử dụng camera để quét mã sản phẩm',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở máy quét',
          description: 'Nhấn biểu tượng máy quét (📷) ở góc phải thanh tìm kiếm.',
        ),
        GuideStep(
          order: 2,
          title: 'Đưa camera vào mã',
          description: 'Hướng camera vào mã QR hoặc barcode. Giữ yên cho đến khi nghe tiếng "bíp".',
        ),
        GuideStep(
          order: 3,
          title: 'Xem kết quả',
          description: 'Nếu mã khớp sản phẩm trong kho, thông tin sẽ hiển thị ngay. Nếu không tìm thấy, có thể thêm mới.',
        ),
      ],
      tips: [
        'Bật đèn flash nếu môi trường thiếu sáng.',
        'Mã QR của app bắt đầu bằng "check_product:" hoặc "check_inv:".',
      ],
    ),

    const GuideSection(
      id: 'inv-print-label',
      moduleId: 'inventory',
      title: 'In tem sản phẩm',
      description: 'In tem QR với giá và thông tin sản phẩm',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Chọn sản phẩm cần in tem',
          description: 'Từ danh sách Kho, nhấn vào sản phẩm cần in tem.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn nút In tem',
          description: 'Trong màn hình chi tiết, nhấn nút "In tem" (biểu tượng máy in).',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn mẫu tem',
          description: 'Chọn loại tem phù hợp:\n• Tem kiểm kho: chỉ có QR và mã\n• Tem bán hàng: có giá KPK/CPK\n• Tem khuyến mãi: có giá gốc và % giảm\n• Tem bảo hành: có ngày bán và hết hạn BH',
        ),
        GuideStep(
          order: 4,
          title: 'Tùy chỉnh nội dung (nếu cần)',
          description: 'Nhấn "Tùy chỉnh" để bật/tắt các trường: tên shop, hotline, slogan...',
        ),
        GuideStep(
          order: 5,
          title: 'Chọn số lượng và in',
          description: 'Nhập số lượng tem cần in, sau đó nhấn "In" để gửi lệnh đến máy in.',
        ),
      ],
      tips: [
        'Điều chỉnh cỡ chữ trong Cài đặt > Thiết kế tem nếu chữ quá to hoặc nhỏ.',
        'Test in 1 tem trước khi in hàng loạt.',
      ],
      warnings: [
        'Đảm bảo máy in đã được kết nối và có giấy.',
      ],
      relatedSections: ['print-connect-bt', 'print-design-label'],
    ),

    const GuideSection(
      id: 'inv-check-stock',
      moduleId: 'inventory',
      title: 'Kiểm kho nhanh',
      description: 'Quét QR để kiểm tra và đối chiếu tồn kho',
      difficulty: 'Trung bình',
      estimatedTime: '10 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Kho > Kiểm kho',
          description: 'Nhấn tab Kho, sau đó chọn "Kiểm kho" từ menu.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn khu vực kiểm',
          description: 'Chọn danh mục hoặc vị trí kệ cần kiểm tra (nếu có phân chia).',
        ),
        GuideStep(
          order: 3,
          title: 'Bắt đầu quét',
          description: 'Nhấn "Bắt đầu quét" và đưa camera vào từng tem QR trên sản phẩm.',
        ),
        GuideStep(
          order: 4,
          title: 'Xem checklist',
          description: 'Bên phải màn hình hiển thị danh sách:\n• ✅ Xanh: đã quét, khớp\n• ❌ Đỏ: thiếu, chưa quét\n• ⚠️ Vàng: thừa, không có trong hệ thống',
        ),
        GuideStep(
          order: 5,
          title: 'Xuất báo cáo',
          description: 'Sau khi quét xong, nhấn "Xuất báo cáo" để lưu kết quả kiểm kho.',
        ),
      ],
      tips: [
        'Bật âm thanh phản hồi để biết khi nào quét thành công.',
        'Kiểm kho định kỳ hàng tuần để phát hiện sớm sai lệch.',
      ],
      relatedSections: ['inv-scan-qr'],
    ),

    const GuideSection(
      id: 'inv-import-excel',
      moduleId: 'inventory',
      title: 'Nhập kho từ Excel',
      description: 'Import danh sách sản phẩm từ file Excel',
      difficulty: 'Nâng cao',
      estimatedTime: '15 phút',
      targetRoles: ['owner', 'manager'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Tải file mẫu',
          description: 'Vào Kho > Menu (⋮) > Nhập từ Excel > Tải file mẫu.',
        ),
        GuideStep(
          order: 2,
          title: 'Điền dữ liệu vào file mẫu',
          description: 'Mở file Excel và điền thông tin theo các cột:\n• Tên sản phẩm (bắt buộc)\n• IMEI/Serial\n• Danh mục\n• Giá nhập, Giá bán\n• Màu, Dung lượng, Tình trạng',
        ),
        GuideStep(
          order: 3,
          title: 'Upload file',
          description: 'Quay lại app, nhấn "Chọn file" và chọn file Excel đã điền.',
        ),
        GuideStep(
          order: 4,
          title: 'Xem trước và xác nhận',
          description: 'Kiểm tra danh sách sản phẩm sẽ được import. Sửa lỗi nếu có.',
        ),
        GuideStep(
          order: 5,
          title: 'Nhập kho',
          description: 'Nhấn "Nhập kho" để thêm tất cả sản phẩm vào hệ thống.',
        ),
      ],
      tips: [
        'Giữ nguyên tên cột trong file mẫu, chỉ điền dữ liệu vào các dòng.',
        'Có thể import tối đa 500 sản phẩm mỗi lần.',
      ],
      warnings: [
        'Sao lưu dữ liệu trước khi import số lượng lớn.',
        'IMEI trùng sẽ bị bỏ qua không import.',
      ],
    ),

    // =========================================================================
    // MODULE: SALES
    // =========================================================================
    const GuideSection(
      id: 'sales-create',
      moduleId: 'sales',
      title: 'Tạo hóa đơn bán hàng',
      description: 'Hướng dẫn tạo và in hóa đơn bán lẻ',
      difficulty: 'Dễ',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào tab Bán hàng',
          description: 'Nhấn tab "Bán hàng" ở thanh điều hướng dưới cùng.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn Tạo hóa đơn',
          description: 'Nhấn nút (+) để bắt đầu tạo hóa đơn mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Thêm sản phẩm',
          description: 'Tìm sản phẩm bằng tên, IMEI hoặc quét QR. Nhấn vào sản phẩm để thêm vào hóa đơn.',
        ),
        GuideStep(
          order: 4,
          title: 'Chọn giá bán',
          description: 'Chọn bán theo giá KPK (không phụ kiện) hoặc CPK (có phụ kiện). Có thể sửa giá nếu cần.',
        ),
        GuideStep(
          order: 5,
          title: 'Nhập thông tin khách hàng',
          description: 'Nhập tên, SĐT khách hàng. Nếu khách cũ, chọn từ danh sách gợi ý.',
        ),
        GuideStep(
          order: 6,
          title: 'Chọn hình thức thanh toán',
          description: 'Chọn: Tiền mặt, Chuyển khoản, Kết hợp (tiền mặt + CK), Quẹt thẻ, Công nợ (trả sau) hoặc Trả góp (NH). Với "Kết hợp", nhập số tiền mặt và chuyển khoản riêng.',
        ),
        GuideStep(
          order: 7,
          title: 'Hoàn tất và in hóa đơn',
          description: 'Nhấn "Hoàn tất" để lưu. Chọn "In hóa đơn" nếu muốn in cho khách.',
        ),
      ],
      tips: [
        'Dùng "Công nợ" khi khách đặt cọc hoặc trả góp.',
        'Hóa đơn đã lưu sẽ tự động trừ tồn kho.',
      ],
      relatedSections: ['sales-debt', 'sales-combined-payment', 'print-receipt'],
    ),

    const GuideSection(
      id: 'sales-debt',
      moduleId: 'sales',
      title: 'Quản lý công nợ',
      description: 'Theo dõi và thu công nợ khách hàng',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      targetRoles: ['owner', 'manager', 'cashier'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Xem danh sách công nợ',
          description: 'Vào Bán hàng > Công nợ để xem danh sách khách đang nợ.',
        ),
        GuideStep(
          order: 2,
          title: 'Lọc theo trạng thái',
          description: 'Lọc: Tất cả, Đang nợ, Quá hạn, Đã thu đủ.',
        ),
        GuideStep(
          order: 3,
          title: 'Thu công nợ',
          description: 'Nhấn vào khách hàng > "Thu tiền". Nhập số tiền thu được.',
        ),
        GuideStep(
          order: 4,
          title: 'Xác nhận thanh toán',
          description: 'Chọn hình thức nhận tiền và nhấn "Xác nhận".',
        ),
      ],
      tips: [
        'Bật thông báo nhắc công nợ quá hạn để không bỏ sót.',
        'Xuất danh sách công nợ ra Excel để đối chiếu.',
      ],
    ),

    const GuideSection(
      id: 'sales-return',
      moduleId: 'sales',
      title: 'Đổi trả hàng',
      description: 'Xử lý khi khách đổi hoặc trả sản phẩm',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Tìm hóa đơn gốc',
          description: 'Vào Bán hàng > Lịch sử > Tìm hóa đơn cần đổi trả.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn Đổi trả',
          description: 'Nhấn vào hóa đơn > chọn "Đổi trả hàng".',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn sản phẩm đổi trả',
          description: 'Tích chọn sản phẩm khách muốn trả và nhập lý do.',
        ),
        GuideStep(
          order: 4,
          title: 'Xử lý tiền',
          description: 'Hệ thống tính toán số tiền hoàn lại hoặc bù thêm nếu đổi sang sản phẩm khác.',
        ),
        GuideStep(
          order: 5,
          title: 'Hoàn tất',
          description: 'Xác nhận để cập nhật kho và tài chính.',
        ),
      ],
      warnings: [
        'Chỉ đổi trả trong thời gian bảo hành theo chính sách shop.',
      ],
    ),

    // =========================================================================
    // MODULE: REPAIRS
    // =========================================================================
    const GuideSection(
      id: 'rep-create',
      moduleId: 'repairs',
      title: 'Tạo đơn sửa chữa',
      description: 'Tiếp nhận máy và lập phiếu sửa chữa',
      difficulty: 'Dễ',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào tab Sửa chữa',
          description: 'Nhấn tab "Sửa chữa" ở thanh điều hướng.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn Tạo đơn mới',
          description: 'Nhấn nút (+) để tạo đơn tiếp nhận máy.',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập thông tin khách',
          description: 'Điền tên, SĐT khách hàng. Nếu khách cũ sẽ tự động gợi ý.',
        ),
        GuideStep(
          order: 4,
          title: 'Nhập thông tin thiết bị',
          description: 'Điền tên máy/model, IMEI, màu sắc, tình trạng vỏ ngoài.',
        ),
        GuideStep(
          order: 5,
          title: 'Mô tả lỗi',
          description: 'Ghi chi tiết tình trạng lỗi, triệu chứng theo mô tả của khách.',
        ),
        GuideStep(
          order: 6,
          title: 'Liệt kê phụ kiện đi kèm',
          description: 'Ghi nhận phụ kiện khách gửi kèm: sạc, cáp, ốp, sim...',
        ),
        GuideStep(
          order: 7,
          title: 'Báo giá dự kiến',
          description: 'Nhập giá sửa dự kiến để khách tham khảo.',
        ),
        GuideStep(
          order: 8,
          title: 'Chụp ảnh biên bản',
          description: 'Chụp ảnh máy ở nhiều góc để làm bằng chứng tình trạng khi nhận.',
        ),
        GuideStep(
          order: 9,
          title: 'In phiếu tiếp nhận',
          description: 'Lưu đơn và in phiếu cho khách giữ lấy.',
        ),
      ],
      tips: [
        'Chụp ảnh chi tiết các vết xước, móp để tránh tranh chấp sau này.',
        'Ghi rõ "Mật khẩu máy: xxxx" nếu khách cung cấp.',
      ],
      relatedSections: ['rep-update-status', 'print-receipt'],
    ),

    const GuideSection(
      id: 'rep-update-status',
      moduleId: 'repairs',
      title: 'Cập nhật trạng thái đơn',
      description: 'Chuyển trạng thái: Đang sửa, Chờ linh kiện, Hoàn thành...',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Tìm đơn cần cập nhật',
          description: 'Từ danh sách Sửa chữa, tìm đơn theo tên khách hoặc mã đơn.',
        ),
        GuideStep(
          order: 2,
          title: 'Mở chi tiết đơn',
          description: 'Nhấn vào đơn để xem chi tiết.',
        ),
        GuideStep(
          order: 3,
          title: 'Đổi trạng thái',
          description: 'Nhấn vào chip trạng thái và chọn trạng thái mới:\n• Đang sửa\n• Chờ linh kiện\n• Đã sửa xong\n• Đã bàn giao',
        ),
        GuideStep(
          order: 4,
          title: 'Ghi chú (nếu cần)',
          description: 'Thêm ghi chú về công việc đã làm, linh kiện đã thay.',
        ),
      ],
      tips: [
        'Khi chuyển sang "Đã sửa xong", hệ thống sẽ tự động gửi thông báo cho khách.',
      ],
    ),

    const GuideSection(
      id: 'rep-handover',
      moduleId: 'repairs',
      title: 'Bàn giao máy cho khách',
      description: 'Quy trình bàn giao và thu tiền khi khách đến lấy máy',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Xác nhận thông tin khách',
          description: 'Yêu cầu khách cho xem phiếu tiếp nhận hoặc CMND/CCCD.',
        ),
        GuideStep(
          order: 2,
          title: 'Kiểm tra máy cùng khách',
          description: 'Bật máy, test các chức năng đã sửa trước mặt khách.',
        ),
        GuideStep(
          order: 3,
          title: 'Thu tiền',
          description: 'Thu tiền sửa chữa theo giá đã báo. Nếu có thay đổi, giải thích rõ.',
        ),
        GuideStep(
          order: 4,
          title: 'Cập nhật trạng thái',
          description: 'Chuyển đơn sang "Đã bàn giao" và ghi nhận số tiền thu được.',
        ),
        GuideStep(
          order: 5,
          title: 'In hóa đơn (tùy chọn)',
          description: 'In hóa đơn VAT nếu khách yêu cầu.',
        ),
      ],
      tips: [
        'Dặn khách thời gian bảo hành và các lưu ý sử dụng.',
      ],
    ),

    // =========================================================================
    // MODULE: CUSTOMERS
    // =========================================================================
    const GuideSection(
      id: 'cust-add',
      moduleId: 'customers',
      title: 'Thêm khách hàng',
      description: 'Lưu thông tin khách hàng vào hệ thống',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Khách hàng',
          description: 'Từ menu hoặc trang chủ, chọn "Khách hàng".',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn Thêm mới',
          description: 'Nhấn nút (+) để thêm khách hàng mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập thông tin',
          description: 'Điền: Tên, SĐT (bắt buộc), Email, Địa chỉ, Ghi chú.',
        ),
        GuideStep(
          order: 4,
          title: 'Lưu',
          description: 'Nhấn "Lưu" để hoàn tất.',
        ),
      ],
      tips: [
        'SĐT là key chính, hệ thống sẽ cảnh báo nếu trùng.',
        'Thêm ghi chú về sở thích, nhu cầu để chăm sóc tốt hơn.',
      ],
    ),

    const GuideSection(
      id: 'cust-history',
      moduleId: 'customers',
      title: 'Xem lịch sử giao dịch',
      description: 'Tra cứu lịch sử mua hàng, sửa chữa của khách',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Tìm khách hàng',
          description: 'Trong danh sách Khách hàng, tìm theo tên hoặc SĐT.',
        ),
        GuideStep(
          order: 2,
          title: 'Xem chi tiết',
          description: 'Nhấn vào khách để xem thông tin chi tiết.',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn tab lịch sử',
          description: 'Chuyển qua các tab: Mua hàng, Sửa chữa, Công nợ để xem từng loại.',
        ),
      ],
    ),

    // =========================================================================
    // MODULE: FINANCE
    // =========================================================================
    const GuideSection(
      id: 'fin-daily',
      moduleId: 'finance',
      title: 'Xem báo cáo ngày',
      description: 'Tổng quan doanh thu, chi phí và lợi nhuận trong ngày',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      isPopular: true,
      targetRoles: ['owner', 'manager'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Tài chính',
          description: 'Từ menu, chọn "Tài chính" hoặc nhấn vào thẻ doanh thu trên Dashboard.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn ngày',
          description: 'Mặc định hiển thị ngày hôm nay. Nhấn vào ngày để chọn ngày khác.',
        ),
        GuideStep(
          order: 3,
          title: 'Xem các chỉ số',
          description: 'Các thẻ hiển thị:\n• Doanh thu: tổng tiền bán hàng + sửa chữa\n• Chi phí: tiền nhập hàng, chi tiêu\n• Lợi nhuận: doanh thu - chi phí',
        ),
        GuideStep(
          order: 4,
          title: 'Xem chi tiết',
          description: 'Nhấn vào từng thẻ để xem danh sách giao dịch chi tiết.',
        ),
      ],
    ),

    const GuideSection(
      id: 'fin-expense',
      moduleId: 'finance',
      title: 'Ghi nhận chi tiêu',
      description: 'Nhập các khoản chi: tiền điện, thuê mặt bằng, lương...',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      targetRoles: ['owner', 'manager'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Tài chính > Chi tiêu',
          description: 'Từ màn hình Tài chính, chọn tab "Chi tiêu".',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn Thêm chi tiêu',
          description: 'Nhấn nút (+) để ghi nhận khoản chi mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn loại chi tiêu',
          description: 'Chọn danh mục: Nhập hàng, Lương, Điện nước, Thuê mặt bằng, Khác...',
        ),
        GuideStep(
          order: 4,
          title: 'Nhập số tiền và mô tả',
          description: 'Điền số tiền, mô tả chi tiết và chọn ngày chi.',
        ),
        GuideStep(
          order: 5,
          title: 'Đính kèm chứng từ (tùy chọn)',
          description: 'Chụp ảnh hóa đơn, biên lai để lưu trữ.',
        ),
        GuideStep(
          order: 6,
          title: 'Lưu',
          description: 'Nhấn "Lưu" để ghi nhận vào sổ.',
        ),
      ],
    ),

    const GuideSection(
      id: 'fin-fund',
      moduleId: 'finance',
      title: 'Quản lý quỹ tiền mặt',
      description: 'Theo dõi tiền mặt trong két, nộp/rút quỹ',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      targetRoles: ['owner', 'manager'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Xem số dư quỹ',
          description: 'Vào Tài chính > Quỹ để xem số tiền mặt hiện có.',
        ),
        GuideStep(
          order: 2,
          title: 'Nộp tiền vào quỹ',
          description: 'Nhấn "Nộp quỹ" khi thu tiền mặt từ bán hàng hoặc thu công nợ.',
        ),
        GuideStep(
          order: 3,
          title: 'Rút tiền từ quỹ',
          description: 'Nhấn "Rút quỹ" khi cần chi tiêu tiền mặt: mua đồ, trả lương...',
        ),
        GuideStep(
          order: 4,
          title: 'Xem lịch sử',
          description: 'Tab "Lịch sử" hiển thị tất cả giao dịch nộp/rút quỹ.',
        ),
      ],
      tips: [
        'Kiểm kê quỹ cuối ngày để đối chiếu với số liệu trên app.',
      ],
    ),

    // =========================================================================
    // MODULE: STAFF
    // =========================================================================
    const GuideSection(
      id: 'staff-add',
      moduleId: 'staff',
      title: 'Thêm nhân viên',
      description: 'Tạo tài khoản cho nhân viên mới',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      targetRoles: ['owner'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Nhân viên',
          description: 'Từ menu, chọn "Quản lý nhân viên".',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn Thêm nhân viên',
          description: 'Nhấn nút (+) để thêm nhân viên mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập thông tin',
          description: 'Điền: Họ tên, SĐT, Email, Ngày sinh, Địa chỉ.',
        ),
        GuideStep(
          order: 4,
          title: 'Chọn vai trò',
          description: 'Chọn vai trò:\n• Kỹ thuật: sửa chữa\n• Thu ngân: bán hàng\n• Quản lý: toàn quyền trừ cài đặt',
        ),
        GuideStep(
          order: 5,
          title: 'Tạo tài khoản đăng nhập',
          description: 'Hệ thống gửi email mời tham gia shop. NV nhấn link để tạo mật khẩu.',
        ),
      ],
      warnings: [
        'Chỉ chủ shop mới có quyền thêm/xóa nhân viên.',
      ],
    ),

    const GuideSection(
      id: 'staff-attendance',
      moduleId: 'staff',
      title: 'Chấm công nhân viên',
      description: 'Ghi nhận giờ làm việc của nhân viên',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      targetRoles: ['owner', 'manager'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Nhân viên > Chấm công',
          description: 'Chọn tab "Chấm công" trong màn hình Nhân viên.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn ngày',
          description: 'Mặc định là ngày hôm nay. Có thể chọn ngày khác để bổ sung.',
        ),
        GuideStep(
          order: 3,
          title: 'Check-in / Check-out',
          description: 'Nhân viên tự nhấn Check-in khi đến và Check-out khi về.\nHoặc quản lý chấm hộ bằng cách chọn NV và nhập giờ.',
        ),
        GuideStep(
          order: 4,
          title: 'Xem báo cáo',
          description: 'Tab "Báo cáo" tổng hợp số giờ làm việc theo tuần/tháng.',
        ),
      ],
    ),

    // =========================================================================
    // MODULE: PRINTING
    // =========================================================================
    const GuideSection(
      id: 'print-connect-bt',
      moduleId: 'printing',
      title: 'Kết nối máy in Bluetooth',
      description: 'Ghép đôi và kết nối máy in nhiệt qua Bluetooth',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Bật Bluetooth trên điện thoại',
          description: 'Vào Cài đặt điện thoại > Bluetooth > Bật.',
        ),
        GuideStep(
          order: 2,
          title: 'Bật máy in',
          description: 'Nhấn nút nguồn trên máy in. Đèn Bluetooth sẽ nhấp nháy.',
        ),
        GuideStep(
          order: 3,
          title: 'Ghép đôi (Pair)',
          description: 'Trong cài đặt Bluetooth điện thoại, tìm và chọn máy in (thường có tên như "Printer", "POS-58"...). Nhấn Pair.',
        ),
        GuideStep(
          order: 4,
          title: 'Kết nối trong app',
          description: 'Vào Shopmanager > Cài đặt > Máy in > Quét máy in Bluetooth.',
        ),
        GuideStep(
          order: 5,
          title: 'Chọn máy in',
          description: 'Chọn máy in từ danh sách thiết bị đã ghép đôi.',
        ),
        GuideStep(
          order: 6,
          title: 'Test in',
          description: 'Nhấn "Test in" để kiểm tra kết nối.',
        ),
      ],
      tips: [
        'Nếu không tìm thấy máy in, thử tắt/bật lại Bluetooth và máy in.',
        'Một số máy in cần nhập mã PIN: thường là 0000 hoặc 1234.',
      ],
      warnings: [
        'Giữ khoảng cách dưới 10m giữa điện thoại và máy in.',
      ],
    ),

    const GuideSection(
      id: 'print-connect-wifi',
      moduleId: 'printing',
      title: 'Kết nối máy in WiFi/LAN',
      description: 'Kết nối máy in qua mạng WiFi hoặc cáp LAN',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Kết nối máy in vào mạng',
          description: 'Cắm cáp LAN vào máy in hoặc cấu hình WiFi trên máy in (xem hướng dẫn của máy in).',
        ),
        GuideStep(
          order: 2,
          title: 'Lấy địa chỉ IP',
          description: 'In trang test trên máy in để xem địa chỉ IP (thường là 192.168.x.x).',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập IP vào app',
          description: 'Vào Shopmanager > Cài đặt > Máy in > Nhập địa chỉ IP máy in.',
        ),
        GuideStep(
          order: 4,
          title: 'Test kết nối',
          description: 'Nhấn "Test kết nối WiFi" để kiểm tra.',
        ),
      ],
      tips: [
        'Điện thoại và máy in phải cùng mạng WiFi.',
        'Cổng mặc định là 9100.',
      ],
    ),

    const GuideSection(
      id: 'print-design-label',
      moduleId: 'printing',
      title: 'Thiết kế mẫu tem',
      description: 'Tùy chỉnh nội dung và cỡ chữ tem sản phẩm',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Cài đặt > Thiết kế tem',
          description: 'Từ màn hình Cài đặt, chọn "Thiết kế tem".',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn loại giấy',
          description: 'Chọn khổ giấy: 80mm (mặc định) hoặc 58mm (tem nhỏ).',
        ),
        GuideStep(
          order: 3,
          title: 'Điều chỉnh cỡ chữ',
          description: 'Kéo thanh trượt để thay đổi cỡ chữ:\n• Nhỏ: dành cho tem nhiều thông tin\n• Trung bình: cân bằng\n• Lớn: dễ đọc từ xa',
        ),
        GuideStep(
          order: 4,
          title: 'Bật/tắt nội dung',
          description: 'Chọn hiển thị: Tên máy, Chi tiết, Giá KPK, Giá CPK, IMEI, Mã QR.',
        ),
        GuideStep(
          order: 5,
          title: 'Thêm nội dung tùy biến',
          description: 'Nhập slogan hoặc thông tin shop muốn in cuối tem.',
        ),
        GuideStep(
          order: 6,
          title: 'Xem trước và lưu',
          description: 'Xem trước mẫu tem và nhấn "Lưu" để áp dụng.',
        ),
      ],
      tips: [
        'Test in 1 tem sau khi thay đổi để kiểm tra kết quả.',
      ],
      relatedSections: ['inv-print-label'],
    ),

    const GuideSection(
      id: 'print-receipt',
      moduleId: 'printing',
      title: 'In hóa đơn/phiếu',
      description: 'In hóa đơn bán hàng, phiếu sửa chữa',
      difficulty: 'Dễ',
      estimatedTime: '2 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Hoàn tất giao dịch',
          description: 'Sau khi lưu hóa đơn bán hàng hoặc phiếu sửa chữa...',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn In',
          description: 'Nhấn nút "In hóa đơn" hoặc "In phiếu" xuất hiện sau khi lưu.',
        ),
        GuideStep(
          order: 3,
          title: 'Chờ in',
          description: 'Máy in sẽ tự động in. Nếu có lỗi, kiểm tra kết nối và giấy.',
        ),
      ],
      tips: [
        'Có thể in lại từ lịch sử giao dịch bất cứ lúc nào.',
      ],
    ),

    // =========================================================================
    // MODULE: SETTINGS
    // =========================================================================
    const GuideSection(
      id: 'set-sync',
      moduleId: 'settings',
      title: 'Đồng bộ dữ liệu',
      description: 'Đồng bộ dữ liệu giữa nhiều thiết bị',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isPopular: true,
      targetRoles: ['owner', 'admin'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Kiểm tra đăng nhập',
          description: 'Đảm bảo tất cả thiết bị đăng nhập cùng tài khoản và chọn cùng shop.',
        ),
        GuideStep(
          order: 2,
          title: 'Vào Cài đặt > Đồng bộ',
          description: 'Xem trạng thái đồng bộ: Đã đồng bộ, Đang đồng bộ, hoặc Lỗi.',
        ),
        GuideStep(
          order: 3,
          title: 'Đồng bộ thủ công',
          description: 'Nhấn "Đồng bộ ngay" để đẩy dữ liệu lên cloud ngay lập tức.',
        ),
        GuideStep(
          order: 4,
          title: 'Tải lại dữ liệu',
          description: 'Nếu máy phụ không nhận dữ liệu, nhấn "Tải lại từ cloud".',
        ),
      ],
      tips: [
        'Dữ liệu tự động đồng bộ khi có kết nối internet.',
        'Nếu offline, dữ liệu sẽ được lưu local và đồng bộ khi có mạng.',
      ],
      warnings: [
        'Không xóa app khi đang có dữ liệu chưa đồng bộ.',
      ],
    ),

    const GuideSection(
      id: 'set-backup',
      moduleId: 'settings',
      title: 'Sao lưu dữ liệu',
      description: 'Tạo bản sao lưu dự phòng dữ liệu shop',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      targetRoles: ['owner'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Cài đặt > Sao lưu',
          description: 'Chọn mục "Sao lưu & Khôi phục".',
        ),
        GuideStep(
          order: 2,
          title: 'Tạo bản sao lưu',
          description: 'Nhấn "Sao lưu ngay" để tạo bản backup mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Chọn vị trí lưu',
          description: 'Chọn lưu vào: Google Drive, thiết bị hoặc gửi qua email.',
        ),
        GuideStep(
          order: 4,
          title: 'Hoàn tất',
          description: 'Chờ quá trình backup hoàn tất. File backup có định dạng .Shopmanager',
        ),
      ],
      tips: [
        'Nên backup định kỳ hàng tuần.',
        'Lưu backup ở nhiều nơi để an toàn.',
      ],
    ),

    const GuideSection(
      id: 'set-shop-info',
      moduleId: 'settings',
      title: 'Cập nhật thông tin shop',
      description: 'Sửa tên shop, địa chỉ, hotline hiển thị trên hóa đơn',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      targetRoles: ['owner'],
      steps: [
        GuideStep(
          order: 1,
          title: 'Vào Cài đặt > Thông tin shop',
          description: 'Chọn mục "Thông tin cửa hàng".',
        ),
        GuideStep(
          order: 2,
          title: 'Cập nhật thông tin',
          description: 'Sửa: Tên shop, Địa chỉ, Hotline, Email, Website.',
        ),
        GuideStep(
          order: 3,
          title: 'Thêm logo',
          description: 'Upload logo shop để in trên hóa đơn.',
        ),
        GuideStep(
          order: 4,
          title: 'Lưu',
          description: 'Nhấn "Lưu" để cập nhật.',
        ),
      ],
    ),

    // =========================================================================
    // MODULE: SUPPLIERS (Quản lý nhà cung cấp)
    // =========================================================================
    const GuideSection(
      id: 'sup-add',
      moduleId: 'suppliers',
      title: 'Thêm nhà cung cấp mới',
      description: 'Hướng dẫn thêm thông tin nhà cung cấp để quản lý nhập hàng và công nợ',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở danh sách NCC',
          description: 'Từ trang tài chính hoặc menu, chọn "Nhà cung cấp" để vào danh sách NCC.',
        ),
        GuideStep(
          order: 2,
          title: 'Nhấn nút Thêm NCC',
          description: 'Nhấn nút "Thêm NCC" ở góc phải dưới màn hình để mở form thêm mới.',
        ),
        GuideStep(
          order: 3,
          title: 'Điền thông tin cơ bản',
          description: 'Nhập tên NCC (bắt buộc), số điện thoại, địa chỉ, email và ghi chú. Thông tin liên hệ giúp liên lạc nhanh khi cần.',
        ),
        GuideStep(
          order: 4,
          title: 'Thêm thông tin ngân hàng',
          description: 'Điền số tài khoản, tên ngân hàng để thanh toán chuyển khoản cho NCC sau này.',
        ),
        GuideStep(
          order: 5,
          title: 'Lưu nhà cung cấp',
          description: 'Nhấn "Lưu" để hoàn tất. NCC sẽ tự động đồng bộ lên cloud và hiện trong danh sách.',
        ),
      ],
      tips: [
        'Nên điền đầy đủ SĐT và tài khoản ngân hàng để thanh toán nhanh khi nhập hàng.',
        'Đánh dấu NCC ưu tiên (★) để dễ tìm khi nhập hàng thường xuyên.',
      ],
      warnings: [
        'Phải tạo NCC trước khi nhập kho để hệ thống tự theo dõi công nợ chính xác.',
      ],
      relatedSections: ['sup-debt', 'inv-add-product'],
    ),
    const GuideSection(
      id: 'sup-debt',
      moduleId: 'suppliers',
      title: 'Theo dõi công nợ NCC',
      description: 'Xem và quản lý công nợ phải trả cho nhà cung cấp',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Xem tổng quan công nợ',
          description: 'Ở đầu danh sách NCC, xem 4 thẻ thống kê: Tổng NCC, Tổng công nợ, NCC còn nợ, và Đã trả trong tháng.',
        ),
        GuideStep(
          order: 2,
          title: 'Lọc NCC còn nợ',
          description: 'Nhấn nút "Còn nợ" để chỉ hiển thị các NCC mà shop đang nợ tiền. Nút "Quá hạn" hiện NCC nợ quá 30 ngày.',
        ),
        GuideStep(
          order: 3,
          title: 'Xem chi tiết công nợ',
          description: 'Nhấn vào thẻ NCC để xem chi tiết: danh sách các đơn nhập hàng, số tiền nợ từng đơn, lịch sử thanh toán.',
        ),
        GuideStep(
          order: 4,
          title: 'Thanh toán công nợ',
          description: 'Trong chi tiết NCC, nhấn "Thanh toán" để ghi nhận trả tiền. Chọn phương thức (tiền mặt/chuyển khoản) và nhập số tiền.',
        ),
        GuideStep(
          order: 5,
          title: 'Kiểm tra sau thanh toán',
          description: 'Số nợ sẽ tự động cập nhật. Nếu trả đủ, trạng thái chuyển thành "Đã tất toán".',
        ),
      ],
      tips: [
        'Sắp xếp "Nợ cao → thấp" để ưu tiên thanh toán NCC nợ nhiều nhất.',
        'Kiểm tra mục "Đã trả trong tháng" để theo dõi chi phí thanh toán NCC hàng tháng.',
      ],
      warnings: [
        'Công nợ NCC được tạo tự động khi nhập kho với phương thức "CÔNG NỢ". Không cần tạo thủ công.',
      ],
      relatedSections: ['sup-add', 'fin-expense'],
    ),
    const GuideSection(
      id: 'sup-history',
      moduleId: 'suppliers',
      title: 'Lịch sử nhập hàng từ NCC',
      description: 'Xem chi tiết các lần nhập hàng và giá trị nhập từ nhà cung cấp',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở chi tiết NCC',
          description: 'Từ danh sách NCC, nhấn vào tên NCC cần xem.',
        ),
        GuideStep(
          order: 2,
          title: 'Xem lịch sử nhập hàng',
          description: 'Cuộn xuống phần "Lịch sử nhập hàng" để xem danh sách tất cả các đơn nhập từ NCC này. Mỗi đơn hiển thị: ngày nhập, sản phẩm, số lượng, tổng tiền.',
        ),
        GuideStep(
          order: 3,
          title: 'Kiểm tra thống kê',
          description: 'Xem tổng giá trị nhập hàng, số đơn nhập, và giá trị trung bình mỗi đơn để đánh giá mức độ hợp tác.',
        ),
      ],
      tips: [
        'So sánh giá nhập giữa các NCC để chọn nguồn hàng tốt nhất.',
      ],
      relatedSections: ['sup-add', 'sup-debt'],
    ),

    // =========================================================================
    // ADDITIONAL: SALES - Combined Payment
    // =========================================================================
    const GuideSection(
      id: 'sales-combined-payment',
      moduleId: 'sales',
      title: 'Thanh toán kết hợp (Tiền mặt + CK)',
      description: 'Hướng dẫn chia thanh toán một đơn hàng bằng cả tiền mặt và chuyển khoản',
      difficulty: 'Trung bình',
      estimatedTime: '3 phút',
      isNew: true,
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Tạo đơn bán hàng',
          description: 'Tạo đơn bán hàng bình thường: thêm sản phẩm, nhập thông tin khách hàng.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn "KẾT HỢP"',
          description: 'Ở phần phương thức thanh toán, nhấn chip "KẾT HỢP" (thay vì Tiền mặt hoặc Chuyển khoản).',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập số tiền mặt',
          description: 'Mở phần "Chi tiết thanh toán kết hợp", nhập số tiền khách trả bằng tiền mặt vào ô "Tiền mặt".',
        ),
        GuideStep(
          order: 4,
          title: 'Nhập số chuyển khoản',
          description: 'Nhập số tiền chuyển khoản vào ô "Chuyển khoản". Tổng tiền mặt + chuyển khoản phải bằng tổng đơn hàng.',
          note: 'Hệ thống tự kiểm tra: nếu tổng không khớp sẽ hiện cảnh báo.',
        ),
        GuideStep(
          order: 5,
          title: 'Xác nhận đơn hàng',
          description: 'Nhấn "Lưu đơn hàng". Hệ thống sẽ tạo 2 giao dịch riêng biệt: 1 tiền mặt + 1 chuyển khoản, để theo dõi chính xác trong sổ quỹ.',
        ),
      ],
      tips: [
        'Ví dụ: Đơn 15 triệu → khách trả 5 triệu tiền mặt + 10 triệu chuyển khoản.',
        'Xem chi tiết đơn hàng sẽ hiển thị rõ ràng số tiền từng phương thức.',
      ],
      warnings: [
        'Tổng tiền mặt + chuyển khoản phải bằng chính xác tổng đơn hàng. Nếu không khớp, đơn sẽ không được lưu.',
      ],
      relatedSections: ['sales-create', 'fin-fund'],
    ),

    // =========================================================================
    // ADDITIONAL: FINANCE - Cash Closing
    // =========================================================================
    const GuideSection(
      id: 'fin-closing',
      moduleId: 'finance',
      title: 'Chốt sổ cuối ngày',
      description: 'Hướng dẫn chốt quỹ tiền mặt cuối ngày để đối soát doanh thu',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isPopular: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở chốt sổ',
          description: 'Từ tab Tài chính, nhấn "Chốt quỹ hôm nay" trong phần Thao tác nhanh.',
        ),
        GuideStep(
          order: 2,
          title: 'Xem tóm tắt ngày',
          description: 'Hệ thống hiển thị: số dư đầu ngày, tổng thu (bán hàng tiền mặt), tổng chi (nhập hàng, chi phí), số dư cuối ngày dự kiến.',
        ),
        GuideStep(
          order: 3,
          title: 'Nhập số tiền thực tế',
          description: 'Đếm tiền mặt trong két và nhập số tiền thực tế. Hệ thống tự tính chênh lệch với số dự kiến.',
        ),
        GuideStep(
          order: 4,
          title: 'Ghi chú chênh lệch',
          description: 'Nếu có chênh lệch, nhập ghi chú giải thích lý do (ví dụ: sai tiền thừa, thiếu tiền lẻ...).',
        ),
        GuideStep(
          order: 5,
          title: 'Xác nhận chốt sổ',
          description: 'Nhấn "Chốt sổ" để hoàn tất. Số dư cuối ngày sẽ là số dư đầu ngày hôm sau.',
        ),
      ],
      tips: [
        'Nên chốt sổ mỗi ngày vào cuối ca để đảm bảo tiền mặt chính xác.',
        'Xem lịch sử chốt sổ để theo dõi xu hướng chênh lệch qua các ngày.',
      ],
      warnings: [
        'Sau khi chốt sổ, các giao dịch tiền mặt trong ngày không nên chỉnh sửa để giữ tính chính xác.',
      ],
      relatedSections: ['fin-daily', 'fin-expense'],
    ),

    // =========================================================================
    // ADDITIONAL: FINANCE - Bank Installment
    // =========================================================================
    const GuideSection(
      id: 'fin-installment',
      moduleId: 'finance',
      title: 'Thống kê trả góp ngân hàng',
      description: 'Theo dõi các đơn bán trả góp qua ngân hàng và tiến độ thanh toán',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở thống kê trả góp',
          description: 'Từ tab Tài chính, nhấn "Trả góp NH" trong phần Báo cáo & Phân tích.',
        ),
        GuideStep(
          order: 2,
          title: 'Xem tổng quan',
          description: 'Xem tổng số đơn trả góp, tổng giá trị, số tiền đã thu và còn lại cần thu từ ngân hàng.',
        ),
        GuideStep(
          order: 3,
          title: 'Lọc theo ngân hàng',
          description: 'Chọn ngân hàng cụ thể (FE, HOME, MIRAE, HD, MB, F83, T86) để xem đơn trả góp của từng NH.',
        ),
        GuideStep(
          order: 4,
          title: 'Xem chi tiết từng đơn',
          description: 'Nhấn vào đơn trả góp để xem: khách hàng, sản phẩm, số tiền góp, ngân hàng, và trạng thái.',
        ),
      ],
      tips: [
        'Kiểm tra thường xuyên để đối soát với bảng kê ngân hàng.',
        'Đơn trả góp được tạo khi chọn phương thức "TRẢ GÓP (NH)" trong đơn bán hàng.',
      ],
      relatedSections: ['sales-create', 'fin-daily'],
    ),

    // =========================================================================
    // ADDITIONAL: STAFF - Permissions
    // =========================================================================
    const GuideSection(
      id: 'staff-permissions',
      moduleId: 'staff',
      title: 'Phân quyền nhân viên',
      description: 'Hướng dẫn thiết lập quyền truy cập cho từng nhân viên',
      difficulty: 'Trung bình',
      estimatedTime: '5 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở danh sách nhân viên',
          description: 'Từ tab Nhân sự, xem danh sách tất cả nhân viên trong shop.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn nhân viên cần phân quyền',
          description: 'Nhấn vào tên nhân viên → chọn "Phân quyền" hoặc biểu tượng khóa.',
        ),
        GuideStep(
          order: 3,
          title: 'Bật/tắt từng quyền',
          description: 'Bật các quyền cần thiết: xem kho, tạo đơn bán, xem tài chính, quản lý nhân viên, xem NCC, xem báo cáo...',
          note: 'Mỗi quyền có mô tả chi tiết kèm theo.',
        ),
        GuideStep(
          order: 4,
          title: 'Lưu thay đổi',
          description: 'Nhấn "Lưu" để áp dụng. Nhân viên cần thoát và đăng nhập lại để quyền mới có hiệu lực.',
        ),
      ],
      tips: [
        'Nhân viên bán hàng chỉ cần bật: Tạo đơn bán, Xem kho. Không cần bật xem tài chính.',
        'Chủ shop (owner) luôn có đầy đủ quyền, không thể bị giới hạn.',
      ],
      warnings: [
        'Cẩn thận khi tắt quyền "Quản lý nhân viên" — nhân viên đó sẽ không thể thay đổi thông tin nhân viên khác.',
      ],
      relatedSections: ['staff-add', 'staff-attendance'],
    ),

    // =========================================================================
    // ADDITIONAL: STAFF - Payroll
    // =========================================================================
    const GuideSection(
      id: 'staff-payroll',
      moduleId: 'staff',
      title: 'Quản lý lương & hoa hồng',
      description: 'Thiết lập mức lương cơ bản, tỷ lệ hoa hồng và xem bảng lương',
      difficulty: 'Nâng cao',
      estimatedTime: '10 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở cài đặt lương',
          description: 'Từ tab Nhân sự → nhấn biểu tượng cài đặt lương (⚙) hoặc "Cài đặt lương" trong menu.',
        ),
        GuideStep(
          order: 2,
          title: 'Thiết lập lương cơ bản',
          description: 'Nhập mức lương cơ bản cho từng nhân viên hoặc theo chức vụ. Lương tính theo tháng.',
        ),
        GuideStep(
          order: 3,
          title: 'Cài đặt hoa hồng',
          description: 'Thiết lập tỷ lệ hoa hồng (%) trên doanh số bán hàng. Có thể cài riêng cho từng nhân viên.',
        ),
        GuideStep(
          order: 4,
          title: 'Xem bảng lương',
          description: 'Vào "Bảng lương" để xem tổng lương tháng = Lương cơ bản + Hoa hồng + Phụ cấp - Khấu trừ (nghỉ, phạt...).',
        ),
        GuideStep(
          order: 5,
          title: 'In phiếu lương',
          description: 'Nhấn "In phiếu lương" để xuất PDF chi tiết cho từng nhân viên.',
        ),
      ],
      tips: [
        'Hoa hồng tự động tính dựa trên đơn bán hàng đã hoàn thành.',
        'Kiểm tra chấm công trước khi chốt lương để đảm bảo chính xác.',
      ],
      warnings: [
        'Không chỉnh sửa lương sau khi đã "Khóa bảng lương" tháng đó.',
      ],
      relatedSections: ['staff-add', 'staff-attendance'],
    ),

    // =========================================================================
    // ADDITIONAL: SETTINGS - Multi-shop
    // =========================================================================
    const GuideSection(
      id: 'set-multi-shop',
      moduleId: 'settings',
      title: 'Quản lý nhiều cửa hàng',
      description: 'Hướng dẫn tạo và chuyển đổi giữa nhiều shop trên cùng tài khoản',
      difficulty: 'Nâng cao',
      estimatedTime: '5 phút',
      isNew: true,
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở chuyển shop',
          description: 'Nhấn vào tên shop ở góc trên trang chủ hoặc vào Cài đặt → "Chuyển shop".',
        ),
        GuideStep(
          order: 2,
          title: 'Tạo shop mới',
          description: 'Nhấn "Tạo shop mới" → nhập tên shop, địa chỉ, SĐT. Chọn ngành nghề (điện tử, thời trang, thực phẩm, tổng hợp).',
        ),
        GuideStep(
          order: 3,
          title: 'Chuyển giữa các shop',
          description: 'Sau khi tạo, nhấn vào tên shop trong danh sách để chuyển đổi. Dữ liệu mỗi shop hoàn toàn riêng biệt.',
        ),
        GuideStep(
          order: 4,
          title: 'Mời nhân viên vào shop',
          description: 'Ở shop mới, thêm nhân viên bằng email. Nhân viên có thể thuộc nhiều shop khác nhau.',
        ),
      ],
      tips: [
        'Mỗi shop có dữ liệu riêng: sản phẩm, đơn hàng, nhân viên, tài chính đều tách biệt.',
        'Chủ shop có thể vào Cài đặt để xóa shop không dùng nữa.',
      ],
      relatedSections: ['set-shop-info', 'set-business-type'],
    ),
    const GuideSection(
      id: 'set-business-type',
      moduleId: 'settings',
      title: 'Chọn ngành nghề kinh doanh',
      description: 'Thiết lập loại hình kinh doanh để tùy chỉnh giao diện và tính năng phù hợp',
      difficulty: 'Dễ',
      estimatedTime: '3 phút',
      steps: [
        GuideStep(
          order: 1,
          title: 'Mở cài đặt ngành nghề',
          description: 'Khi tạo shop mới hoặc vào Cài đặt → "Ngành nghề", chọn loại hình kinh doanh.',
        ),
        GuideStep(
          order: 2,
          title: 'Chọn ngành nghề',
          description: 'Chọn 1 trong 4 loại: Điện tử (sửa chữa + bảo hành), Thời trang (size + biến thể), Thực phẩm (hạn sử dụng), Tổng hợp.',
        ),
        GuideStep(
          order: 3,
          title: 'Xem tính năng',
          description: 'Hệ thống tự bật/tắt tính năng phù hợp. VD: shop thời trang sẽ ẩn tab Sửa chữa, Bảo hành và hiện quản lý Size/Biến thể.',
        ),
        GuideStep(
          order: 4,
          title: 'Xác nhận',
          description: 'Nhấn "Lưu" để áp dụng. Giao diện sẽ tự động cập nhật theo ngành nghề đã chọn.',
        ),
      ],
      tips: [
        'Có thể đổi ngành nghề bất cứ lúc nào. Dữ liệu cũ vẫn được giữ nguyên.',
        'Mỗi ngành có danh mục sản phẩm mặc định riêng.',
      ],
      relatedSections: ['set-multi-shop', 'set-shop-info'],
    ),
  ];

  // ---------------------------------------------------------------------------
  // HELPER METHODS
  // ---------------------------------------------------------------------------

  static List<GuideModule> getModules({String? userRole}) {
    if (userRole == null || userRole == 'all' || userRole == 'owner') {
      return modules;
    }
    return modules.where((m) {
      return m.targetRoles.contains('all') || m.targetRoles.contains(userRole);
    }).toList();
  }

  static List<GuideSection> getSectionsByModule(String moduleId, {String? userRole}) {
    return sections.where((s) {
      final matchModule = s.moduleId == moduleId;
      final matchRole = userRole == null || userRole == 'all' || userRole == 'owner'
          ? true
          : s.targetRoles.contains('all') || s.targetRoles.contains(userRole);
      return matchModule && matchRole;
    }).toList();
  }

  static List<GuideSection> searchSections(String query, {String? userRole}) {
    final lower = query.toLowerCase().trim();
    if (lower.isEmpty) return [];

    return sections.where((s) {
      final matchRole = userRole == null || userRole == 'all' || userRole == 'owner'
          ? true
          : s.targetRoles.contains('all') || s.targetRoles.contains(userRole);
      if (!matchRole) return false;

      final haystack = '${s.title} ${s.description} ${s.steps.map((st) => '${st.title} ${st.description}').join(' ')}'.toLowerCase();
      return haystack.contains(lower);
    }).toList();
  }

  static List<GuideSection> getPopularSections({String? userRole}) {
    return sections.where((s) {
      final matchRole = userRole == null || userRole == 'all' || userRole == 'owner'
          ? true
          : s.targetRoles.contains('all') || s.targetRoles.contains(userRole);
      return s.isPopular && matchRole;
    }).toList();
  }

  static List<GuideSection> getNewSections({String? userRole}) {
    return sections.where((s) {
      final matchRole = userRole == null || userRole == 'all' || userRole == 'owner'
          ? true
          : s.targetRoles.contains('all') || s.targetRoles.contains(userRole);
      return s.isNew && matchRole;
    }).toList();
  }

  static GuideModule? findModule(String id) {
    try {
      return modules.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  static GuideSection? findSection(String id) {
    try {
      return sections.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<GuideSection> getRelatedSections(GuideSection section) {
    if (section.relatedSections.isEmpty) return [];
    return sections.where((s) => section.relatedSections.contains(s.id)).toList();
  }
}
