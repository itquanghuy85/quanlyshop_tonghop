import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_button_styles.dart';

/// Design System Theme cho toàn bộ ứng dụng
/// Định nghĩa theme thống nhất cho MaterialApp
class AppTheme {
  // Private constructor để ngăn tạo instance
  AppTheme._();

  /// Theme chính cho MaterialApp
  static ThemeData get lightTheme {
    return ThemeData(
      // ========== COLORS ==========
      primaryColor: AppColors.primary,
      primaryColorLight: AppColors.primaryLight,
      primaryColorDark: AppColors.primaryDark,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: const Color.fromARGB(255, 15, 228, 125),
      dividerColor: AppColors.divider,

      // ========== COLOR SCHEME ==========
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        secondary: AppColors.secondary,
        secondaryContainer: AppColors.secondaryLight,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.onPrimary,
        onSecondary: AppColors.onSecondary,
        onSurface: AppColors.onSurface,
        onError: AppColors.onError,
      ),

      // ========== TYPOGRAPHY ==========
      fontFamily: AppTextStyles.fontFamily,
      textTheme: AppTextStyles.textTheme,

      // ========== APP BAR ==========
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 17,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(
          color: AppColors.primary,
          size: 22,
        ),
        actionsIconTheme: IconThemeData(
          color: AppColors.primary,
          size: 22,
        ),
        toolbarHeight: 56,
      ),

      // ========== BOTTOM NAVIGATION BAR ==========
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.onSurface.withAlpha(130),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 11,
        ),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // ========== TAB BAR ==========
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.onSurface.withAlpha(150),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.primary,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(AppColors.primary.withAlpha(30)),
      ),

      // ========== CARD ==========
      cardTheme: CardThemeData(
        color: AppColors.surface,
        shadowColor: AppColors.shadow,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
        ),
        margin: EdgeInsets.zero,
      ),

      // ========== BUTTONS ==========
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: AppButtonStyles.elevatedButtonStyle,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: AppButtonStyles.outlinedButtonStyle,
      ),
      textButtonTheme: TextButtonThemeData(
        style: AppButtonStyles.textButtonStyle,
      ),

      // ========== INPUT DECORATION ==========
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: AppTextStyles.body2.copyWith(
          color: AppColors.onSurface.withOpacity(0.7),
        ),
        hintStyle: AppTextStyles.body2.copyWith(
          color: AppColors.onSurface.withOpacity(0.5),
        ),
        errorStyle: AppTextStyles.caption.copyWith(
          color: AppColors.error,
        ),
      ),

      // ========== DIALOG ==========
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius * 1.5),
        ),
        titleTextStyle: AppTextStyles.headline6,
        contentTextStyle: AppTextStyles.body1,
      ),

      // ========== SNACKBAR ==========
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: AppTextStyles.body2.copyWith(
          color: AppColors.onSurface,
        ),
        actionTextColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ========== CHIP ==========
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        disabledColor: AppColors.surface.withOpacity(0.5),
        selectedColor: AppColors.primary.withOpacity(0.1),
        secondarySelectedColor: AppColors.secondary.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: AppTextStyles.body2,
        secondaryLabelStyle: AppTextStyles.body2.copyWith(
          color: AppColors.primary,
        ),
        brightness: Brightness.light,
        deleteIconColor: AppColors.onSurface.withOpacity(0.7),
        checkmarkColor: AppColors.primary,
      ),

      // ========== FLOATING ACTION BUTTON ==========
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.onSecondary,
        elevation: 6,
        focusElevation: 8,
        hoverElevation: 8,
        disabledElevation: 0,
      ),

      // ========== ICON THEME ==========
      iconTheme: const IconThemeData(
        color: AppColors.onSurface,
        size: 24,
      ),

      // ========== DIVIDER ==========
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ========== PROGRESS INDICATOR ==========
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primary.withOpacity(0.2),
        circularTrackColor: AppColors.primary.withOpacity(0.2),
      ),

      // ========== SWITCH ==========
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.onSurface.withOpacity(0.5);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withOpacity(0.3);
          }
          return AppColors.onSurface.withOpacity(0.2);
        }),
      ),

      // ========== CHECKBOX ==========
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
        side: BorderSide(color: AppColors.onSurface.withOpacity(0.5)),
      ),

      // ========== RADIO ==========
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.onSurface.withOpacity(0.5);
        }),
      ),

      // ========== USE MATERIAL 3 ==========
      useMaterial3: true,

      // ========== VISUAL DENSITY ==========
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  /// Dark theme (tương lai có thể implement)
  static ThemeData get darkTheme {
    return lightTheme.copyWith(
      brightness: Brightness.dark,
      // TODO: Implement dark theme colors
    );
  }
}