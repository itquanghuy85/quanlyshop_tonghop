import 'package:flutter/material.dart';

/// Data models for in-app help center.
class HelpCategory {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<String> audience; // Role codes that should see this category

  const HelpCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.audience = const ['all'],
  });
}

class HelpTopic {
  final String id;
  final String categoryId;
  final String title;
  final String summary;
  final List<String> steps;
  final List<String> tips;
  final List<String> tags;
  final List<String> audience;
  final String difficulty;
  final String? estimatedTime;
  final List<String> prerequisites;
  final List<String> resources;
  final List<String> relatedTopicIds;
  final bool isFeatured;
  final String? videoUrl;

  const HelpTopic({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.summary,
    required this.steps,
    this.tips = const [],
    this.tags = const [],
    this.audience = const ['all'],
    this.difficulty = 'Cơ bản',
    this.estimatedTime,
    this.prerequisites = const [],
    this.resources = const [],
    this.relatedTopicIds = const [],
    this.isFeatured = false,
    this.videoUrl,
  });
}

/// Static repository for help content. This can later be moved to Firestore.
class HelpCenterRepository {
  static final List<HelpCategory> categories = [
    HelpCategory(
      id: 'inventory',
      title: 'Quản lý kho',
      description: 'Nhập hàng, kiểm kho, in tem và đồng bộ số lượng giữa các thiết bị.',
      icon: Icons.inventory_2,
      audience: const ['all'],
    ),
    HelpCategory(
      id: 'repairs',
      title: 'Đơn sửa chữa',
      description: 'Quy trình tạo đơn, cập nhật trạng thái, bàn giao và hạch toán đơn sửa chữa.',
      icon: Icons.build_circle,
      audience: const ['technician', 'manager', 'owner'],
    ),
    HelpCategory(
      id: 'sales',
      title: 'Bán hàng và công nợ',
      description: 'Tạo hóa đơn bán lẻ, thu công nợ, in phiếu và xem báo cáo doanh thu.',
      icon: Icons.point_of_sale,
      audience: const ['manager', 'owner', 'cashier'],
    ),
    HelpCategory(
      id: 'finance',
      title: 'Tài chính & báo cáo',
      description: 'Tổng quan lời lỗ, dòng tiền, quỹ và nhật ký chi tiêu.',
      icon: Icons.analytics_outlined,
      audience: const ['owner', 'manager'],
    ),
    HelpCategory(
      id: 'setup',
      title: 'Thiết lập hệ thống',
      description: 'Tài khoản, phân quyền, đồng bộ dữ liệu và sao lưu.',
      icon: Icons.settings_suggest,
      audience: const ['owner', 'admin'],
    ),
  ];

  static final List<HelpTopic> topics = [
    HelpTopic(
      id: 'inventory-fast-check',
      categoryId: 'inventory',
      title: 'Kiểm kho nhanh bằng QR',
      summary: 'Chuẩn bị thiết bị, in tem và quét mã để kiểm tra tồn kho.',
      steps: const [
        'Vào Kho > Kiểm kho nhanh và chọn khu vực cần kiểm.',
        'In tem QR nếu sản phẩm chưa có mã bằng nút In tem trong chi tiết sản phẩm.',
        'Nhấn Bắt đầu quét và đưa camera vào mã (hỗ trợ mã ngắn 4-5 số hoặc IMEI).',
        'Quan sát checklist bên phải: hàng thiếu sẽ được đánh dấu đỏ.',
        'Sau khi hoàn tất, nhấn Xuất báo cáo để lưu kết quả.',
      ],
      tips: const [
        'Có thể bật âm thanh và rung để phản hồi mỗi khi mã được quét.',
        'Nếu thiếu ánh sáng, bật đèn flash ngay trong màn hình quét.',
      ],
      tags: const ['qr', 'inventory', 'scan'],
      audience: const ['all'],
      difficulty: 'Cơ bản',
      estimatedTime: '5 phút',
      prerequisites: const [
        'Máy có camera hoạt động tốt',
        'Đã dán tem QR cho sản phẩm',
      ],
      resources: const [
        'Video demo thao tác trên kho mẫu',
        'Checklist kiểm kho chuẩn PDF',
      ],
      relatedTopicIds: const ['inventory-print-label', 'setup-sync-data'],
      isFeatured: true,
      videoUrl: 'https://youtu.be/dummy-fast-check',
    ),
    HelpTopic(
      id: 'inventory-print-label',
      categoryId: 'inventory',
      title: 'In tem sản phẩm',
      summary: 'Tạo tem QR với giá bán, bảo hành và mã sản phẩm.',
      steps: const [
        'Từ màn hình Kho, chọn sản phẩm và nhấn nút In tem.',
        'Chọn mẫu tem phù hợp (Kiểm kho, Bán hàng, Khuyến mãi, Bảo hành).',
        'Điền số lượng cần in, xem trước nội dung tem.',
        'Nếu cần tùy chỉnh, mở mục "Tùy chỉnh nội dung tem" để bật/tắt các trường.',
        'Kết nối máy in bluetooth và nhấn In.',
      ],
      tips: const [
        'Tem kiểm kho dùng mã "check_product:" nên có thể quét lại trong tính năng Kiểm kho.',
        'Giá CPK có thể cấu hình trong phần Cài đặt tem để tự động tính theo hệ số.',
      ],
      tags: const ['label', 'printing'],
      audience: const ['all'],
      difficulty: 'Trung bình',
      estimatedTime: '7 phút',
      prerequisites: const [
        'Máy in nhiệt bluetooth đã ghép đôi',
        'Đã thiết lập mẫu tem trong phần Thiết kế tem',
      ],
      resources: const [
        'Tài liệu hướng dẫn cài đặt máy in SUNMI',
        'Template Excel nhập nhanh dữ liệu tem',
      ],
      relatedTopicIds: const ['inventory-fast-check', 'sales-create-invoice'],
      isFeatured: true,
    ),
    HelpTopic(
      id: 'repairs-create-order',
      categoryId: 'repairs',
      title: 'Tạo đơn sửa mới',
      summary: 'Lập đơn nhận máy, ghi nhận tình trạng và phụ tùng dự kiến.',
      steps: const [
        'Vào tab Sửa chữa > nhấn dấu + để tạo đơn mới.',
        'Nhập thông tin khách hàng, thiết bị, tình trạng ban đầu và ghi chú hẹn.',
        'Chọn nhân viên kỹ thuật phụ trách và tải ảnh biên bản nếu có.',
        'Lưu đơn để hệ thống cấp mã và đưa vào danh sách chờ sửa.',
      ],
      tips: const [
        'Có thể quét QR/IMEI để tự động điền thông tin thiết bị.',
        'Khi hoàn tất sửa chữa, chuyển trạng thái để kích hoạt thông báo cho khách.',
      ],
      tags: const ['repair', 'order'],
      audience: const ['technician', 'manager'],
      difficulty: 'Cơ bản',
      estimatedTime: '4 phút',
      prerequisites: const [
        'Đã bật đồng bộ khách hàng với Cloud',
      ],
      resources: const [
        'Biểu mẫu biên nhận bàn giao PDF',
      ],
      relatedTopicIds: const ['setup-sync-data'],
      isFeatured: true,
    ),
    HelpTopic(
      id: 'sales-create-invoice',
      categoryId: 'sales',
      title: 'Tạo hóa đơn bán lẻ',
      summary: 'Chọn hàng hóa, phụ kiện và in hóa đơn bán hàng.',
      steps: const [
        'Vào tab Bán hàng > nhấn nút Tạo hóa đơn.',
        'Tìm sản phẩm bằng tên, mã, IMEI hoặc quét QR.',
        'Chọn số lượng, giá bán và ghi chú bảo hành nếu cần.',
        'Nhập thông tin khách hàng và hình thức thanh toán.',
        'Hoàn tất để lưu hóa đơn, có thể in tem và gửi hóa đơn qua Zalo/SMS.',
      ],
      tips: const [
        'Sử dụng công nợ khi khách thanh toán một phần và cần theo dõi thu sau.',
        'Sau khi bán có thể tự động trừ tồn kho nếu sản phẩm được liên kết kho.',
      ],
      tags: const ['sales', 'invoice'],
      audience: const ['cashier', 'manager'],
      difficulty: 'Trung bình',
      estimatedTime: '6 phút',
      prerequisites: const [
        'Đã liên kết máy in hóa đơn',
      ],
      resources: const [
        'Video thao tác tạo hóa đơn trên Android',
        'Checklist thu ngân ca tối',
      ],
      relatedTopicIds: const ['inventory-print-label'],
      isFeatured: false,
    ),
    HelpTopic(
      id: 'setup-sync-data',
      categoryId: 'setup',
      title: 'Đồng bộ dữ liệu giữa nhiều máy',
      summary: 'Kiểm tra trạng thái sync và xử lý khi bị treo.',
      steps: const [
        'Ở tab Cài đặt, kiểm tra mục Đồng bộ xem đã đăng nhập cùng Shop chưa.',
        'Nhấn "Đồng bộ ngay" để đẩy dữ liệu lên cloud.',
        'Nếu máy phụ không lên dữ liệu, vào mục "Tải lại dữ liệu từ cloud".',
        'Đảm bảo kết nối internet ổn định trong suốt quá trình sync.',
      ],
      tips: const [
        'Super admin có thể đổi sang shop khác bằng nút "Chọn shop khác".',
        'Kiểm tra nhật ký sync trong SYNC_SYSTEM_GUIDE.md nếu cần debug sâu.',
      ],
      tags: const ['sync', 'cloud'],
      audience: const ['owner', 'admin', 'manager'],
      difficulty: 'Nâng cao',
      estimatedTime: '10 phút',
      prerequisites: const [
        'Đã đăng nhập cùng tài khoản trên các thiết bị',
        'Kết nối internet ổn định',
      ],
      resources: const [
        'Bảng kiểm tra sự cố đồng bộ',
        'Video hướng dẫn đồng bộ lần đầu',
      ],
      relatedTopicIds: const ['inventory-fast-check'],
      isFeatured: true,
    ),
  ];

  static List<HelpTopic> searchTopics(String query, {String? audience}) {
    final lower = query.trim().toLowerCase();
    return topics.where((topic) {
      final matchesAudience = audience == null || audience == 'all'
          ? true
          : topic.audience.contains('all') || topic.audience.contains(audience);
      if (!matchesAudience) return false;
      if (lower.isEmpty) return true;
      final haystack = (
        topic.title +
        topic.summary +
        topic.steps.join(' ') +
        topic.tips.join(' ') +
        topic.tags.join(' ')
      ).toLowerCase();
      return haystack.contains(lower);
    }).toList();
  }

  static List<HelpTopic> topicsByCategory(String categoryId, {String? audience}) {
    return topics.where((topic) {
      final matchesCategory = topic.categoryId == categoryId;
      final matchesAudience = audience == null || audience == 'all'
          ? true
          : topic.audience.contains('all') || topic.audience.contains(audience);
      return matchesCategory && matchesAudience;
    }).toList();
  }

  static List<HelpTopic> featuredTopics({String? audience}) {
    return topics.where((topic) {
      final matchesAudience = audience == null || audience == 'all'
          ? true
          : topic.audience.contains('all') || topic.audience.contains(audience);
      return topic.isFeatured && matchesAudience;
    }).toList();
  }

  static List<HelpTopic> relatedTopics(HelpTopic topic, {String? audience}) {
    if (topic.relatedTopicIds.isEmpty) return const [];
    final allowedAudience = audience ?? 'all';
    return topics.where((candidate) {
      if (candidate.id == topic.id) return false;
      if (!topic.relatedTopicIds.contains(candidate.id)) return false;
      if (allowedAudience == 'all') return true;
      return candidate.audience.contains('all') ||
          candidate.audience.contains(allowedAudience);
    }).toList();
  }

  static HelpCategory? findCategory(String id) {
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
