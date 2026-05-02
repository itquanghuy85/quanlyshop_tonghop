import 'package:flutter/material.dart';

class FinanceV2Theme {
  static const Color pageBg = Color(0xFFF3F7FC);
  static const Color panelBg = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0F1F3D);
  static const Color subInk = Color(0xFF5D6E8D);
  static const Color positive = Color(0xFF0F8A5F);
  static const Color negative = Color(0xFFC0392B);
  static const Color warn = Color(0xFFB9770E);
  static const Color accent = Color(0xFF164A9E);

  static const double radiusPanel = 16;
  static const double radiusControl = 12;

  static const TextStyle titleLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: ink,
  );

  static const TextStyle titleMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  static const TextStyle bodyMd = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: ink,
  );

  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: subInk,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: subInk,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: ink,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: subInk,
  );

  static const TextStyle chip = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: subInk,
  );

  static const TextStyle amountLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: ink,
  );

  static const TextStyle amountMd = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: ink,
  );

  static const TextStyle amountHero = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: -0.5,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: ink,
    height: 1.6,
  );

  static bool isDesktop(double width) => width >= 1200;
  static bool isTablet(double width) => width >= 700 && width < 1200;

  static double contentHPad(double width) {
    if (isDesktop(width)) return 20;
    if (isTablet(width)) return 16;
    return 12;
  }

  static double sectionGap(double width) {
    if (isDesktop(width)) return 16;
    if (isTablet(width)) return 14;
    return 12;
  }

  static double cardPad(double width) {
    if (isDesktop(width)) return 16;
    if (isTablet(width)) return 15;
    return 14;
  }

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF163E84), Color(0xFF1A6BC2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration elevatedPanel({Color? color}) {
    return BoxDecoration(
      color: color ?? panelBg,
      borderRadius: BorderRadius.circular(radiusPanel),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F1F3D).withValues(alpha: 0.08),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
