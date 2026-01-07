import 'package:flutter/material.dart';

/// Bộ màu thống nhất cho toàn bộ ứng dụng
/// Định nghĩa tất cả màu sắc được sử dụng trong app
class AppColors {
  // Private constructor để ngăn tạo instance
  AppColors._();

  // ========== PRIMARY COLORS ==========
  /// Màu chính của app - Tím
  static const Color primary = Color.fromARGB(255, 77, 142, 233); // Purple 700

  /// Màu chính nhạt hơn
  static const Color primaryLight = Color(0xFFBA68C8); // Purple 300

  /// Màu chính tối hơn
  static const Color primaryDark = Color(0xFF6A1B9A); // Purple 800

  /// Màu phụ - Cam
  static const Color secondary = Color(0xFFFF9800); // Orange 500

  /// Màu phụ nhạt hơn
  static const Color secondaryLight = Color(0xFFFFB74D); // Orange 300

  /// Màu phụ tối hơn
  static const Color secondaryDark = Color(0xFFF57C00); // Orange 700

  // ========== SURFACE COLORS ==========
  /// Màu nền chính
  static const Color background = Color(0xFFF8FAFF);

  /// Màu bề mặt (card, dialog, etc.)
  static const Color surface = Colors.white;

  /// Màu bóng đổ
  static const Color shadow = Color(0x1F000000);

  /// Màu đường kẻ phân cách
  static const Color divider = Color(0xFFE0E0E0);

  /// Màu viền outline
  static const Color outline = Color(0xFFE0E0E0);

  // ========== TEXT COLORS ==========
  /// Màu chữ trên primary color
  static const Color onPrimary = Colors.white;

  /// Màu chữ trên secondary color
  static const Color onSecondary = Colors.white;

  /// Màu chữ trên surface
  static const Color onSurface = Color(0xFF1C1B1F);

  /// Màu chữ trên background
  static const Color onBackground = Color(0xFF1C1B1F);

  // ========== SEMANTIC COLORS ==========
  /// Màu lỗi
  static const Color error = Color(0xFFD32F2F); // Red 700

  /// Màu chữ trên error
  static const Color onError = Colors.white;

  /// Màu thành công
  static const Color success = Color(0xFF388E3C); // Green 700

  /// Màu chữ trên success
  static const Color onSuccess = Colors.white;

  /// Màu cảnh báo
  static const Color warning = Color(0xFFF57C00); // Orange 700

  /// Màu chữ trên warning
  static const Color onWarning = Colors.white;

  /// Màu thông tin
  static const Color info = Color(0xFF9C27B0); // Purple 500

  /// Màu chữ trên info
  static const Color onInfo = Colors.white;

  // ========== STATUS COLORS ==========
  /// Màu trạng thái active
  static const Color active = Color(0xFF4CAF50); // Green 500

  /// Màu trạng thái inactive
  static const Color inactive = Color(0xFF9E9E9E); // Grey 500

  /// Màu trạng thái pending
  static const Color pending = Color(0xFFFF9800); // Orange 500

  /// Màu trạng thái completed
  static const Color completed = Color(0xFF4CAF50); // Green 500

  /// Màu trạng thái cancelled
  static const Color cancelled = Color(0xFFF44336); // Red 500

  // ========== GREY SCALE ==========
  /// Grey 50
  static const Color grey50 = Color(0xFFFAFAFA);

  /// Grey 100
  static const Color grey100 = Color(0xFFF5F5F5);

  /// Grey 200
  static const Color grey200 = Color(0xFFEEEEEE);

  /// Grey 300
  static const Color grey300 = Color(0xFFE0E0E0);

  /// Grey 400
  static const Color grey400 = Color(0xFFBDBDBD);

  /// Grey 500
  static const Color grey500 = Color(0xFF9E9E9E);

  /// Grey 600
  static const Color grey600 = Color(0xFF757575);

  /// Grey 700
  static const Color grey700 = Color(0xFF616161);

  /// Grey 800
  static const Color grey800 = Color(0xFF424242);

  /// Grey 900
  static const Color grey900 = Color(0xFF212121);

  // ========== SPECIAL COLORS ==========
  /// Màu cho border focus
  static const Color focusBorder = Color(0xFF7B1FA2);

  /// Màu cho hover state
  static const Color hover = Color(0x1F7B1FA2);

  /// Màu cho ripple effect
  static const Color ripple = Color(0x337B1FA2);

  // ========== UTILITY METHODS ==========
  /// Tạo màu với opacity
  static Color withOpacity(Color color, double opacity) {
    return color.withOpacity(opacity);
  }

  /// Blend 2 màu
  static Color blend(Color color1, Color color2, double ratio) {
    return Color.lerp(color1, color2, ratio)!;
  }

  /// Tạo gradient từ primary colors
  static LinearGradient primaryGradient = const LinearGradient(
    colors: [Color.fromARGB(255, 221, 233, 4), primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Tạo gradient từ secondary colors
  static LinearGradient secondaryGradient = const LinearGradient(
    colors: [secondary, secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}