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

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF163E84), Color(0xFF1A6BC2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration elevatedPanel({Color? color}) {
    return BoxDecoration(
      color: color ?? panelBg,
      borderRadius: BorderRadius.circular(16),
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
