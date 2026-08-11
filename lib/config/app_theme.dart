import 'package:flutter/material.dart';

/// Shared color palette + reusable decorations for Yatra Mitra.
/// Pulled from the student dashboard mockup so every screen
/// (admin / helpdesk / student) uses the same creamy-yellow theme
/// instead of hardcoding hex values in each file.
class AppTheme {
  AppTheme._();

  // Backgrounds
  static const Color background = Color(0xFFFFF8EC);
  static const Color cardBackground = Colors.white;

  // Brand
  static const Color primaryYellow = Color(0xFFF5A623);
  static const Color primaryYellowDark = Color(0xFFE0941A);
  static const Color accentOrange = Color(0xFFFF9800);

  // Status
  static const Color statusGreen = Color(0xFF2E9A5C);
  static const Color statusRed = Color(0xFFE0403A);
  static const Color statusBlue = Color(0xFF3B82F6);
  static const Color sosRed = Color(0xFFE0403A);

  // Text
  static const Color textPrimary = Color(0xFF1F2430);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Borders
  static const Color border = Color(0xFFF0E4D0);

  static BoxDecoration cardDecoration({Color? color, double radius = 18}) {
    return BoxDecoration(
      color: color ?? cardBackground,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static TextStyle heading(double size, {Color? color, FontWeight? weight}) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w700,
      color: color ?? textPrimary,
    );
  }
}
