import 'package:flutter/material.dart';

/// UI Constants - Modern Design System
class UIConstants {
  // 🎨 Colors - Modern Palette
  static const Color primaryColor = Color(0xFF1E40AF);
  static const Color secondaryColor = Color(0xFF7C3AED);
  static const Color successColor = Color(0xFF059669);
  static const Color errorColor = Color(0xFFDC2626);
  static const Color warningColor = Color(0xFFD97706);

  static const Color surfaceColor = Colors.white;
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  static const Color borderColor = Color(0xFFD1D5DB);
  static const Color dividerColor = Color(0xFFE5E7EB);

  // 🎨 Brand Colors for Inventory
  static const Color brandIPhone = Color(0xFF2962FF); // Blue for iPhone
  static const Color brandSamsung = Color(0xFF1976D2); // Blue for Samsung
  static const Color brandAccessory = Color(0xFF4CAF50); // Green for Accessories
  static const Color brandParts = Color(0xFFFF9800); // Orange for Parts
  static const Color brandOther = Color(0xFF9C27B0); // Purple for Other

  // 📊 Inventory Status Colors
  static const Color stockNormal = Color(0xFF2E7D32); // Green for normal stock
  static const Color stockLow = Color(0xFFFF9800); // Orange for low stock
  static const Color stockOut = Color(0xFFC62828); // Red for out of stock

  // 📏 Spacing Scale - Modern 8px Grid
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing56 = 56.0;
  static const double spacing64 = 64.0;

  // 🔘 Border Radius Values (for backwards compatibility)
  static const double borderRadiusValue4 = 4.0;
  static const double borderRadiusValue8 = 8.0;
  static const double borderRadiusValue10 = 10.0;
  static const double borderRadiusValue12 = 12.0;
  static const double borderRadiusValue16 = 16.0;
  static const double borderRadiusValue20 = 20.0;
  static const double borderRadiusValue24 = 24.0;

  // 📏 Icon Sizes
  static const double iconSize12 = 12.0;
  static const double iconSize16 = 16.0;
  static const double iconSize20 = 20.0;
  static const double iconSize24 = 24.0;
  static const double iconSize28 = 28.0;
  static const double iconSize32 = 32.0;
  static const double iconSize40 = 40.0;
  static const double iconSize48 = 48.0;
  static const double iconSize64 = 64.0;

  // 🔘 Button Dimensions
  static const double buttonHeight40 = 40.0;
  static const double buttonHeight44 = 44.0;
  static const double buttonHeight48 = 48.0;
  static const double buttonHeight56 = 56.0;

  // 📦 Card Properties
  static const double cardElevation2 = 2.0;
  static const double cardElevation4 = 4.0;
  static const double cardElevation8 = 8.0;

  // 📱 App Bar
  static const double appBarHeight = 64.0;

  // 📝 Input Field Configurations
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  static const EdgeInsets inputPaddingSmall = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
  static const EdgeInsets inputPaddingLarge = EdgeInsets.symmetric(horizontal: 20, vertical: 20);
  static const EdgeInsets inputPaddingVertical12 = EdgeInsets.symmetric(vertical: 12);
  static const EdgeInsets inputPaddingHorizontal16 = EdgeInsets.symmetric(horizontal: 16);

  // 📏 Common Padding
  static const EdgeInsets padding4 = EdgeInsets.all(4);
  static const EdgeInsets paddingAll4 = EdgeInsets.all(4);
  static const EdgeInsets padding8 = EdgeInsets.all(8);
  static const EdgeInsets padding12 = EdgeInsets.all(12);
  static const EdgeInsets padding16 = EdgeInsets.all(16);
  static const EdgeInsets padding20 = EdgeInsets.all(20);
  static const EdgeInsets padding24 = EdgeInsets.all(24);
  static const EdgeInsets padding32 = EdgeInsets.all(32);

  // Horizontal Padding
  static const EdgeInsets paddingHorizontal8 = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets paddingHorizontal12 = EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets paddingHorizontal16 = EdgeInsets.symmetric(horizontal: 16);
  static const EdgeInsets paddingHorizontal20 = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets paddingHorizontal24 = EdgeInsets.symmetric(horizontal: 24);

  // Vertical Padding
  static const EdgeInsets paddingVertical4 = EdgeInsets.symmetric(vertical: 4);
  static const EdgeInsets paddingVertical8 = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets paddingVertical10 = EdgeInsets.symmetric(vertical: 10);
  static const EdgeInsets paddingVertical12 = EdgeInsets.symmetric(vertical: 12);
  static const EdgeInsets paddingVertical16 = EdgeInsets.symmetric(vertical: 16);
  static const EdgeInsets paddingVertical20 = EdgeInsets.symmetric(vertical: 20);
  static const EdgeInsets paddingVertical24 = EdgeInsets.symmetric(vertical: 24);

  // 📏 SizedBox Heights
  static const SizedBox height4 = SizedBox(height: 4);
  static const SizedBox height6 = SizedBox(height: 6);
  static const SizedBox height8 = SizedBox(height: 8);
  static const SizedBox height12 = SizedBox(height: 12);
  static const SizedBox height16 = SizedBox(height: 16);
  static const SizedBox height20 = SizedBox(height: 20);
  static const SizedBox height24 = SizedBox(height: 24);
  static const SizedBox height32 = SizedBox(height: 32);
  static const SizedBox height40 = SizedBox(height: 40);
  static const SizedBox height48 = SizedBox(height: 48);
  static const SizedBox height56 = SizedBox(height: 56);
  static const SizedBox height64 = SizedBox(height: 64);

  // 📏 SizedBox Widths
  static const SizedBox width4 = SizedBox(width: 4);
  static const SizedBox width8 = SizedBox(width: 8);
  static const SizedBox width12 = SizedBox(width: 12);
  static const SizedBox width16 = SizedBox(width: 16);
  static const SizedBox width20 = SizedBox(width: 20);
  static const SizedBox width24 = SizedBox(width: 24);
  static const SizedBox width32 = SizedBox(width: 32);
  static const SizedBox width40 = SizedBox(width: 40);
  static const SizedBox width48 = SizedBox(width: 48);

  // 🎨 Box Shadows - Modern Elevation
  static const List<BoxShadow> shadowSmall = [
    BoxShadow(
      color: Color(0x0D000000),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 2),
      blurRadius: 4,
    ),
  ];

  static const List<BoxShadow> shadowLarge = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 8,
    ),
  ];

  static const List<BoxShadow> shadowExtraLarge = [
    BoxShadow(
      color: Color(0x1F000000),
      offset: Offset(0, 8),
      blurRadius: 16,
    ),
  ];

  // 🎯 Border Styles
  static const BorderRadius borderRadius4 = BorderRadius.all(Radius.circular(4));
  static const BorderRadius borderRadius8 = BorderRadius.all(Radius.circular(8));
  static const BorderRadius borderRadius12 = BorderRadius.all(Radius.circular(12));
  static const BorderRadius borderRadius16 = BorderRadius.all(Radius.circular(16));
  static const BorderRadius borderRadius20 = BorderRadius.all(Radius.circular(20));
  static const BorderRadius borderRadius24 = BorderRadius.all(Radius.circular(24));

  // 📊 Animation Durations
  static const Duration duration150 = Duration(milliseconds: 150);
  static const Duration duration200 = Duration(milliseconds: 200);
  static const Duration duration300 = Duration(milliseconds: 300);
  static const Duration duration500 = Duration(milliseconds: 500);

  // 🎨 Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorGradient = LinearGradient(
    colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Extension methods for easier access
extension UIConstantsExtension on BuildContext {
  // 🎨 Colors
  Color get primaryColor => UIConstants.primaryColor;
  Color get secondaryColor => UIConstants.secondaryColor;
  Color get successColor => UIConstants.successColor;
  Color get errorColor => UIConstants.errorColor;
  Color get warningColor => UIConstants.warningColor;

  Color get surfaceColor => UIConstants.surfaceColor;
  Color get backgroundColor => UIConstants.backgroundColor;
  Color get cardColor => UIConstants.cardColor;

  Color get textPrimary => UIConstants.textPrimary;
  Color get textSecondary => UIConstants.textSecondary;
  Color get textTertiary => UIConstants.textTertiary;

  // 📏 Spacing
  double get spacing4 => UIConstants.spacing4;
  double get spacing8 => UIConstants.spacing8;
  double get spacing12 => UIConstants.spacing12;
  double get spacing16 => UIConstants.spacing16;
  double get spacing20 => UIConstants.spacing20;
  double get spacing24 => UIConstants.spacing24;
  double get spacing32 => UIConstants.spacing32;
  double get spacing40 => UIConstants.spacing40;
  double get spacing48 => UIConstants.spacing48;
  double get spacing56 => UIConstants.spacing56;
  double get spacing64 => UIConstants.spacing64;

  // 📏 Common Widgets
  SizedBox get height4 => UIConstants.height4;
  SizedBox get height8 => UIConstants.height8;
  SizedBox get height12 => UIConstants.height12;
  SizedBox get height16 => UIConstants.height16;
  SizedBox get height20 => UIConstants.height20;
  SizedBox get height24 => UIConstants.height24;
  SizedBox get height32 => UIConstants.height32;
  SizedBox get height40 => UIConstants.height40;
  SizedBox get height48 => UIConstants.height48;
  SizedBox get height56 => UIConstants.height56;
  SizedBox get height64 => UIConstants.height64;

  SizedBox get width4 => UIConstants.width4;
  SizedBox get width8 => UIConstants.width8;
  SizedBox get width12 => UIConstants.width12;
  SizedBox get width16 => UIConstants.width16;
  SizedBox get width20 => UIConstants.width20;
  SizedBox get width24 => UIConstants.width24;
  SizedBox get width32 => UIConstants.width32;
  SizedBox get width40 => UIConstants.width40;
  SizedBox get width48 => UIConstants.width48;

  // 🎨 Theme Colors
  Color get colorSchemePrimary => Theme.of(this).colorScheme.primary;
  Color get colorSchemeSecondary => Theme.of(this).colorScheme.secondary;
  Color get colorSchemeTertiary => Theme.of(this).colorScheme.tertiary;
  Color get colorSchemeError => Theme.of(this).colorScheme.error;
  Color get colorSchemeSurface => Theme.of(this).colorScheme.surface;
  Color get colorSchemeBackground => Theme.of(this).colorScheme.surface;
  Color get colorSchemeOnPrimary => Theme.of(this).colorScheme.onPrimary;
  Color get colorSchemeOnSurface => Theme.of(this).colorScheme.onSurface;

  // 📝 Text Styles
  TextStyle get textThemeDisplayLarge => Theme.of(this).textTheme.displayLarge!;
  TextStyle get textThemeDisplayMedium => Theme.of(this).textTheme.displayMedium!;
  TextStyle get textThemeDisplaySmall => Theme.of(this).textTheme.displaySmall!;
  TextStyle get textThemeHeadlineLarge => Theme.of(this).textTheme.headlineLarge!;
  TextStyle get textThemeHeadlineMedium => Theme.of(this).textTheme.headlineMedium!;
  TextStyle get textThemeHeadlineSmall => Theme.of(this).textTheme.headlineSmall!;
  TextStyle get textThemeTitleLarge => Theme.of(this).textTheme.titleLarge!;
  TextStyle get textThemeTitleMedium => Theme.of(this).textTheme.titleMedium!;
  TextStyle get textThemeTitleSmall => Theme.of(this).textTheme.titleSmall!;
  TextStyle get textThemeBodyLarge => Theme.of(this).textTheme.bodyLarge!;
  TextStyle get textThemeBodyMedium => Theme.of(this).textTheme.bodyMedium!;
  TextStyle get textThemeBodySmall => Theme.of(this).textTheme.bodySmall!;
  TextStyle get textThemeLabelLarge => Theme.of(this).textTheme.labelLarge!;
  TextStyle get textThemeLabelMedium => Theme.of(this).textTheme.labelMedium!;
  TextStyle get textThemeLabelSmall => Theme.of(this).textTheme.labelSmall!;

  // 🎨 Inventory Brand Colors
  Color getBrandColor(String productName) {
    final name = productName.toUpperCase();
    if (name.startsWith("IP-") || name.contains("IPHONE")) return UIConstants.brandIPhone;
    if (name.startsWith("SS-") || name.contains("SAMSUNG")) return UIConstants.brandSamsung;
    if (name.startsWith("PIN-") || name.startsWith("MH-")) return UIConstants.brandParts;
    if (name.startsWith("PK-") || name.startsWith("ACCESSORY")) return UIConstants.brandAccessory;
    return UIConstants.brandOther;
  }

  // 📊 Stock Status Colors
  (Color color, String text) getStockStatus(int quantity) {
    if (quantity == 0) return (UIConstants.stockOut, "Hết");
    if (quantity < 5) return (UIConstants.stockLow, quantity.toString());
    return (UIConstants.stockNormal, quantity.toString());
  }
}