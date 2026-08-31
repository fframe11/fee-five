import 'package:flutter/material.dart';

/// Centralized color palette for AccessGuardian
/// Implements the "Volcanic Ash" design system:
/// - Purple: #8338EC (Primary Brand)
/// - Orange: #FB5607 (Secondary Action / Focus Accent)
/// - Dark: #212529 (Dark Background & Text)
/// - Off-white: #E9ECEF (Light Background)
class AppColors {
  // Volcanic Ash Core Palette
  static const Color primary = Color(0xFF8338EC);
  static const Color primaryDark = Color(0xFF5E17EB);
  static const Color primaryLight = Color(0xFF9D5FF5);
  static const Color primarySurface = Color(0xFFF3E8FF);

  static const Color secondary = Color(0xFFFB5607);
  static const Color secondaryLight = Color(0xFFFF7A38);
  static const Color secondarySurface = Color(0xFFFFF1EB);

  static const Color dark = Color(0xFF212529);
  static const Color darkSurface = Color(0xFF1E2125);
  static const Color darkBorder = Color(0xFF343A40);

  static const Color light = Color(0xFFE9ECEF);
  static const Color lightSurface = Color(0xFFF8F9FA);
  static const Color lightBorder = Color(0xFFDDE1E5);

  // Colorblind accessibility fallback palette
  static const Color colorBlindPrimary = Color(0xFF0D47A1);
  static const Color colorBlindSecondary = Color(0xFFFFB300);

  /// Helper to get dynamic primary color based on accessibility state
  static Color getPrimary(bool isColorBlind, {bool isHighContrast = false}) {
    if (isHighContrast) return Colors.black;
    if (isColorBlind) return colorBlindPrimary;
    return primary;
  }

  /// Helper to get dynamic secondary color based on accessibility state
  static Color getSecondary(bool isColorBlind, {bool isHighContrast = false}) {
    if (isHighContrast) return Colors.white;
    if (isColorBlind) return colorBlindSecondary;
    return secondary;
  }
}
