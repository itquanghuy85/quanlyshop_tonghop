import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// Button styles thống nhất cho toàn bộ ứng dụng
/// Định nghĩa tất cả button styles được sử dụng trong app
class AppButtonStyles {
  // Private constructor để ngăn tạo instance
  AppButtonStyles._();

  // ========== DIMENSIONS ==========
  /// Chiều cao button chính
  static const double buttonHeight = 48.0;

  /// Chiều cao button nhỏ
  static const double smallButtonHeight = 36.0;

  /// Chiều cao button lớn
  static const double largeButtonHeight = 56.0;

  /// Border radius cho button
  static const double borderRadius = 8.0;

  /// Border radius nhỏ
  static const double smallBorderRadius = 6.0;

  /// Border radius lớn
  static const double largeBorderRadius = 12.0;

  /// Padding ngang cho button
  static const double horizontalPadding = 16.0;

  /// Padding dọc cho button
  static const double verticalPadding = 12.0;

  // ========== ELEVATED BUTTON ==========
  /// Style cho ElevatedButton chính
  static ButtonStyle get elevatedButtonStyle {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      elevation: 2,
      shadowColor: AppColors.shadow,
      minimumSize: const Size(double.infinity, buttonHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      textStyle: AppTextStyles.button,
    ).copyWith(
      // Hover state
      overlayColor: WidgetStateProperty.all(
        AppColors.onPrimary.withOpacity(0.1),
      ),
      // Disabled state
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey400;
        }
        return AppColors.primary;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.onPrimary;
      }),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return 0;
        }
        if (states.contains(WidgetState.hovered)) {
          return 4;
        }
        if (states.contains(WidgetState.pressed)) {
          return 1;
        }
        return 2;
      }),
    );
  }

  /// Style cho ElevatedButton nhỏ
  static ButtonStyle get smallElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      minimumSize: WidgetStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: WidgetStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 12),
      ),
    );
  }

  /// Style cho ElevatedButton lớn
  static ButtonStyle get largeElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      minimumSize: WidgetStateProperty.all(
        const Size(double.infinity, largeButtonHeight),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
      ),
      textStyle: WidgetStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 16),
      ),
    );
  }

  /// Style cho ElevatedButton secondary
  static ButtonStyle get secondaryElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: WidgetStateProperty.all(AppColors.secondary),
      foregroundColor: WidgetStateProperty.all(AppColors.onSecondary),
    );
  }

  /// Style cho ElevatedButton success
  static ButtonStyle get successElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: WidgetStateProperty.all(AppColors.success),
      foregroundColor: WidgetStateProperty.all(Colors.white),
    );
  }

  /// Style cho ElevatedButton warning
  static ButtonStyle get warningElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: WidgetStateProperty.all(AppColors.warning),
      foregroundColor: WidgetStateProperty.all(Colors.white),
    );
  }

  /// Style cho ElevatedButton error
  static ButtonStyle get errorElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: WidgetStateProperty.all(AppColors.error),
      foregroundColor: WidgetStateProperty.all(AppColors.onError),
    );
  }

  // ========== OUTLINED BUTTON ==========
  /// Style cho OutlinedButton chính
  static ButtonStyle get outlinedButtonStyle {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: Colors.transparent,
      side: const BorderSide(color: AppColors.primary, width: 1.5),
      minimumSize: const Size(double.infinity, buttonHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      textStyle: AppTextStyles.button.copyWith(
        color: AppColors.primary,
      ),
    ).copyWith(
      // Hover state
      overlayColor: WidgetStateProperty.all(
        AppColors.primary.withOpacity(0.1),
      ),
      // Disabled state
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const BorderSide(color: AppColors.grey400, width: 1);
        }
        return const BorderSide(color: AppColors.primary, width: 1.5);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.primary;
      }),
    );
  }

  /// Style cho OutlinedButton nhỏ
  static ButtonStyle get smallOutlinedButtonStyle {
    return outlinedButtonStyle.copyWith(
      minimumSize: WidgetStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: WidgetStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 12, color: AppColors.primary),
      ),
    );
  }

  // ========== TEXT BUTTON ==========
  /// Style cho TextButton chính
  static ButtonStyle get textButtonStyle {
    return TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: Colors.transparent,
      minimumSize: const Size(0, buttonHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      textStyle: AppTextStyles.button.copyWith(
        color: AppColors.primary,
      ),
    ).copyWith(
      // Hover state
      overlayColor: WidgetStateProperty.all(
        AppColors.primary.withOpacity(0.1),
      ),
      // Disabled state
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.primary;
      }),
    );
  }

  /// Style cho TextButton nhỏ
  static ButtonStyle get smallTextButtonStyle {
    return textButtonStyle.copyWith(
      minimumSize: WidgetStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: WidgetStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 12, color: AppColors.primary),
      ),
    );
  }

  // ========== ICON BUTTON ==========
  /// Style cho IconButton
  static ButtonStyle get iconButtonStyle {
    return IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.onSurface,
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(40, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(smallBorderRadius),
      ),
    ).copyWith(
      // Hover state
      overlayColor: WidgetStateProperty.all(
        AppColors.onSurface.withOpacity(0.1),
      ),
    );
  }

  /// Style cho IconButton có background
  static ButtonStyle get filledIconButtonStyle {
    return IconButton.styleFrom(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.onSurface,
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(40, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(smallBorderRadius),
      ),
      elevation: 1,
      shadowColor: AppColors.shadow,
    ).copyWith(
      // Hover state
      overlayColor: WidgetStateProperty.all(
        AppColors.onSurface.withOpacity(0.1),
      ),
    );
  }

  // ========== FAB (FLOATING ACTION BUTTON) ==========
  /// Style cho FloatingActionButton
  static ButtonStyle get fabStyle {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.all(AppColors.secondary),
      foregroundColor: WidgetStateProperty.all(AppColors.onSecondary),
    );
  }

  /// Compact FAB decoration - for use with FloatingActionButton.extended
  /// Returns a map containing recommended properties
  static Map<String, dynamic> compactFabProps({
    required Color backgroundColor,
    Color? foregroundColor,
    IconData? icon,
    String? label,
  }) {
    return {
      'backgroundColor': backgroundColor,
      'foregroundColor': foregroundColor ?? Colors.white,
      'elevation': 4.0,
      'highlightElevation': 8.0,
      'shape': RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      'extendedPadding': const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      'extendedIconLabelSpacing': 6.0,
      'extendedTextStyle': const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    };
  }

  /// Compact action button style for list items
  static ButtonStyle get compactActionButtonStyle {
    return ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      textStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Mini FAB style for compact spaces
  static ButtonStyle get miniFabStyle {
    return ElevatedButton.styleFrom(
      elevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      textStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // ========== CHIP BUTTON ==========
  /// Style cho ActionChip
  static ButtonStyle get chipButtonStyle {
    return TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      textStyle: AppTextStyles.caption.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ========== UTILITY METHODS ==========

  /// Tạo button style với màu tùy chỉnh
  static ButtonStyle withColor(ButtonStyle style, Color backgroundColor, Color foregroundColor) {
    return style.copyWith(
      backgroundColor: WidgetStateProperty.all(backgroundColor),
      foregroundColor: WidgetStateProperty.all(foregroundColor),
    );
  }

  /// Tạo button style với size tùy chỉnh
  static ButtonStyle withSize(ButtonStyle style, double height, double? width) {
    return style.copyWith(
      minimumSize: WidgetStateProperty.all(
        Size(width ?? double.infinity, height),
      ),
    );
  }

  /// Tạo button style với border radius tùy chỉnh
  static ButtonStyle withBorderRadius(ButtonStyle style, double radius) {
    return style.copyWith(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}