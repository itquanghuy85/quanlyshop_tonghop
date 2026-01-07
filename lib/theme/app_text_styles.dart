import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography thống nhất cho toàn bộ ứng dụng
/// Định nghĩa tất cả text styles được sử dụng trong app
class AppTextStyles {
  // Private constructor để ngăn tạo instance
  AppTextStyles._();

  // ========== FONT FAMILY ==========
  /// Font chính của app
  static const String fontFamily = 'Roboto';

  /// Font chữ số (cho price, quantity)
  static const String numberFontFamily = 'Roboto';

  // ========== FONT SIZES ==========
  /// Heading 1 - 32px
  static const double h1 = 30.0;

  /// Heading 2 - 28px
  static const double h2 = 26.0;

  /// Heading 3 - 24px
  static const double h3 = 24.0;

  /// Heading 4 - 20px
  static const double h4 = 20.0;

  /// Heading 5 - 18px
  static const double h5 = 18.0;

  /// Heading 6 - 16px
  static const double h6 = 14.0;

  /// Subtitle 1 - 16px
  static const double subtitle1Size = 15.0;

  /// Subtitle 2 - 14px
  static const double subtitle2Size = 13.0;

  /// Body 1 - 16px
  static const double body1Size = 15.0;

  /// Body 2 - 14px
  static const double body2Size = 13.0;

  /// Button - 14px
  static const double buttonSize = 13.0;

  /// Caption - 12px
  static const double captionSize = 12.0;

  /// Overline - 10px
  static const double overlineSize = 10.0;

  // ========== LINE HEIGHTS ==========
  /// Line height cho heading
  static const double headingLineHeight = 1.2;

  /// Line height cho body text
  static const double bodyLineHeight = 1.5;

  /// Line height cho caption
  static const double captionLineHeight = 1.4;

  // ========== LETTER SPACINGS ==========
  /// Letter spacing cho heading
  static const double headingLetterSpacing = -0.5;

  /// Letter spacing cho button
  static const double buttonLetterSpacing = 0.5;

  // ========== TEXT STYLES ==========

  // HEADINGS
  /// Heading 1 - Page titles, main headings
  static TextStyle get headline1 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h1,
        fontWeight: FontWeight.w700,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  /// Heading 2 - Section headings
  static TextStyle get headline2 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h2,
        fontWeight: FontWeight.w600,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  /// Heading 3 - Subsection headings
  static TextStyle get headline3 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h3,
        fontWeight: FontWeight.w600,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  /// Heading 4 - Card titles, dialog titles
  static TextStyle get headline4 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h4,
        fontWeight: FontWeight.w600,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  /// Heading 5 - AppBar titles
  static TextStyle get headline5 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h5,
        fontWeight: FontWeight.w600,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  /// Heading 6 - Small headings, list item titles
  static TextStyle get headline6 => TextStyle(
        fontFamily: fontFamily,
        fontSize: h6,
        fontWeight: FontWeight.w600,
        height: headingLineHeight,
        letterSpacing: headingLetterSpacing,
        color: AppColors.onSurface,
      );

  // SUBTITLES
  /// Subtitle 1 - Large subtitles
  static TextStyle get subtitle1 => TextStyle(
        fontFamily: fontFamily,
        fontSize: subtitle1Size,
        fontWeight: FontWeight.w500,
        height: bodyLineHeight,
        color: AppColors.onSurface.withOpacity(0.7),
      );

  /// Subtitle 2 - Small subtitles
  static TextStyle get subtitle2 => TextStyle(
        fontFamily: fontFamily,
        fontSize: subtitle2Size,
        fontWeight: FontWeight.w500,
        height: bodyLineHeight,
        color: AppColors.onSurface.withOpacity(0.7),
      );

  // BODY TEXT
  /// Body 1 - Main content text
  static TextStyle get body1 => TextStyle(
        fontFamily: fontFamily,
        fontSize: body1Size,
        fontWeight: FontWeight.w400,
        height: bodyLineHeight,
        color: AppColors.onSurface,
      );

  /// Body 2 - Secondary content text
  static TextStyle get body2 => TextStyle(
        fontFamily: fontFamily,
        fontSize: body2Size,
        fontWeight: FontWeight.w400,
        height: bodyLineHeight,
        color: AppColors.onSurface,
      );

  // BUTTON TEXT
  /// Button - Button labels
  static TextStyle get button => TextStyle(
        fontFamily: fontFamily,
        fontSize: buttonSize,
        fontWeight: FontWeight.w500,
        height: 1.0,
        letterSpacing: buttonLetterSpacing,
        color: AppColors.onPrimary,
      );

  // CAPTION
  /// Caption - Small descriptive text
  static TextStyle get caption => TextStyle(
        fontFamily: fontFamily,
        fontSize: captionSize,
        fontWeight: FontWeight.w400,
        height: captionLineHeight,
        color: AppColors.onSurface.withOpacity(0.6),
      );

  // OVERLINE
  /// Overline - Very small text
  static TextStyle get overline => TextStyle(
        fontFamily: fontFamily,
        fontSize: overlineSize,
        fontWeight: FontWeight.w500,
        height: captionLineHeight,
        letterSpacing: 1.5,
        color: AppColors.onSurface.withOpacity(0.5),
      );

  // ========== MATERIAL TEXT THEME ==========
  /// TextTheme cho Material Design
  static TextTheme get textTheme => TextTheme(
        displayLarge: headline1,
        displayMedium: headline2,
        displaySmall: headline3,
        headlineLarge: headline4,
        headlineMedium: headline5,
        headlineSmall: headline6,
        titleLarge: subtitle1,
        titleMedium: subtitle2,
        bodyLarge: body1,
        bodyMedium: body2,
        labelLarge: button,
        bodySmall: caption,
      );

  // ========== UTILITY METHODS ==========

  /// Tạo text style với màu tùy chỉnh
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }

  /// Tạo text style với font weight tùy chỉnh
  static TextStyle withWeight(TextStyle style, FontWeight weight) {
    return style.copyWith(fontWeight: weight);
  }

  /// Tạo text style với size tùy chỉnh
  static TextStyle withSize(TextStyle style, double size) {
    return style.copyWith(fontSize: size);
  }

  /// Tạo text style cho price/money
  static TextStyle get priceStyle => TextStyle(
        fontFamily: numberFontFamily,
        fontSize: body1Size,
        fontWeight: FontWeight.w600,
        color: AppColors.success,
        letterSpacing: 0.5,
      );

  /// Tạo text style cho quantity
  static TextStyle get quantityStyle => TextStyle(
        fontFamily: numberFontFamily,
        fontSize: body2Size,
        fontWeight: FontWeight.w500,
        color: AppColors.info,
      );

  /// Tạo text style cho status text
  static TextStyle statusStyle(Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: captionSize,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.5,
      );

  /// Tạo text style cho error text
  static TextStyle get errorStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: captionSize,
        fontWeight: FontWeight.w500,
        color: AppColors.error,
      );

  /// Tạo text style cho success text
  static TextStyle get successStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: captionSize,
        fontWeight: FontWeight.w500,
        color: AppColors.success,
      );

  /// Tạo text style cho warning text
  static TextStyle get warningStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: captionSize,
        fontWeight: FontWeight.w500,
        color: AppColors.warning,
      );
}