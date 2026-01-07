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
        background: Color.fromARGB(255, 107, 243, 11),
        error: AppColors.error,
        onPrimary: AppColors.onPrimary,
        onSecondary: AppColors.onSecondary,
        onSurface: AppColors.onSurface,
        onBackground: AppColors.onBackground,
        onError: AppColors.onError,
      ),

      // ========== TYPOGRAPHY ==========
      fontFamily: AppTextStyles.fontFamily,
      textTheme: AppTextStyles.textTheme,

      // ========== APP BAR ==========
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 4,
        shadowColor: AppColors.shadow,
        centerTitle: true,
        titleTextStyle: AppTextStyles.headline6.copyWith(
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: AppColors.onPrimary,
        ),
      ),

      // ========== BOTTOM NAVIGATION BAR ==========
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color.fromARGB(255, 137, 247, 162),
        selectedItemColor: const Color.fromARGB(255, 167, 243, 14),
        unselectedItemColor: AppColors.onSurface.withOpacity(0.6),
        selectedLabelStyle: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.caption,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // ========== TAB BAR ==========
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.grey300,
        labelStyle: TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.secondary, width: 3),
          insets: EdgeInsets.symmetric(horizontal: 16),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
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
          borderSide: BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
          borderSide: BorderSide(color: AppColors.error, width: 2),
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.onSecondary,
        elevation: 6,
        focusElevation: 8,
        hoverElevation: 8,
        disabledElevation: 0,
      ),

      // ========== ICON THEME ==========
      iconTheme: IconThemeData(
        color: AppColors.onSurface,
        size: 24,
      ),

      // ========== DIVIDER ==========
      dividerTheme: DividerThemeData(
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
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.primary;
          }
          return AppColors.onSurface.withOpacity(0.5);
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.primary.withOpacity(0.3);
          }
          return AppColors.onSurface.withOpacity(0.2);
        }),
      ),

      // ========== CHECKBOX ==========
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(AppColors.onPrimary),
        side: BorderSide(color: AppColors.onSurface.withOpacity(0.5)),
      ),

      // ========== RADIO ==========
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
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