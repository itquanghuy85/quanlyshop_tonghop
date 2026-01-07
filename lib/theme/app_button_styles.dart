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
      overlayColor: MaterialStateProperty.all(
        AppColors.onPrimary.withOpacity(0.1),
      ),
      // Disabled state
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return AppColors.grey400;
        }
        return AppColors.primary;
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.onPrimary;
      }),
      elevation: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return 0;
        }
        if (states.contains(MaterialState.hovered)) {
          return 4;
        }
        if (states.contains(MaterialState.pressed)) {
          return 1;
        }
        return 2;
      }),
    );
  }

  /// Style cho ElevatedButton nhỏ
  static ButtonStyle get smallElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      minimumSize: MaterialStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: MaterialStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 12),
      ),
    );
  }

  /// Style cho ElevatedButton lớn
  static ButtonStyle get largeElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      minimumSize: MaterialStateProperty.all(
        const Size(double.infinity, largeButtonHeight),
      ),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
      ),
      textStyle: MaterialStateProperty.all(
        AppTextStyles.button.copyWith(fontSize: 16),
      ),
    );
  }

  /// Style cho ElevatedButton secondary
  static ButtonStyle get secondaryElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: MaterialStateProperty.all(AppColors.secondary),
      foregroundColor: MaterialStateProperty.all(AppColors.onSecondary),
    );
  }

  /// Style cho ElevatedButton success
  static ButtonStyle get successElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: MaterialStateProperty.all(AppColors.success),
      foregroundColor: MaterialStateProperty.all(Colors.white),
    );
  }

  /// Style cho ElevatedButton warning
  static ButtonStyle get warningElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: MaterialStateProperty.all(AppColors.warning),
      foregroundColor: MaterialStateProperty.all(Colors.white),
    );
  }

  /// Style cho ElevatedButton error
  static ButtonStyle get errorElevatedButtonStyle {
    return elevatedButtonStyle.copyWith(
      backgroundColor: MaterialStateProperty.all(AppColors.error),
      foregroundColor: MaterialStateProperty.all(AppColors.onError),
    );
  }

  // ========== OUTLINED BUTTON ==========
  /// Style cho OutlinedButton chính
  static ButtonStyle get outlinedButtonStyle {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: AppColors.primary, width: 1.5),
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
      overlayColor: MaterialStateProperty.all(
        AppColors.primary.withOpacity(0.1),
      ),
      // Disabled state
      side: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return BorderSide(color: AppColors.grey400, width: 1);
        }
        return BorderSide(color: AppColors.primary, width: 1.5);
      }),
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.primary;
      }),
    );
  }

  /// Style cho OutlinedButton nhỏ
  static ButtonStyle get smallOutlinedButtonStyle {
    return outlinedButtonStyle.copyWith(
      minimumSize: MaterialStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: MaterialStateProperty.all(
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
      overlayColor: MaterialStateProperty.all(
        AppColors.primary.withOpacity(0.1),
      ),
      // Disabled state
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return AppColors.grey600;
        }
        return AppColors.primary;
      }),
    );
  }

  /// Style cho TextButton nhỏ
  static ButtonStyle get smallTextButtonStyle {
    return textButtonStyle.copyWith(
      minimumSize: MaterialStateProperty.all(
        const Size(0, smallButtonHeight),
      ),
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
      textStyle: MaterialStateProperty.all(
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
      overlayColor: MaterialStateProperty.all(
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
      overlayColor: MaterialStateProperty.all(
        AppColors.onSurface.withOpacity(0.1),
      ),
    );
  }

  // ========== FAB (FLOATING ACTION BUTTON) ==========
  /// Style cho FloatingActionButton
  static ButtonStyle get fabStyle {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.all(AppColors.secondary),
      foregroundColor: MaterialStateProperty.all(AppColors.onSecondary),
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
      backgroundColor: MaterialStateProperty.all(backgroundColor),
      foregroundColor: MaterialStateProperty.all(foregroundColor),
    );
  }

  /// Tạo button style với size tùy chỉnh
  static ButtonStyle withSize(ButtonStyle style, double height, double? width) {
    return style.copyWith(
      minimumSize: MaterialStateProperty.all(
        Size(width ?? double.infinity, height),
      ),
    );
  }

  /// Tạo button style với border radius tùy chỉnh
  static ButtonStyle withBorderRadius(ButtonStyle style, double radius) {
    return style.copyWith(
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}